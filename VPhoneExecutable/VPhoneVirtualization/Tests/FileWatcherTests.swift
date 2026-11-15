import AppKit
import Darwin
import Foundation

@main
enum FileWatcherTests {
    @MainActor
    static func main() async {
        let mock = MockFileWatcherGuestControl()
        let model = VPhoneFileWatcherModel(control: mock)

        // 1. Initial State
        precondition(model.events.isEmpty, "Initial events must be empty")
        precondition(model.selectedEvent == nil, "No event initially selected")
        precondition(model.captureState == .idle, "Initial capture state must be idle")

        // 2. Ingest Standard Write
        model.ingest(
            operation: .write,
            path: "/private/var/mobile/Containers/Data/Application/1234/Documents/profile.jpg",
            size: 2048,
            process: "TargetApp",
            contentSnippet: "JPEG DATA",
            callerSymbol: "saveProfileImage()"
        )

        precondition(model.events.count == 1, "Must have 1 event")
        guard let ev1 = model.events.first else { preconditionFailure("Missing event 1") }
        precondition(ev1.operation == .write, "Operation must be write")
        precondition(ev1.category == .documents, "Category must be Documents: \(ev1.category)")
        precondition(ev1.fileName == "profile.jpg", "File name must be profile.jpg")
        precondition(!ev1.hasRisk, "Standard image write should have no risk")

        // 3. Ingest Plaintext Token / Secret Write (Risk High)
        model.ingest(
            operation: .write,
            path: "/private/var/mobile/Containers/Data/Application/1234/Documents/session.json",
            size: 128,
            process: "TargetApp",
            contentSnippet: "{\"access_token\": \"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...\", \"bearer\": \"secret123\"}",
            callerSymbol: "saveAuthToken()"
        )

        precondition(model.events.count == 2, "Must have 2 events")
        guard let ev2 = model.events.first else { preconditionFailure("Missing event 2") }
        precondition(ev2.hasRisk, "Auth token in JSON must trigger risk")
        precondition(ev2.highestSeverity == .high, "Auth token severity must be High")
        precondition(ev2.risks.first?.masvsID == "MASVS-STORAGE-1", "MASVS ID must be MASVS-STORAGE-1")

        // 4. Ingest Unencrypted Database Creation (Risk Medium)
        model.ingest(
            operation: .create,
            path: "/private/var/mobile/Containers/Data/Application/1234/Library/Application Support/user_data.sqlite",
            size: 4096,
            process: "TargetApp",
            contentSnippet: "SQLite format 3\0",
            callerSymbol: "sqlite3_open()"
        )

        precondition(model.events.count == 3, "Must have 3 events")
        guard let ev3 = model.events.first else { preconditionFailure("Missing event 3") }
        precondition(ev3.category == .appSupport, "Category must be App Support")
        precondition(ev3.hasRisk, "Unencrypted SQLite must trigger risk")
        precondition(ev3.highestSeverity == .medium, "Database severity must be Medium")
        precondition(ev3.risks.first?.masvsID == "MASVS-STORAGE-2", "MASVS ID must be MASVS-STORAGE-2")

        // 5. Ingest NSUserDefaults / Preferences with Auth Flag
        model.ingest(
            operation: .write,
            path: "/private/var/mobile/Containers/Data/Application/1234/Library/Preferences/com.example.app.plist",
            size: 64,
            process: "TargetApp",
            contentSnippet: "user_id = 998812, auth_status = 1",
            callerSymbol: "NSUserDefaults.setObject:forKey:"
        )

        precondition(model.events.count == 4, "Must have 4 events")
        guard let ev4 = model.events.first else { preconditionFailure("Missing event 4") }
        precondition(ev4.category == .preferences, "Category must be Preferences")
        precondition(ev4.hasRisk, "Sensitive preference write must trigger risk")

        // 6. Test Filtering
        model.risksOnly = true
        precondition(model.filteredEvents.count == 3, "Filtered risksOnly must be 3 (out of 4)")

        model.risksOnly = false
        model.filterCategory = "Documents"
        precondition(model.filteredEvents.count == 2, "Filtered by Documents must be 2")

        model.filterCategory = "ALL"
        model.filterOperation = "CREATE"
        precondition(model.filteredEvents.count == 1, "Filtered by CREATE must be 1")

        model.filterOperation = "ALL"
        model.filterSearch = "sqlite"
        precondition(model.filteredEvents.count == 1, "Filtered search for sqlite must be 1")
        model.filterSearch = ""

        // 7. Test Export JSON and CSV
        let json = model.exportJSON()
        precondition(!json.isEmpty, "Exported JSON must not be empty")
        let parsed = (try? JSONSerialization.jsonObject(with: json)) as? [[String: Any]]
        precondition(parsed?.count == 4, "Exported JSON must contain 4 records")

        let csv = model.exportCSV()
        precondition(csv.contains("Timestamp,Operation,Category,Path"), "CSV must contain header")
        precondition(csv.contains("session.json"), "CSV must contain session.json")

        // 8. Test Finding Dispatch to MASVS Store
        let finding = ev2.risks.first!
        let ok = model.sendHitToFindings(event: ev2, finding: finding)
        precondition(ok, "sendHitToFindings must return true")
        precondition(!VPhoneMASVSFindingStore.shared.findings.isEmpty, "MASVS FindingStore must contain new finding")

        // 9. Test Frida Script Generation
        let script = model.fridaHookScript(containerPath: "/private/var/mobile/Containers/Data/Application/1234")
        precondition(script.contains("VPhone Sandbox File Watcher"), "Script must contain header")
        precondition(script.contains("writeToFile:atomically:"), "Script must hook NSData write")
        precondition(script.contains("NSUserDefaults"), "Script must hook NSUserDefaults")

        // 10. Clear Events
        model.clearEvents()
        precondition(model.events.isEmpty, "Events must be empty after clear")

        model.selectedApp = VPhoneAppRecord(json: ["bundle_id": "fixture.app", "pid": 42])
        mock.documents = [["name": "removed.txt", "type": "file", "size": 10]]
        await model.startLiveCapture()
        defer { model.stopLiveCapture() }
        await model.pollContainer()
        precondition(model.events.isEmpty, "The initial scan is a baseline")

        mock.documents = [["name": "added.txt", "type": "file", "size": 20]]
        await model.pollContainer()
        precondition(model.events.count == 2)
        precondition(model.events.contains { $0.operation == .create && $0.relativePath == "Documents/added.txt" })
        precondition(model.events.contains { $0.operation == .delete && $0.relativePath == "Documents/removed.txt" })

        print("File Watcher checks passed: operation tracking, category resolution, plaintext secret / unencrypted DB risk heuristics, MASVS finding dispatch, and JSON/CSV timeline export.")
    }
}

