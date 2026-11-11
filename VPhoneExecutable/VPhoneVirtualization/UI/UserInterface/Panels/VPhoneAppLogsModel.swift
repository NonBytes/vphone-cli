import Foundation
#if canImport(VPhonePentestKit)
import VPhonePentestKit
#endif
import SwiftUI

@MainActor
@Observable
final class VPhoneAppLogsModel {
    let control: VPhoneGuestControl
    var apps: [VPhoneAppRecord] = []
    var selectedID = ""
    var tab = 0
    var loadingApps = false
    var resolving = false
    var error: String?
    var console: VPhoneConsoleModel?
    var crashes: VPhoneCrashLogsModel?
    private var generation = 0

    init(control: VPhoneGuestControl) { self.control = control }
    var selectedApp: VPhoneAppRecord? { apps.first { $0.bundleID == selectedID } }

    func refreshApps() async {
        guard !loadingApps, control.isConnected else { return }
        loadingApps = true
        defer { loadingApps = false }
        do {
            let result = try await control.call("apps.list")
            apps = result.objects("apps").compactMap(VPhoneAppRecord.init(json:)).sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            if !selectedID.isEmpty, selectedApp == nil { selectedID = "" }
        } catch { self.error = error.localizedDescription }
    }

    func configure() async {
        generation += 1
        let current = generation
        console?.isRunning = false; console = nil; crashes = nil; error = nil
        guard let app = selectedApp else { resolving = false; return }
        crashes = VPhoneCrashLogsModel(control: control, bundleID: app.bundleID)
        resolving = true
        defer { if current == generation { resolving = false } }
        do {
            let info = try await control.call("apps.info", params: ["bundle_id": app.bundleID])
            let scope = try VPhoneAppLogScope(bundleID: app.bundleID, executable: info.string("executable") ?? "")
            guard current == generation, !Task.isCancelled else { return }
            console = VPhoneConsoleModel(control: control, appScope: scope)
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    func close() {
        generation += 1
        console?.isRunning = false
    }
}

