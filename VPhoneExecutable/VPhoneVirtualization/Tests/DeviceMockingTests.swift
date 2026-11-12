import AppKit
import Foundation

@main
enum DeviceMockingTests {
    static func main() async {
        // 1. Battery Power State Values
        precondition(VPhoneBatteryPowerState.unplugged.connectivityValue == 2, "Unplugged must have connectivity value 2")
        precondition(VPhoneBatteryPowerState.charging.connectivityValue == 1, "Charging must have connectivity value 1")
        precondition(VPhoneBatteryPowerState.full.connectivityValue == 3, "Full must have connectivity value 3")

        // 2. Biometric Mock Mode Frida Script Generation
        for mode in VPhoneBiometricMockMode.allCases {
            let script = mode.fridaScript
            precondition(!script.isEmpty, "Mode \(mode.rawValue) must have non-empty frida script")
            if mode == .forceSuccess {
                precondition(script.contains("evaluatePolicy"), "forceSuccess must hook evaluatePolicy")
                precondition(script.contains("canEvaluatePolicy"), "forceSuccess must hook canEvaluatePolicy")
            } else if mode == .userCancel {
                precondition(script.contains("evaluatePolicy"), "userCancel must hook evaluatePolicy")
            }
        }

        // 3. Model State & Battery Application
        await MainActor.run {
            let mock = MockDeviceMockingGuestControl()
            let model = VPhoneDeviceMockingModel(control: mock)

            Task {
                await model.setQuickBattery(percent: 20, state: .unplugged)
                precondition(model.batteryLevel == 20, "Battery level must be set to 20")
                precondition(model.powerState == .unplugged, "Power state must be unplugged")

                await model.applyBiometricMode(.forceSuccess)
                precondition(model.isBiometricHookActive, "Biometric hook must be active")
                precondition(model.biometricMode == .forceSuccess, "Biometric mode must be forceSuccess")
            }
        }

        print("Device Mocking checks passed: battery simulation, biometric mock modes, and Frida script synthesis.")
    }
}

// MARK: - Mock Guest Controller

@MainActor
private final class MockDeviceMockingGuestControl: VPhoneGuestControlling {
    var isConnected = true
    var guestIPAddress: String? { nil }
    var sandboxMachineScope: String { "" }

    func call(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        return ["ok": true]
    }

    func downloadFile(path: String) async throws -> Data { Data() }
    func sendRequest(_: [String: Any]) async throws -> ([String: Any], Data?) { ([:], nil) }
    func uploadFile(path: String, data: Data, permissions: String) async throws {}
    func pullFile(_: String, to: URL, maximumBytes: Int?, permissions: Int?) async throws -> Int64 { 0 }
    func installIPA(localURL: URL) async throws -> String { "" }
    func screenshotJPEG() async throws -> Data { Data() }
    func guestProxy() async throws -> VPhoneProxyStatus { fatalError() }
    func runGuestToolReply(_: String, arguments: [String]) async throws -> [String: Any] { [:] }
    func makeFridaRelay(localPort: UInt16, guestPort: UInt16) async throws -> VPhoneFridaPortRelay { fatalError() }
}
