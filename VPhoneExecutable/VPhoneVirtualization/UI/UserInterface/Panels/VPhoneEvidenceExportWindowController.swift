import AppKit
import SwiftUI

@MainActor
@Observable
final class VPhoneEvidenceExportModel {
    let control: VPhoneGuestControl
    var apps: [VPhoneAppRecord] = []
    var selectedID = "" { didSet { invalidate() } }
    var title = "" { didSet { invalidate() } }
    var notes = "" { didSet { invalidate() } }
    var redact = true { didSet { invalidate() } }
    var secrets = "" { didSet { invalidate() } }
    var allowOriginals = false { didSet { invalidate() } }
    var attachments: [VPhoneEvidenceArtifact] = []
    var scriptHash: String?
    var reviewed: [VPhoneEvidenceArtifact] = []
    var selectedPreview = ""
    var busy = false
    var message = ""
    var error: String?
    var generation = 0
    init(control: VPhoneGuestControl) { self.control = control }
    func invalidate() { reviewed = []; message = "" }
    func close() { generation += 1; reviewed = []; attachments = []; secrets = ""; notes = ""; scriptHash = nil }
    func refresh() async {
        guard !busy, control.isConnected else { return }
        busy = true; let operation = generation; defer { busy = false }
        do {
            let result = try await control.appList()
            guard operation == generation else { return }
            apps = result.objects("apps").compactMap(VPhoneAppRecord.init(json:)).sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        } catch { if operation == generation { self.error = error.localizedDescription } }
    }
    func addFiles(script: Bool = false) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = !script; panel.canChooseDirectories = false
        let operation = generation
        panel.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, response == .OK, operation == generation, !busy else { return }
                do {
                    if script {
                        guard let url = panel.url else { return }
                        scriptHash = VPhoneEvidencePackage.hash(try VPhoneEvidencePackage.read(url)); invalidate()
                    } else {
                        // Read everything first so an invalid selection cannot partially change the case.
                        var added: [VPhoneEvidenceArtifact] = []
                        for url in panel.urls {
                            let data = try VPhoneEvidencePackage.read(url)
                            let ext = url.pathExtension.lowercased()
                            let textExtensions = ["txt", "log", "json", "ips", "crash", "csv", "md", "xml", "plist"]
                            let isText = textExtensions.contains(ext) && String(data: data, encoding: .utf8).map { !$0.contains("\0") } == true
                            let safeExtension = isText ? "txt" : (["png", "jpg", "jpeg", "pcap", "pcapng"].contains(ext) ? ext : "bin")
                            added.append(.init(name: "attachment-\(attachments.count + added.count + 1)-\(UUID().uuidString.prefix(8)).\(safeExtension)", data: data, isText: isText))
                        }
                        guard attachments.count + added.count <= 32,
                              (attachments + added).reduce(0, { $0 + $1.data.count }) <= 96 * 1024 * 1024 else { throw VPhoneSandboxError("Attachment limit: 32 files / 96 MiB total.") }
                        attachments += added; invalidate()
                    }
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    func capture() async {
        guard !busy, control.isConnected, attachments.count < 32 else { return }
        busy = true; let operation = generation; defer { busy = false }
        do {
            let data = try await control.screenshotJPEG()
            guard operation == generation else { return }
            guard data.count <= VPhoneEvidencePackage.maximumFileBytes,
                  attachments.reduce(data.count, { $0 + $1.data.count }) <= 96 * 1024 * 1024 else { throw VPhoneSandboxError("Screenshot exceeds evidence limits.") }
            attachments.append(.init(name: "screenshot-\(UUID().uuidString.prefix(8)).jpg", data: data, isText: false)); invalidate(); error = nil
        } catch { if operation == generation { self.error = error.localizedDescription } }
    }
    func prepare() async {
        guard !busy, control.isConnected else { return }
        guard title.utf8.count <= 512, notes.utf8.count <= 65536, secrets.utf8.count <= 8192 else { error = "Title, notes or replacement list exceeds its limit."; return }
        busy = true; invalidate(); error = nil
        let operation = generation
        let appID = selectedID, caseTitle = title, caseNotes = notes
        let shouldRedact = redact, originals = allowOriginals, files = attachments, hash = scriptHash
        let literals = secrets.components(separatedBy: .newlines).filter { !$0.isEmpty }
        defer { busy = false }
        do {
            // Refresh app version at review time; an old picker row is not provenance.
            let result = try await control.appList()
            let liveApps = result.objects("apps").compactMap(VPhoneAppRecord.init(json:))
            let app = liveApps.first { $0.bundleID == appID }
            guard appID.isEmpty || app != nil else { throw VPhoneSandboxError("Selected app is no longer installed. Refresh and choose again.") }
            let guest = try await control.call("device.info")
            guard operation == generation else { return }
            // Only version fields, never full device.info (which includes identifiers).
            let versionKeys = ["ios_version", "ios_build", "os_version", "os_build", "system_version", "build_version", "product_version", "product_build_version", "version", "build"]
            var versions: [String: String] = [:]
            for key in versionKeys { if let value = guest.string(key) { versions[key] = value } }
            var metadata: [String: Any] = [
                "formatVersion": 1, "reviewedAt": ISO8601DateFormatter().string(from: Date()),
                "title": caseTitle, "notes": caseNotes,
                "coreVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "coreBuild": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                "guestVersionFields": versions, "textRedaction": shouldRedact,
                "binaryOriginalsIncluded": originals,
                "limitations": "Text redaction is best effort. Review every exported file. Binary files are unchanged originals. No app/guest association is verified for imported attachments. Script hash identifies a selected local file, not proof of execution."
            ]
            if let app { metadata["app"] = ["bundleID": app.bundleID, "name": app.displayName, "version": app.version, "build": app.build] }
            if let hash { metadata["selectedScriptSHA256"] = hash }
            let json = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            var output = [VPhoneEvidenceArtifact(name: "context.txt", data: json, isText: true)]
            output += files.filter { $0.isText || originals }
            reviewed = output.map { file in
                if shouldRedact, file.isText, let text = String(data: file.data, encoding: .utf8) {
                    return VPhoneEvidenceArtifact(name: file.name, data: Data(VPhoneEvidencePackage.redact(text, literals: literals).utf8), isText: true)
                }
                return file
            }
            selectedPreview = "context.txt"
            message = "Review ready: \(reviewed.count) files. \(files.filter { !$0.isText && !originals }.count) binary files excluded. Export writes exactly these reviewed bytes."
        } catch { if operation == generation { self.error = error.localizedDescription } }
    }
    func export() {
        guard !busy, !reviewed.isEmpty else { return }
        let snapshot = reviewed, operation = generation
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, response == .OK, let parent = panel.url, operation == generation,
                      reviewed.map(\.id) == snapshot.map(\.id) else { return }
                do {
                    let folder = try VPhoneEvidencePackage.write(snapshot, to: parent)
                    message = "Exported locally: " + folder.path; error = nil
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

@MainActor
final class VPhoneEvidenceExportWindowController: NSObject, NSWindowDelegate {
    let model: VPhoneEvidenceExportModel
    var window: NSWindow?
    init(control: VPhoneGuestControl) { model = .init(control: control) }
    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 780), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Evidence Export"; window.isReleasedWhenClosed = false; window.delegate = self
            window.contentViewController = NSHostingController(rootView: VPhoneEvidenceExportView(model: model))
            window.contentMinSize = NSSize(width: 800, height: 680); window.center(); self.window = window
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
        Task { await model.refresh() }
    }
    nonisolated func windowWillClose(_: Notification) { MainActor.assumeIsolated { model.close(); window = nil } }
}

private struct VPhoneEvidenceExportView: View {
    @Bindable var model: VPhoneEvidenceExportModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Case title", text: $model.title)
            HStack {
                Picker("App", selection: $model.selectedID) {
                    Text("Guest only / no target app").tag("")
                    ForEach(model.apps) { Text("\($0.displayName) — \($0.bundleID)").tag($0.bundleID) }
                }
                Button("Refresh Apps") { Task { await model.refresh() } }
            }
            TextField("Notes / test steps", text: $model.notes)
            HStack {
                Button("Add Evidence Files…") { model.addFiles() }
                Button("Capture Guest Screenshot") { Task { await model.capture() } }
                Button("Choose Script for Hash…") { model.addFiles(script: true) }
            }
            Text("Import saved logs, crash reports, sandbox diffs, workspaces or PCAP. Imported files are not automatically linked to the selected app. Script contents are never exported.").font(.caption).foregroundStyle(.secondary)
            if let hash = model.scriptHash { Text("Selected script SHA-256: " + hash).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(model.attachments) { file in
                        HStack {
                            Text("\(file.name) — \(file.data.count) B — \(file.isText ? "UTF-8 text" : "binary original")")
                            Spacer()
                            Button("Remove") { model.attachments.removeAll { $0.id == file.id }; model.invalidate() }
                        }
                    }
                }
            }.frame(height: 90)
            Toggle("Redact common credentials in text", isOn: $model.redact)
            TextField("Additional exact secrets to replace (one per line)", text: $model.secrets, axis: .vertical).lineLimit(2...3)
            Toggle("Include unchanged binary originals (screenshots / PCAP cannot be redacted here)", isOn: $model.allowOriginals)
            Text("Redaction is best effort and may change JSON syntax. Review text below; inspect binary originals separately before sharing. No files are uploaded.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Prepare Preview") { Task { await model.prepare() } }.disabled(!model.control.isConnected)
                Button("Export Reviewed Evidence…") { model.export() }.disabled(model.reviewed.isEmpty)
                if model.busy { ProgressView().controlSize(.small) }
            }
            if !model.reviewed.isEmpty {
                Picker("Preview", selection: $model.selectedPreview) { ForEach(model.reviewed, id: \.name) { Text($0.name).tag($0.name) } }
                if let file = model.reviewed.first(where: { $0.name == model.selectedPreview }) {
                    ScrollView {
                        Text(file.isText ? String(decoding: file.data.prefix(256 * 1024), as: UTF8.self) : "Binary original: \(file.data.count) bytes; SHA-256 \(VPhoneEvidencePackage.hash(file.data))")
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minHeight: 120)
                    if file.isText && file.data.count > 256 * 1024 { Text("Preview limited to first 256 KiB; export includes the complete reviewed file.").font(.caption) }
                }
            }
            if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Text(model.message).font(.caption).textSelection(.enabled)
        }.padding(16).disabled(model.busy)
    }
}
