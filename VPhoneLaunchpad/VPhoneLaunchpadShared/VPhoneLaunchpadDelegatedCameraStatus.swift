import Foundation

/// Read-only status returned by the installed, signed Launchpad. This describes
/// delegated camera operations, not a privileged helper owned by the trial app.
nonisolated struct VPhoneLaunchpadDelegatedCameraStatus: Decodable, Sendable {
    let helper: String
    let hostReady: Bool
    let developerTools: Bool
    let installing: Bool

    var helperReady: Bool {
        helper == "ready" || helper.hasPrefix("ready (")
    }

    var cameraOperationsReady: Bool {
        helperReady && hostReady && developerTools && !installing
    }
}
