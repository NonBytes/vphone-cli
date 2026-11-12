import AppKit
import Foundation

@main
enum RuntimeInspectorTests {
    static func main() async {
        // 1. Runtime Method & Signature Construction
        let method = VPhoneRuntimeMethod(
            className: "JailbreakDetector",
            name: "isJailbroken",
            isClassMethod: false,
            returnType: "BOOL",
            argumentCount: 0
        )
        precondition(method.id == "-[JailbreakDetector isJailbroken]", "Method ID must be formatted correctly")
        precondition(method.signature == "- (BOOL)isJailbroken", "Signature must match")

        let classMethod = VPhoneRuntimeMethod(
            className: "SecurityCheck",
            name: "checkIntegrity",
            isClassMethod: true,
            returnType: "BOOL"
        )
        precondition(classMethod.id == "+[SecurityCheck checkIntegrity]", "Class method ID must use +")

        // 2. Watcher Script Synthesis (C-API)
        let watcherScript = VPhoneRuntimeInspectorModel.synthesizeWatcher(className: "JailbreakDetector", method: method)
        precondition(watcherScript.contains("libobjc.A.dylib"), "Watcher must use libobjc.A.dylib C exports")
        precondition(watcherScript.contains("class_getInstanceMethod"), "Instance method must use class_getInstanceMethod")
        precondition(watcherScript.contains("Interceptor.attach"), "Watcher must use Interceptor.attach")
        precondition(watcherScript.contains("isJailbroken"), "Watcher must contain method name")

        // 3. Override Script Synthesis (C-API)
        let overrideFalse = VPhoneRuntimeInspectorModel.synthesizeOverride(
            className: "JailbreakDetector",
            method: method,
            action: .forceBoolFalse
        )
        precondition(overrideFalse.contains("Interceptor.replace"), "Override must use Interceptor.replace")
        precondition(overrideFalse.contains("return ptr(0);"), "Override false must return ptr(0)")

        let overrideTrue = VPhoneRuntimeInspectorModel.synthesizeOverride(
            className: "LicenseManager",
            method: VPhoneRuntimeMethod(className: "LicenseManager", name: "isSubscriptionActive", returnType: "BOOL"),
            action: .forceBoolTrue
        )
        precondition(overrideTrue.contains("return ptr(1);"), "Override true must return ptr(1)")

        // 4. Model State, Filters, and Presets
        await MainActor.run {
            let mock = MockRuntimeGuestControl()
            let model = VPhoneRuntimeInspectorModel(control: mock)

            precondition(!model.classes.isEmpty, "Default presets must not be empty")
            precondition(model.selectedClass != nil, "A class must be selected by default")

            // Test category filtering
            model.filterCategory = .securityOnly
            precondition(!model.filteredClasses.isEmpty, "Security filter must return classes")

            // Test search query
            model.searchQuery = "jailbreak"
            let searchResults = model.filteredClasses
            precondition(!searchResults.isEmpty, "Search for 'jailbreak' must return matching classes")
            precondition(searchResults.contains(where: { $0.className == "JailbreakDetector" }))

            model.searchQuery = ""

            // Test MASVS Finding Creation
            let finding = model.createMASVSFinding()
            precondition(finding != nil, "Finding must be generated for selected class/method")
            if let f = finding {
                precondition(f.category == .resilience, "Category must be resilience")
                precondition(f.severity == .high, "Severity must be high")
                precondition(f.proof.contains("Frida Dynamic Interceptor Hook"), "Proof must contain hook")
            }

            // Test Class Dumper Script
            let dumper = model.generateClassDumperScript()
            precondition(dumper.contains("objc_getClassList"), "Dumper must use objc_getClassList")
            precondition(dumper.contains("class_copyMethodList"), "Dumper must use class_copyMethodList")
        }

        print("Runtime Inspector checks passed: method signatures, C-API Frida watcher synthesis, return value override, presets, and MASVS finding export.")
    }
}

// MARK: - Mock Guest Controller

@MainActor
private final class MockRuntimeGuestControl: VPhoneGuestControlling {
    var isConnected = true
    var guestIPAddress: String? { nil }
    var sandboxMachineScope: String { "" }

    func call(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        if method == "apps.list" {
            return [
                "apps": [
                    [
                        "id": "com.target.bankapp",
                        "name": "Target Bank",
                        "bundle": "/Applications/TargetBank.app",
                        "running": true
                    ]
                ]
            ]
        }
        return [:]
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
