import Foundation

struct Failure: Error { let message: String }
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure(message: message) }
}
func rejects(_ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw Failure(message: "Invalid input unexpectedly succeeded")
}

@main struct ProxyTests {
    static func main() throws {
        for host in ["192.168.64.1", "localhost", "burp.local", "::1", "[2001:db8::1]"] {
            let request = try VPhoneProxyRequest(enabled: true, host: host, port: 8080).validated()
            try expect(!request.host.contains("["), "IPv6 brackets should be normalized")
        }
        for host in ["", "http://localhost", "localhost:8080", "a b", "a\nb", "999.999.0.1", "-bad.local", "foo..bar", "$(echo nope)"] {
            try rejects { _ = try VPhoneProxyRequest(enabled: true, host: host, port: 8080).validated() }
        }
        for port in [0, -1, 65536] {
            try rejects { _ = try VPhoneProxyRequest(enabled: true, host: "localhost", port: port).validated() }
        }
        let original: [String: Any] = ["ExceptionsList": ["*.local"], "ExcludeSimpleHostnames": 1,
            "ProxyAutoConfigEnable": 1, "ProxyAutoConfigURLString": "https://example.invalid/proxy.pac"]
        let request = VPhoneProxyRequest(enabled: true, host: "192.168.64.1", port: 8080)
        let applied = try request.updating(original)
        try expect(applied["HTTPEnable"] as? Int == 1 && applied["HTTPSEnable"] as? Int == 1, "Both protocols must be enabled")
        try expect(applied["HTTPSPort"] as? Int == 8080, "HTTPS port missing")
        try expect(applied["ProxyAutoConfigEnable"] as? Int == 0, "PAC must not override manual proxy")
        try expect(applied["ExceptionsList"] as? [String] == ["*.local"], "Bypass list changed")
        try expect(applied["ProxyAutoConfigURLString"] as? String == original["ProxyAutoConfigURLString"] as? String, "PAC URL was lost")
        let disabled = try VPhoneProxyRequest(enabled: false, host: "", port: 0).updating(applied)
        try expect(disabled["HTTPEnable"] as? Int == 0 && disabled["HTTPSEnable"] as? Int == 0, "Off must disable both protocols")
        try expect(disabled["HTTPProxy"] as? String == "192.168.64.1", "Off must retain saved server")
        try expect(disabled["HTTPPort"] as? Int == 8080, "Off must retain saved port")
        let state = try VPhoneProxyStatus(proxies: [applied])
        try expect(state.enabled && !state.mixed && !state.automatic, "Applied state mismatch")
        try expect(tryState(disabled)?.enabled == false, "Disabled state mismatch")
        var different = applied
        different["HTTPSPort"] = 9090
        try expect(tryState(different)?.mixed == true, "Different protocols must be reported")
        let differentServices = try VPhoneProxyStatus(proxies: [applied, disabled])
        try expect(differentServices.mixed, "Different services must be reported")
        try rejects { _ = try VPhoneProxyStatus(proxies: []) }
        try expect(tryState(original)?.automatic == true, "Automatic proxy missing")
        let stdout = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        func reply(_ status: Int, _ stdout: String, _ stderr: String = "", signal: Any = NSNull()) throws -> [String: Any] {
            let data = try JSONSerialization.data(withJSONObject: ["status": status, "stdout": stdout, "stderr": stderr, "signal": signal])
            return ["ok": true, "crashed": false, "result": String(decoding: data, as: UTF8.self)]
        }
        let decoded = try VPhoneProxyScriptResult.decode(reply(0, stdout))
        try expect(decoded.enabled && decoded.port == 8080, "Nested process result failed")
        try rejects { _ = try VPhoneProxyScriptResult.decode(["ok": false, "error": "unsupported"]) }
        try rejects { _ = try VPhoneProxyScriptResult.decode(["ok": true, "crashed": true]) }
        try rejects { _ = try VPhoneProxyScriptResult.decode(reply(1, stdout, "permission denied")) }
        try rejects { _ = try VPhoneProxyScriptResult.decode(reply(0, stdout, signal: 9)) }
        try rejects { _ = try VPhoneProxyScriptResult.decode(reply(0, "not json")) }
        print("PASS: proxy validation, preservation, protocol/service differences and nested RPC failures")
    }
    static func tryState(_ proxy: [String: Any]) -> VPhoneProxyStatus? { try? VPhoneProxyStatus(proxies: [proxy]) }
}
