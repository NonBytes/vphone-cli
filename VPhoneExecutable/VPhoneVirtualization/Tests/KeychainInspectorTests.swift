import Foundation

@MainActor final class VPhoneGuestControl: VPhoneGuestControlling {
    typealias KeychainIdentity = VPhoneGuestKeychainIdentity
    typealias KeychainResult = VPhoneGuestKeychainResult
    var isConnected = true
    var guestIPAddress: String? { nil }
    var sandboxMachineScope: String { "" }
    var entries: [[String: Any]] = []
    var reads: [KeychainIdentity] = []
    var updates: [(KeychainIdentity, String)] = []
    var deletes: [KeychainIdentity] = []
    var adds: [(String, String, String)] = []
    var value = "fixture-secret"
    var slow = false
    var denied = false
    func sendRequest(_ request: [String: Any]) async throws -> ([String: Any], Data?) {
        if let type = request["t"] as? String {
            if type == "keychain_add" {
                if denied { throw VPhoneProxyError("fixture add refusal") }
                adds.append((request["account"] as? String ?? "", request["service"] as? String ?? "", request["password"] as? String ?? ""))
                return (["ok": true], nil)
            } else if type == "keychain_update" {
                if denied { throw VPhoneProxyError("fixture update refusal") }
                let ident = KeychainIdentity(itemClass: request["class"] as? String ?? "genp", account: request["account"] as? String ?? "", service: request["service"] as? String ?? "", server: request["server"] as? String ?? "", accessGroup: request["group"] as? String ?? "")
                updates.append((ident, request["value"] as? String ?? ""))
                return (["ok": true], nil)
            } else if type == "keychain_delete" {
                if denied { throw VPhoneProxyError("fixture delete refusal") }
                let ident = KeychainIdentity(itemClass: request["class"] as? String ?? "genp", account: request["account"] as? String ?? "", service: request["service"] as? String ?? "", server: request["server"] as? String ?? "", accessGroup: request["group"] as? String ?? "")
                deletes.append(ident)
                return (["ok": true, "removed": true], nil)
            }
        }
        return ([:], nil)
    }
    func uploadFile(path: String, data: Data, permissions: String) async throws {}
    func downloadFile(path: String) async throws -> Data { Data() }
    func pullFile(_ path: String, to localURL: URL, maximumBytes: Int?, permissions: Int?) async throws -> Int64 { 0 }
    func installIPA(localURL: URL) async throws -> String { "" }
    func screenshotJPEG() async throws -> Data { Data() }
    func guestProxy() async throws -> VPhoneProxyStatus { fatalError() }
    func runGuestToolReply(_ name: String, arguments: [String]) async throws -> [String: Any] { [:] }
    func makeFridaRelay(localPort: UInt16, guestPort: UInt16) async throws -> VPhoneFridaPortRelay { fatalError() }
    func appList() async throws -> [String: Any] { ["apps":[]] }
    func call(_ method: String, params: [String: Any]) async throws -> [String: Any] { ["entitlements":["keychain-access-groups":["group.fixture"]]] }
    func listKeychainItems() async throws -> KeychainResult { .init(items:entries,diagnostics:["fixture metadata"]) }
    func keychainValue(of identity: KeychainIdentity) async throws -> String {
        reads.append(identity)
        if slow { try? await Task.sleep(for:.milliseconds(100)) }
        if denied { throw VPhoneProxyError("fixture refusal") }
        return value
    }
    func updateKeychainItem(_ identity: KeychainIdentity, value: String) async throws {
        if denied { throw VPhoneProxyError("fixture update refusal") }
        updates.append((identity, value))
    }
    func deleteKeychainItem(_ identity: KeychainIdentity) async throws -> Bool {
        if denied { throw VPhoneProxyError("fixture delete refusal") }
        deletes.append(identity)
        return true
    }
    func addKeychainItem(account: String, service: String, password: String) async throws {
        if denied { throw VPhoneProxyError("fixture add refusal") }
        adds.append((account, service, password))
    }
}
@main struct KeychainInspectorTests {
    @MainActor static func main() async throws {
        func entry(_ account: String, service: String = "service", group: String = "group.fixture", source: String = "security", itemClass: String = "genp") -> [String: Any] {
            ["class":itemClass,"account":account,"service":service,"accessGroup":group,"source":source,"protection":"ak","created":100.0]
        }
        precondition(VPhoneKeychainInspectionRow.groups(from:["entitlements":["keychain-access-groups":["group.fixture","*","$(AppIdentifierPrefix)foo","bad group","group.fixture"]]]) == ["group.fixture"])
        precondition(VPhoneKeychainInspectionRow.groups(from:["entitlements":["application-identifier":"TEAM.app"]]).isEmpty)
        let control = VPhoneGuestControl(), model = VPhoneKeychainInspectorModel(control:control)
        model.scope = "manual"; model.manualGroup = "group.fixture"
        control.entries = [entry("unique"),entry("elsewhere",group:"group.other"),entry("protected",source:"database"),entry("certificate",itemClass:"cert")]
        await model.inspect(values:false)
        precondition(model.rows.count == 3 && control.reads.isEmpty)
        await model.inspect(values:true)
        precondition(control.reads.count == 1 && control.reads[0].accessGroup == "group.fixture")
        precondition(model.rows.first?.value == "fixture-secret" && !model.reveal && !model.exportValues)
        let redacted = try model.reportData()
        precondition(!String(decoding:redacted,as:UTF8.self).contains("fixture-secret"))
        model.exportValues = true
        let withValues = try model.reportData()
        precondition(String(decoding:withValues,as:UTF8.self).contains("fixture-secret"))
        let snapshot = try JSONSerialization.jsonObject(with:model.reportData()) as! [String: Any]
        precondition(snapshot["groups"] as? [String] == ["group.fixture"])
        model.manualGroup = "group.changed"
        precondition(model.rows.isEmpty && model.capturedAt == nil, "Scope edits must clear old results synchronously")
        do { _ = try model.reportData(); fatalError("Exported stale scope") } catch {}
        model.manualGroup = "group.fixture"; control.reads = []
        control.entries = [entry("same",service:""),entry("same",service:"other"),entry("same",service:"other")]
        await model.inspect(values:true)
        precondition(control.reads.isEmpty && model.rows.allSatisfy { $0.value == nil && $0.valueState.contains("ambiguous") })
        control.entries = [entry("large")]; control.value = String(repeating:"x",count:65537)
        await model.inspect(values:true)
        precondition(model.truncated && model.rows[0].value == nil)
        control.value = ""; await model.inspect(values:true)
        precondition(model.rows[0].value == "" && model.rows[0].revealedValue.contains("empty") && model.rows[0].valueState.contains("legacy"))
        control.denied = true; await model.inspect(values:true)
        precondition(model.rows[0].value == nil && model.rows[0].valueState.contains("failed")); control.denied = false
        control.entries = (0..<501).map { entry("item\($0)") }
        await model.inspect(values:false)
        precondition(model.rows.count == 500 && model.truncated)
        control.entries = [entry("cancel")]; control.slow = true; control.value = "late-secret"
        let pending = Task { await model.inspect(values:true) }
        while !model.busy { await Task.yield() }
        model.clear(); await pending.value
        precondition(model.rows.isEmpty && model.capturedAt == nil && !model.reveal && !model.exportValues)
        model.manualGroup = "*"; control.reads = []; await model.inspect(values:true)
        precondition(control.reads.isEmpty && model.error != nil)
        model.scope = "app"; model.selectedID = "com.example.fixture"
        precondition(model.resolving && model.rows.isEmpty)
        await model.inspect(values:false)
        precondition(model.rows.isEmpty, "Scan must wait for the newly selected app's scope")
        while model.resolving { await Task.yield() }
        precondition(model.groups == ["group.fixture"])
        model.scope = "manual"
        precondition(!model.resolving && model.rows.isEmpty)

        // Mutating Keychain Operations & Frida Script Synthesis Tests
        try await model.addItem(account: "injected_user", service: "auth_svc", password: "pwned_password", accessGroup: "group.fixture")
        precondition(control.adds.count == 1 && control.adds[0].0 == "injected_user" && control.adds[0].2 == "pwned_password")
        precondition(model.rows.count == 1 && model.rows[0].account == "injected_user" && model.rows[0].value == "pwned_password")
        precondition(model.lastActionMessage?.contains("Added") == true)

        let addedID = model.rows[0].id
        try await model.updateItem(id: addedID, newValue: "escalated_token_999")
        precondition(control.updates.count == 1 && control.updates[0].1 == "escalated_token_999")
        precondition(model.rows[0].value == "escalated_token_999")
        precondition(model.lastActionMessage?.contains("Updated") == true)

        let addScript = model.generateFridaScript(action: .add, account: "test_acc", service: "test_svc", value: "test_val")
        precondition(addScript.contains("SecItemAdd") && addScript.contains("test_acc") && addScript.contains("test_svc"))

        let updateScript = model.generateFridaScript(action: .update, account: "test_acc", service: "test_svc", value: "new_val")
        precondition(updateScript.contains("SecItemUpdate") && updateScript.contains("new_val"))

        let deleteScript = model.generateFridaScript(action: .delete, account: "test_acc", service: "test_svc")
        precondition(deleteScript.contains("SecItemDelete") && deleteScript.contains("test_acc"))

        try await model.deleteItem(id: addedID)
        precondition(control.deletes.count == 1 && control.deletes[0].account == "injected_user")
        precondition(model.rows.isEmpty && model.selection.isEmpty)
        precondition(model.lastActionMessage?.contains("Deleted") == true)

        control.denied = true
        do {
            try await model.addItem(account: "denied", service: "svc", password: "p")
            fatalError("Denied addItem must throw")
        } catch {}
        control.denied = false

        print("Keychain Inspector fixtures passed: exact scope, metadata-only scan, ambiguity, redacted export, frozen provenance, value/row limits, refusal, cancellation, item editing, injection, and deletion.")
    }
}
