import AppKit
import Foundation

@main
enum PasteboardInspectorTests {
    static func main() async {
        // 1. Risk Assessment - High Risk (Private Key)
        let privKey = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA0...\n-----END RSA PRIVATE KEY-----"
        let assessPriv = VPhoneClipboardRiskAssessment.evaluate(text: privKey)
        precondition(assessPriv.level == .high, "Private key must be high risk")
        precondition(assessPriv.title == "Private Cryptographic Key")

        // 2. Risk Assessment - High Risk (JWT)
        let jwt = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let assessJWT = VPhoneClipboardRiskAssessment.evaluate(text: jwt)
        precondition(assessJWT.level == .high, "JWT must be high risk")
        precondition(assessJWT.title == "JWT Session / Auth Token")

        // 3. Risk Assessment - High Risk (API Key)
        let apiKey = "sk_live_51MzXYZ1234567890abcdef"
        let assessAPI = VPhoneClipboardRiskAssessment.evaluate(text: apiKey)
        precondition(assessAPI.level == .high, "API Key must be high risk")

        // 4. Risk Assessment - Medium Risk (Credit Card)
        let card = "Card: 4111 2222 3333 4444"
        let assessCard = VPhoneClipboardRiskAssessment.evaluate(text: card)
        precondition(assessCard.level == .medium, "Card must be medium risk")

        // 5. Risk Assessment - Clean
        let cleanText = "Welcome to vphone"
        let assessClean = VPhoneClipboardRiskAssessment.evaluate(text: cleanText)
        precondition(assessClean.level == .clean, "Benign text must be clean")

        // 6. Payload Library Coverage
        let payloads = VPhonePasteboardPayload.builtIns
        precondition(!payloads.isEmpty, "Built-in payloads must not be empty")
        let categories = Set(payloads.map(\.category))
        precondition(categories.contains(.formatStrings), "Must contain format strings")
        precondition(categories.contains(.memoryStress), "Must contain memory stress")
        precondition(categories.contains(.xssHtml), "Must contain XSS / HTML")
        precondition(categories.contains(.sqli), "Must contain SQLi")
        precondition(categories.contains(.deepLinks), "Must contain deep links")
        precondition(categories.contains(.unicodeBidi), "Must contain unicode / BiDi")

        // 7. Model State & Audit Report
        await MainActor.run {
            let mock = MockPasteboardGuestControl()
            let model = VPhonePasteboardModel(control: mock)

            let snapshot = VPhoneClipboardSnapshot(
                text: privKey,
                types: ["public.utf8-plain-text"],
                hasImage: false,
                changeCount: 1
            )
            model.history.append(VPhoneClipboardHistoryItem(snapshot: snapshot))

            let report = model.generateAuditReport()
            precondition(report.contains("High Risk Findings: 1"), "Report must count high risk findings")
            precondition(report.contains("Private Cryptographic Key"), "Report must include finding title")
            precondition(report.contains("UIPasteboard.general"), "Report must mention UIPasteboard")

            // Test payload injection
            let expectation = "%@%@%@%@"
            Task {
                await model.injectPayload(expectation)
                precondition(mock.storedClipboardText == expectation, "Mock must receive injected payload")
            }
        }

        print("Pasteboard Inspector checks passed: risk assessment, JWT/Key leakage detection, payload categories, injection and MASVS report export.")
    }
}

// MARK: - Mock Guest Controller

@MainActor
private final class MockPasteboardGuestControl: VPhoneGuestControlling {
    var isConnected = true
    var guestIPAddress: String? { nil }
    var sandboxMachineScope: String { "" }

    var storedClipboardText: String? = ""
    var changeCount: Int = 0

    func call(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        switch method {
        case "clipboard.get":
            return [
                "text": storedClipboardText ?? "",
                "types": ["public.plain-text"],
                "has_image": false,
                "change_count": changeCount
            ]
        case "clipboard.set":
            storedClipboardText = params["text"] as? String
            changeCount += 1
            return ["ok": true]
        case "clipboard.clear":
            storedClipboardText = nil
            changeCount += 1
            return ["ok": true]
        default:
            return ["ok": true]
        }
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
