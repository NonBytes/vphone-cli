import Foundation

enum VPhoneLocalization { static let bundle = Bundle.main }
struct VPhoneGuestToolStatus { let message: String; let isError: Bool }

/// Only supplies transport responses to the real ConsoleModel. No guest API
/// implementation is replaced in the shipped bundle.
@MainActor final class VPhoneGuestControl {
    var isConnected = true
    var response: [String: Any] = [:]
    var parameters: [String: Any] = [:]
    var slow = false
    var slowExecutable = false
    func call(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        if method == "apps.info" {
            let bundleID = params["bundle_id"] as? String ?? ""
            if slowExecutable && bundleID == "com.example.a" { try? await Task.sleep(for: .milliseconds(100)) }
            return ["executable":bundleID == "com.example.a" ? "AppA" : "AppB"]
        }
        precondition(method == "logs.syslog")
        parameters = params
        if slow { try? await Task.sleep(for: .milliseconds(100)) }
        return response
    }
}

@MainActor final class VPhoneCrashLogsModel {
    let bundleID: String?
    init(control: VPhoneGuestControl, bundleID: String? = nil) { self.bundleID = bundleID }
}

@main struct AppLogsTests {
    @MainActor static func main() async throws {
        let scope = try VPhoneAppLogScope(bundleID: "com.example.probe", executable: "/Applications/Probe.app/Probe")
        precondition(scope.process == "Probe" && scope.includes(process: "Probe"))
        for process in ["ProbeHelper", "OtherProbe", "", "probe"] { precondition(!scope.includes(process: process)) }
        for executable in ["", ".", "..", "bad\nname"] {
            do { _ = try VPhoneAppLogScope(bundleID: "com.example.probe", executable: executable); fatalError("Invalid scope accepted") } catch {}
        }
        let control = VPhoneGuestControl()
        let model = VPhoneConsoleModel(control: control, appScope: scope)
        precondition(!model.isRunning, "Scoped logs must require explicit Start")
        model.processFilter = "Other"
        precondition(model.captureParameters["process"] as? String == "Probe", "Editable filters cannot widen app scope")
        precondition(model.captureParameters(includeSession: false)["session"] == nil, "One-shot refresh must omit session")
        let firstSession = model.captureParameters(includeSession: true)["session"] as? String
        precondition(firstSession != nil && model.captureParameters(includeSession: true)["session"] as? String == firstSession, "Continuous polls reuse the active session")
        model.isRunning = true; model.isRunning = false
        let rotatedAfterPause = model.captureParameters(includeSession: true)["session"] as? String
        precondition(rotatedAfterPause != nil && rotatedAfterPause != firstSession, "Pausing must rotate the log session")
        model.levelFilter = .error
        let rotatedAfterFilter = model.captureParameters(includeSession: true)["session"] as? String
        precondition(rotatedAfterFilter != nil && rotatedAfterFilter != rotatedAfterPause, "Changing level filter must rotate the log session")
        model.levelFilter = .all
        control.response = ["entries": [
            ["process": "Probe", "pid": 12, "message": "old process"],
            ["process": "ProbeHelper", "pid": 13, "message": "other process"],
            ["process": "Probe", "pid": 14, "message": "relaunch"],
        ], "truncated": true]
        await model.captureOnce()
        precondition(model.entries.count == 2 && model.entries.map(\.pid) == [12,14])
        precondition(model.lastCaptureTruncated)
        model.searchText = "relaunch"
        precondition(model.visibleEntries.count == 1 && model.visibleEntries[0].pid == 14)
        model.clear(); model.searchText = ""
        model.apply(syslogResult: ["entries": (0..<10050).map { ["process": "Probe", "message": "line \($0)"] }])
        precondition(model.entries.count == VPhoneConsoleModel.maximumEntries)
        model.clear(); control.slow = true
        let pending = Task { await model.captureOnce() }
        await Task.yield(); pending.cancel(); await pending.value
        precondition(model.entries.isEmpty, "Cancelled capture must not append late results")
        let general = VPhoneConsoleModel(control: control)
        precondition(general.isRunning && general.appScope == nil)
        general.apply(syslogResult: ["entries": [["process":"Anything", "message":"general console unchanged"]]])
        precondition(general.entries.count == 1)

        let ips = "{\"app_name\":\"Probe\",\"bundleID\":\"com.example.probe\"}\n{\"bundleInfo\":{\"CFBundleIdentifier\":\"com.example.probe\"}}"
        precondition(VPhoneCrashIdentity.bundleID(in: ips) == scope.bundleID)
        let bodyOnly = "{\"app_name\":\"Probe\"}\n{\"bundleInfo\":{\"CFBundleIdentifier\":\"com.example.other\"}}"
        precondition(VPhoneCrashIdentity.bundleID(in: bodyOnly) == "com.example.other")
        precondition(VPhoneCrashIdentity.bundleID(in: "Process: Probe\nIdentifier: com.example.legacy\n") == "com.example.legacy")
        precondition(VPhoneCrashIdentity.bundleID(in: "Process: Probe\nPath: /Applications/Probe.app\n") == nil)
        precondition(VPhoneCrashIdentity.bundleID(in: "{\"app_name\":\"Probe\"}\n{broken") == nil)
        let fields = VPhoneCrashReportContent.Fields(crashResult: ["path":"/fixture.ips", "content":ips, "size":ips.utf8.count, "truncated":false])!
        let content = VPhoneCrashReportContent(fields)
        precondition(content.reportedBundleID == scope.bundleID && content.rawText == ips && content.isReindented)
        let truncated = VPhoneCrashReportContent.Fields(crashResult: ["path":"/partial.ips", "content":"{\"bundleID\":\"com.example.probe\"}\n{broken", "truncated":true])!
        precondition(VPhoneCrashReportContent(truncated).truncated)
        let browser = VPhoneAppLogsModel(control: control)
        browser.apps = ["com.example.a", "com.example.b"].map { VPhoneAppRecord(json:["bundle_id":$0, "name":$0])! }
        control.slowExecutable = true
        browser.selectedID = "com.example.a"
        let old = Task { await browser.configure() }
        while !browser.resolving { await Task.yield() }
        browser.selectedID = "com.example.b"
        await browser.configure(); await old.value
        precondition(browser.console?.appScope?.bundleID == "com.example.b")
        precondition(browser.crashes?.bundleID == "com.example.b", "Stale app response must not replace the selected scope")
        browser.console?.isRunning = true
        await browser.configure()
        precondition(browser.console?.isRunning == false, "Reload App Scope must pause the new console")
        browser.selectedID = "com.example.a"
        let closing = Task { await browser.configure() }
        while !browser.resolving { await Task.yield() }
        browser.close(); await closing.value
        precondition(browser.console == nil, "Closing must ignore a pending scope response")
        print("App logs fixtures passed: explicit Start, exact process scope, PID relaunch, row cap, cancellation, search, crash identity and raw text preservation.")
    }
}
