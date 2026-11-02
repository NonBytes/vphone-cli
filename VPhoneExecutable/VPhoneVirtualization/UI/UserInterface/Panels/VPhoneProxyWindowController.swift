import AppKit
import SwiftUI

@MainActor
@Observable
final class VPhoneProxyModel {
    let control: VPhoneGuestControl
    var enabled = false
    var host = ""
    var port = ""
    var busy = false
    var current: VPhoneProxyStatus?
    var error: String?
    var applied = false

    init(control: VPhoneGuestControl) { self.control = control }

    var request: VPhoneProxyRequest {
        VPhoneProxyRequest(enabled: enabled, host: host, port: Int(port) ?? 0)
    }
    var valid: Bool { (try? request.validated()) != nil }
    var validationMessage: String? {
        do { _ = try request.validated(); return nil } catch { return error.localizedDescription }
    }

    func load(apply: Bool = false) async {
        guard !busy else { return }
        busy = true
        error = nil
        applied = false
        defer { busy = false }
        do {
            let status = try await control.guestProxy(apply ? request : nil)
            current = status
            enabled = status.enabled
            host = status.host
            port = status.port > 0 ? String(status.port) : ""
            applied = apply
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor
final class VPhoneProxyWindowController {
    private let model: VPhoneProxyModel
    private let window: VPhoneGuestToolWindow

    init(control: VPhoneGuestControl) {
        let model = VPhoneProxyModel(control: control)
        self.model = model
        window = VPhoneGuestToolWindow(
            title: VPhoneLocalization.text("Proxy"), autosaveName: "vphone-guest-proxy",
            size: NSSize(width: 490, height: 350), minSize: NSSize(width: 450, height: 320)
        ) { VPhoneProxyView(model: model) }
    }

    func show() {
        window.show()
        Task { await model.load() }
    }
}

private struct VPhoneProxyView: View {
    @Bindable var model: VPhoneProxyModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Form {
                Toggle(VPhoneLocalization.text("Enable Proxy"), isOn: $model.enabled)
                TextField(VPhoneLocalization.text("Server"), text: $model.host)
                    .disabled(!model.enabled)
                TextField(VPhoneLocalization.text("Port"), text: $model.port)
                    .disabled(!model.enabled)
            }
            .disabled(model.busy || model.current == nil)
            Text(VPhoneLocalization.text("Applies to HTTP and HTTPS traffic in this VM."))
                .font(.caption).foregroundStyle(.secondary)
            if let status = model.current {
                Text(status.automatic ? VPhoneLocalization.text("Current: Automatic proxy")
                     : !status.enabled ? VPhoneLocalization.text("Current: Proxy off")
                     : VPhoneLocalization.format("Current: %@:%@", status.host, String(status.port)))
                    .font(.caption)
                if status.mixed || status.automatic {
                    Text(VPhoneLocalization.text("Apply replaces automatic or different HTTP/HTTPS proxy settings."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if model.enabled, model.current != nil, let validation = model.validationMessage {
                Text(validation).font(.caption).foregroundStyle(.secondary)
            }
            if model.applied {
                Text(VPhoneLocalization.text("Proxy applied. Reopen apps to renew existing connections."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Button(VPhoneLocalization.text("Reload")) { Task { await model.load() } }
                    .disabled(model.busy)
                Spacer()
                Button(VPhoneLocalization.text("Apply")) { Task { await model.load(apply: true) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.current == nil || !model.valid)
            }
        }
        .padding(20)
    }
}
