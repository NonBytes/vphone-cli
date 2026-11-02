import Foundation

extension VPhoneGuestControl {
    func guestProxy(_ request: VPhoneProxyRequest? = nil) async throws -> VPhoneProxyStatus {
        let root = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent().deletingLastPathComponent()
        let helper = root.appendingPathComponent("Resources/guest-resources/vphone-guest-proxy")
        let remote = "/private/var/tmp/vphone-guest-proxy"
        let arguments: [String]
        if let request {
            let request = try request.validated()
            arguments = ["apply", String(decoding: try JSONEncoder().encode(request), as: UTF8.self)]
        } else {
            arguments = ["read"]
        }
        // Upload on each operation: a guest reboot may have cleared /var/tmp.
        try await uploadFile(path: remote, data: Data(contentsOf: helper), permissions: "700")
        let encoded = String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self)
        let reply = try await call("script.eval", params: [
            "source": "proc.run(\"\(remote)\", \(encoded))", "timeout": 20,
        ])
        return try VPhoneProxyScriptResult.decode(reply)
    }
}
