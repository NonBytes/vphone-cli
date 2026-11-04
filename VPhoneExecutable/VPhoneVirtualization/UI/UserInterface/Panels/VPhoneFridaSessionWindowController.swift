import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class VPhoneFridaSessionModel {
    let control: VPhoneGuestControl
    var apps: [VPhoneAppRecord] = []
    var selectedID = ""
    var mode = "spawn"
    var endpoint = ""
    var usesGuestTransport = true
    var scriptURL: URL?
    var scriptSource = ""
    var log = ""
    var error: String?
    var state = "Detached"
    var pid: Int?
    var busy = false
    var refreshing = false
    private(set) var client: VPhoneFridaClient?
    private var generation = 0
    private var relay: VPhoneFridaPortRelay?

    init(control: VPhoneGuestControl) { self.control = control }
    var selectedApp: VPhoneAppRecord? { apps.first { $0.id == selectedID } }
    var active: Bool { client != nil }
    var canStart: Bool {
        !active && !busy && control.isConnected && selectedApp != nil &&
            (mode == "spawn" || selectedApp?.isRunning == true) && (usesGuestTransport || !endpoint.isEmpty)
    }

    func refresh() async {
        guard !refreshing, !active, !busy else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let result = try await control.appList()
            apps = result.objects("apps").compactMap(VPhoneAppRecord.init(json:))
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            if selectedApp == nil { selectedID = "" }
            if endpoint.isEmpty, let address = control.guestIPAddress {
                endpoint = address.contains(":") ? "[\(address)]:27042" : address + ":27042"
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func chooseScript() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Select a local Frida JavaScript file"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.javaScript]
        panel.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, response == .OK, let url = panel.url, !busy else { return }
                do {
                    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    guard values.isRegularFile == true, let size = values.fileSize, size <= 512 * 1024 else {
                        throw VPhoneProxyError("Choose a JavaScript file no larger than 512 KiB.")
                    }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 512 * 1024, let source = String(data: data, encoding: .utf8),
                          !source.contains("\0"), !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw VPhoneProxyError("The script must contain nonempty UTF-8 JavaScript without NUL bytes.")
                    }
                    scriptURL = url
                    scriptSource = source
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
        }
    }

    func start() async {
        guard canStart, let app = selectedApp else { return }
        generation += 1
        let request = generation
        busy = true; error = nil; state = "Connecting…"
        defer {
            if request == generation, client == nil { busy = false; state = "Detached" }
        }
        do {
            var target = app.bundleID
            if mode == "attach" {
                // Recheck at the action boundary instead of trusting a PID
                // from a list that may have been open for hours.
                let result = try await control.appList()
                guard request == generation, control.isConnected else { return }
                guard let current = result.objects("apps").compactMap(VPhoneAppRecord.init(json:))
                    .first(where: { $0.bundleID == app.bundleID }), current.pid > 0 else {
                    throw VPhoneProxyError("The selected app is no longer running. Launch it and refresh the app list.")
                }
                target = String(current.pid)
            }
            let status = try await control.guestTool("vphone-guest-frida", arguments: ["status"], as: VPhoneFridaStatus.self)
            guard request == generation, control.isConnected else { return }
            guard status.running, !status.token.isEmpty else {
                throw VPhoneProxyError("Start the managed Frida server in Features > Frida Server first.")
            }
            var address = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            if usesGuestTransport {
                let control = control
                let relay = try VPhoneFridaPortRelay { output, end in
                    try await VPhoneGuestShellChannel.openPort(control: control, port: 27042, onOutput: output, onEnd: { _ in end() })
                }
                self.relay = relay
                let port = try await relay.start()
                guard request == generation, control.isConnected else { relay.stop(); return }
                address = "127.0.0.1:\(port)"
            }
            let client = VPhoneFridaClient()
            client.onEvent = { [weak self] event in self?.receive(event) }
            client.onExit = { [weak self] failure in
                guard let self else { return }
                self.client = nil; busy = false; pid = nil; state = "Detached"
                relay?.stop(); relay = nil
                if let failure { error = failure; append("[error] " + failure) }
                append("[session] Detached")
            }
            try client.launch()
            self.client = client
            client.armTimeout()
            client.send([
                "command": "start", "endpoint": address,
                "token": status.token, "mode": mode,
                "target": target, "source": scriptSource,
            ])
            append("[session] \(mode == "spawn" ? "Spawn" : "Attach") \(app.bundleID)")
            if let scriptURL { append("[script] " + scriptURL.lastPathComponent) }
        } catch {
            guard request == generation else { return }
            relay?.stop(); relay = nil
            busy = false; state = "Detached"; self.error = error.localizedDescription
        }
    }

    func loadScript() {
        guard let client, pid != nil, !busy, !scriptSource.isEmpty else { return }
        busy = true; error = nil
        client.armTimeout()
        client.send(["command": "load", "source": scriptSource])
        append("[script] Loading " + (scriptURL?.lastPathComponent ?? "script"))
    }

    func detach() {
        generation += 1
        guard let client else { relay?.stop(); relay = nil; busy = false; state = "Detached"; return }
        busy = true; state = "Detaching…"
        client.detach()
    }

    private func receive(_ event: VPhoneFridaClientEvent) {
        switch event.event {
        case "attached":
            client?.cancelTimeout(); busy = false; pid = event.pid
            state = "Attached — PID \(event.pid ?? 0)"
            append("[session] \(state), client \(event.message ?? "unknown")")
        case "loaded":
            client?.cancelTimeout(); busy = false
            append("[script] Script loaded")
        case "error":
            client?.cancelTimeout(); busy = false
            error = event.message ?? "Frida operation failed"
            append("[error] " + (error ?? ""))
        case "message":
            append(event.message ?? "")
        case "data":
            append("[data: base64] " + (event.message ?? ""))
        case "detached":
            busy = true; state = "Detaching…"
            append("[session] " + (event.message ?? "Target detached"))
        default: break
        }
    }

    private func append(_ text: String) {
        let timestamp = Date().formatted(.iso8601)
        log += "\(timestamp) \(text)\n"
        if log.utf8.count > 1024 * 1024 {
            log = "[Earlier output trimmed; console retains up to 1 MiB]\n" + String(log.suffix(256 * 1024))
        }
    }

    func saveLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "frida-session.log"
        panel.allowedContentTypes = [.plainText]
        panel.begin { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self, response == .OK, let url = panel.url else { return }
                do { try log.write(to: url, atomically: true, encoding: .utf8) }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}

@MainActor
final class VPhoneFridaSessionWindowController: NSObject, NSWindowDelegate {
    private let model: VPhoneFridaSessionModel
    private var window: NSWindow?
    init(control: VPhoneGuestControl) { model = VPhoneFridaSessionModel(control: control) }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Frida Session"
            window.contentViewController = NSHostingController(rootView: VPhoneFridaSessionView(model: model))
            window.contentMinSize = NSSize(width: 660, height: 510)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("vphone-frida-session")
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        Task { await model.refresh() }
    }

    nonisolated func windowWillClose(_: Notification) {
        MainActor.assumeIsolated { model.detach(); window = nil }
    }
}

