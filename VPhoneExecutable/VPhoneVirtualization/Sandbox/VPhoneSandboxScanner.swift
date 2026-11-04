import CryptoKit
import Darwin
import Foundation

/// Descriptor-relative, read-only traversal. No path below the admitted root
/// is followed through a symlink, including a file swapped while scanning.
struct VPhoneSandboxScanner {
    struct Limits {
        var entries = VPhoneSandboxSnapshot.maximumEntries
        var depth = 32
        var fileBytes: Int64 = 32 * 1024 * 1024
        var totalBytes: Int64 = 128 * 1024 * 1024
        var seconds: Double = 8
    }
    var limits = Limits()
    private var entries: [VPhoneSandboxEntry] = []
    private var notes: [String] = []
    private var complete = true
    private var hashedBytes: Int64 = 0
    private var deadline: Double = 0

    mutating func scan(rootFD: Int32, identity: VPhoneSandboxIdentity) throws -> VPhoneSandboxSnapshot {
        let started = Date()
        entries = []; notes = []; complete = true; hashedBytes = 0
        deadline = ProcessInfo.processInfo.systemUptime + limits.seconds
        var root = stat()
        guard fstat(rootFD, &root) == 0, root.st_mode & S_IFMT == S_IFDIR else {
            throw VPhoneSandboxError("The data container could not be opened as a directory.")
        }
        walk(rootFD, path: ".", metadata: root, depth: 0)
        let result = VPhoneSandboxSnapshot(identity: identity, capturedAt: started, completedAt: max(started, Date()),
                                          enumerationComplete: complete, notes: notes, entries: entries.sorted { $0.path < $1.path })
        try result.validate()
        return result
    }

    private mutating func incomplete(_ reason: String) {
        complete = false
        if notes.count < 100, !notes.contains(reason) { notes.append(reason) }
    }

    private func entry(_ path: String, _ kind: VPhoneSandboxEntry.Kind, _ st: stat) -> VPhoneSandboxEntry {
        let time = Self.nanoseconds(seconds: Int64(st.st_mtimespec.tv_sec), fraction: Int64(st.st_mtimespec.tv_nsec))
        var value = VPhoneSandboxEntry(path: path, kind: kind, size: kind == .file ? max(0, st.st_size) : 0,
            modifiedNanoseconds: time ?? 0,
            mode: UInt32(st.st_mode & 0o7777), uid: st.st_uid, gid: st.st_gid)
        if time == nil { value.error = "Modification time is outside the supported nanosecond range." }
        return value
    }

