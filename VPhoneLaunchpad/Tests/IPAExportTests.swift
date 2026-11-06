import Foundation
import CryptoKit
import Darwin

@MainActor final class VPhoneGuestControl {
    let root: URL
    var isConnected = true
    var operations: [String] = []
    var deployments = 0
    var delayReads = false
    var mutateAfterRead = false
    init(root: URL) { self.root = root }
    func appInfo(bundleID: String) async throws -> [String: Any] {
        ["bundle_id": "com.example.export-fixture", "path": root.path, "version": "1.0", "build": "9"]
    }
    func appBinary(bundleID: String) async throws -> [String: Any] { ["encrypted": true] }
    func deployGuestTool(_ name: String) async throws -> String {
        precondition(name == "vphone-guest-export"); deployments += 1; return "/synthetic/helper"
    }
    func runGuestTool<T: Decodable>(_ path: String, arguments: [String], as type: T.Type) async throws -> T {
        precondition(path == "/synthetic/helper" && arguments[1] == root.path)
        operations.append(arguments[0])
        let encoded: Data
        switch arguments[0] {
        case "manifest": encoded = try JSONEncoder().encode(VPhoneIPAReader.manifest(root: root.path))
        case "read":
            if delayReads { try await Task.sleep(for: .milliseconds(100)) }
            let requests = try JSONDecoder().decode([VPhoneIPARead].self, from: Data(arguments[2].utf8))
            encoded = try JSONEncoder().encode(VPhoneIPAReader.read(root: root.path, requests: requests))
            if mutateAfterRead {
                mutateAfterRead = false
                try Data("changed during export".utf8).write(to: root.appendingPathComponent("Nested/data.bin"))
            }
        default: fatalError("Unexpected guest operation")
        }
        return try JSONDecoder().decode(T.self, from: encoded)
    }
}

