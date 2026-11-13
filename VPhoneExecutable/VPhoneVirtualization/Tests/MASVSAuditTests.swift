import AppKit
import Foundation

@main
enum MASVSAuditTests {
    static func main() async {
        // 1. Scoring & Grade Calculation
        let check1 = VPhoneMASVSCheckItem(
            code: "MASVS-RESILIENCE-1",
            title: "Position Independent Executable (PIE)",
            category: .resilience,
            severity: .high,
            isPassed: false,
            detail: "PIE is disabled"
        )
        let check2 = VPhoneMASVSCheckItem(
            code: "MASVS-NETWORK-1",
            title: "App Transport Security (ATS)",
            category: .network,
            severity: .high,
            isPassed: false,
            detail: "NSAllowsArbitraryLoads is true"
        )
        let check3 = VPhoneMASVSCheckItem(
            code: "MASVS-STORAGE-1",
            title: "Data Protection",
            category: .storage,
            severity: .medium,
            isPassed: true,
            detail: "Protected"
        )

        let report = VPhoneMASVSAuditReport(
            bundleID: "com.test.audit",
            appName: "Test Audit",
            version: "1.0.0",
            build: "100",
            targetOS: "iOS 18.0",
            checks: [check1, check2, check3]
        )

        precondition(report.score == 70, "Score must be 100 - (15 + 15) = 70, got \(report.score)")
        precondition(report.grade == "B", "Grade for score 70 must be B, got \(report.grade)")
        precondition(report.criticalCount == 0, "Critical count must be 0")
        precondition(report.highCount == 2, "High count must be 2")
        precondition(report.passCount == 1, "Pass count must be 1")

        // 2. Markdown & HTML Rendering
        let markdown = report.renderMarkdown()
        precondition(markdown.contains("OWASP MASVS v2 Security Audit Report"), "Markdown must have title")
        precondition(markdown.contains("com.test.audit"), "Markdown must cite bundle ID")
        precondition(markdown.contains("Grade: **B**"), "Markdown must report grade")

        let html = report.renderHTML()
        precondition(html.contains("<!DOCTYPE html>"), "HTML must contain doctype")
        precondition(html.contains("Test Audit"), "HTML must contain app name")
        precondition(html.contains("badge-pass"), "HTML must contain pass badge")

        // 3. End-to-end Audit with Mock Guest Control
        await MainActor.run {
            let mock = MockMASVSGuestControl()
            let model = VPhoneMASVSAuditModel(control: mock)

            Task {
                await model.loadApps()
                precondition(!model.apps.isEmpty, "Model must load mock apps")

                await model.runFullAudit(bundleID: "com.test.mockbank")
                precondition(model.lastReport != nil, "Audit must produce report")
                if let r = model.lastReport {
                    precondition(!r.checks.isEmpty, "Checks list must not be empty")
                    let added = model.exportFindingsToStore()
                    precondition(added > 0, "Must export failed checks to store")
                }
            }
        }

        print("MASVS Audit checks passed: score deduction, grade evaluation, Markdown/HTML rendering, and automated audit flow.")
    }
}

// MARK: - Mock Guest Controller

@MainActor
private final class MockMASVSGuestControl: VPhoneGuestControlling {
    var isConnected = true
    var guestIPAddress: String? { nil }
    var sandboxMachineScope: String { "" }

    func call(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        if method == "apps.list" {
            return [
                "apps": [
                    [
                        "bundle_id": "com.test.mockbank",
                        "name": "Mock Bank",
                        "version": "2.1.0",
                        "build": "42",
                        "type": "user",
                        "pid": 1234,
                        "bundle_path": "/var/containers/Bundle/Application/MockBank.app",
                        "data_path": "/var/mobile/Containers/Data/Application/MockBank"
                    ]
                ]
            ]
        }
        if method == "apps.info" {
            return [
                "ats": ["NSAllowsArbitraryLoads": true],
                "permissions": ["NSCameraUsageDescription": "Camera access for QR code scanner"]
            ]
        }
        if method == "apps.binary" {
            return [
                "pie": true,
                "arc": true,
                "canary": true,
                "encrypted": false,
                "stack_executable": false,
                "weak_crypto": ["_CC_MD5"],
                "dangerous_c": ["_strcpy"],
                "entitlements": ["get-task-allow": false]
            ]
        }
        if method == "apps.url_schemes" {
            return ["schemes": ["mockbank://"]]
        }
        return [:]
    }

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
    func appList() async throws -> [String: Any] { try await call("apps.list", params: [:]) }
    func appInfo(bundleID: String) async throws -> [String: Any] { try await call("apps.info", params: ["bundleID": bundleID]) }
    func appBinary(bundleID: String) async throws -> [String: Any] { try await call("apps.binary", params: ["bundleID": bundleID]) }
    func appURLSchemes() async throws -> [String: Any] { try await call("apps.url_schemes", params: [:]) }
    func guestProxy(_ request: VPhoneProxyRequest?) async throws -> VPhoneProxyStatus {
        VPhoneProxyStatus(enabled: false, host: "", port: 0, mixed: false, automatic: false, services: 0)
    }
}
