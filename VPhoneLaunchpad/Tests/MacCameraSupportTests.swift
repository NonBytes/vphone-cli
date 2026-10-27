import Foundation

@main
struct MacCameraSupportTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("camera-support-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = contents.appendingPathComponent("Info.plist")
        func writeVersion(_ version: Int?) throws {
            var values: [String: Any] = ["CFBundleShortVersionString": "2.14.0"]
            if let version { values["VPhoneMacCameraControlVersion"] = version }
            try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(to: info)
        }
        try writeVersion(nil)
        precondition(!VPhoneLaunchpadMacCameraSupport.supports(root), "Version alone must not imply camera support")
        try writeVersion(1)
        precondition(!VPhoneLaunchpadMacCameraSupport.supports(root), "Missing helper must not be accepted")
        let helper = contents.appendingPathComponent("Helpers/VPhoneMacCamera.app/Contents/MacOS/vphone-mac-camera")
        try FileManager.default.createDirectory(
            at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test fixture".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: helper.path)
        precondition(!VPhoneLaunchpadMacCameraSupport.supports(root), "Non-executable helper must not be accepted")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        precondition(
            VPhoneLaunchpadMacCameraSupport.supports(root), "Declared capability and helper should be detected")
        try writeVersion(0)
        precondition(
            !VPhoneLaunchpadMacCameraSupport.supports(root), "Unsupported control version must not be accepted")
        try Data("not a plist".utf8).write(to: info)
        precondition(!VPhoneLaunchpadMacCameraSupport.supports(root), "Malformed capability metadata must be rejected")
        print("Mac camera capability tests passed: 6 cases")
    }
}
