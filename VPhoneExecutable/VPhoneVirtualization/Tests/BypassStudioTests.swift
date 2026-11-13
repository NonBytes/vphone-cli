import AppKit
import Darwin
import Foundation

@main
enum BypassStudioTests {
    static func main() async {
        await MainActor.run {
            let mock = MockBypassGuestControl()
            let model = VPhoneBypassStudioModel(control: mock)

            // 1. Initial State
            precondition(!model.modules.isEmpty, "Default modules must not be empty")
            precondition(model.events.isEmpty, "Initial events must be empty")
            precondition(model.totalIntercepts == 0, "Initial intercepts must be 0")
            precondition(model.captureState == .idle, "Initial state must be idle")

            // 2. Test Module Toggling
            guard let firstMod = model.modules.first else { preconditionFailure("No modules") }
            let initialEnabled = firstMod.isEnabled
            model.toggleModule(firstMod.id)
            precondition(model.modules.first?.isEnabled != initialEnabled, "Module toggle must invert state")
            model.toggleModule(firstMod.id)
            precondition(model.modules.first?.isEnabled == initialEnabled, "Module toggle must restore state")

            // 3. Test Event Ingestion
            model.ingestBypassEvent([
                "module_id": "jb_filesystem",
                "category": "jailbreak",
                "vector": "access()",
                "target": "/Applications/Cydia.app",
                "action": "Spoofed ENOENT (-1)"
            ])

            model.ingestBypassEvent([
                "module_id": "ssl_sectrust",
                "category": "sslPinning",
                "vector": "SecTrustEvaluate",
                "target": "api.example.com",
                "action": "Forced Valid (0)"
            ])

            model.ingestBypassEvent([
                "module_id": "debug_ptrace",
                "category": "antiDebug",
                "vector": "ptrace()",
                "target": "PT_DENY_ATTACH (31)",
                "action": "Neutralized (return 0)"
            ])

            precondition(model.events.count == 3, "Must have 3 events ingested")
            precondition(model.totalIntercepts == 3, "Total intercepts must be 3, got \(model.totalIntercepts)")

            // 4. Test Filtering
            model.selectedCategoryFilter = VPhoneBypassCategory.jailbreak.rawValue
            precondition(model.filteredEvents.count == 1, "Must have 1 jailbreak event")

            model.selectedCategoryFilter = VPhoneBypassCategory.sslPinning.rawValue
            precondition(model.filteredEvents.count == 1, "Must have 1 SSL event")

            model.selectedCategoryFilter = "ALL"
            model.eventSearchQuery = "ptrace"
            precondition(model.filteredEvents.count == 1, "Search for ptrace must yield 1 event")

            model.eventSearchQuery = ""

            // 5. Test Script Generation
            let script = model.generatedBypassScript
            precondition(script.contains("VPhone Multi-Engine SSL Pinning & Jailbreak Detection Bypass Studio"), "Script header required")
            precondition(script.contains("SecTrustEvaluate"), "Script must contain SecTrust")
            precondition(script.contains("PT_DENY_ATTACH"), "Script must contain ptrace")
            precondition(script.contains("jbPaths"), "Script must contain jb paths")

            // Disable all and check
            model.disableAll()
            let emptyScript = model.generatedBypassScript
            precondition(emptyScript.contains("// jb_filesystem disabled"), "Should mark jb_filesystem as disabled")
            precondition(emptyScript.contains("// ssl_sectrust disabled"), "Should mark ssl_sectrust as disabled")

            // 6. Test Clear Events
            model.clearEvents()
            precondition(model.events.isEmpty, "Events must be empty after clear")
            precondition(model.totalIntercepts == 0, "Intercepts must be reset to 0")
        }

        print("Bypass Studio checks passed: module toggling, multi-engine event ingestion, category/search filters, telemetry metrics, and dynamic script synthesis.")
    }
}

// MARK: - Mock Guest Controller

@MainActor
private final class MockBypassGuestControl: VPhoneGuestControlling {
    var isConnected = true
    var guestIPAddress: String? { nil }
    var sandboxMachineScope: String { "" }

    func call(_ method: String, params: [String: Any]) async throws -> [String: Any] { [:] }
    func sendRequest(_ request: [String: Any]) async throws -> ([String: Any], Data?) { ([:], nil) }
    func uploadFile(path: String, data: Data, permissions: String) async throws {}
    func downloadFile(path: String) async throws -> Data { Data() }
    func pullFile(_ path: String, to localURL: URL, maximumBytes: Int?, permissions: Int?) async throws -> Int64 { 0 }
    func installIPA(localURL: URL) async throws -> String { "" }
    func screenshotJPEG() async throws -> Data { Data() }
    func guestCACertificates(_ arguments: [String]) async throws -> VPhoneCAList { VPhoneCAList(certificates: []) }
    func runGuestToolReply(_ name: String, arguments: [String]) async throws -> [String: Any] { [:] }
    func makeFridaRelay(localPort: UInt16, guestPort: UInt16) async throws -> VPhoneFridaPortRelay {
        throw VPhoneGuestControlError.connectionLost("test")
    }
    func guestProxy(_ request: VPhoneProxyRequest?) async throws -> VPhoneProxyStatus {
        VPhoneProxyStatus(enabled: false, host: "", port: 0, mixed: false, automatic: false, services: 0)
    }
}
