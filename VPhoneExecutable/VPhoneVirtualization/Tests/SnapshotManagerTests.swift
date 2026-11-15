import AppKit
import Darwin
import Foundation

@main
enum SnapshotManagerTests {
    @MainActor static func main() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vphone-snapshot-test-\(UUID().uuidString)")
        let fm = FileManager.default

        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let files = ["Disk.img", "SEPStorage", "nvram.bin"].map { tempDir.appendingPathComponent($0) }
        let baseline = Data("baseline".utf8)
        let current = Data("current".utf8)
        for file in files { try baseline.write(to: file) }

        let model = VPhoneSnapshotManagerModel(control: MockSnapshotGuestControl(), machineDirectory: tempDir)
        model.loadSnapshots()
        precondition(model.snapshots.isEmpty && !model.isVMRunning)
        try await model.createSnapshot(name: "baseline-test", note: "Clean baseline state")
        precondition(model.snapshots.count == 1 && model.snapshots.first?.note == "Clean baseline state")
        for file in files { try current.write(to: file) }

        let sep = files[1]
        let marked = chflags(sep.path, UInt32(UF_IMMUTABLE))
        precondition(marked == 0)
        defer { _ = chflags(sep.path, 0) }
        do {
            try await model.rollbackToSnapshot(name: "baseline-test")
            preconditionFailure("Rollback should fail on immutable SEPStorage")
        } catch let error as VPhoneSnapshotError {
            precondition(error.localizedDescription.contains("Could not move 'SEPStorage' aside"))
        }
        for file in files {
            let data = try Data(contentsOf: file)
            precondition(data == current, "Failed rollback changed \(file.lastPathComponent)")
        }
        let unmarked = chflags(sep.path, 0)
        precondition(unmarked == 0)

        try await model.rollbackToSnapshot(name: "baseline-test")
        for file in files {
            let data = try Data(contentsOf: file)
            precondition(data == baseline)
        }
        try await model.deleteSnapshot(name: "baseline-test")
        precondition(model.snapshots.isEmpty)

        print("Snapshot Manager checks passed: APFS CoW snapshot creation, metadata encoding, rollback state restoration, and cleanup.")
    }
}

// MARK: - Mock Guest Controller

@MainActor
private final class MockSnapshotGuestControl: VPhoneGuestControlling {
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
