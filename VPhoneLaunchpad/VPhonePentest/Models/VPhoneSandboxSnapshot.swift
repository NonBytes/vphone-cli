import Foundation
import Darwin

struct VPhoneSandboxError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct VPhoneSandboxIdentity: Codable, Equatable, Sendable {
    let machineID: String
    let bundleID: String
    let name: String
    let version: String
    let build: String
    let root: String

    static func canonicalRoot(_ path: String) throws -> String {
        let root = path.hasPrefix("/var/") ? "/private" + path : path
        let base = "/private/var/mobile/Containers/Data/Application/"
        guard root.hasPrefix(base), UUID(uuidString: String(root.dropFirst(base.count))) != nil else {
            throw VPhoneSandboxError("Only an app's UUID data container is supported. App Groups and bundle directories are excluded.")
        }
        return root
    }
}

struct VPhoneSandboxEntry: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable { case file, directory, symlink, other, unavailable }
    let path: String
    let kind: Kind
    let size: Int64
    let modifiedNanoseconds: Int64
    let mode: UInt32
    let uid: UInt32
    let gid: UInt32
    var sha256: String?
    var linkTarget: String?
    var error: String?
    var id: String { path }

    var isVerified: Bool {
        error == nil && (kind == .directory || (kind == .file && sha256 != nil) || (kind == .symlink && linkTarget != nil))
    }
    var summary: String {
        let permissions = String(mode, radix: 8)
        return "\(kind.rawValue), \(size) B, mode \(permissions)" + (sha256.map { ", SHA-256 " + $0 } ?? "")
    }
}

struct VPhoneSandboxSnapshot: Codable, Sendable {
    static let maximumEntries = 2001
    static let maximumJSONBytes = 2 * 1024 * 1024
    var formatVersion = 1
    let identity: VPhoneSandboxIdentity
    let capturedAt: Date
    let completedAt: Date
    let enumerationComplete: Bool
    let notes: [String]
    let entries: [VPhoneSandboxEntry]

    func validate() throws {
        let hashCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        func validHash(_ value: String) -> Bool {
            value.utf8.count == 64 && value.unicodeScalars.allSatisfy { hashCharacters.contains($0) }
        }
        guard formatVersion == 1, validHash(identity.machineID), !identity.bundleID.isEmpty,
              identity.bundleID.utf8.count <= 512,
              try VPhoneSandboxIdentity.canonicalRoot(identity.root) == identity.root,
              capturedAt.timeIntervalSince1970.isFinite, completedAt.timeIntervalSince1970.isFinite,
              completedAt >= capturedAt, entries.count <= Self.maximumEntries, notes.count <= 100,
              notes.allSatisfy({ $0.utf8.count <= 2048 }) else {
            throw VPhoneSandboxError("Unsupported or malformed sandbox snapshot.")
        }
        var seen = Set<String>()
        for entry in entries {
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            guard seen.insert(entry.path).inserted, !entry.path.isEmpty, entry.path.utf8.count <= 4096,
                  !entry.path.contains("\0"), !entry.path.hasPrefix("/"),
                  entry.path == "." || parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  entry.size >= 0, entry.mode <= 0o7777,
                  entry.sha256.map(validHash) ?? true,
                  (entry.linkTarget?.utf8.count ?? 0) <= 4096,
                  (entry.error?.utf8.count ?? 0) <= 2048 else {
                throw VPhoneSandboxError("Invalid or duplicate path in sandbox snapshot.")
            }
        }
        guard entries.contains(where: { $0.path == "." && $0.kind == .directory }) else {
            throw VPhoneSandboxError("The snapshot has no data-container root.")
        }
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumJSONBytes else { throw VPhoneSandboxError("Snapshot exceeds 2 MiB.") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }

    static func read(_ url: URL) throws -> Self {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw VPhoneSandboxError("Open a regular baseline JSON file, not a symlink.") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size <= maximumJSONBytes else { throw VPhoneSandboxError("Baseline must be a regular JSON file no larger than 2 MiB.") }
        return try decode(file.read(upToCount: maximumJSONBytes + 1) ?? Data())
    }

    /// The export is private from creation, including its temporary file.
    /// rename replaces the chosen directory entry without following a link.
    static func writeReport(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".vphone-sandbox-" + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw VPhoneSandboxError("Could not create the sandbox report file.") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close(); unlink(temporary.path) }
        try file.write(contentsOf: data)
        try file.close()
        guard rename(temporary.path, url.path) == 0 else { throw VPhoneSandboxError("Could not save the sandbox report.") }
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumJSONBytes else { throw VPhoneSandboxError("Snapshot exceeds 2 MiB.") }
        return data
    }
}

struct VPhoneSandboxChange: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case added = "Added", removed = "Removed", changed = "Content / type changed"
        case metadata = "Metadata changed", uncertain = "Uncertain"
    }
    let path: String
    let kind: Kind
    let before: VPhoneSandboxEntry?
    let after: VPhoneSandboxEntry?
    let reason: String
    var id: String { path }

    static func compare(_ baseline: VPhoneSandboxSnapshot, _ current: VPhoneSandboxSnapshot) throws -> [Self] {
        try baseline.validate(); try current.validate()
        guard baseline.identity.machineID == current.identity.machineID,
              baseline.identity.bundleID == current.identity.bundleID,
              baseline.identity.root == current.identity.root else {
            throw VPhoneSandboxError("Baseline belongs to another machine, app or data container. Capture a new baseline after reinstalling the app or moving the VM.")
        }
        let old = Dictionary(uniqueKeysWithValues: baseline.entries.map { ($0.path, $0) })
        let new = Dictionary(uniqueKeysWithValues: current.entries.map { ($0.path, $0) })
        return Set(old.keys).union(new.keys).sorted().compactMap { path in
            let before = old[path], after = new[path]
            let kind: Kind
            let reason: String
            if before?.isVerified == false || after?.isVerified == false ||
                (before == nil && !baseline.enumerationComplete) || (after == nil && !current.enumerationComplete) {
                kind = .uncertain
                reason = before?.error ?? after?.error ?? "Content was not verified, or one tree was not fully enumerated."
            } else if before == nil {
                kind = .added; reason = "Path was absent from the baseline."
            } else if after == nil {
                kind = .removed; reason = "Path is absent from the current scan."
            } else if before!.kind != after!.kind || before!.sha256 != after!.sha256 || before!.linkTarget != after!.linkTarget {
                kind = .changed; reason = "Type, SHA-256 or symlink target differs."
            } else if before!.size != after!.size || before!.mode != after!.mode || before!.uid != after!.uid || before!.gid != after!.gid ||
                (before!.kind != .directory && before!.modifiedNanoseconds != after!.modifiedNanoseconds) {
                kind = .metadata; reason = "Size, permissions, ownership or modification time differs."
            } else { return nil }
            return Self(path: path, kind: kind, before: before, after: after, reason: reason)
        }
    }
}
