import Darwin
import Foundation

struct VPhoneNetworkTarget: Codable, Sendable {
    let host: String
    let port: Int
    func normalized() throws -> Self {
        let value = try VPhoneProxyRequest(enabled: true, host: host, port: port).validated()
        return Self(host: value.host, port: value.port)
    }
}

struct VPhoneNetworkProbeResult: Codable, Sendable {
    struct Attempt: Codable, Sendable {
        let address: String
        let connected: Bool
        let error: String?
    }
    let origin: String
    let target: VPhoneNetworkTarget
    let addresses: [String]
    let dnsError: String?
    let attempts: [Attempt]
    let elapsedMilliseconds: Int
    let completedAt: Double
}

enum VPhoneNetworkProbe {
    private struct Endpoint: Sendable { let address: String; let family: Int32; let socketAddress: Data }
    private final class Resolution: @unchecked Sendable {
        let lock = NSLock()
        var addresses: [Endpoint] = []
        var error: String?
    }

    /// Run away from the UI actor. DNS waits at most three seconds; TCP uses
    /// another three-second budget across all candidates and sends no payload.
    static func run(_ input: VPhoneNetworkTarget, origin: String) throws -> VPhoneNetworkProbeResult {
        let target = try input.normalized()
        let started = ProcessInfo.processInfo.systemUptime
        let resolution = Resolution(), finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM; hints.ai_protocol = IPPROTO_TCP
            var first: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(target.host, String(target.port), &hints, &first)
            var endpoints: [Endpoint] = [], seen = Set<String>()
            if let first {
                defer { freeaddrinfo(first) }
                var cursor: UnsafeMutablePointer<addrinfo>? = first
                while let row = cursor, endpoints.count < 8 {
                    defer { cursor = row.pointee.ai_next }
                    let item = row.pointee
                    guard item.ai_family == AF_INET || item.ai_family == AF_INET6,
                          let address = item.ai_addr, item.ai_addrlen > 0,
                          item.ai_addrlen <= MemoryLayout<sockaddr_storage>.size else { continue }
                    var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    guard getnameinfo(address, item.ai_addrlen, &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
                    let numeric = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    guard seen.insert(numeric).inserted else { continue }
                    endpoints.append(Endpoint(address: numeric, family: item.ai_family,
                        socketAddress: Data(bytes: address, count: Int(item.ai_addrlen))))
                }
            }
            resolution.lock.lock()
            resolution.addresses = endpoints
            resolution.error = status == 0 ? (endpoints.isEmpty ? "DNS returned no usable addresses." : nil) : String(cString: gai_strerror(status))
            resolution.lock.unlock()
            finished.signal()
        }
        let timedOut = finished.wait(timeout: .now() + 3) == .timedOut
        resolution.lock.lock()
        let endpoints = timedOut ? [] : resolution.addresses
        let dnsError = timedOut ? "DNS resolution exceeded three seconds." : resolution.error
        resolution.lock.unlock()
        var attempts: [VPhoneNetworkProbeResult.Attempt] = []
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        for endpoint in endpoints {
            let fd = socket(endpoint.family, SOCK_STREAM, 0)
            guard fd >= 0 else {
                attempts.append(.init(address: endpoint.address, connected: false, error: String(cString: strerror(errno)))); continue
            }
            defer { Darwin.close(fd) }
            guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0, fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else {
                attempts.append(.init(address: endpoint.address, connected: false, error: "Cannot configure TCP socket.")); continue
            }
            let connected = endpoint.socketAddress.withUnsafeBytes {
                Darwin.connect(fd, $0.baseAddress!.assumingMemoryBound(to: sockaddr.self), socklen_t($0.count))
            }
            var failure = connected == 0 ? 0 : errno
            if failure == EINPROGRESS {
                while true {
                    let remaining = deadline - ProcessInfo.processInfo.systemUptime
                    if remaining <= 0 { failure = ETIMEDOUT; break }
                    var event = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    let ready = poll(&event, 1, Int32(max(1, min(3000, remaining * 1000))))
                    if ready < 0, errno == EINTR { continue }
                    if ready == 0 { failure = ETIMEDOUT }
                    else if ready < 0 { failure = errno }
                    else {
                        var pending: Int32 = 0
                        var length = socklen_t(MemoryLayout<Int32>.size)
                        failure = getsockopt(fd, SOL_SOCKET, SO_ERROR, &pending, &length) == 0 ? pending : errno
                    }
                    break
                }
            }
            attempts.append(.init(address: endpoint.address, connected: failure == 0,
                                  error: failure == 0 ? nil : String(cString: strerror(failure))))
            if failure == 0 || ProcessInfo.processInfo.systemUptime >= deadline { break }
        }
        return VPhoneNetworkProbeResult(origin: origin, target: target, addresses: endpoints.map(\.address), dnsError: dnsError,
            attempts: attempts, elapsedMilliseconds: Int((ProcessInfo.processInfo.systemUptime - started) * 1000),
            completedAt: Date().timeIntervalSince1970)
    }
}