    static func nanoseconds(seconds: Int64, fraction: Int64) -> Int64? {
        guard (0..<1_000_000_000).contains(fraction) else { return nil }
        let (whole, overflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        let (value, sumOverflow) = whole.addingReportingOverflow(fraction)
        return overflow || sumOverflow ? nil : value
    }

    private func same(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_mode == b.st_mode &&
            a.st_uid == b.st_uid && a.st_gid == b.st_gid && a.st_size == b.st_size &&
            a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
            a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }

    private mutating func walk(_ fd: Int32, path: String, metadata: stat, depth: Int) {
        let index = entries.count
        entries.append(entry(path, .directory, metadata))
        guard depth < limits.depth else {
            entries[index].error = "Depth limit reached."
            incomplete("Depth limit reached; some descendants were not scanned."); return
        }
        let copy = dup(fd)
        guard copy >= 0 else { entries[index].error = "Could not duplicate directory descriptor."; incomplete("A directory was unreadable."); return }
        guard let directory = fdopendir(copy) else {
            Darwin.close(copy); entries[index].error = "Directory enumeration failed."
            incomplete("A directory was unreadable."); return
        }
        defer { closedir(directory) }
        var names: [String] = []
        while true {
            errno = 0
            guard let row = readdir(directory) else {
                if errno != 0 { entries[index].error = "Directory read failed."; incomplete("A directory read failed.") }
                break
            }
            var field = row.pointee.d_name
            let capacity = MemoryLayout.size(ofValue: field)
            let name = withUnsafePointer(to: &field) {
                $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(validatingCString: $0) }
            }
            guard let name else { incomplete("A filename was not valid UTF-8 and was skipped."); continue }
            if name == "." || name == ".." { continue }
            guard names.count < limits.entries, ProcessInfo.processInfo.systemUptime < deadline else {
                incomplete("Entry or time limit reached; the tree is incomplete."); break
            }
            names.append(name)
        }
        for name in names.sorted() {
            guard entries.count < limits.entries, ProcessInfo.processInfo.systemUptime < deadline else {
                incomplete("Entry or time limit reached; the tree is incomplete."); break
            }
            let relative = path == "." ? name : path + "/" + name
            guard relative.utf8.count <= 4096 else { incomplete("A path exceeded the path limit."); continue }
            var st = stat()
            guard fstatat(fd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else {
                var value = entry(relative, .unavailable, stat())
                value.error = "Cannot stat path: " + String(cString: strerror(errno))
                entries.append(value); continue
            }
            switch st.st_mode & S_IFMT {
            case S_IFDIR:
                let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                var opened = stat()
                if child >= 0, fstat(child, &opened) == 0, same(st, opened) {
                    walk(child, path: relative, metadata: opened, depth: depth + 1)
                } else {
                    var value = entry(relative, .directory, st); value.error = "Directory inaccessible or changed before opening."
                    entries.append(value); incomplete("A directory was inaccessible or changed during scanning.")
                }
                if child >= 0 { Darwin.close(child) }
            case S_IFREG:
                entries.append(hashFile(fd, name: name, path: relative, metadata: st))
            case S_IFLNK:
                var value = entry(relative, .symlink, st)
                var bytes = [UInt8](repeating: 0, count: 4097)
                let count = readlinkat(fd, name, &bytes, bytes.count)
                var after = stat()
                if count >= 0, count <= 4096,
                   fstatat(fd, name, &after, AT_SYMLINK_NOFOLLOW) == 0, same(st, after),
                   let target = String(bytes: bytes.prefix(count), encoding: .utf8) {
                    value.linkTarget = target
                } else { value.error = "Symlink could not be read consistently." }
                entries.append(value)
            default:
                var value = entry(relative, .other, st); value.error = "Special file; contents were not read."
                entries.append(value)
            }
        }
        var after = stat()
        if fstat(fd, &after) != 0 || !same(metadata, after) {
            entries[index].error = "Directory changed during scanning."
            incomplete("A directory changed while its tree was scanned.")
        }
    }

    private mutating func hashFile(_ parent: Int32, name: String, path: String, metadata: stat) -> VPhoneSandboxEntry {
        var value = entry(path, .file, metadata)
        guard value.error == nil else { return value }
        guard metadata.st_size <= limits.fileBytes, metadata.st_size <= limits.totalBytes - hashedBytes else {
            value.error = "File exceeds the 32 MiB per-file or 128 MiB total hashing budget."; return value
        }
        let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { value.error = "Cannot read file: " + String(cString: strerror(errno)); return value }
        defer { Darwin.close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, same(metadata, opened), opened.st_mode & S_IFMT == S_IFREG else {
            value.error = "File changed before opening."; return value
        }
        var hasher = SHA256()
        var bytes = [UInt8](repeating: 0, count: 65536)
        var readBytes: Int64 = 0
        while true {
            guard ProcessInfo.processInfo.systemUptime < deadline else { value.error = "Hashing time limit reached."; return value }
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                value.error = "File read failed: " + String(cString: strerror(errno)); return value
            }
            readBytes += Int64(count); hashedBytes += Int64(count)
            guard readBytes <= limits.fileBytes, hashedBytes <= limits.totalBytes else {
                value.error = "Hashing budget exceeded while reading."; return value
            }
            hasher.update(data: Data(bytes.prefix(count)))
        }
        var after = stat(), pathAfter = stat()
        guard readBytes == metadata.st_size, fstat(fd, &after) == 0, same(metadata, after),
              fstatat(parent, name, &pathAfter, AT_SYMLINK_NOFOLLOW) == 0, same(metadata, pathAfter) else {
            value.error = "File changed during scanning; hash discarded."; return value
        }
        value.sha256 = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return value
    }
}
