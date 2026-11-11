import Foundation

@MainActor final class VPhoneGuestControl: VPhoneGuestControlling {
    typealias KeychainIdentity = VPhoneGuestKeychainIdentity
    typealias KeychainResult = VPhoneGuestKeychainResult
    var isConnected = true
    var guestIPAddress: String? { nil }
    var sandboxMachineScope: String { "" }
    var entries: [[String: Any]] = []
    var reads: [KeychainIdentity] = []
    var value = "fixture-secret"
    var slow = false
    var denied = false
    func sendRequest(_ request: [String: Any]) async throws -> ([String: Any], Data?) { ([:], nil) }
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
        print("Keychain Inspector fixtures passed: exact scope, metadata-only scan, ambiguity, redacted export, frozen provenance, value/row limits, refusal and cancellation.")
    }
}
