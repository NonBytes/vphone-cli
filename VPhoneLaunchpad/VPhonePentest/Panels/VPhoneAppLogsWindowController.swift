import AppKit
import SwiftUI

@MainActor
final class VPhoneAppLogsWindowController: NSObject, NSWindowDelegate {
    private let model: VPhoneAppLogsModel
    private var window: NSWindow?
    init(control: VPhoneGuestControl) { model = VPhoneAppLogsModel(control: control) }

    func show(app: VPhoneAppRecord? = nil) {
        if let app {
            if !model.apps.contains(where: { $0.bundleID == app.bundleID }) { model.apps.append(app) }
            model.selectedID = app.bundleID
        }
        if window == nil {
            let hosting = NSHostingController(rootView: VPhoneAppLogsView(model: model))
            hosting.sceneBridgingOptions = [.toolbars]
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 760),
                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "App Logs & Crash Viewer"
            window.contentViewController = hosting
            window.contentMinSize = NSSize(width: 960, height: 540)
            window.isReleasedWhenClosed = false; window.delegate = self
            window.setFrameAutosaveName("vphone-app-logs"); window.center(); self.window = window
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
        Task { await model.refreshApps() }
    }

    nonisolated func windowWillClose(_: Notification) {
        MainActor.assumeIsolated { model.close(); window = nil }
    }
}

private struct VPhoneAppLogsView: View {
    @Bindable var model: VPhoneAppLogsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("App", selection: $model.selectedID) {
                    Text("Choose an app…").tag("")
                    ForEach(model.apps) { app in
                        Text("\(app.displayName) — \(app.bundleID)").tag(app.bundleID)
                    }
                }
                Button("Refresh Apps") { Task { await model.refreshApps() } }
                    .disabled(model.loadingApps || !model.control.isConnected)
                Button("Reload App Scope") { Task { await model.configure() } }
                    .disabled(model.resolving || model.selectedApp == nil || !model.control.isConnected)
                if model.loadingApps || model.resolving { ProgressView().controlSize(.small) }
            }.padding(12)
            if let app = model.selectedApp {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.bundleID).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    if let scope = model.console?.appScope {
                        Text("Log executable: \(scope.process). Choose Start to collect new entries. Apps sharing this executable name may match; extensions and system-service logs are excluded.")
                    }
                    Text("Crash candidates are matched by filename using the bundle ID or executable. Verify report identity in its contents. No report is deleted from the guest.")
                    Text("Log captures run in 2-second batches with gaps between batches, up to 2,000 entries per batch and 10,000 retained rows. Private/redacted values remain redacted. Exports stay local and may contain app data.")
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 8)
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal, 12) }
            Divider()
            if model.selectedApp == nil {
                ContentUnavailableView("Choose an App", systemImage: "text.magnifyingglass", description: Text("Select an installed app to inspect its new logs and crash report candidates."))
            } else {
                TabView(selection: $model.tab) {
                    Group {
                        if let console = model.console {
                            VPhoneConsoleView(model: console).id(ObjectIdentifier(console))
                        } else if model.resolving {
                            ProgressView()
                        } else {
                            ContentUnavailableView("Logs Unavailable", systemImage: "exclamationmark.triangle", description: Text("Reload App Scope after checking the guest connection and executable."))
                        }
                    }.tabItem { Text("App Logs") }.tag(0)
                    Group {
                        if let crashes = model.crashes { VPhoneCrashLogsView(model: crashes).id(ObjectIdentifier(crashes)) }
                    }.tabItem { Text("Crash Reports") }.tag(1)
                }.id(model.selectedID)
            }
        }
        .task(id: model.selectedID) { await model.configure() }
    }
}
