import Foundation

@main struct FridaReleaseTests {
    static func main() async throws {
        for value in ["17.25.2", "1.0.0"] { precondition(VPhoneFridaRelease.validVersion(value)) }
        for value in ["../latest", "17.2", "v17.25.2", "17.25.2/other", "17.25.2\n"] { precondition(!VPhoneFridaRelease.validVersion(value)) }
        let release = VPhoneFridaRelease(tag_name: "17.25.2", assets: [
            .init(name: "frida_17.25.2_iphoneos-arm.deb", browser_download_url: URL(string: "https://evil.example/file")!, size: 10, digest: "sha256:" + String(repeating: "0", count: 64))
        ])
        precondition(release.asset != nil)
        do { _ = try await release.download(); fatalError("Accepted nonofficial download URL") } catch { }
        let unsupported = VPhoneFridaRelease(tag_name: "17.25.2", assets: [])
        precondition(unsupported.asset == nil)
        do { _ = try await VPhoneFridaRelease.fetch("../latest"); fatalError("Accepted invalid tag") } catch { }
        print("PASS: version validation, official asset selection and URL rejection")
        if CommandLine.arguments.contains("--live") {
            let live = try await VPhoneFridaRelease.fetch("latest")
            let files = try await live.download()
            precondition(files.server.count > 100_000 && files.agent.count > 100_000)
            print("PASS: official release \(live.tag_name) download, SHA-256, extraction, binary signatures")
        }
    }
}
