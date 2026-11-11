import Foundation
import Darwin

@MainActor final class VPhoneGuestControl: VPhoneGuestControlling {
    var isConnected = true
    var guestIPAddress: String? { nil }
    var sandboxMachineScope: String { "" }
    var slow = false
    func call(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        try await call(method)
    }
    func sendRequest(_ request: [String: Any]) async throws -> ([String: Any], Data?) { ([:], nil) }
    func uploadFile(path: String, data: Data, permissions: String) async throws {}
    func downloadFile(path: String) async throws -> Data { Data() }
    func pullFile(_ path: String, to localURL: URL, maximumBytes: Int?, permissions: Int?) async throws -> Int64 { 0 }
    func installIPA(localURL: URL) async throws -> String { "" }
    func guestProxy() async throws -> VPhoneProxyStatus { fatalError() }
    func runGuestToolReply(_ name: String, arguments: [String]) async throws -> [String: Any] { [:] }
    func makeFridaRelay(localPort: UInt16, guestPort: UInt16) async throws -> VPhoneFridaPortRelay { fatalError() }
    func appList() async throws -> [String: Any] { ["apps": [["bundle_id": "com.example.fixture", "name": "Fixture", "version": "3", "build": "42"]]] }
    func screenshotJPEG() async throws -> Data { Data([0xff, 0xd8, 0xff]) }
    func call(_ method: String) async throws -> [String: Any] {
        precondition(method == "device.info")
        if slow { try await Task.sleep(for: .milliseconds(80)) }
        return ["ios_version": "27.0.1", "udid": "PRIVATE-DEVICE-ID", "host": "PRIVATE-HOST"]
    }
}
@main struct EvidenceExportTests {
    @MainActor static func main() async throws {
        func rejects(_ operation: () throws -> Void) { do { try operation(); fatalError("Invalid input accepted") } catch {} }
        let fixture = "Authorization: Bearer synthetic-auth\n{\"token\":\"synthetic-json\",\"password\":\"synthetic-pass\"}\nhttps://fixture.test/?access_token=synthetic-query&x=1\nprivate-literal"
        let text = VPhoneEvidencePackage.redact(fixture, literals: ["private-literal"])
        for secret in ["synthetic-auth", "synthetic-json", "synthetic-pass", "synthetic-query", "private-literal"] { precondition(!text.contains(secret), "Secret leaked: " + secret) }
        precondition(text.contains("&x=1"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.log")
        try Data(fixture.utf8).write(to: source)
        let link = root.appendingPathComponent("link.log")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        rejects { _ = try VPhoneEvidencePackage.read(link) }
        rejects { _ = try VPhoneEvidencePackage.read(root) }
        let sourceData = try VPhoneEvidencePackage.read(source)
        precondition(sourceData == Data(fixture.utf8))
        let control = VPhoneGuestControl(), model = VPhoneEvidenceExportModel(control: control)
        await model.refresh(); model.selectedID = "com.example.fixture"; model.title = "Synthetic evidence"
        model.attachments = [.init(name: "attachment.txt", data: Data(fixture.utf8), isText: true), .init(name: "capture.pcap", data: Data([1,2,3]), isText: false)]
        model.secrets = "private-literal"
        await model.prepare()
        precondition(model.reviewed.count == 2, "Binary originals must be excluded by default")
        let context = String(decoding: model.reviewed[0].data, as: UTF8.self)
        precondition(context.contains("27.0.1") && context.contains("42") && !context.contains("PRIVATE-"))
        precondition(!String(decoding: model.reviewed[1].data, as: UTF8.self).contains("synthetic-json"))
        let snapshot = model.reviewed
        let folder = try VPhoneEvidencePackage.write(snapshot, to: root)
        var metadata = stat(); precondition(stat(folder.path, &metadata) == 0 && metadata.st_mode & 0o777 == 0o700)
        let manifestURL = folder.appendingPathComponent("manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        let entries = manifest["files"] as! [[String: Any]]
        precondition(entries.count == 2)
        for file in snapshot {
            let output = folder.appendingPathComponent(file.name), data = try Data(contentsOf: output)
            precondition(data == file.data)
            precondition(stat(output.path, &metadata) == 0 && metadata.st_mode & 0o777 == 0o600)
            let entry = entries.first { $0["file"] as? String == file.name }!
            precondition(entry["sha256"] as? String == VPhoneEvidencePackage.hash(data))
        }
        model.notes = "Changed after review"; precondition(model.reviewed.isEmpty)
        model.allowOriginals = true; await model.prepare(); precondition(model.reviewed.count == 3)
        precondition(model.reviewed.last!.data == Data([1,2,3]))
        rejects { _ = try VPhoneEvidencePackage.write([.init(name: "../escape", data: Data(), isText: true)], to: root) }
        rejects { _ = try VPhoneEvidencePackage.write([.init(name: "manifest.json", data: Data(), isText: true)], to: root) }
        rejects { _ = try VPhoneEvidencePackage.write([snapshot[0],snapshot[0]], to: root) }
        control.slow = true
        let preparing = Task { await model.prepare() }
        try await Task.sleep(for: .milliseconds(10)); model.close(); await preparing.value
        precondition(model.reviewed.isEmpty && model.attachments.isEmpty && model.secrets.isEmpty)
        print("PASS: Evidence redaction, provenance, binary opt-in, stale review, private export and manifest hashes")
    }
}
