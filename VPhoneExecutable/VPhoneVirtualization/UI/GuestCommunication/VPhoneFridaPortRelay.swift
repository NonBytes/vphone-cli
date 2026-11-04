import Foundation
import Network

/// A byte stream used by the relay. The production channel is a WebSocket
/// over VSOCK; tests can exercise TCP/backpressure without a VM.
protocol VPhoneFridaPortChannel: Sendable {
    func send(_ data: Data)
    func close()
}

/// Private loopback-only transport for one Frida client lifetime. The Frida
/// token is still checked by the guest server; this never exposes vphoned.
final class VPhoneFridaPortRelay: @unchecked Sendable {
    typealias OpenChannel = @Sendable (
        @escaping @Sendable (Data) -> Void, @escaping @Sendable () -> Void
    ) async throws -> any VPhoneFridaPortChannel

    private let listener: NWListener
    private let queue = DispatchQueue(label: "vphone.frida.relay")
    private let openChannel: OpenChannel
    // All mutable state belongs to queue.
    private var startup: CheckedContinuation<UInt16, any Error>?
    private var bridges: [UUID: VPhoneFridaPortBridge] = [:]
    private var stopped = false

    init(openChannel: @escaping OpenChannel) throws {
        self.openChannel = openChannel
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !stopped else {
                    continuation.resume(throwing: VPhoneProxyError("The Frida relay has stopped."))
                    return
                }
                startup = continuation
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if let port = listener.port { startup?.resume(returning: port.rawValue); startup = nil }
                    case let .failed(error): end(error: error)
                    case .cancelled: end(error: VPhoneProxyError("The Frida relay was cancelled."))
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self, !stopped, bridges.count < 8 else { connection.cancel(); return }
                    let id = UUID()
                    let bridge = VPhoneFridaPortBridge(connection: connection, queue: queue, openChannel: openChannel) { [weak self] in
                        self?.bridges.removeValue(forKey: id)
                    }
                    bridges[id] = bridge
                    bridge.start()
                }
                listener.start(queue: queue)
            }
        }
    }

    func stop() { queue.async { [self] in end(error: VPhoneProxyError("The Frida relay has stopped.")) } }

    private func end(error: any Error) {
        guard !stopped else { return }
        stopped = true
        startup?.resume(throwing: error); startup = nil
        listener.cancel()
        let active = Array(bridges.values)
        bridges.removeAll()
        for bridge in active { bridge.close() }
    }
}

private final class VPhoneFridaPortBridge: @unchecked Sendable {
    let connection: NWConnection
    let queue: DispatchQueue
    let openChannel: VPhoneFridaPortRelay.OpenChannel
    let onClose: @Sendable () -> Void
    // queue owns channel/closed. Guest callbacks only schedule onto queue or
    // use NWConnection's thread-safe send with bounded, synchronous backpressure.
    private var channel: (any VPhoneFridaPortChannel)?
    private var closed = false

    init(connection: NWConnection, queue: DispatchQueue,
         openChannel: @escaping VPhoneFridaPortRelay.OpenChannel, onClose: @escaping @Sendable () -> Void) {
        self.connection = connection; self.queue = queue; self.openChannel = openChannel; self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.close() }
        }
        connection.start(queue: queue)
        Task { [self] in
            do {
                let channel = try await openChannel({ [weak self] data in self?.deliver(data) }, { [weak self] in
                    guard let self else { return }; queue.async { self.close() }
                })
                queue.async { [self] in
                    guard !closed else { channel.close(); return }
                    self.channel = channel
                    receive()
                }
            } catch { queue.async { [self] in close() } }
        }
    }

    private func receive() {
        guard !closed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self, !closed else { return }
            if let data, !data.isEmpty { channel?.send(data) }
            if complete || error != nil { close() } else { receive() }
        }
    }

    private func deliver(_ data: Data) {
        let sent = DispatchSemaphore(value: 0)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil, let self { queue.async { self.close() } }
            sent.signal()
        })
        if sent.wait(timeout: .now() + 10) == .timedOut { queue.async { [self] in close() } }
    }

    func close() {
        guard !closed else { return }
        closed = true
        connection.cancel()
        channel?.close(); channel = nil
        onClose()
    }
}
