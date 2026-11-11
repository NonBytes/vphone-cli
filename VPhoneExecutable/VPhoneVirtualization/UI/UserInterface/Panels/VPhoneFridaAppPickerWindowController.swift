import AppKit
import SwiftUI

/// A process-manager-style window for choosing the app Frida Session will
/// spawn or attach to — a sortable, searchable table (icon, name, bundle ID,
/// PID), not a dropdown with everything squeezed onto one menu row.
@MainActor
final class VPhoneFridaAppPickerWindowController: NSObject, NSWindowDelegate {
    private let model: VPhoneFridaSessionModel
    private var window: NSWindow?
    private var onChoose: ((VPhoneAppRecord) -> Void)?

    init(model: VPhoneFridaSessionModel) {
        self.model = model
    }

    func show(onChoose: @escaping (VPhoneAppRecord) -> Void) {
        self.onChoose = onChoose
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Choose App"
            window.contentViewController = NSHostingController(rootView: VPhoneFridaAppPickerView(
                model: model,
                onChoose: { [weak self] app in self?.choose(app) },
                onCancel: { [weak self] in self?.window?.close() },
            ))
            window.contentMinSize = NSSize(width: 480, height: 360)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("vphone-frida-app-picker")
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func choose(_ app: VPhoneAppRecord) {
        onChoose?(app)
        window?.close()
    }

    nonisolated func windowWillClose(_: Notification) {
        MainActor.assumeIsolated { window = nil }
    }
}

private struct VPhoneFridaAppPickerView: View {
    @Bindable var model: VPhoneFridaSessionModel
    let onChoose: (VPhoneAppRecord) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<VPhoneAppRecord>] = [.init(\.displayName)]
    @State private var selection: VPhoneAppRecord.ID?

    private var filtered: [VPhoneAppRecord] {
        let list = searchText.isEmpty ? model.apps : model.apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) || $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
        return list.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(of: VPhoneAppRecord.self, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.displayName) { app in
                    HStack(spacing: 8) {
                        appIcon(app).frame(width: 24, height: 24).accessibilityHidden(true)
                        Text(app.displayName).lineLimit(1).truncationMode(.tail)
                    }
                    .padding(.vertical, 2)
                    .task(id: model.icons.revision) { model.icons.request(app) }
                }
                .width(min: 140, ideal: 200, max: .infinity)

                TableColumn("Bundle ID", value: \.bundleID) { app in
                    VPhonePanelMonoText(app.bundleID)
                }
                .width(min: 160, ideal: 220, max: .infinity)

                TableColumn("PID", value: \.pid) { app in
                    HStack(spacing: 4) {
                        Circle().fill(app.isRunning ? Color.green : Color.clear).frame(width: 6, height: 6)
                        VPhonePanelMonoText(app.isRunning ? String(app.pid) : "—", secondary: !app.isRunning)
                    }
                    .accessibilityLabel(app.isRunning ? Text("Running, PID \(app.pid)") : Text("Not running"))
                }
                .width(min: 60, ideal: 70, max: 100)
            } rows: {
                ForEach(filtered) { app in
                    TableRow(app)
                }
            }
            .contextMenu(forSelectionType: VPhoneAppRecord.ID.self) { ids in
                if let id = ids.first, let app = filtered.first(where: { $0.id == id }) {
                    Button("Choose") { onChoose(app) }
                }
            } primaryAction: { ids in
                if let id = ids.first, let app = filtered.first(where: { $0.id == id }) {
                    onChoose(app)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Choose") {
                    guard let selection, let app = filtered.first(where: { $0.id == selection }) else { return }
                    onChoose(app)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
            .padding(12)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: Text("Search Apps"))
        .frame(minWidth: 480, minHeight: 360)
    }

    @ViewBuilder
    private func appIcon(_ app: VPhoneAppRecord) -> some View {
        if let icon = model.icons.image(for: app) {
            Image(nsImage: icon).resizable().interpolation(.high)
        } else {
            Image(systemName: "app.fill").resizable().foregroundStyle(.secondary)
        }
    }
}
