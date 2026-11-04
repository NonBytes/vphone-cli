import AppKit
import SwiftUI

@MainActor
@Observable
final class VPhoneFridaModel {
    let control: VPhoneGuestControl
    var version = "latest"
    var status: VPhoneFridaStatus?
    var busy = false
    var message = ""
    var error: String?
    init(control: VPhoneGuestControl) { self.control = control }
    var endpoint: String { (control.guestIPAddress ?? "<guest-ip>") + ":27042" }
    var command: String { "frida-ps -ai -H \(endpoint) --token \(status?.token ?? "<token>")" }

    func operation(_ name: String) async {
        guard !busy else { return }
        busy = true; error = nil; message = ""
        defer { busy = false }
        do {
            status = try await control.guestTool("vphone-guest-frida", arguments: [name], as: VPhoneFridaStatus.self)
            if name == "start" { message = "Frida started. Use a matching Frida client on the Mac." }
            if name == "stop" { message = "Frida stopped." }
        } catch { self.error = String(describing: error) }
    }

    func install() async {
        guard !busy, status?.running != true else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            message = "Checking official GitHub release…"
            let release = try await VPhoneFridaRelease.fetch(version.trimmingCharacters(in: .whitespacesAndNewlines))
            message = "Downloading Frida \(release.tag_name) and verifying SHA-256…"
            let files = try await release.download()
            message = "Installing in this VM…"
            status = try await control.guestTool("vphone-guest-frida", arguments: ["prepare"], as: VPhoneFridaStatus.self)
            let root = "/private/var/vphone-frida/"
            try await control.uploadFile(path: root + "usr/sbin/frida-server", data: files.server, permissions: "700")
            try await control.uploadFile(path: root + "usr/lib/frida-1.0/frida-agent.dylib", data: files.agent, permissions: "600")
            try await control.uploadFile(path: root + "version", data: Data(release.tag_name.utf8), permissions: "600")
            status = try await control.guestTool("vphone-guest-frida", arguments: ["status"], as: VPhoneFridaStatus.self)
            message = "Frida \(release.tag_name) installed. Click Start when ready."
        } catch { self.error = String(describing: error); message = "" }
    }
}

@MainActor
final class VPhoneFridaWindowController {
    private let model: VPhoneFridaModel
    private let window: VPhoneGuestToolWindow
    init(control: VPhoneGuestControl) {
        let model = VPhoneFridaModel(control: control)
        self.model = model
        window = VPhoneGuestToolWindow(title: "Frida Server", autosaveName: "vphone-frida-server",
                                      size: NSSize(width: 610, height: 490), minSize: NSSize(width: 540, height: 420)) {
            VPhoneFridaView(model: model)
        }
    }
    func show() { window.show(); Task { await model.operation("status") } }
}

private struct VPhoneFridaView: View {
    @Bindable var model: VPhoneFridaModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Release (latest or version)", text: $model.version)
                Button("Download & Install") { Task { await model.install() } }
                    .disabled(model.busy || model.status == nil || model.status?.running == true)
            }
            Text("Official frida/frida iOS package. Downloads are checked against GitHub's SHA-256 digest.")
                .font(.caption).foregroundStyle(.secondary)
            if let status = model.status {
                Label(status.running ? "Running — PID \(status.pid ?? 0)" : "Stopped", systemImage: status.running ? "checkmark.circle.fill" : "stop.circle")
                    .foregroundStyle(status.running ? .green : .secondary)
                Text("Installed version: \(status.installed ? (status.version.isEmpty ? "Unknown" : status.version) : "Not installed")")
                if status.running {
                    Text("Endpoint: \(model.endpoint)").textSelection(.enabled)
                    SecureField("Connection token", text: .constant(status.token))
                    HStack {
                        Text("frida-ps -ai -H \(model.endpoint) --token <token>").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Button("Copy command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.command, forType: .string)
                        }
                    }
                }
            }
            Text("Start opens port 27042 on this VM with a new authentication token. Closing this window leaves the server running; Stop ends it. It does not start automatically after a reboot.")
                .font(.caption).foregroundStyle(.secondary)
            if !model.message.isEmpty { Text(model.message).font(.callout).foregroundStyle(.green) }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            ScrollView {
                Text(model.status?.log.isEmpty == false ? model.status!.log : "No server output.")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 70)
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Button("Reload") { Task { await model.operation("status") } }.disabled(model.busy)
                Spacer()
                Button("Stop") { Task { await model.operation("stop") } }.disabled(model.busy || model.status?.running != true)
                Button("Start") { Task { await model.operation("start") } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.status?.installed != true || model.status?.running == true)
            }
        }.padding(20)
    }
}
