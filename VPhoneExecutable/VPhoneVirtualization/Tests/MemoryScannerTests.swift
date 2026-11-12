import AppKit
import Foundation

@main
enum MemoryScannerTests {
    static func main() async {
        // 1. Pattern Type Severities & Default Regexes
        precondition(VPhoneMemoryPatternType.jwt.severity == .high, "JWT must be high severity")
        precondition(VPhoneMemoryPatternType.privateKey.severity == .high, "Private key must be high severity")
        precondition(VPhoneMemoryPatternType.apiKey.severity == .high, "API Key must be high severity")
        precondition(!VPhoneMemoryPatternType.jwt.defaultRegex.isEmpty, "JWT regex must not be empty")

        // 2. In-Memory Buffer Scanner Engine
        let sampleApiKey = "AIza" + "SyDemoSecurityApiKeyScannerTest0123"
        let testBuffer = """
        User session data:
        Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiIxMjM0NTYiLCJyb2xlIjoidXNlciJ9.signatureValue12345
        Google API Key: \(sampleApiKey)
        Login Credentials: username=admin&password=SuperSecretPassword123!
        RSA Key: -----BEGIN RSA PRIVATE KEY-----
        """

        await MainActor.run {
            let mock = MockMemoryScannerGuestControl()
            let model = VPhoneMemoryScannerModel(control: mock)

            // Test scanning all patterns
            model.selectedPattern = .all
            let matches = model.scanBuffer(text: testBuffer)
            precondition(!matches.isEmpty, "Scanner must detect secrets in sample buffer")
            model.matches = matches
            model.selectedMatchID = matches.first?.id

            let foundTypes = Set(matches.map(\.patternType))
            precondition(foundTypes.contains(.jwt), "Must detect JWT")
            precondition(foundTypes.contains(.apiKey), "Must detect API Key")
            precondition(foundTypes.contains(.password), "Must detect password")
            precondition(foundTypes.contains(.privateKey), "Must detect private key")

            // Test Frida Script Synthesis
            let script = model.generateFridaScannerScript()
            precondition(script.contains("Process.enumerateRanges"), "Script must enumerate memory ranges")
            precondition(script.contains("readByteArray"), "Script must read byte arrays")
            precondition(script.contains("rw-"), "Script must target rw- ranges")

            // Test MASVS Finding Creation
            let finding = model.createMASVSFinding()
            precondition(finding != nil, "MASVS finding must be created")
            if let f = finding {
                precondition(f.category == .storage, "Category must be MASVS-STORAGE")
                precondition(f.severity == .high, "Severity must be high")
                precondition(f.proof.contains("VPhone App Memory Search & Scanner"), "Proof must cite scanner")
                precondition(f.remediation.contains("memset_s"), "Remediation must advise clearing memory")
            }

            // Test Clearing
            model.clearMatches()
            precondition(model.matches.isEmpty, "Matches must be empty after clear")
        }

        print("Memory Scanner checks passed: pattern detection, buffer scanner, Frida script synthesis, and MASVS finding export.")
    }
}

// MARK: - Mock Guest Controller

@MainActor
private final class MockMemoryScannerGuestControl: VPhoneGuestControlling {
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
