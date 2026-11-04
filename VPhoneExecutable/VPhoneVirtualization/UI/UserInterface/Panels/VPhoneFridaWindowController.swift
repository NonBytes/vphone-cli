import AppKit
import SwiftUI

@MainActor
@Observable
final class VPhoneFridaModel {
    let control: VPhoneGuestControl
    var version = "latest"
    var otherVersion = ""
    var versions: [String] = []
    var loadingVersions = false
    var releaseError: String?
    var customServer: URL?
    var customAgent: URL?
    var status: VPhoneFridaStatus?
    var busy = false
    var message = ""
    var error: String?
    init(control: VPhoneGuestControl) { self.control = control }
    var endpoint: String { (control.guestIPAddress ?? "<guest-ip>") + ":27042" }
    var command: String { "frida-ps -ai -H \(endpoint) --token \(status?.token ?? "<token>")" }

    func refreshVersions() async {
        guard !loadingVersions else { return }
        loadingVersions = true; releaseError = nil
        defer { loadingVersions = false }
        do { versions = try await VPhoneFridaRelease.versions() }
        catch { releaseError = "Could not load release list. Use Latest, Other version or Custom, or try Refresh." }
    }

    func chooseCustomFile(agent: Bool) {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = agent ? "Select matching frida-agent.dylib" : "Select custom iOS frida-server"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, response == .OK, let url = panel.url else { return }
                if agent { customAgent = url } else { customServer = url }
            }
        }
    }

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
            let files: (server: Data, agent: Data?)
            let label: String
            let preparation: String
            if version == "custom" {
                guard let server = customServer else { throw VPhoneProxyError("Select a custom iOS frida-server first.") }
                let agent = customAgent
                message = "Checking custom iOS binaries…"
                files = try await Task.detached { try VPhoneFridaCustom.load(server: server, agent: agent) }.value
                label = "Custom: " + server.lastPathComponent
                preparation = agent == nil ? "prepare-custom" : "prepare-custom-agent"
            } else {
                message = "Checking official GitHub release…"
                let selected = version == "other" ? otherVersion.trimmingCharacters(in: .whitespacesAndNewlines) : version
                let release = try await VPhoneFridaRelease.fetch(selected)
                message = "Downloading Frida \(release.tag_name) and verifying SHA-256…"
                let downloaded = try await release.download()
                files = (downloaded.server, downloaded.agent)
                label = release.tag_name
                preparation = "prepare"
            }
            message = "Installing in this VM…"
            status = try await control.guestTool("vphone-guest-frida", arguments: [preparation], as: VPhoneFridaStatus.self)
            let root = "/private/var/vphone-frida/"
            try await control.uploadFile(path: root + "usr/sbin/frida-server", data: files.server, permissions: "700")
            if let agent = files.agent {
                try await control.uploadFile(path: root + "usr/lib/frida-1.0/frida-agent.dylib", data: agent, permissions: "600")
            }
            try await control.uploadFile(path: root + "version", data: Data(label.utf8), permissions: "600")
            status = try await control.guestTool("vphone-guest-frida", arguments: ["status"], as: VPhoneFridaStatus.self)
            message = "Frida \(label) installed. Click Start when ready."
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
                                      size: NSSize(width: 690, height: 610), minSize: NSSize(width: 600, height: 560)) {
            VPhoneFridaView(model: model)
        }
    }
    func show() { window.show(); Task { await model.operation("status"); await model.refreshVersions() } }
}

private struct VPhoneFridaView: View {
    @Bindable var model: VPhoneFridaModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Release", selection: $model.version) {
                    Text("Latest release").tag("latest")
                    ForEach(model.versions, id: \.self) { Text($0).tag($0) }
                    Divider()
                    Text("Other version…").tag("other")
                    Text("Custom…").tag("custom")
                }.pickerStyle(.menu).disabled(model.busy)
                Button("Refresh") { Task { await model.refreshVersions() } }
                    .disabled(model.loadingVersions || model.busy)
                Button(model.version == "custom" ? "Install Custom" : "Download & Install") { Task { await model.install() } }
                    .disabled(model.busy || model.status == nil || model.status?.running == true || (model.version == "custom" && model.customServer == nil))
            }
            if model.version == "other" {
                TextField("Version, e.g. 17.25.2", text: $model.otherVersion).disabled(model.busy)
            }
            if model.version == "custom" {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Choose Server…") { model.chooseCustomFile(agent: false) }
                        Text(model.customServer?.lastPathComponent ?? "No server selected").lineLimit(1)
                    }
                    HStack {
                        Button("Choose Agent…") { model.chooseCustomFile(agent: true) }
                        Text(model.customAgent?.lastPathComponent ?? "Optional matching agent").lineLimit(1)
                        if model.customAgent != nil { Button("Clear") { model.customAgent = nil } }
                    }
                }.disabled(model.busy)
                Text("Select a signed, uncompressed iOS arm64 executable. If the server does not embed its agent, select the matching frida-agent.dylib too. Standard Frida server command-line options are required.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.loadingVersions { Text("Loading releases…").font(.caption).foregroundStyle(.secondary) }
            if let error = model.releaseError { Text(error).font(.caption).foregroundStyle(.secondary) }
            Text(model.version == "custom" ? "Custom files are checked locally and uploaded only to this VM." : "Official frida/frida iOS package. Downloads are checked against GitHub's SHA-256 digest.")
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
