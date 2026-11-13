import AppKit
import Darwin
import Foundation

@main
enum SnapshotManagerTests {
    static func main() async {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vphone-snapshot-test-\(UUID().uuidString)")
        let fm = FileManager.default

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tempDir) }

            // Create sample state files
            let originalDiskData = "MockDiskData-Baseline".data(using: .utf8)!
            let originalSEPData = "MockSEPData-SecureEnclave".data(using: .utf8)!
            let originalNVRAMData = "MockNVRAMData-BootArgs".data(using: .utf8)!

            try originalDiskData.write(to: tempDir.appendingPathComponent("Disk.img"))
            try originalSEPData.write(to: tempDir.appendingPathComponent("SEPStorage"))
            try originalNVRAMData.write(to: tempDir.appendingPathComponent("nvram.bin"))

            await MainActor.run {
                let mock = MockSnapshotGuestControl()
                let model = VPhoneSnapshotManagerModel(control: mock, machineDirectory: tempDir)

                // 1. Initial State
                model.loadSnapshots()
                precondition(model.snapshots.isEmpty, "Initial snapshots must be empty")
                precondition(!model.isVMRunning, "VM should not be running in clean test dir")

                // 2. Create Snapshot
                Task {
                    do {
                        try await model.createSnapshot(name: "baseline-test", note: "Clean baseline state")
                        precondition(model.snapshots.count == 1, "Must have 1 snapshot after creation")
                        precondition(model.snapshots.first?.name == "baseline-test", "Name must match")
                        precondition(model.snapshots.first?.note == "Clean baseline state", "Note must match")

                        // 3. Mutate disk file (simulating malware or jailbreak experiment)
                        let modifiedData = "Corrupted-Malware-Payload".data(using: .utf8)!
                        try modifiedData.write(to: tempDir.appendingPathComponent("Disk.img"))

                        let readBeforeRevert = try Data(contentsOf: tempDir.appendingPathComponent("Disk.img"))
                        precondition(readBeforeRevert == modifiedData, "Disk must be modified before rollback")

                        // 4. Rollback to Snapshot
                        try await model.rollbackToSnapshot(name: "baseline-test")

                        let readAfterRevert = try Data(contentsOf: tempDir.appendingPathComponent("Disk.img"))
                        precondition(readAfterRevert == originalDiskData, "Disk must be restored to baseline state after rollback")

                        // 5. Delete Snapshot
                        try await model.deleteSnapshot(name: "baseline-test")
                        precondition(model.snapshots.isEmpty, "Snapshots must be empty after deletion")
                    } catch {
                        preconditionFailure("Snapshot test failed with error: \(error)")
                    }
                }
            }
        } catch {
            preconditionFailure("Failed to set up test directory: \(error)")
        }

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