@main struct IPAExportTests {
    static func rejects(_ operation: () throws -> Void) { do { try operation(); fatalError("Unsafe export accepted") } catch {} }
    static func changed(_ entry: VPhoneIPAEntry, path: String? = nil, size: Int64? = nil, kind: VPhoneIPAEntry.Kind? = nil, target: String? = nil) -> VPhoneIPAEntry {
        .init(path: path ?? entry.path, kind: kind ?? entry.kind, size: size ?? entry.size, mode: entry.mode, modified: entry.modified, modifiedNanoseconds: entry.modifiedNanoseconds, device: entry.device, inode: entry.inode, target: target)
    }
    static func run(_ executable: String, _ args: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = args
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); precondition(process.terminationStatus == 0)
    }
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/vphone-ipa-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Fixture.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Nested/EmptyDirectory"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier":"com.example.export-fixture", "CFBundleExecutable":"Fixture", "CFBundleShortVersionString":"1.0", "CFBundleVersion":"9"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: app.appendingPathComponent("Info.plist"))
        let executable = Data((0..<700_019).map { UInt8($0 % 251) })
        try executable.write(to: app.appendingPathComponent("Fixture"))
        try FileManager.default.setAttributes([.posixPermissions:0o755], ofItemAtPath:app.appendingPathComponent("Fixture").path)
        let resource = Data([0,1,2,0xff,3])
        try resource.write(to: app.appendingPathComponent("Nested/data.bin"))
        try Data().write(to: app.appendingPathComponent("Nested/empty"))
        for index in 0..<130 { try Data("tiny \(index)".utf8).write(to: app.appendingPathComponent("Nested/tiny-\(index)")) }
        try FileManager.default.createSymbolicLink(atPath:app.appendingPathComponent("resource-link").path,withDestinationPath:"Nested/data.bin")
        let snapshot = try VPhoneIPAReader.manifest(root:app.path)
        try snapshot.validate()
        let main = snapshot.entries.first { $0.path == "Fixture" }!
        let part = VPhoneIPARead(entry:main,offset:9,length:111)
        let chunk = try VPhoneIPAReader.read(root:app.path,requests:[part])[0]
        precondition(Data(base64Encoded:chunk.data) == executable.subdata(in:9..<120))
        rejects { try VPhoneIPASnapshot(root:app.path,entries:snapshot.entries + [main]).validate() }
        rejects { try VPhoneIPASnapshot(root:app.path,entries:snapshot.entries + [changed(main,path:"../escape")]).validate() }
        rejects { try VPhoneIPASnapshot(root:app.path,entries:snapshot.entries + [changed(main,path:"fixture")]).validate() }
        rejects { try VPhoneIPASnapshot(root:app.path,entries:snapshot.entries + [changed(main,path:"huge",size:VPhoneIPASnapshot.maximumBytes+1)]).validate() }
        for target in ["../outside", "/etc/passwd", "Nested/../../outside", "Nested/../Fixture"] {
            rejects { try VPhoneIPASnapshot(root:app.path,entries:snapshot.entries + [changed(main,path:"unsafe-link",kind:.symlink,target:target)]).validate() }
        }
        rejects { _ = try VPhoneIPAReader.read(root:app.path,requests:[.init(entry:main,offset:-1,length:1)]) }
        rejects { _ = try VPhoneIPAReader.read(root:app.path,requests:[.init(entry:main,offset:0,length:VPhoneIPARead.maximumBatchBytes+1)]) }
        let alias = root.appendingPathComponent("Alias.app")
        try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:app)
        rejects { _ = try VPhoneIPAReader.manifest(root:alias.path) }
        let control = VPhoneGuestControl(root:app)
        let record = VPhoneAppRecord(json:["bundle_id":"com.example.export-fixture","name":"Fixture","version":"1.0","build":"9"])!
        let model = VPhoneIPAExportModel(control:control,app:record,workspaceParent:root)
        let destination = root.appendingPathComponent("export.ipa")
        await model.start(to:destination)
        precondition(model.error == nil && model.exportedURL == destination, model.error ?? "Export not completed")
        precondition(control.deployments == 1 && control.operations.filter { $0 == "read" }.count >= 3)
        precondition(model.encrypted == true, "Encrypted state must be reported without changing file bytes")
        let ipa = try Data(contentsOf:destination)
        precondition(ipa.starts(with:[0x50,0x4b]))
        precondition(model.sha256 == SHA256.hash(data:ipa).map { String(format:"%02x",$0) }.joined())
        var status = stat(); precondition(stat(destination.path,&status) == 0 && status.st_mode & 0o777 == 0o600)
        let extracted = root.appendingPathComponent("unpacked")
        try run("/usr/bin/ditto",["-x","-k",destination.path,extracted.path])
        let payload = extracted.appendingPathComponent("Payload/Fixture.app")
        let copied = try Data(contentsOf:payload.appendingPathComponent("Fixture"))
        precondition(copied == executable)
        let linked = try FileManager.default.destinationOfSymbolicLink(atPath:payload.appendingPathComponent("resource-link").path)
        precondition(linked == "Nested/data.bin")
        precondition(stat(payload.appendingPathComponent("Fixture").path,&status) == 0 && status.st_mode & 0o111 != 0)
        let original = try Data(contentsOf:app.appendingPathComponent("Fixture")); precondition(original == executable)
        let oldDestination = root.appendingPathComponent("keep.ipa"); let oldBytes = Data("keep original".utf8)
        try oldBytes.write(to:oldDestination)
        control.delayReads = true
        let cancelled = Task { await model.start(to:oldDestination) }
        try await Task.sleep(for:.milliseconds(20)); model.cancel(); await cancelled.value
        let afterCancel = try Data(contentsOf:oldDestination)
        precondition(afterCancel == oldBytes && model.exportedURL == nil && !model.busy)
        control.delayReads = false; control.mutateAfterRead = true
        await model.start(to:oldDestination)
        let afterFailure = try Data(contentsOf:oldDestination)
        precondition(model.error != nil && afterFailure == oldBytes && model.exportedURL == nil)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath:root.path).filter { $0.hasPrefix("vphone-ipa-") }
        precondition(leftovers.isEmpty, "Partial export workspaces must be removed")
        // Refuse a file swapped to a symlink after enumeration, without reading outside the bundle.
        let updated = try VPhoneIPAReader.manifest(root:app.path)
        let item = updated.entries.first { $0.path == "Nested/data.bin" }!
        try FileManager.default.removeItem(at:app.appendingPathComponent(item.path))
        try FileManager.default.createSymbolicLink(atPath:app.appendingPathComponent(item.path).path,withDestinationPath:destination.path)
        rejects { _ = try VPhoneIPAReader.read(root:app.path,requests:[.init(entry:item,offset:0,length:1)]) }
        print("PASS: IPA Payload layout, exact installed bytes, encryption reporting, executable bits, safe links, batched ranges, cancellation, mutation refusal, private output and cleanup")
    }
}