private struct VPhoneFridaSessionView: View {
    @Bindable var model: VPhoneFridaSessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("App", selection: $model.selectedID) {
                    Text("Select an app…").tag("")
                    ForEach(model.apps) { app in
                        Text("\(app.displayName) — \(app.bundleID)\(app.isRunning ? " (PID \(app.pid))" : "")").tag(app.id)
                    }
                }.disabled(model.active || model.busy)
                Button("Refresh Apps") { Task { await model.refresh() } }
                    .disabled(model.active || model.busy || model.refreshing || !model.control.isConnected)
            }
            HStack {
                Picker("Mode", selection: $model.mode) {
                    Text("Spawn").tag("spawn")
                    Text("Attach to running PID").tag("attach")
                }.pickerStyle(.segmented)
            }.disabled(model.active || model.busy)
            HStack {
                Toggle("Use guest transport (VSOCK)", isOn: $model.usesGuestTransport)
                if !model.usesGuestTransport {
                    TextField("Guest IP:27042", text: $model.endpoint)
                        .font(.system(.body, design: .monospaced))
                }
            }.disabled(model.active || model.busy)
            Text("Spawn starts or relaunches the app with the selected script loaded before resuming. Attach requires a running app; refresh the list after launching it. Native client: Frida 17.25.2; use a matching server when possible.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Choose Script…") { model.chooseScript() }.disabled(model.busy)
                Text(model.scriptURL?.lastPathComponent ?? "No script selected").lineLimit(1)
                if model.scriptURL != nil {
                    Button("Clear Selection") { model.scriptURL = nil; model.scriptSource = "" }.disabled(model.busy)
                }
                Spacer()
                Button("Load / Replace Script") { model.loadScript() }
                    .disabled(model.busy || model.pid == nil || model.scriptSource.isEmpty)
            }
            Text("Choose a local UTF-8 .js file (up to 512 KiB). Scripts run in the selected guest process. Frida 17 scripts using ObjC/Swift bridges must bundle those bridges themselves.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(model.state).font(.system(.body, design: .monospaced))
                if model.busy || model.refreshing { ProgressView().controlSize(.small) }
                Spacer()
                Button("Detach") { model.detach() }.disabled(!model.active)
                Button(model.mode == "spawn" ? "Spawn" : "Attach") { Task { await model.start() } }
                    .buttonStyle(.borderedProminent).disabled(!model.canStart || model.refreshing)
            }
            if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Divider()
            ScrollView {
                Text(model.log.isEmpty ? "Session console" : model.log)
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Button("Clear Console") { model.log = "" }
                Button("Save Log…") { model.saveLog() }.disabled(model.log.isEmpty)
                Spacer()
                Text("Closing this window detaches. The app and Frida server keep running.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16)
        .onChange(of: model.control.isConnected) { _, connected in
            if !connected { model.detach() }
        }
    }
}
