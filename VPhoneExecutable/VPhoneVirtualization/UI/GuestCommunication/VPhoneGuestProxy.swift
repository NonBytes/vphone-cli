import Foundation
import VPhoneCoreKit
#if canImport(VPhonePentestKit)
import VPhonePentestKit
#endif

extension VPhoneGuestControl {
    func guestProxy() async throws -> VPhoneProxyStatus {
        try await guestProxy(nil)
    }

    func guestProxy(_ request: VPhoneProxyRequest?) async throws -> VPhoneProxyStatus {
        let arguments: [String]
        if let request {
            let request = try request.validated()
            arguments = ["apply", String(decoding: try JSONEncoder().encode(request), as: UTF8.self)]
        } else {
            arguments = ["read"]
        }
        return try await guestTool("vphone-guest-proxy", arguments: arguments, as: VPhoneProxyStatus.self)
    }

    func guestCACertificates(_ arguments: [String] = ["list"]) async throws -> VPhoneCAList {
        try await guestTool("vphone-guest-ca", arguments: arguments, as: VPhoneCAList.self)
    }

    func runGuestToolReply(_ name: String, arguments: [String]) async throws -> [String: Any] {
        let root = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent().deletingLastPathComponent()
        let helper = root.appendingPathComponent("Resources/guest-resources/\(name)")
        let remote = "/private/var/tmp/\(name)"
        // Upload on each operation: a guest reboot may have cleared /var/tmp.
        try await uploadFile(path: remote, data: Data(contentsOf: helper), permissions: "700")
        let encoded = String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)
        return try await call("script.eval", params: [
            "source": "proc.run(\"\(remote)\", \(encoded))", "timeout": 20,
        ])
    }

    func makeFridaRelay(localPort: UInt16, guestPort: UInt16) async throws -> VPhoneFridaPortRelay {
        try VPhoneFridaPortRelay(localPort: localPort) { output, end in
            try await VPhoneGuestShellChannel.openPort(control: self, port: guestPort, onOutput: output, onEnd: { _ in end() })
        }
    }

    func openDownloadDirectory(_ url: URL) throws -> any VPhoneDownloadDirectoryWriting {
        try _VPhoneVMDownloadDirectory(url: url)
    }

    func markDownloadQuarantined(_ url: URL) {
        VPhoneHostDownloadDirectory.markQuarantined(url)
    }
}

private final class _VPhoneVMDownloadDirectory: VPhoneDownloadDirectoryWriting {
    private let base: VPhoneHostDownloadDirectory

    init(url: URL) throws {
        base = try VPhoneHostDownloadDirectory(url: url)
    }

    func writeUniqueQuarantinedFile(named name: String, data: Data) throws {
        let dest = try base.writeUniqueFile(named: name, data: data)
        VPhoneHostDownloadDirectory.markQuarantined(dest)
    }
}
