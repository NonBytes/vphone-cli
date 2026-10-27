import Foundation

@main
struct DelegatedCameraStatusTests {
    static func main() throws {
        let fixtures: [(String, Bool, Bool, Bool, Bool)] = [
            ("ready (21)", true, true, false, true),
            ("ready", true, true, false, true),
            ("not installed", true, true, false, false),
            ("ready but invalid", true, true, false, false),
            ("ready (21)", false, true, false, false),
            ("ready (21)", true, false, false, false),
            ("ready (21)", true, true, true, false),
        ]
        for (helper, host, tools, installing, expected) in fixtures {
            let value = VPhoneLaunchpadDelegatedCameraStatus(
                helper: helper, hostReady: host, developerTools: tools, installing: installing
            )
            precondition(value.cameraOperationsReady == expected, "Unexpected delegated readiness: \(helper)")
        }
        do {
            _ = try JSONDecoder().decode(VPhoneLaunchpadDelegatedCameraStatus.self, from: Data("{}".utf8))
            preconditionFailure("Missing readiness fields must not pass")
        } catch is DecodingError {}
        if let file = CommandLine.arguments.dropFirst().first {
            let live = try JSONDecoder().decode(VPhoneLaunchpadDelegatedCameraStatus.self, from: Data(contentsOf: URL(fileURLWithPath: file)))
            precondition(live.cameraOperationsReady, "Installed signed Launchpad is not ready for delegated camera operations")
            print("Live signed Launchpad status: delegated camera operations ready")
        }
        print("Delegated camera status tests passed: 8 cases")
    }
}
