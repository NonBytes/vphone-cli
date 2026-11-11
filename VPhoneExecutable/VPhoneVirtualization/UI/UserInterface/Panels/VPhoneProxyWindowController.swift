import AppKit
#if canImport(VPhonePentestKit)
import VPhonePentestKit
#endif
import SwiftUI
import UniformTypeIdentifiers

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
    var certificates: [VPhoneCACertificate] = []
    var caError: String?
    var caLoaded = false

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
        do {
            certificates = try await control.guestCACertificates().certificates
            caLoaded = true
            caError = nil
        } catch { caError = error.localizedDescription }
    }

    func importCertificate() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = VPhoneLocalization.text("Import CA Certificate…")
        panel.allowedContentTypes = ["der", "cer", "crt", "pem"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, response == .OK, let url = panel.url else { return }
                do {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 0, size <= VPhoneCACertificate.maximumSize else { throw VPhoneProxyError("Select one CA certificate smaller than 64 KB.") }
                    let (der, _, info) = try VPhoneCACertificate.parse(Data(contentsOf: url))
                    let alert = NSAlert()
                    alert.messageText = VPhoneLocalization.text("Trust CA in this VM?")
                    alert.informativeText = "\(info.name)\nSHA-256: \(info.sha256)\n\n" + VPhoneLocalization.text("This VM will trust certificates issued by this CA. The Mac trust store is not changed.")
                    alert.addButton(withTitle: VPhoneLocalization.text("Trust in VM"))
                    alert.addButton(withTitle: VPhoneLocalization.text("Cancel"))
                    guard alert.runModal() == .alertFirstButtonReturn else { return }
                    await updateCertificates(["import", der.base64EncodedString()])
                } catch { caError = error.localizedDescription }
            }
        }
    }

    func removeCertificate(_ certificate: VPhoneCACertificate) {
        guard !busy else { return }
        let alert = NSAlert()
        alert.messageText = VPhoneLocalization.text("Remove CA from this VM?")
        alert.informativeText = "\(certificate.name)\nSHA-256: \(certificate.sha256)\n\n" + VPhoneLocalization.text("Connections signed by this CA may stop working.")
        alert.addButton(withTitle: VPhoneLocalization.text("Remove from VM"))
        alert.addButton(withTitle: VPhoneLocalization.text("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await updateCertificates(["remove", certificate.sha256]) }
    }

    private func updateCertificates(_ arguments: [String]) async {
        guard !busy else { return }
        busy = true
        caError = nil
        defer { busy = false }
        do {
            certificates = try await control.guestCACertificates(arguments).certificates
            caLoaded = true
        } catch { caError = error.localizedDescription }
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
            size: NSSize(width: 560, height: 590), minSize: NSSize(width: 500, height: 520)
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
                Label(VPhoneLocalization.text("Proxy settings applied successfully."), systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold)).foregroundStyle(.green)
                    .accessibilityAddTraits(.updatesFrequently)
                Text(VPhoneLocalization.text("Proxy applied. Reopen apps to renew existing connections."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text(VPhoneLocalization.text("CA Certificates")).font(.headline)
                Spacer()
                Button(VPhoneLocalization.text("Import CA Certificate…")) { model.importCertificate() }
                    .disabled(model.busy)
            }
            if let error = model.caError { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if model.caLoaded, model.certificates.isEmpty {
                Text(VPhoneLocalization.text("No custom root CA certificates in this VM."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.certificates) { cert in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(cert.name).font(.subheadline)
                                Text(VPhoneLocalization.text(cert.trusted ? "Trusted root CA" : "Custom root CA"))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("SHA-256: \(cert.sha256)").font(.system(size: 10, design: .monospaced))
                                    .textSelection(.enabled).lineLimit(2)
                                Text(cert.expires, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(VPhoneLocalization.text("Remove")) { model.removeCertificate(cert) }
                                .disabled(model.busy)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 90, maxHeight: 180)
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
