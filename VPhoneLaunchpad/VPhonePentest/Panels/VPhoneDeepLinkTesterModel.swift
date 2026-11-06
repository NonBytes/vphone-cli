import AppKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class VPhoneDeepLinkTesterModel {
    let control: VPhoneGuestControl
    var apps: [VPhoneAppRecord] = []
    var schemes: [String:[String]] = [:]
    var selectedID = "" { didSet { if selectedID != oldValue { resetEditor() } } }
    var rawURL = ""
    var caseName = ""
    var notes = ""
    var parameters: [VPhoneDeepLinkParameter] = []
    var archive = VPhoneDeepLinkArchive()
    var selectedCase: String?
    var selectedRun: String?
    var refreshing = false
    var opening = false
    var error: String?
    var message = ""
    private var generation = 0
    var selectedApp: VPhoneAppRecord? { apps.first { $0.bundleID == selectedID } }
    var declaredSchemes: [String] { schemes[selectedID] ?? [] }
    init(control: VPhoneGuestControl) { self.control = control }
    func resetEditor() {
        rawURL = declaredSchemes.first.map { $0 + "://" } ?? ""
        caseName = ""; notes = ""; parameters = []; error = nil; message = ""
    }
    func close() { generation += 1 }
    func refresh() async {
        guard !refreshing, !opening, control.isConnected else { return }
        refreshing = true; let operation = generation; defer { refreshing = false }
        do {
            let list = try await control.appList()
            guard operation == generation else { return }
            apps = list.objects("apps").compactMap(VPhoneAppRecord.init(json:)).sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            if selectedApp == nil { selectedID = "" }
            let result = try await control.appURLSchemes()
            guard operation == generation else { return }
            schemes = (result["schemes"] as? [String:[String]] ?? [:]).mapValues { Array(Set($0.filter(VPhoneDeepLinkURL.validScheme))).sorted() }
            if rawURL.isEmpty { rawURL = declaredSchemes.first.map { $0 + "://" } ?? "" }
            error = nil
        } catch { if operation == generation { self.error = "Unable to refresh apps/schemes: " + error.localizedDescription } }
    }
    func applyParameters() {
        do { rawURL = try VPhoneDeepLinkURL.append(parameters,to:rawURL); parameters = []; error = nil }
        catch { self.error = error.localizedDescription }
    }
    func currentCase() throws -> VPhoneDeepLinkCase {
        guard let app = selectedApp else { throw VPhoneProxyError("Choose an installed target app.") }
        let name = caseName.trimmingCharacters(in:.whitespacesAndNewlines)
        let value = VPhoneDeepLinkCase(name:name.isEmpty ? "Deep-link test" : name,bundleID:app.bundleID,appName:app.displayName,appVersion:app.version,appBuild:app.build,url:try VPhoneDeepLinkURL.validated(rawURL),notes:notes,savedAt:Date())
        try value.validate(); return value
    }
    func saveCase() {
        do {
            guard archive.cases.count < 100 else { throw VPhoneProxyError("100 saved cases reached. Remove a case before adding another.") }
            let test = try currentCase(); archive.cases.append(test); selectedCase = test.id; error = nil; message = "Case saved in memory. Save Workspace to retain it across sessions."
        } catch { self.error = error.localizedDescription }
    }
    func load(_ test: VPhoneDeepLinkCase) {
        guard !opening else { return }
        guard apps.contains(where: { $0.bundleID == test.bundleID }) else { error = "This case's target app is not installed in this guest. No URL was opened."; return }
        selectedID = test.bundleID; rawURL = test.url; caseName = test.name; notes = test.notes; parameters = []
        error = nil; message = "Loaded into editor only. Choose Open URL to execute."
    }
    func openURL() async {
        guard !opening, control.isConnected else { return }
        let test: VPhoneDeepLinkCase
        do { test = try currentCase() } catch { self.error = error.localizedDescription; return }
        opening = true; error = nil; message = ""; let operation = generation
        defer { opening = false }
        let started = Date(), clock = ProcessInfo.processInfo.systemUptime
        let accepted: Bool, resultMessage: String
        do {
            _ = try await control.appOpenURL(test.url,bundleID:test.bundleID)
            accepted = true; resultMessage = "Guest accepted the open request. Target route, frontmost app and Universal Link association are not verified."
        } catch {
            accepted = false; resultMessage = String(("Guest request failed: " + error.localizedDescription).prefix(2048))
        }
        let run = VPhoneDeepLinkRun(test:test,startedAt:started,elapsedMilliseconds:Int((ProcessInfo.processInfo.systemUptime-clock)*1000),accepted:accepted,message:resultMessage)
        archive.history.insert(run,at:0); if archive.history.count > 100 { archive.history.removeLast(archive.history.count-100) }
        selectedRun = run.id
        if operation == generation { message = resultMessage }
    }
    func saveWorkspace() {
        guard !opening else { return }
        do {
            let data = try archive.data()
            let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "deep-link-workspace.json"
            panel.begin { [weak self] response in
                Task { @MainActor [weak self] in
                    guard response == .OK, let url = panel.url else { return }
                    do { try VPhoneSandboxSnapshot.writeReport(data,to:url); self?.message = "Workspace saved locally." }
                    catch { self?.error = error.localizedDescription }
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    func openWorkspace() {
        guard !opening else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, response == .OK, let url = panel.url, !opening else { return }
                do {
                    let loaded = try VPhoneDeepLinkArchive.read(url)
                    archive = loaded; selectedCase = nil; selectedRun = nil
                    error = nil; message = "Workspace loaded. No links were opened."
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}
