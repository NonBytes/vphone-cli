import Darwin
import Foundation

struct VPhoneNetworkError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct VPhoneCaptureRequest: Codable, Equatable, Sendable {
    enum Transport: String, CaseIterable, Codable, Sendable { case any, tcp, udp, icmp }
    var interface = "en0"
    var transport: Transport = .tcp
    var port: Int?
    var address = ""
    var seconds = 15
    var maximumBytes: Int64 = 16 * 1024 * 1024
    var snapLength = 256

    func validate() throws {
        guard !interface.isEmpty, interface.utf8.count < 16,
              interface.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }),
              (1...60).contains(seconds), (65536...64 * 1024 * 1024).contains(maximumBytes),
              (64...65535).contains(snapLength), port.map({ (1...65535).contains($0) }) ?? true,
              !(transport == .icmp && port != nil), address.isEmpty || Self.numericAddress(address) != nil else {
            throw VPhoneNetworkError("Use a valid interface, optional numeric IP/port, 1–60 seconds, 64 KiB–64 MiB, and snap length 64–65535. ICMP has no port.")
        }
    }

    static func numericAddress(_ text: String) -> Data? {
        var v4 = in_addr(), v6 = in6_addr()
        if inet_pton(AF_INET, text, &v4) == 1 { return withUnsafeBytes(of: &v4) { Data($0) } }
        if inet_pton(AF_INET6, text, &v6) == 1 { return withUnsafeBytes(of: &v6) { Data($0) } }
        return nil
    }

    /// Filters are deliberately structured, not a partial tcpdump expression
    /// parser. Malformed/truncated headers never invent TCP/UDP ports.
    func matches(_ packet: Data, linkType: UInt32) -> Bool {
        if transport == .any && port == nil && address.isEmpty { return true }
        let b = [UInt8](packet)
        var offset: Int
        var version: Int
        func u16(_ at: Int) -> Int { Int(b[at]) << 8 | Int(b[at + 1]) }
        switch linkType {
        case 1:
            guard b.count >= 14 else { return false }
            offset = 14
            var type = u16(12)
            for _ in 0..<2 where type == 0x8100 || type == 0x88a8 {
                guard b.count >= offset + 4 else { return false }
                type = u16(offset + 2); offset += 4
            }
            guard type == 0x0800 || type == 0x86dd else { return false }
            version = type == 0x0800 ? 4 : 6
        case 0:
            guard b.count >= 5 else { return false }
            var family: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &family) { packet.copyBytes(to: $0, from: 0..<4) }
            guard family == AF_INET || family == AF_INET6 else { return false }
            offset = 4; version = family == AF_INET ? 4 : 6
        case 12, 101:
            guard let first = b.first else { return false }
            offset = 0; version = Int(first >> 4)
        default: return false
        }
        var proto: Int
        var portsAvailable = true
        let source: Data, destination: Data
        var end: Int
        if version == 4 {
            guard b.count >= offset + 20, b[offset] >> 4 == 4 else { return false }
            let header = Int(b[offset] & 15) * 4
            let total = u16(offset + 2)
            guard header >= 20, total >= header, b.count >= offset + header else { return false }
            end = min(b.count, offset + total)
            proto = Int(b[offset + 9])
            source = Data(b[(offset + 12)..<(offset + 16)])
            destination = Data(b[(offset + 16)..<(offset + 20)])
            portsAvailable = u16(offset + 6) & 0x1fff == 0
            offset += header
        } else if version == 6 {
            guard b.count >= offset + 40, b[offset] >> 4 == 6 else { return false }
            end = min(b.count, offset + 40 + u16(offset + 4))
            proto = Int(b[offset + 6])
            source = Data(b[(offset + 8)..<(offset + 24)])
            destination = Data(b[(offset + 24)..<(offset + 40)])
            offset += 40
            for _ in 0..<8 {
                if proto == 44 {
                    guard offset + 8 <= end else { return false }
                    portsAvailable = u16(offset + 2) & 0xfff8 == 0
                    proto = Int(b[offset]); offset += 8
                    if !portsAvailable { break }
                } else if proto == 0 || proto == 43 || proto == 60 || proto == 51 {
                    guard offset + 2 <= end else { return false }
                    let count = proto == 51 ? (Int(b[offset + 1]) + 2) * 4 : (Int(b[offset + 1]) + 1) * 8
                    guard offset + count <= end else { return false }
                    proto = Int(b[offset]); offset += count
                } else { break }
            }
        } else { return false }
        switch transport {
        case .any: break
        case .tcp: if proto != 6 { return false }
        case .udp: if proto != 17 { return false }
        case .icmp: if proto != 1 && proto != 58 { return false }
        }
        if !address.isEmpty {
            guard let expected = Self.numericAddress(address), expected == source || expected == destination else { return false }
        }
        if let port {
            guard portsAvailable, proto == 6 || proto == 17, offset + 4 <= end else { return false }
            return u16(offset) == port || u16(offset + 2) == port
        }
        return true
    }
}

