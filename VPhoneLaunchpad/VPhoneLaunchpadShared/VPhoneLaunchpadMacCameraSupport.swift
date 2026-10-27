import Foundation

/// Capability is declared by the actual bound bundle, never inferred from
/// a local-build suffix: older local builds do not expose camera control.
nonisolated enum VPhoneLaunchpadMacCameraSupport {
    static func supports(_ bundle: URL) -> Bool {
        guard let data = try? Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let version = info["VPhoneMacCameraControlVersion"] as? Int, version >= 1
        else { return false }
        return FileManager.default.isExecutableFile(
            atPath: bundle.appendingPathComponent(
                "Contents/Helpers/VPhoneMacCamera.app/Contents/MacOS/vphone-mac-camera"
            ).path)
    }

    static var embedded: URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources.appendingPathComponent("EmbeddedCore/VPhone.bundle")
        return supports(url) ? url : nil
    }
}
