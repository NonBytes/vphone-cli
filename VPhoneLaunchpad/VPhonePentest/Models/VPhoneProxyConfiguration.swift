import Darwin
import Foundation

struct VPhoneProxyRequest: Codable, Equatable {
    var enabled: Bool
    var host: String
    var port: Int

    func validated() throws -> Self {
        guard enabled else { return self }
        var host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        var address = in6_addr()
        let ipv6 = host.withCString { inet_pton(AF_INET6, $0, &address) == 1 }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let dns = !host.isEmpty && host.utf8.count <= 253 && labels.allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
        }
        var ipv4Address = in_addr()
        let numeric = !host.isEmpty && host.utf8.allSatisfy { (48...57).contains($0) || $0 == 46 }
        let ipv4 = host.withCString { inet_pton(AF_INET, $0, &ipv4Address) == 1 }
        guard ipv6 || (dns && (!numeric || ipv4)) else {
            throw VPhoneProxyError("Enter an IP address or hostname without a URL or port.")
        }
        guard (1...65535).contains(port) else { throw VPhoneProxyError("Port must be between 1 and 65535.") }
        return Self(enabled: enabled, host: host, port: port)
    }

    func updating(_ original: [String: Any]) throws -> [String: Any] {
        let value = try validated()
        var proxy = original
        proxy["HTTPEnable"] = value.enabled ? 1 : 0
        proxy["HTTPSEnable"] = value.enabled ? 1 : 0
        proxy["ProxyAutoConfigEnable"] = 0
        proxy["ProxyAutoDiscoveryEnable"] = 0
        if value.enabled {
            proxy["HTTPProxy"] = value.host
            proxy["HTTPSProxy"] = value.host
            proxy["HTTPPort"] = value.port
            proxy["HTTPSPort"] = value.port
        }
        return proxy
    }
}

struct VPhoneProxyStatus: Codable {
    var enabled: Bool
    var host: String
    var port: Int
    var mixed: Bool
    var automatic: Bool
    var services: Int

    init(proxies: [[String: Any]]) throws {
        guard !proxies.isEmpty else { throw VPhoneProxyError("No guest network interface was found.") }
        let first = proxies.first(where: {
            ($0["HTTPEnable"] as? NSNumber)?.boolValue == true || ($0["HTTPSEnable"] as? NSNumber)?.boolValue == true
        }) ?? proxies[0]
        let http = (first["HTTPEnable"] as? NSNumber)?.boolValue == true
        let https = (first["HTTPSEnable"] as? NSNumber)?.boolValue == true
        host = first[http ? "HTTPProxy" : "HTTPSProxy"] as? String
            ?? first["HTTPProxy"] as? String ?? ""
        port = first[http ? "HTTPPort" : "HTTPSPort"] as? Int ?? first["HTTPPort"] as? Int ?? 0
        automatic = proxies.contains {
            ($0["ProxyAutoConfigEnable"] as? NSNumber)?.boolValue == true
                || ($0["ProxyAutoDiscoveryEnable"] as? NSNumber)?.boolValue == true
        }
        enabled = http || https || automatic
        mixed = http != https || (http && https && (
            first["HTTPProxy"] as? String != first["HTTPSProxy"] as? String
                || first["HTTPPort"] as? Int != first["HTTPSPort"] as? Int))
            || proxies.dropFirst().contains { !NSDictionary(dictionary: first).isEqual(to: $0) }
        services = proxies.count
    }
}

struct VPhoneProxyError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
