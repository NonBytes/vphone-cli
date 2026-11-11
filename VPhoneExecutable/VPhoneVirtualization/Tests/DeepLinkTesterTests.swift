import Foundation

@MainActor final class VPhoneGuestControl: VPhoneGuestControlling {
    var isConnected = true
    var guestIPAddress: String? { nil }
    var sandboxMachineScope: String { "" }
    var calls: [(String,String)] = []
    var refuse = false
    var slow = false
    func call(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        if method == "apps.binary", params["bundle_id"] as? String == "com.example.fixture" {
            return ["entitlements": ["com.apple.developer.associated-domains": ["applinks:example.test", "webcredentials:ignored.test"]]]
        }
        return [:]
    }
    func sendRequest(_ request: [String: Any]) async throws -> ([String: Any], Data?) { ([:], nil) }
    func uploadFile(path: String, data: Data, permissions: String) async throws {}
    func downloadFile(path: String) async throws -> Data { Data() }
    func pullFile(_ path: String, to localURL: URL, maximumBytes: Int?, permissions: Int?) async throws -> Int64 { 0 }
    func installIPA(localURL: URL) async throws -> String { "" }
    func screenshotJPEG() async throws -> Data { Data() }
    func guestProxy() async throws -> VPhoneProxyStatus { fatalError() }
    func runGuestToolReply(_ name: String, arguments: [String]) async throws -> [String: Any] { [:] }
    func makeFridaRelay(localPort: UInt16, guestPort: UInt16) async throws -> VPhoneFridaPortRelay { fatalError() }
    func appList() async throws -> [String:Any] { ["apps":[["bundle_id":"com.example.fixture","name":"Fixture","version":"1","build":"2"],["bundle_id":"com.example.other","name":"Other"]]] }
    func appURLSchemes() async throws -> [String:Any] { ["schemes":["com.example.fixture":["fixture","fixture","bad scheme"]]] }
    func appOpenURL(_ url: String, bundleID: String) async throws -> [String:Any] {
        calls.append((url,bundleID))
        if slow { try? await Task.sleep(for:.milliseconds(100)) }
        if refuse { throw VPhoneProxyError("fixture refusal") }
        return ["url":url,"bundle_id":bundleID]
    }
}
@main struct DeepLinkTesterTests {
    @MainActor static func main() async throws {
        func rejects(_ operation: () throws -> Void) { do { try operation(); fatalError("Invalid input accepted") } catch {} }
        for value in ["", "https//missing-colon", "1scheme://path", "a\n://bad", String(repeating:"a",count:8193)] { rejects { _ = try VPhoneDeepLinkURL.validated(value) } }
        for value in ["fixture://path?x=%zz", "fixture://path?x=%00", "fixture:opaque", "https://example.test/a%2Fb?q=a+b#part"] {
            let validated = try VPhoneDeepLinkURL.validated(value); precondition(validated == value)
        }
        var first = VPhoneDeepLinkParameter(); first.name = "a+b"; first.value = "x y&z=ไทย"
        var second = VPhoneDeepLinkParameter(); second.name = "a+b"; second.value = ""
        let built = try VPhoneDeepLinkURL.append([first,second],to:"fixture://host/path?existing=%2F#fragment")
        precondition(built.contains("existing=%2F&a%2Bb=x%20y%26z%3D%E0%B9%84%E0%B8%97%E0%B8%A2&a%2Bb=#fragment"))
        rejects { _ = try VPhoneDeepLinkURL.append(Array(repeating:first,count:33),to:"fixture://path") }
        let control = VPhoneGuestControl(), model = VPhoneDeepLinkTesterModel(control:control)
        await model.refresh(); model.selectedID = "com.example.fixture"
        precondition(model.declaredSchemes == ["fixture"] && model.rawURL == "fixture://")
        model.caseName = "Case A"; model.rawURL = "fixture://path?token=synthetic-fixture"; model.notes = "expected route"
        model.saveCase()
        precondition(model.archive.cases.count == 1 && control.calls.isEmpty, "Saving a case must not execute it")
        await model.openURL()
        precondition(control.calls.count == 1 && control.calls[0].0 == model.rawURL && control.calls[0].1 == "com.example.fixture")
        precondition(model.archive.history.count == 1 && model.archive.history[0].accepted)
        model.load(model.archive.cases[0]); precondition(control.calls.count == 1)
        control.refuse = true; await model.openURL()
        precondition(model.archive.history.count == 2 && !model.archive.history[0].accepted)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:folder) }
        let url = folder.appendingPathComponent("workspace.json")
        try VPhoneSandboxSnapshot.writeReport(model.archive.data(),to:url)
        let loaded = try VPhoneDeepLinkArchive.read(url)
        precondition(loaded.cases.count == 1 && loaded.history.count == 2 && loaded.cases[0].url == model.rawURL)
        precondition(control.calls.count == 2, "Reading a workspace must never execute its URLs")
        let link = folder.appendingPathComponent("symlink.json")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:url)
        rejects { _ = try VPhoneDeepLinkArchive.read(link) }
        var invalid = model.archive; invalid.schema = 2; rejects { _ = try invalid.data() }
        invalid = model.archive; invalid.cases.append(invalid.cases[0]); rejects { _ = try invalid.data() }
        invalid = model.archive
        invalid.cases = (0...100).map { _ in var test = model.archive.cases[0]; test.id = UUID().uuidString; return test }
        rejects { try invalid.validate() }
        let oversized = folder.appendingPathComponent("oversized.json")
        try Data(repeating:32,count:VPhoneDeepLinkArchive.maximumBytes + 1).write(to:oversized)
        rejects { _ = try VPhoneDeepLinkArchive.read(oversized) }
        rejects { _ = try VPhoneDeepLinkArchive.read(folder) }
        let missing = VPhoneDeepLinkCase(name:"Missing",bundleID:"com.example.missing",appName:"Missing",appVersion:"",appBuild:"",url:"fixture://missing",notes:"",savedAt:Date())
        model.load(missing); precondition(model.error != nil && control.calls.count == 2)
        control.refuse = false; control.slow = true
        let request = Task { await model.openURL() }
        while !model.opening { await Task.yield() }
        model.selectedID = "com.example.other"; model.close(); await request.value
        precondition(model.archive.history[0].test.bundleID == "com.example.fixture", "A delayed result must retain its original target")
        precondition(model.archive.history.count == 3, "Closing must not erase the fact that a URL was opened")
        let attrs = try FileManager.default.attributesOfItem(atPath:url.path)
        precondition((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        // Feature 4: Associated Domains, Fuzz Payloads, Batch Fuzzer, Filtered History & MASVS Findings
        VPhoneMASVSFindingStore.shared.clear()
        let domains = VPhoneDeepLinkFuzzer.associatedDomains(fromEntitlements: [
            "com.apple.developer.associated-domains": ["applinks:api.example.test", "applinks:*.example.test", "activitycontinuation:ignored.test"]
        ])
        precondition(domains == ["api.example.test"])
        let generatedPayloads = try VPhoneDeepLinkFuzzer.buildPayloads(
            baseURL: "fixture://open?target={PAYLOAD}",
            categories: [.openRedirect, .xss]
        )
        precondition(!generatedPayloads.isEmpty && generatedPayloads.count <= VPhoneDeepLinkFuzzer.maximumBatchSize)
        precondition(generatedPayloads.allSatisfy { !$0.url.contains("{PAYLOAD}") && $0.url.hasPrefix("fixture://open?target=") })

        let fuzzModel = VPhoneDeepLinkTesterModel(control: control)
        control.refuse = false; control.slow = false
        await fuzzModel.refresh()
        fuzzModel.selectedID = "com.example.fixture"
        await fuzzModel.refreshSelectedAppDomains()
        precondition(fuzzModel.associatedDomains == ["example.test"])
        fuzzModel.rawURL = "fixture://open?next={PAYLOAD}"
        fuzzModel.fuzzCategories = [.openRedirect]
        fuzzModel.fuzzDelayMilliseconds = 0
        await fuzzModel.runFuzzBatch()
        precondition(!fuzzModel.fuzzing && fuzzModel.fuzzCompleted == fuzzModel.fuzzTotal && fuzzModel.fuzzTotal > 0)
        precondition(fuzzModel.archive.history.count == fuzzModel.fuzzTotal)
        fuzzModel.historyFilter = "Accepted"
        precondition(fuzzModel.filteredHistory.count == fuzzModel.fuzzTotal)
        fuzzModel.historyFilter = "Failed"
        precondition(fuzzModel.filteredHistory.isEmpty)
        fuzzModel.historyFilter = "All"
        if let firstRun = fuzzModel.archive.history.first {
            fuzzModel.sendRunToFindings(firstRun)
            precondition(VPhoneMASVSFindingStore.shared.findings.count == 1)
            precondition(VPhoneMASVSFindingStore.shared.findings[0].category == .platform)
        }
        VPhoneMASVSFindingStore.shared.clear()

        print("Deep Link Tester checks passed: raw payload preservation, query encoding, no automatic replay, success/failure history, associated domains, payload fuzzer, target provenance, bounded archive and private export.")
    }
}
