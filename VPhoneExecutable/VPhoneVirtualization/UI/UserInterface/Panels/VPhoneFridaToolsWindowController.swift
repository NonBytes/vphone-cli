import AppKit
import SwiftUI

enum VPhoneFridaToolsTab: Hashable {
    case server, session
}

@MainActor @Observable
final class VPhoneFridaToolsState {
    var tab = VPhoneFridaToolsTab.server
}

/// Frida Server and Frida Session in one window, as two tabs: installing and
/// starting the guest server, then spawning or attaching to a script-loaded
/// session, used to be two separate windows — switching to Session before
/// the server was running dead-ended with "start it in the other window".
@MainActor
final class VPhoneFridaToolsWindowController: NSObject, NSWindowDelegate {
    private let fridaModel: VPhoneFridaModel
    private let sessionModel: VPhoneFridaSessionModel
    private let state = VPhoneFridaToolsState()
    private var window: NSWindow?

    init(control: VPhoneGuestControl, machineDirectory: URL? = nil) {
        fridaModel = VPhoneFridaModel(control: control, machineDirectory: machineDirectory)
        sessionModel = VPhoneFridaSessionModel(control: control, machineDirectory: machineDirectory)
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 740),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Frida Tools"
            window.contentViewController = NSHostingController(
                rootView: VPhoneFridaToolsView(state: state, fridaModel: fridaModel, sessionModel: sessionModel),
            )
            window.contentMinSize = NSSize(width: 800, height: 680)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("vphone-frida-tools")
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        Task { await fridaModel.operation("status"); await fridaModel.refreshVersions() }
        Task { await sessionModel.refresh() }
    }

    nonisolated func windowWillClose(_: Notification) {
        MainActor.assumeIsolated { sessionModel.detach(); sessionModel.icons.reset(); window = nil }
    }
}

private struct VPhoneFridaToolsView: View {
    @Bindable var state: VPhoneFridaToolsState
    @Bindable var fridaModel: VPhoneFridaModel
    @Bindable var sessionModel: VPhoneFridaSessionModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $state.tab) {
                Text("Server").tag(VPhoneFridaToolsTab.server)
                Text("Session").tag(VPhoneFridaToolsTab.session)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], 16)
            Divider().padding(.top, 10)
            switch state.tab {
            case .server:
                ScrollView { VPhoneFridaView(model: fridaModel) }
            case .session:
                VPhoneFridaSessionView(model: sessionModel)
            }
        }
    }
}
