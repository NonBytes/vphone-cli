import Foundation

@main struct NetworkGuestSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else { fatalError("Pass VM, guest helper, traffic fixture") }
        let machine = CommandLine.arguments[1], helper = CommandLine.arguments[2], traffic = CommandLine.arguments[3]
        let cli = "/Applications/vphone-launchpad.app/Contents/MacOS/vphone-launchpad-cli"
        func run(_ args: [String]) throws -> [String: Any] {
            let process = Process(), output = Pipe(), errors = Pipe()
            process.executableURL = URL(fileURLWithPath: cli); process.arguments = args
            process.standardOutput = output; process.standardError = errors
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile(), stderr = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw VPhoneNetworkError("CLI failed: " + String(decoding: stderr, as: UTF8.self))
            }
            return value
        }
        func rpc(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
            let json = String(decoding: try JSONSerialization.data(withJSONObject: params), as: UTF8.self)
            let reply = try run(["guest", "rpc", machine, method, json])
            guard reply["ok"] as? Bool == true, let result = reply["result"] as? [String: Any] else { throw VPhoneNetworkError("RPC failed: " + method) }
            return result
        }
        let nonce = UUID().uuidString
        let remote = "/private/var/tmp/vphone-network-fixture-" + nonce
        let sender = remote + "-traffic"
        func invoke(_ path: String, _ args: [String]) throws -> [String: Any] {
            let encodedPath = String(decoding: try JSONEncoder().encode(path), as: UTF8.self)
            let encodedArgs = String(decoding: try JSONEncoder().encode(args), as: UTF8.self)
            return try rpc("script.eval", ["source": "proc.run(\(encodedPath), \(encodedArgs))", "timeout": 20])
        }
        func state(_ args: [String]) throws -> VPhoneCaptureStatus {
            let value = try VPhoneProxyScriptResult.decode(invoke(remote, args), as: VPhoneCaptureStatus.self)
            try value.validate(); return value
        }
        var captureID: String?
        var uploaded: [String] = []
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("vphone-network-fixture-" + nonce + ".pcap")
        defer { try? FileManager.default.removeItem(at: local) }
        func cleanup() throws {
            if let id = captureID {
                _ = try state(["stop", id])
                for _ in 0..<20 {
                    if !(try state(["status"])).active { break }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                _ = try state(["discard", id]); captureID = nil
            }
            for path in uploaded { _ = try rpc("files.remove", ["path": path]) }
            uploaded = []
        }
        do {
            _ = try run(["guest", "push", machine, helper, remote, "--mode", "700"]); uploaded.append(remote)
            _ = try run(["guest", "push", machine, traffic, sender, "--mode", "700"]); uploaded.append(sender)
            guard try state(["status"]).phase == .idle else { throw VPhoneNetworkError("Existing capture retained: live fixture requires idle state.") }
            var request = VPhoneCaptureRequest()
            request.interface = "lo0"; request.transport = .udp; request.address = "127.0.0.1"
            request.port = Int.random(in: 49152...65535); request.seconds = 15; request.maximumBytes = 65536
            let encoded = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
            let initial = try state(["start", encoded]); captureID = initial.id
            var running = initial
            for _ in 0..<30 {
                running = try state(["status"])
                if running.phase != .starting { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard running.phase == .running else { throw VPhoneNetworkError("Worker failed: " + (running.error ?? running.phase.rawValue)) }
            let sent = try invoke(sender, [String(request.port!)])
            guard let text = sent["result"] as? String,
                  let result = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  result["status"] as? Int == 0 else { throw VPhoneNetworkError("Traffic fixture failed") }
            Thread.sleep(forTimeInterval: 0.4)
            _ = try state(["stop", initial.id])
            var finished = try state(["status"])
            for _ in 0..<30 where finished.active { Thread.sleep(forTimeInterval: 0.1); finished = try state(["status"]) }
            guard finished.phase == .completed, finished.reason == "Stopped by user", finished.packets >= 3 else {
                throw VPhoneNetworkError("Stop/count validation failed: " + (finished.error ?? finished.reason) + " packets=\(finished.packets)")
            }
            _ = try run(["guest", "pull", machine, "/private/var/vphone-network/capture.pcap", local.path])
            let summary = try VPhonePCAP.inspect(local, maximumBytes: request.maximumBytes)
            guard summary.packets == finished.packets, summary.bytes == finished.bytes,
                  try Data(contentsOf: local).range(of: Data("vphone-network-fixture-canary".utf8)) != nil else { throw VPhoneNetworkError("Exported PCAP fixture mismatch") }
            _ = try state(["discard", initial.id]); captureID = nil
            request.seconds = 1
            let timed = try state(["start", String(decoding: try JSONEncoder().encode(request), as: UTF8.self)])
            captureID = timed.id
            var expired = timed
            for _ in 0..<40 where expired.active {
                Thread.sleep(forTimeInterval: 0.1); expired = try state(["status"])
            }
            guard expired.phase == .completed, expired.reason == "Duration limit reached", expired.bytes == 24 else {
                throw VPhoneNetworkError("Automatic duration limit failed: " + (expired.error ?? expired.reason))
            }
            let target = String(decoding: try JSONEncoder().encode(VPhoneNetworkTarget(host: "127.0.0.1", port: 1)), as: UTF8.self)
            let probe = try VPhoneProxyScriptResult.decode(invoke(remote, ["diagnose", target]), as: VPhoneNetworkProbeResult.self)
            guard probe.dnsError == nil, probe.addresses == ["127.0.0.1"], !probe.attempts.isEmpty else { throw VPhoneNetworkError("Guest DNS/TCP probe failed") }
            try cleanup()
            print("Live guest network fixture passed: lo0 UDP canary, Stop, PCAP export/counters, automatic duration limit, guest DNS/TCP, discard. Temporary helpers removed.")
        } catch { try? cleanup(); throw error }
    }
}
