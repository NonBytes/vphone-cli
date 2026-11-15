import Foundation

@MainActor
final class MockBinaryDiffGuestControl: VPhoneGuestControlling {
    var isConnected = true
    var guestIPAddress: String? { nil }
    var sandboxMachineScope: String { "" }
    func sendRequest(_ request: [String: Any]) async throws -> ([String: Any], Data?) { ([:], nil) }
    func uploadFile(path: String, data: Data, permissions: String) async throws {}
    func downloadFile(path: String) async throws -> Data { Data() }
    func pullFile(_ path: String, to localURL: URL, maximumBytes: Int?, permissions: Int?) async throws -> Int64 { 0 }
    func installIPA(localURL: URL) async throws -> String { "" }
    func screenshotJPEG() async throws -> Data { Data() }
    func guestProxy() async throws -> VPhoneProxyStatus { fatalError() }
    func runGuestToolReply(_ name: String, arguments: [String]) async throws -> [String: Any] { [:] }
    func makeFridaRelay(localPort: UInt16, guestPort: UInt16) async throws -> VPhoneFridaPortRelay { fatalError() }
    func appList() async throws -> [String: Any] { ["apps": []] }
    func call(_ method: String, params: [String: Any]) async throws -> [String: Any] { [:] }
}

@main
struct BinaryDiffTests {
    @MainActor
    static func main() async throws {
        // Create Mock Base and Target Mach-O Summaries
        let baseSummary = VPhoneMachOSecuritySummary(
            cpuType: "arm64",
            isPIE: true,
            isStackCanaryPresent: true,
            isStackExecutable: false,
            isARCEnabled: true,
            cryptID: 1,
            isEncrypted: true,
            cdHash: "0123456789abcdef",
            teamID: "ABCDEF1234",
            identifier: "com.example.prod",
            rpaths: ["@executable_path/Frameworks"],
            linkedDylibs: ["/System/Library/Frameworks/UIKit.framework/UIKit", "/usr/lib/libSystem.B.dylib"],
            entitlements: [
                VPhoneMachOEntitlementItem(key: "application-identifier", value: "ABCDEF1234.com.example.prod", isDangerous: false),
                VPhoneMachOEntitlementItem(key: "keychain-access-groups", value: "[\"group.prod\"]", isDangerous: false)
            ],
            rawEntitlementsXML: "<plist></plist>",
            loadCommands: []
        )

        // Target Summary with intentional security regressions:
        // 1. PIE disabled (regression)
        // 2. get-task-allow = true added (critical regression!)
        // 3. FridaGadget.dylib linked (suspicious dylib regression)
        // 4. Executable stack (critical regression!)
        let targetSummary = VPhoneMachOSecuritySummary(
            cpuType: "arm64",
            isPIE: false,
            isStackCanaryPresent: true,
            isStackExecutable: true,
            isARCEnabled: true,
            cryptID: 0,
            isEncrypted: false,
            cdHash: "fedcba9876543210",
            teamID: "ABCDEF1234",
            identifier: "com.example.staging",
            rpaths: ["@executable_path/Frameworks"],
            linkedDylibs: [
                "/System/Library/Frameworks/UIKit.framework/UIKit",
                "/usr/lib/libSystem.B.dylib",
                "@executable_path/Frameworks/FridaGadget.dylib"
            ],
            entitlements: [
                VPhoneMachOEntitlementItem(key: "application-identifier", value: "ABCDEF1234.com.example.staging", isDangerous: false),
                VPhoneMachOEntitlementItem(key: "get-task-allow", value: "true", isDangerous: true, riskDescription: "Allows debuggers to attach"),
                VPhoneMachOEntitlementItem(key: "keychain-access-groups", value: "[\"group.prod\"]", isDangerous: false)
            ],
            rawEntitlementsXML: "<plist></plist>",
            loadCommands: []
        )

        // 1. Diffing Test
        let report = VPhoneBinaryDiffer.diff(
            base: baseSummary,
            baseName: "ProdBuild",
            target: targetSummary,
            targetName: "StagingBuild"
        )

        precondition(report.changes.count >= 5, "Must detect all differences across hardening, entitlements, dylibs")
        precondition(report.regressions.count >= 4, "Must detect 4 regressions: PIE, Executable Stack, get-task-allow, FridaGadget")

        // 2. Specific Regression Checks
        let pieReg = report.regressions.first { $0.name.contains("PIE") }
        precondition(pieReg != nil && pieReg?.isRegression == true)

        let stackReg = report.regressions.first { $0.name.contains("Executable Stack") }
        precondition(stackReg != nil && stackReg?.severity == .critical)

        let taskAllowReg = report.regressions.first { $0.name == "get-task-allow" }
        precondition(taskAllowReg != nil && taskAllowReg?.severity == .critical)

        let dylibReg = report.regressions.first { $0.name.contains("FridaGadget") }
        precondition(dylibReg != nil && dylibReg?.severity == .high)

        // 3. Export Formats
        let md = report.markdownReport()
        precondition(md.contains("Security Regressions") && md.contains("get-task-allow"))

        let json = try report.jsonData()
        precondition(json.count > 0)
        let jsonStr = String(decoding: json, as: UTF8.self)
        precondition(jsonStr.contains("ProdBuild") && jsonStr.contains("StagingBuild"))

        // 4. Model & MASVS Finding Dispatch
        let control = MockBinaryDiffGuestControl()
        let model = VPhoneBinaryDiffModel(control: control)
        model.diffReport = report
        precondition(model.filteredItems.count == report.items.count)

        model.showRegressionsOnly = true
        precondition(model.filteredItems.count == report.regressions.count)

        let dispatched = model.sendRegressionsToMASVS()
        precondition(dispatched >= 4, "Dispatched regressions to MASVS store")

        print("Binary Diff checks passed: structural comparison, hardening regressions, get-task-allow detection, suspicious dylib flagging, markdown/json export, and MASVS dispatch.")
    }
}
