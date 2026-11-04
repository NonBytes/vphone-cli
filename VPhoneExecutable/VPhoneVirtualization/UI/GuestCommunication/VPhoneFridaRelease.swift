import CryptoKit
import Foundation

struct VPhoneFridaRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let browser_download_url: URL
        let size: Int
        let digest: String?
    }
    let tag_name: String
    let assets: [Asset]

    static func validVersion(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+\z"#, options: .regularExpression) != nil
    }
    var asset: Asset? { assets.first { $0.name == "frida_\(tag_name)_iphoneos-arm.deb" } }
    static func fetch(_ version: String) async throws -> Self {
        guard version == "latest" || validVersion(version) else { throw VPhoneProxyError("Enter latest or a version such as 17.25.2.") }
        let path = version == "latest" ? "latest" : "tags/" + version
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/frida/frida/releases/" + path)!)
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("VPhone-Frida-Manager", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw VPhoneProxyError("GitHub release lookup failed (not found, rate limited, or unavailable). Try again later.") }
        let release = try JSONDecoder().decode(Self.self, from: data)
        guard validVersion(release.tag_name), release.asset != nil else { throw VPhoneProxyError("This release has no supported iOS server package.") }
        return release
    }

    func download() async throws -> (server: Data, agent: Data) {
        guard let asset, asset.size > 0, asset.size <= 100 * 1024 * 1024,
              asset.browser_download_url.scheme == "https", asset.browser_download_url.host == "github.com",
              asset.browser_download_url.path == "/frida/frida/releases/download/\(tag_name)/\(asset.name)",
              let digest = asset.digest, digest.range(of: #"^sha256:[0-9a-f]{64}\z"#, options: .regularExpression) != nil else {
            throw VPhoneProxyError("The release asset has no valid SHA-256 digest or download URL.")
        }
        var request = URLRequest(url: asset.browser_download_url)
        request.timeoutInterval = 180
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw VPhoneProxyError("Frida download failed.") }
        let archive = try Data(contentsOf: temporary, options: .mappedIfSafe)
        let hash = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard archive.count == asset.size, "sha256:" + hash == digest else { throw VPhoneProxyError("Frida package size or SHA-256 verification failed.") }
        return try await Task.detached {
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("vphone-frida-" + UUID().uuidString)
            try fm.createDirectory(at: work, withIntermediateDirectories: false)
            defer { try? fm.removeItem(at: work) }
            let deb = work.appendingPathComponent("package.deb")
            try archive.write(to: deb)
            let payload = work.appendingPathComponent("data.tar.xz")
            try Self.member("data.tar.xz", archive: deb, output: payload)
            let server = work.appendingPathComponent("frida-server")
            let agent = work.appendingPathComponent("frida-agent.dylib")
            try Self.member("./usr/sbin/frida-server", archive: payload, output: server)
            try Self.member("./usr/lib/frida-1.0/frida-agent.dylib", archive: payload, output: agent)
            for file in [server, agent] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                process.arguments = ["--verify", "--all-architectures", file.path]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run(); process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw VPhoneProxyError("Frida binary signature verification failed.") }
            }
            return (try Data(contentsOf: server), try Data(contentsOf: agent))
        }.value
    }

    // Read fixed members only; never unpack arbitrary paths from the package.
    private static func member(_ name: String, archive: URL, output: URL) throws {
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xOf", archive.path, name]
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard process.terminationStatus == 0, size > 0, size <= 256 * 1024 * 1024 else { throw VPhoneProxyError("Cannot read the supported Frida package layout.") }
    }
}
