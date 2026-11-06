import Foundation

struct VPhoneKeychainInspectionRow: Codable, Identifiable, Sendable {
    let id: String
    let itemClass: String
    let account: String
    let service: String
    let server: String
    let label: String
    let accessGroup: String
    let accessibility: String
    let source: String
    let created: Double?
    let modified: Double?
    var value: String?
    var valueState: String
    var encoding: String?
    var revealedValue: String { value.map { $0.isEmpty ? "(empty returned string)" : $0 } ?? valueState }

    /// Exact identity for the existing guest API. No broad class/group-only
    /// query is issued, and duplicate identities are not guessed at.
    var identityKey: String { [itemClass,account,service,server,accessGroup].map { "\($0.utf8.count):\($0)" }.joined() }
    var readable: Bool { source == "security" && ["genp","inet"].contains(itemClass) && !accessGroup.isEmpty && (!account.isEmpty || !service.isEmpty || !server.isEmpty) }
    func queryMatches(_ candidate: Self) -> Bool {
        candidate.source == "security" && candidate.itemClass == itemClass && candidate.accessGroup == accessGroup
            && (account.isEmpty || candidate.account == account)
            && (service.isEmpty || candidate.service == service)
            && (server.isEmpty || candidate.server == server)
    }
    func redacted() -> Self {
        var result = self; result.value = nil
        if value != nil { result.valueState = "redacted" }
        return result
    }
    static func groups(from info: [String: Any]) -> [String] {
        let entitlements = info["entitlements"] as? [String: Any] ?? [:]
        return Array(Set((entitlements["keychain-access-groups"] as? [String] ?? []).filter(validGroup))).sorted()
    }
    static func validGroup(_ group: String) -> Bool {
        !group.isEmpty && group.utf8.count <= 255 && !group.contains("*") && !group.contains("$(")
            && !group.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }
    }
}
