import Foundation
#if canImport(VPhonePentestKit)
import VPhonePentestKit
#endif

extension VPhoneGuestControl {
    func guestProxy(_ request: VPhoneProxyRequest? = nil) async throws -> VPhoneProxyStatus {
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

    func guestTool<T: Decodable>(_ name: String, arguments: [String], as type: T.Type) async throws -> T {
        let root = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent().deletingLastPathComponent()
        let helper = root.appendingPathComponent("Resources/guest-resources/\(name)")
        let remote = "/private/var/tmp/\(name)"
        // Upload on each operation: a guest reboot may have cleared /var/tmp.
        try await uploadFile(path: remote, data: Data(contentsOf: helper), permissions: "700")
        let encoded = String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)
        let reply = try await call("script.eval", params: [
            "source": "proc.run(\"\(remote)\", \(encoded))", "timeout": 20,
        ])
        return try VPhoneProxyScriptResult.decode(reply, as: type)
    }
}
