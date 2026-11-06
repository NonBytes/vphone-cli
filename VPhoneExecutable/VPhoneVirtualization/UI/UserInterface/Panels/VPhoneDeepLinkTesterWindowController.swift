import AppKit
import SwiftUI

@MainActor
final class VPhoneDeepLinkTesterWindowController: NSObject, NSWindowDelegate {
    private let model: VPhoneDeepLinkTesterModel
    private var window: NSWindow?
    init(control: VPhoneGuestControl) { model = .init(control:control) }
    func show(app: VPhoneAppRecord? = nil) {
        if let app, !model.opening {
            if !model.apps.contains(where: { $0.bundleID == app.bundleID }) { model.apps.append(app) }
            model.selectedID = app.bundleID
        }
        if window == nil {
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1080,height:800),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
            window.title = "Deep Link Tester"
            window.contentViewController = NSHostingController(rootView:VPhoneDeepLinkTesterView(model:model))
            window.contentMinSize = NSSize(width:880,height:640)
            window.isReleasedWhenClosed = false; window.delegate = self
            window.setFrameAutosaveName("vphone-deep-link-tester"); window.center(); self.window = window
        }
        NSApp.activate(ignoringOtherApps:true); window?.makeKeyAndOrderFront(nil)
        Task { await model.refresh() }
    }
    nonisolated func windowWillClose(_: Notification) { MainActor.assumeIsolated { model.close(); window = nil } }
}

private struct VPhoneDeepLinkTesterView: View {
    @Bindable var model: VPhoneDeepLinkTesterModel
    @State private var tab = 0
    @State private var replacingWorkspace = false
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Picker("App",selection:$model.selectedID) {
                    Text("Choose an app…").tag("")
                    ForEach(model.apps) { Text("\($0.displayName) — \($0.bundleID)").tag($0.bundleID) }
                }.disabled(model.opening)
                Button("Refresh Apps / Schemes") { Task { await model.refresh() } }.disabled(model.opening || model.refreshing || !model.control.isConnected)
                if model.refreshing || model.opening { ProgressView().controlSize(.small) }
            }
            HStack {
                Text("Declared URL schemes:").font(.caption)
                if model.declaredSchemes.isEmpty { Text("None reported; manual URLs are still allowed.").font(.caption).foregroundStyle(.secondary) }
                else {
                    Menu("Choose scheme…") {
                        ForEach(model.declaredSchemes,id:\.self) { scheme in Button(scheme) { model.rawURL = scheme + "://" } }
                    }.disabled(model.opening)
                    Text(model.declaredSchemes.joined(separator:", ")).font(.system(.caption,design:.monospaced)).lineLimit(2).textSelection(.enabled)
                }
            }
            TextField("Case name",text:$model.caseName).disabled(model.opening)
            TextField("Raw URL — scheme://host/path?key=value",text:$model.rawURL).font(.system(.body,design:.monospaced)).disabled(model.opening)
            TextField("Notes / expected behavior",text:$model.notes).disabled(model.opening)
            DisclosureGroup("Query parameter builder (applies once; duplicate keys and empty values supported)") {
                ScrollView {
                    VStack {
                        ForEach($model.parameters) { $parameter in
                            HStack {
                                TextField("Name",text:$parameter.name)
                                TextField("Value",text:$parameter.value)
                                Button("Remove") { model.parameters.removeAll { $0.id == parameter.id } }
                            }
                        }
                    }
                }.frame(maxHeight:100)
                HStack {
                    Button("Add Parameter") { model.parameters.append(.init()) }.disabled(model.parameters.count >= 32)
                    Button("Apply Parameters to URL") { model.applyParameters() }.disabled(model.parameters.isEmpty)
                    Text("Names/values are percent-encoded. Raw URL mode preserves entered payloads.").font(.caption).foregroundStyle(.secondary)
                }
            }.disabled(model.opening)
            HStack {
                Button("Open URL in Selected App") { Task { await model.openURL() } }.disabled(model.opening || model.refreshing || !model.control.isConnected || model.selectedApp == nil)
                Button("Save Case") { model.saveCase() }.disabled(model.opening || model.selectedApp == nil)
                Spacer()
                Button("Open Workspace…") {
                    if model.archive.cases.isEmpty && model.archive.history.isEmpty { model.openWorkspace() } else { replacingWorkspace = true }
                }.disabled(model.opening)
                Button("Save Workspace…") { model.saveWorkspace() }.disabled(model.opening)
            }
            Text("Open sends one request to the guest and may launch the app or trigger its actions/network traffic. Guest acceptance does not prove routing, frontmost app or Universal Link association. Imported/saved cases never execute automatically.").font(.caption).foregroundStyle(.secondary)
            Picker("View",selection:$tab) {
                Text("Saved Cases").tag(0)
                Text("Run History").tag(1)
            }.pickerStyle(.segmented)
            Group {
                if tab == 0 {
                VStack(alignment:.leading) {
                    Table(model.archive.cases,selection:$model.selectedCase) {
                        TableColumn("Case",value:\.name)
                        TableColumn("App",value:\.appName)
                        TableColumn("URL",value:\.url)
                    }
                    HStack {
                        Button("Load Selected Case") {
                            if let test = model.archive.cases.first(where: { $0.id == model.selectedCase }) { model.load(test) }
                        }.disabled(model.opening || model.selectedCase == nil)
                        Button("Remove Selected Case") { model.archive.cases.removeAll { $0.id == model.selectedCase }; model.selectedCase = nil }
                            .disabled(model.opening || model.selectedCase == nil)
                        Text("\(model.archive.cases.count) / 100 saved cases").font(.caption).foregroundStyle(.secondary)
                    }
                }
                } else {
                VStack(alignment:.leading) {
                    Table(model.archive.history,selection:$model.selectedRun) {
                        TableColumn("Time",value:\.dateText)
                        TableColumn("Case") { Text($0.test.name) }
                        TableColumn("App") { Text($0.test.appName) }
                        TableColumn("URL") { Text($0.test.url).lineLimit(1) }
                        TableColumn("Outcome",value:\.outcome)
                    }
                    if let run = model.archive.history.first(where: { $0.id == model.selectedRun }) {
                        Text("\(run.test.bundleID) — \(run.test.appVersion) (\(run.test.appBuild)) — \(run.elapsedMilliseconds) ms\n\(run.test.url)\n\(run.message)").font(.system(.caption,design:.monospaced)).textSelection(.enabled).lineLimit(4)
                    }
                    HStack {
                        Button("Load Selected Run into Editor") {
                            if let run = model.archive.history.first(where: { $0.id == model.selectedRun }) { model.load(run.test) }
                        }.disabled(model.opening || model.selectedRun == nil)
                        Text("\(model.archive.history.count) / 100 recent runs; oldest runs roll off.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                }
            }.frame(minHeight:180)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if !model.message.isEmpty { Text(model.message).font(.caption).textSelection(.enabled) }
            Text("Cases and history stay in memory. Save Workspace retains them across sessions in a private local JSON file. URLs and notes may contain tokens/secrets; review before sharing. Loading replaces the current workspace and opens no links.").font(.caption).foregroundStyle(.secondary)
        }.padding(16)
        .confirmationDialog("Replace the in-memory workspace?",isPresented:$replacingWorkspace,titleVisibility:.visible) {
            Button("Choose Workspace File…") { model.openWorkspace() }
            Button("Cancel",role:.cancel) {}
        } message: { Text("Save Workspace first to keep unsaved cases/history. Your existing files will not be changed.") }
    }
}