// MARK: - Mock Controller

@MainActor
private final class MockFileWatcherGuestControl: VPhoneGuestControlling {
    var isConnected = true
    var guestIPAddress: String? { nil }
    var sandboxMachineScope: String { "" }

    var documents: [[String: Any]] = []

    func call(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        switch (method, params["path"] as? String) {
        case ("apps.info", _): return ["data_path": "/fixture"]
        case ("files.list", "/fixture"): return ["entries": [["name": "Documents", "type": "dir"]]]
        case ("files.list", "/fixture/Documents"): return ["entries": documents]
        default: return [:]
        }
    }
    func sendRequest(_ request: [String: Any]) async throws -> ([String: Any], Data?) { ([:], nil) }
    func uploadFile(path: String, data: Data, permissions: String) async throws {}
    func downloadFile(path: String) async throws -> Data { Data() }
    func pullFile(_ path: String, to localURL: URL, maximumBytes: Int?, permissions: Int?) async throws -> Int64 { 0 }
    func installIPA(localURL: URL) async throws -> String { "" }
    func screenshotJPEG() async throws -> Data { Data() }
    func guestCACertificates(_ arguments: [String]) async throws -> VPhoneCAList { VPhoneCAList(certificates: []) }
    func runGuestToolReply(_ name: String, arguments: [String]) async throws -> [String: Any] { [:] }
    func makeFridaRelay(localPort: UInt16, guestPort: UInt16) async throws -> VPhoneFridaPortRelay { fatalError() }
}
