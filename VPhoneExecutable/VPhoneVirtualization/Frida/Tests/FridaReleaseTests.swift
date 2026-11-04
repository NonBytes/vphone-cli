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
        func macho(platform: UInt32 = 2, type: UInt32 = 2) -> Data {
            var words: [UInt32] = [0xfeedfacf, 0x0100000c, 0, type, 1, 24, 0, 0, 0x32, 24, platform, 0, 0, 0]
            return words.withUnsafeMutableBytes { Data($0) }
        }
        try VPhoneFridaCustom.validate(macho(), executable: true)
        try VPhoneFridaCustom.validate(macho(type: 6), executable: false)
        for data in [Data(), Data("ELF".utf8), macho(platform: 1), macho(platform: 7), macho(type: 6), Data(macho().prefix(40))] {
            do { try VPhoneFridaCustom.validate(data, executable: true); fatalError("Accepted incompatible custom server") } catch { }
        }
        do { try VPhoneFridaCustom.validate(macho(), executable: false); fatalError("Accepted executable as agent") } catch { }
        print("PASS: version validation, official asset selection, URL rejection and custom iOS Mach-O validation")
        if let at = CommandLine.arguments.firstIndex(of: "--custom"), CommandLine.arguments.count > at + 2 {
            let files = try VPhoneFridaCustom.load(server: URL(fileURLWithPath: CommandLine.arguments[at + 1]), agent: URL(fileURLWithPath: CommandLine.arguments[at + 2]))
            precondition(files.server.count > 100_000 && files.agent!.count > 100_000)
            print("PASS: selected custom server and matching agent signatures")
        }

        if CommandLine.arguments.contains("--live") {
            let versions = try await VPhoneFridaRelease.versions()
            precondition(!versions.isEmpty && versions.allSatisfy(VPhoneFridaRelease.validVersion))
            let live = try await VPhoneFridaRelease.fetch("latest")
            let files = try await live.download()
            precondition(files.server.count > 100_000 && files.agent.count > 100_000)
            print("PASS: official release \(live.tag_name) download, SHA-256, extraction, binary signatures")
        }
    }
}
