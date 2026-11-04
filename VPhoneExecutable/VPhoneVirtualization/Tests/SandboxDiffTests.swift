import CryptoKit
import Darwin
import Foundation

@main
struct SandboxDiffTests {
    static func main() throws {
        precondition(VPhoneSandboxScanner.nanoseconds(seconds: 1, fraction: 1) == 1_000_000_001)
        precondition(VPhoneSandboxScanner.nanoseconds(seconds: Int64.max, fraction: 0) == nil)
        precondition(VPhoneSandboxScanner.nanoseconds(seconds: Int64.min, fraction: 0) == nil)
        precondition(VPhoneSandboxScanner.nanoseconds(seconds: 1, fraction: -1) == nil)
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("vphone-sandbox-tests-" + UUID().uuidString)
        let root = work.appendingPathComponent("container")
        try fm.createDirectory(at: root.appendingPathComponent("Library"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let identity = VPhoneSandboxIdentity(machineID: String(repeating: "a", count: 64), bundleID: "com.example.probe",
            name: "Probe", version: "1", build: "1", root: "/private/var/mobile/Containers/Data/Application/" + UUID().uuidString)
        func write(_ path: String, _ text: String) throws { try Data(text.utf8).write(to: root.appendingPathComponent(path)) }
        try write("same-size.txt", "old")
        try write("removed.txt", "removed")
        try write("permissions.txt", "unchanged")
        try write("Library/data.sqlite", "sqlite fixture")
        try write("type-change", "file")
        try Data("outside data must not be hashed".utf8).write(to: work.appendingPathComponent("outside"))
        try fm.createSymbolicLink(atPath: root.appendingPathComponent("escape").path, withDestinationPath: work.path)
        try fm.createSymbolicLink(atPath: root.appendingPathComponent("broken").path, withDestinationPath: "/not-present")
        precondition(mkfifo(root.appendingPathComponent("pipe").path, 0o600) == 0)
        func scan(_ limits: VPhoneSandboxScanner.Limits = .init()) throws -> VPhoneSandboxSnapshot {
            let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            precondition(fd >= 0); defer { Darwin.close(fd) }
            var scanner = VPhoneSandboxScanner(); scanner.limits = limits
            return try scanner.scan(rootFD: fd, identity: identity)
        }
        let before = try scan()
        precondition(before.enumerationComplete)
        precondition(before.entries.first { $0.path == "same-size.txt" }?.sha256 == SHA256.hash(data: Data("old".utf8)).map { String(format: "%02x", $0) }.joined())
        precondition(before.entries.first { $0.path == "escape" }?.kind == .symlink)
        precondition(before.entries.first { $0.path == "broken" }?.linkTarget == "/not-present")
        precondition(!before.entries.contains { $0.path.hasPrefix("escape/") })
        precondition(before.entries.first { $0.path == "pipe" }?.isVerified == false)
        let restored = try VPhoneSandboxSnapshot.decode(before.encoded())
        precondition(restored.entries == before.entries)
        let report = work.appendingPathComponent("baseline.json")
        try VPhoneSandboxSnapshot.writeReport(before.encoded(), to: report)
        let saved = try VPhoneSandboxSnapshot.read(report)
        precondition(saved.entries == before.entries)
        let mode = try fm.attributesOfItem(atPath: report.path)[.posixPermissions] as! NSNumber
        precondition(mode.intValue == 0o600)
        let aliasFile = work.appendingPathComponent("baseline-link.json")
        try fm.createSymbolicLink(at: aliasFile, withDestinationURL: report)
        do { _ = try VPhoneSandboxSnapshot.read(aliasFile); fatalError("Followed baseline symlink") } catch { }
        let baselineDate = try fm.attributesOfItem(atPath: root.appendingPathComponent("same-size.txt").path)[.modificationDate]!
        try write("same-size.txt", "new")
        try fm.setAttributes([.modificationDate: baselineDate], ofItemAtPath: root.appendingPathComponent("same-size.txt").path)
        try fm.removeItem(at: root.appendingPathComponent("removed.txt"))
        try write("added.plist", "new plist")
        try fm.removeItem(at: root.appendingPathComponent("type-change"))
        try fm.createDirectory(at: root.appendingPathComponent("type-change"), withIntermediateDirectories: false)
        try fm.setAttributes([.posixPermissions: 0o400], ofItemAtPath: root.appendingPathComponent("permissions.txt").path)
        let after = try scan()
        let changes = try VPhoneSandboxChange.compare(before, after)
        precondition(changes.first { $0.path == "same-size.txt" }?.kind == .changed)
        precondition(changes.first { $0.path == "added.plist" }?.kind == .added)
        precondition(changes.first { $0.path == "removed.txt" }?.kind == .removed)
        precondition(changes.first { $0.path == "permissions.txt" }?.kind == .metadata)
        precondition(changes.first { $0.path == "type-change" }?.kind == .changed)
        precondition(changes.first { $0.path == "pipe" }?.kind == .uncertain)
        precondition(!changes.contains { $0.path == "Library/data.sqlite" })
        var tiny = VPhoneSandboxScanner.Limits(); tiny.fileBytes = 1
        let skipped = try scan(tiny)
        let skippedChanges = try VPhoneSandboxChange.compare(before, skipped)
        precondition(skippedChanges.first { $0.path == "same-size.txt" }?.kind == .uncertain)
        tiny = .init(); tiny.entries = 2
        let partial = try scan(tiny)
        precondition(!partial.enumerationComplete)
        let uncertain = try VPhoneSandboxChange.compare(before, partial)
        precondition(!uncertain.contains { $0.kind == .removed })
        tiny = .init(); tiny.depth = 0
        let depthLimited = try scan(tiny)
        precondition(!depthLimited.enumerationComplete)
        let duplicate = VPhoneSandboxSnapshot(identity: identity, capturedAt: before.capturedAt, completedAt: before.completedAt,
            enumerationComplete: true, notes: [], entries: before.entries + [before.entries[0]])
        do { try duplicate.validate(); fatalError("Accepted duplicate paths") } catch { }
        let escaped = VPhoneSandboxEntry(path: "../outside", kind: .directory, size: 0, modifiedNanoseconds: 0, mode: 0o755, uid: 0, gid: 0)
        let badPath = VPhoneSandboxSnapshot(identity: identity, capturedAt: before.capturedAt, completedAt: before.completedAt,
            enumerationComplete: true, notes: [], entries: before.entries + [escaped])
        do { try badPath.validate(); fatalError("Accepted escaping path") } catch { }
        let other = VPhoneSandboxIdentity(machineID: String(repeating: "b", count: 64), bundleID: identity.bundleID,
            name: "Probe", version: "1", build: "1", root: identity.root)
        let foreign = VPhoneSandboxSnapshot(identity: other, capturedAt: before.capturedAt, completedAt: before.completedAt,
            enumerationComplete: true, notes: [], entries: before.entries)
        do { _ = try VPhoneSandboxChange.compare(before, foreign); fatalError("Compared another machine") } catch { }
        for path in ["/tmp", identity.root + "/../other", identity.root + "/child", identity.root + "/"] {
            do { _ = try VPhoneSandboxIdentity.canonicalRoot(path); fatalError("Accepted invalid root") } catch { }
        }
        let alias = try VPhoneSandboxIdentity.canonicalRoot(String(identity.root.dropFirst(8)))
        precondition(alias == identity.root)
        print("Sandbox Diff passed: SHA-256, same-size edits, add/remove/metadata, symlink isolation, FIFO, partial scans, JSON and machine/root validation")
    }
}
