import AppKit
import Darwin
import Foundation

@main
enum CryptoTracerTests {
    static func main() async {
        await MainActor.run {
            let mock = MockCryptoGuestControl()
            let model = VPhoneCryptoTracerModel(control: mock)

            // Test 1: Ingest Normal Secure AES-256-CBC
            model.ingestRawEvent(
                funcName: "CCCrypt",
                op: 0, // Encrypt
                alg: 0, // AES
                opts: 1, // PKCS7Padding (no ECB)
                keyHex: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
                keyLen: 32, // 256-bit
                ivHex: "1234567890abcdef1234567890abcdef",
                inHex: "48656c6c6f20576f726c64", // "Hello World"
                inLen: 11,
                outHex: "deadbeefcafebabe12345678deadbeef",
                outLen: 16
            )

            assert(model.events.count == 1, "Should ingest 1 event")
            let evt = model.events[0]
            assert(evt.operation == "Encrypt", "Operation should be Encrypt")
            assert(evt.algorithm == "AES-256-CBC", "Alg should be AES-256-CBC")
            assert(evt.isECB == false, "Should not be ECB")
            assert(evt.vulnerabilities.isEmpty, "Secure AES-CBC should have no vulnerabilities")
            assert(evt.inputASCII == "Hello World", "ASCII input should match")
            assert(model.uniqueKeysCount == 1, "Should record 1 unique key")

            // Test 2: Ingest Insecure ECB Mode
            model.ingestRawEvent(
                funcName: "CCCrypt",
                op: 0,
                alg: 0,
                opts: 2, // ECB Mode
                keyHex: "00112233445566778899aabbccddeeff",
                keyLen: 16,
                ivHex: "",
                inHex: "4141414141414141",
                inLen: 8,
                outHex: "bbbbbbbbbbbbbbbb",
                outLen: 16
            )

            assert(model.events.count == 2, "Should ingest second event")
            let ecbEvt = model.events[1]
            assert(ecbEvt.isECB == true, "Must detect ECB mode")
            assert(ecbEvt.algorithm == "AES-128-ECB", "Alg should be AES-128-ECB")
            assert(ecbEvt.vulnerabilities.contains { $0.id == "ECB_MODE" }, "Must flag ECB_MODE vulnerability")

            // Test 3: Ingest Deprecated DES Cipher & Static Zero IV
            model.ingestRawEvent(
                funcName: "CCCrypt",
                op: 1, // Decrypt
                alg: 1, // DES
                opts: 0,
                keyHex: "0102030405060708",
                keyLen: 8,
                ivHex: "0000000000000000", // All zeroes static IV
                inHex: "1122334455667788",
                inLen: 8,
                outHex: "6162636465666768",
                outLen: 8
            )

            assert(model.events.count == 3, "Should have 3 events")
            let desEvt = model.events[2]
            assert(desEvt.operation == "Decrypt", "Operation should be Decrypt")
            assert(desEvt.vulnerabilities.contains { $0.id == "DEPRECATED_ALG" }, "Must flag DEPRECATED_ALG")
            assert(desEvt.vulnerabilities.contains { $0.id == "STATIC_ZERO_IV" }, "Must flag STATIC_ZERO_IV")

            // Test 4: Filtering & Search
            model.searchText = "Hello"
            assert(model.filteredEvents.count == 1, "Search for 'Hello' should match 1 event")

            model.searchText = ""
            model.vulnerabilityOnly = true
            assert(model.filteredEvents.count == 2, "Vulnerability-only filter should return 2 events")

            model.vulnerabilityOnly = false
            model.operationFilter = "Decrypt"
            assert(model.filteredEvents.count == 1, "Decrypt filter should return 1 event")

            // Test 5: Frida Script & Audit Report Synthesis
            let script = model.generateFridaScript()
            assert(script.contains("CCCrypt"), "Frida script must hook CCCrypt")
            assert(script.contains("Interceptor.attach"), "Frida script must use Interceptor.attach")
            assert(!script.contains("ObjC.classes"), "Frida script must be QuickJS C-API compatible")

            let report = model.exportAuditReportMarkdown()
            assert(report.contains("# Cryptographic API Security Audit Report"), "Report must have markdown header")
            assert(report.contains("ECB_MODE") || report.contains("Insecure ECB Block Mode"), "Report must include ECB findings")
        }

        print("Crypto Tracer checks passed: AES/ECB detection, static IV analysis, deprecated ciphers, QuickJS script and audit reporting.")
    }
}

// MARK: - Mock Guest Controller

@MainActor
private final class MockCryptoGuestControl: VPhoneGuestControlling {
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
