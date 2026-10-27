import Foundation
import SwiftUI

/// The source-built development app cannot authenticate to the release's
/// privileged helper. An explicitly selected development companion delegates
/// installation to the installed, signed app's existing CLI instead. It does
/// not replace, re-sign or change the helper's client requirement.
nonisolated enum VPhoneLaunchpadCameraDevelopment {
    static var isEnabled: Bool {
        #if DEBUG
            (Bundle.main.object(forInfoDictionaryKey: "VPhoneCameraDevelopmentCompanion") as? Bool == true)
            || ProcessInfo.processInfo.environment["VPHONE_LAUNCHPAD_CAMERA_COMPANION"] == "1"
        #else
            false
        #endif
    }

    static let officialCLI = URL(
        fileURLWithPath:
            "/Applications/vphone-launchpad.app/Contents/MacOS/vphone-launchpad-cli")

    @concurrent static func run(_ arguments: [String]) async throws -> String? {
        let data = try await output(arguments)
        return ((try JSONSerialization.jsonObject(with: data)) as? [String: Any])?["version"] as? String
    }

    @concurrent static func helperStatus() async throws -> VPhoneLaunchpadDelegatedCameraStatus {
        let data = try await output(["status"])
        return try JSONDecoder().decode(VPhoneLaunchpadDelegatedCameraStatus.self, from: data)
    }

    @concurrent static func verify(_ version: String) async throws {
        let data = try await output(["bundle", "verify", version])
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              result["policy"] as? String == "passed", result["preflight"] as? String == "passed"
        else { throw VPhoneLaunchpadError("The installed Launchpad did not approve this Core Bundle.") }
    }

    @concurrent private static func output(_ arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = officialCLI
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        // The official app owns progress, errors and any administrator prompt.
        process.standardError = FileHandle.standardError
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw VPhoneLaunchpadError("The installed Launchpad could not complete the operation.")
        }
        return data
    }
}

struct VPhoneLaunchpadMacCameraBundleSection: View {
    @Environment(VPhoneLaunchpadModel.self) private var model
    @State private var busy = false
    @State private var error: VPhoneLaunchpadError?

    private var cameraVersion: String? {
        model.bundles.installed.filter {
            VPhoneLaunchpadMacCameraSupport.supports(VPhoneLaunchpadBundleStore.bundle(version: $0.version))
        }.max { $0.receipt.installedAt < $1.receipt.installedAt }?.version
    }

    var body: some View {
        Section("Mac Camera") {
            Text("Use your Mac camera in iPhone and iPad guests. The included Core Bundle supplies the camera source.")
            if let version = cameraVersion {
                LabeledContent("Installed", value: version)
                Button("Use for New Machines") {
                    Task {
                        busy = true
                        defer { busy = false }
                        do {
                            if VPhoneLaunchpadCameraDevelopment.isEnabled {
                                _ = try await VPhoneLaunchpadCameraDevelopment.run(["bundle", "set-default", version])
                                model.bundles.defaultVersion = version
                            } else {
                                await model.bundles.setDefault(version)
                            }
                        } catch { self.error = VPhoneLaunchpadError(error.localizedDescription) }
                    }
                }
                .disabled(busy)
            }
            if let embedded = VPhoneLaunchpadMacCameraSupport.embedded {
                Button(busy ? "Installing…" : "Install Included Camera Bundle") {
                    Task {
                        busy = true
                        defer { busy = false }
                        do {
                            if VPhoneLaunchpadCameraDevelopment.isEnabled {
                                let result = try await VPhoneLaunchpadCameraDevelopment.run([
                                    "bundle", "install-local", embedded.path,
                                ])
                                await model.bundles.refresh()
                                if let version = result {
                                    model.bundles.defaultVersion = version
                                }
                            } else {
                                await model.bundles.installLocal(embedded)
                                model.present(.bundleInstall)
                            }
                        } catch { self.error = VPhoneLaunchpadError(error.localizedDescription) }
                    }
                }
                .disabled(busy || (!model.canInstallBundles && !VPhoneLaunchpadCameraDevelopment.isEnabled))
            } else {
                Text("Build the camera edition to include a camera-enabled Core Bundle.")
                    .foregroundStyle(.secondary)
            }
        }
        .errorAlert($error)
    }
}

struct VPhoneLaunchpadMachineCameraSection: View {
    let machine: VPhoneLaunchpadMachine
    @Environment(VPhoneLaunchpadModel.self) private var model
    @State private var busy = false
    @State private var message = ""
    @State private var error: VPhoneLaunchpadError?

    private var supportsCamera: Bool {
        guard let version = model.machines.bundleVersion(for: machine.path) else { return false }
        return VPhoneLaunchpadMacCameraSupport.supports(VPhoneLaunchpadBundleStore.bundle(version: version))
    }

    private var cameraVersion: String? {
        model.bundles.installed.filter {
            VPhoneLaunchpadMacCameraSupport.supports(VPhoneLaunchpadBundleStore.bundle(version: $0.version))
        }.max { $0.receipt.installedAt < $1.receipt.installedAt }?.version
    }

    var body: some View {
        Section("Mac Camera") {
            if supportsCamera {
                HStack {
                    Button("Start Mac Camera", systemImage: "camera") { send("start") }
                    Button("Stop Camera", systemImage: "camera.slash") { send("stop") }
                }
                .disabled(busy || model.machines.state(of: machine.path) != .running)
                Text("Start the machine first. Camera access is requested by the Mac Camera companion.")
                    .font(.caption).foregroundStyle(.secondary)
                if !message.isEmpty { Text(message).font(.caption) }
            } else {
                Text("This machine uses a Core Bundle without Mac Camera control.")
                    .foregroundStyle(.secondary)
                if let version = cameraVersion {
                    Button("Use Camera Bundle for This Machine") {
                        Task {
                            busy = true
                            defer { busy = false }
                            do {
                                if VPhoneLaunchpadCameraDevelopment.isEnabled {
                                    _ = try await VPhoneLaunchpadCameraDevelopment.run([
                                        "vm", "set-bundle", machine.name, version, "--root",
                                        machine.path.url.deletingLastPathComponent().path,
                                    ])
                                    await model.machines.refresh()
                                } else {
                                    await model.machines.setBundle(
                                        version, for: [machine.path], updateEnvironment: false)
                                }
                            } catch { self.error = VPhoneLaunchpadError(error.localizedDescription) }
                        }
                    }
                    .disabled(busy || model.machines.state(of: machine.path) != .stopped)
                    Text("Stop the machine before switching. Guest data and firmware stay in place.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Install Camera Bundle…") { model.present(.coreBundle) }
                }
            }
        }
        .errorAlert($error)
        .id(machine.path)
    }

    private func send(_ action: String) {
        Task {
            busy = true
            defer { busy = false }
            do {
                let reply = try await VPhoneLaunchpadGuestSocket.send(
                    ["t": "camera", "action": action, "screen": false],
                    socketPath: machine.path.url.appendingPathComponent("vphone.sock").path, timeout: 15
                )
                if let object = reply as? [String: Any], let result = object["result"] as? [String: Any] {
                    let streaming = result["streaming"] as? Bool ?? false
                    message =
                        streaming
                        ? String(localized: "Mac Camera streaming requested") : String(localized: "Mac Camera stopped")
                }
            } catch { self.error = VPhoneLaunchpadError(error.localizedDescription) }
        }
    }
}
