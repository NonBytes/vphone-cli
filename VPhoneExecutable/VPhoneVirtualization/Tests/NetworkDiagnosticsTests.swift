import Darwin
import Foundation

@main struct NetworkDiagnosticsTests {
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        precondition(value(), label)
    }
    static func rejects(_ label: String, _ body: () throws -> Void) {
        do { try body(); preconditionFailure(label) } catch {}
    }
    static func main() throws {
        var request = VPhoneCaptureRequest()
        try request.validate()
        request.interface = "en0;echo"
        rejects("unsafe interface") { try request.validate() }
        request.interface = "lo0"; request.port = 0
        rejects("invalid port") { try request.validate() }
        request.port = 443; request.transport = .icmp
        rejects("ICMP port") { try request.validate() }
        request.transport = .tcp; request.address = "example.com"
        rejects("numeric address only") { try request.validate() }
        request.address = "127.0.0.1"
        try request.validate()
        // Ethernet IPv4 TCP with source 127.0.0.1 and destination port 443.
        var packet = [UInt8](repeating: 0, count: 54)
        packet[12] = 8; packet[14] = 0x45; packet[17] = 40; packet[23] = 6
        packet[26] = 127; packet[29] = 1; packet[30] = 10; packet[33] = 1
        packet[34] = 0xc0; packet[35] = 0x01; packet[36] = 1; packet[37] = 0xbb
        check(request.matches(Data(packet), linkType: 1), "IPv4 TCP matches")
        request.port = 80
        check(!request.matches(Data(packet), linkType: 1), "wrong port rejected")
        request.port = 443; packet[21] = 1
        check(!request.matches(Data(packet), linkType: 1), "noninitial fragment has no ports")
        packet[21] = 0
        check(!request.matches(Data(packet.prefix(36)), linkType: 1), "truncated ports rejected")
        request.address = "10.0.0.2"
        check(!request.matches(Data(packet), linkType: 1), "wrong address rejected")
        request.address = ""; request.port = nil; request.transport = .any
        check(request.matches(Data([0]), linkType: 1), "unfiltered capture preserves non-IP frames")
        // IPv6 UDP after a hop-by-hop extension header.
        var v6 = [UInt8](repeating: 0, count: 56)
        v6[0] = 0x60; v6[5] = 16; v6[6] = 0; v6[23] = 1; v6[39] = 2
        v6[40] = 17; v6[48] = 0x14; v6[49] = 0xe9; v6[51] = 53
        request.transport = .udp; request.port = 5353; request.address = "::1"
        check(request.matches(Data(v6), linkType: 101), "IPv6 extension header")
        v6[6] = 44; v6[43] = 8
        check(!request.matches(Data(v6), linkType: 101), "IPv6 noninitial fragment")
        rejects("URL is not a target") { _ = try VPhoneNetworkTarget(host: "https://example.com", port: 443).normalized() }
        let normalized = try VPhoneNetworkTarget(host: "[::1]", port: 443).normalized()
        check(normalized.host == "::1", "IPv6 target normalization")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.pcap")
        let header = VPhonePCAP.header(snapLength: 256, linkType: 1)
        let record = VPhonePCAP.record(seconds: 1, microseconds: 999999, packet: Data(packet), originalLength: 54)
        try (header + record).write(to: url)
        let summary = try VPhonePCAP.inspect(url)
        check(summary.packets == 1 && summary.bytes == 94 && summary.linkType == 1, "PCAP round trip")
        try header.write(to: url)
        let empty = try VPhonePCAP.inspect(url)
        check(empty.packets == 0, "empty PCAP is valid")
        try (header + record.dropLast()).write(to: url)
        rejects("partial packet body") { _ = try VPhonePCAP.inspect(url) }
        try (header + record.prefix(8)).write(to: url)
        rejects("partial packet header") { _ = try VPhonePCAP.inspect(url) }
        try (header + VPhonePCAP.record(seconds: 1, microseconds: 1000000, packet: Data(), originalLength: 0)).write(to: url)
        rejects("bad timestamp") { _ = try VPhonePCAP.inspect(url) }
        try (header + VPhonePCAP.record(seconds: 1, microseconds: 0, packet: Data([1,2]), originalLength: 1)).write(to: url)
        rejects("captured length beyond original") { _ = try VPhonePCAP.inspect(url) }
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        rejects("no symlink export") { _ = try VPhonePCAP.inspect(link) }

        // Native decoder consumes complete records and rejects unsafe lengths.
        var bpf = [UInt8](repeating: 0, count: 24)
        bpf[8] = 4; bpf[12] = 4; bpf[16] = 20
        var offset = 0, decoded = VPhoneBPFRecord()
        let parsed = bpf.withUnsafeBufferPointer { vp_capture_next($0.baseAddress, $0.count, &offset, &decoded) }
        check(parsed == 1 && offset == 24 && decoded.dataOffset == 20 && decoded.capturedLength == 4, "BPF record parsing")
        offset = 0; bpf[8] = 5
        check(bpf.withUnsafeBufferPointer { vp_capture_next($0.baseAddress, $0.count, &offset, &decoded) } == -1, "BPF overflow rejected")
        bpf[8] = 4; bpf[16] = 0; offset = 0
        check(bpf.withUnsafeBufferPointer { vp_capture_next($0.baseAddress, $0.count, &offset, &decoded) } == -1, "BPF zero header rejected")

        // A local listener proves DNS/TCP success without external traffic.
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw VPhoneNetworkError("Cannot create fixture socket") }
        defer { close(listener) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(listener, 1) == 0 else { throw VPhoneNetworkError("Cannot bind fixture socket") }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &size) } }
        let result = try VPhoneNetworkProbe.run(.init(host: "127.0.0.1", port: Int(UInt16(bigEndian: address.sin_port))), origin: "Fixture")
        check(result.addresses == ["127.0.0.1"] && result.attempts.first?.connected == true, "loopback TCP probe")
        print("Network diagnostics fixtures passed (filters, PCAP, BPF decoder, local DNS/TCP).")
    }
}