struct VPhoneCaptureStatus: Codable, Sendable {
    enum Phase: String, Codable, Sendable { case idle, starting, running, completed, failed, interrupted }
    var id = ""
    var phase: Phase = .idle
    var request: VPhoneCaptureRequest?
    var startedAt = Date().timeIntervalSince1970
    var endedAt: Double?
    var packets: Int64 = 0
    var seen: Int64 = 0
    var matched: Int64 = 0
    var truncated: Int64 = 0
    var bytes: Int64 = 0
    var receivedByBPF: UInt32?
    var droppedByBPF: UInt32?
    var linkType: UInt32?
    var reason = ""
    var error: String?
    var active: Bool { phase == .starting || phase == .running }

    func validate() throws {
        if phase == .idle { guard id.isEmpty else { throw VPhoneNetworkError("Invalid idle capture state.") }; return }
        guard UUID(uuidString: id) != nil, let request else { throw VPhoneNetworkError("Invalid capture identity.") }
        try request.validate()
        guard startedAt.isFinite, endedAt?.isFinite ?? true, packets >= 0, seen >= matched, matched >= packets,
              truncated >= 0, truncated <= packets, bytes >= 0, bytes <= request.maximumBytes,
              linkType.map({ [0, 1, 101].contains($0) }) ?? true else { throw VPhoneNetworkError("Invalid capture counters.") }
    }
}

enum VPhonePCAP {
    struct Summary: Equatable { let packets: Int64; let bytes: Int64; let linkType: UInt32; let snapLength: UInt32 }
    static func word(_ value: UInt32) -> Data {
        var value = value.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    static func header(snapLength: UInt32, linkType: UInt32) -> Data {
        word(0xa1b2c3d4) + word(0x00040002) + word(0) + word(0) + word(snapLength) + word(linkType)
    }
    static func record(seconds: UInt32, microseconds: UInt32, packet: Data, originalLength: UInt32) -> Data {
        word(seconds) + word(microseconds) + word(UInt32(packet.count)) + word(originalLength) + packet
    }

    static func inspect(_ url: URL, maximumBytes: Int64 = 64 * 1024 * 1024) throws -> Summary {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw VPhoneNetworkError("Cannot open the PCAP file.") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              (24...maximumBytes).contains(metadata.st_size) else { throw VPhoneNetworkError("PCAP is not a bounded regular file.") }
        func read(_ count: Int) throws -> Data {
            let data = try file.read(upToCount: count) ?? Data()
            guard data.count == count else { throw VPhoneNetworkError("PCAP ended mid-record.") }
            return data
        }
        let head = [UInt8](try read(24))
        let little: Bool
        if Array(head[0..<4]) == [0xd4, 0xc3, 0xb2, 0xa1] { little = true }
        else if Array(head[0..<4]) == [0xa1, 0xb2, 0xc3, 0xd4] { little = false }
        else { throw VPhoneNetworkError("Unsupported PCAP magic.") }
        func u32(_ b: [UInt8], _ offset: Int) -> UInt32 {
            let bytes = little ? Array(b[offset..<(offset + 4)].reversed()) : Array(b[offset..<(offset + 4)])
            return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        let version = little ? head[4] == 2 && head[5] == 0 && head[6] == 4 && head[7] == 0 : head[4] == 0 && head[5] == 2 && head[6] == 0 && head[7] == 4
        let snap = u32(head, 16), link = u32(head, 20)
        guard version, (64...65535).contains(snap), [0, 1, 101].contains(link) else { throw VPhoneNetworkError("Unsupported PCAP header.") }
        var offset: Int64 = 24, packets: Int64 = 0
        while offset < metadata.st_size {
            guard metadata.st_size - offset >= 16 else { throw VPhoneNetworkError("PCAP has a partial record header.") }
            let record = [UInt8](try read(16))
            let count = u32(record, 8), original = u32(record, 12)
            guard u32(record, 4) < 1_000_000, count <= snap, count <= original,
                  Int64(count) <= metadata.st_size - offset - 16 else { throw VPhoneNetworkError("PCAP has a malformed packet record.") }
            try file.seek(toOffset: UInt64(offset + 16 + Int64(count)))
            offset += 16 + Int64(count); packets += 1
        }
        return Summary(packets: packets, bytes: metadata.st_size, linkType: link, snapLength: snap)
    }
}
