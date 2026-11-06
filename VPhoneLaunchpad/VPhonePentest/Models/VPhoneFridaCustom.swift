import Foundation

/// Inspect custom binaries as data. Never execute an iOS server on the Mac.
enum VPhoneFridaCustom {
    static let maximumSize = 256 * 1024 * 1024

    static func load(server: URL, agent: URL?) throws -> (server: Data, agent: Data?) {
        func read(_ url: URL, executable: Bool) throws -> Data {
            let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard size.isRegularFile == true, let count = size.fileSize, count > 0, count <= maximumSize else {
                throw VPhoneProxyError("Select an iOS Mach-O file smaller than 256 MB.")
            }
            let data = try Data(contentsOf: url)
            try validate(data, executable: executable)
            // Verify the exact bytes that will be uploaded, even if the selected file changes.
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("vphone-custom-frida-" + UUID().uuidString)
            try data.write(to: copy)
            defer { try? FileManager.default.removeItem(at: copy) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = ["--verify", "--all-architectures", copy.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw VPhoneProxyError("The custom binary has an invalid or missing code signature. Sign the iOS binary before importing it.") }
            return data
        }
        return (try read(server, executable: true), try agent.map { try read($0, executable: false) })
    }

    static func validate(_ data: Data, executable: Bool) throws {
        guard data.count >= 32, data.count <= maximumSize else { throw VPhoneProxyError("Invalid custom binary size.") }
        func u32(_ offset: Int, big: Bool = false) -> UInt32? {
            guard offset >= 0, offset <= data.count - 4 else { return nil }
            let b = data[offset..<(offset + 4)].map(UInt32.init)
            return big ? b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3] : b[3] << 24 | b[2] << 16 | b[1] << 8 | b[0]
        }
        func slice(_ offset: Int, _ size: Int) -> Bool {
            guard offset >= 0, size >= 32, offset <= data.count - size,
                  u32(offset) == 0xfeedfacf, u32(offset + 4) == 0x0100000c,
                  u32(offset + 12) == (executable ? 2 : 6),
                  let count = u32(offset + 16), count <= 4096,
                  let length = u32(offset + 20), Int(length) <= size - 32 else { return false }
            var cursor = offset + 32
            let end = cursor + Int(length)
            var ios = false
            for _ in 0..<count {
                guard cursor <= end - 8, let command = u32(cursor), let length = u32(cursor + 4), length >= 8, Int(length) <= end - cursor else { return false }
                if command == 0x32 {
                    guard length >= 24, u32(cursor + 8) == 2 else { return false }
                    ios = true
                } else if command == 0x25 {
                    guard length >= 16 else { return false }
                    ios = true
                }
                cursor += Int(length)
            }
            return ios && cursor == end
        }
        if slice(0, data.count) { return }
        if u32(0, big: true) == 0xcafebabe, let count = u32(4, big: true), count <= 32 {
            for index in 0..<Int(count) {
                let at = 8 + index * 20
                guard at <= data.count - 20 else { break }
                if u32(at, big: true) == 0x0100000c, let offset = u32(at + 8, big: true), let size = u32(at + 12, big: true), slice(Int(offset), Int(size)) { return }
            }
        }
        throw VPhoneProxyError(executable ? "Select an iOS arm64 frida-server executable, not a Mac, Android or simulator binary." : "Select a matching iOS arm64 frida-agent.dylib.")
    }
}
