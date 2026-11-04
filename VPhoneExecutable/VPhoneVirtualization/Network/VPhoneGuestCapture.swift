import Darwin
import Foundation

final class VPhoneGuestCapture {
    static let directory = "/private/var/vphone-network"
    static let capturePath = directory + "/capture.pcap"
    let fd: Int32
    private let lock: Int32

    init() throws {
        let parent = open("/private/var", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw VPhoneNetworkError("Cannot open guest capture parent.") }
        defer { Darwin.close(parent) }
        if mkdirat(parent, "vphone-network", 0o700) != 0, errno != EEXIST { throw VPhoneNetworkError("Cannot create guest capture directory.") }
        let root = openat(parent, "vphone-network", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        var metadata = stat()
        guard root >= 0, fstat(root, &metadata) == 0, metadata.st_uid == geteuid(), metadata.st_mode & 0o777 == 0o700 else {
            if root >= 0 { Darwin.close(root) }
            throw VPhoneNetworkError("Unsafe capture directory ownership or permissions.")
        }
        fd = root
        let guardFD = openat(root, "management.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard guardFD >= 0, Self.safeLock(guardFD) else {
            if guardFD >= 0 { Darwin.close(guardFD) }
            Darwin.close(root); throw VPhoneNetworkError("Cannot open a private capture management lock.")
        }
        lock = guardFD
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while flock(lock, LOCK_EX | LOCK_NB) != 0 {
            if errno != EWOULDBLOCK || ProcessInfo.processInfo.systemUptime >= deadline {
                Darwin.close(lock); Darwin.close(root); throw VPhoneNetworkError("Another capture operation is busy.")
            }
            usleep(20000)
        }
    }
    deinit { flock(lock, LOCK_UN); Darwin.close(lock); Darwin.close(fd) }

    func unlockManagement() { flock(lock, LOCK_UN) }
    func read<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        let file = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { throw VPhoneNetworkError("Cannot read capture state.") }
        defer { Darwin.close(file) }
        var st = stat()
        guard fstat(file, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_uid == geteuid(), st.st_nlink == 1,
              st.st_mode & 0o077 == 0, (0...16384).contains(st.st_size) else { throw VPhoneNetworkError("Unsafe capture state file.") }
        var bytes = [UInt8](repeating: 0, count: 16385)
        let count = Darwin.read(file, &bytes, bytes.count)
        guard count >= 0, count <= 16384 else { throw VPhoneNetworkError("Capture state exceeds its limit.") }
        return try JSONDecoder().decode(T.self, from: Data(bytes.prefix(count)))
    }

    func write<T: Encodable>(_ value: T, to name: String) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 16384 else { throw VPhoneNetworkError("Capture state exceeds its limit.") }
        let temporary = "state-" + UUID().uuidString + ".tmp"
        let file = openat(fd, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw VPhoneNetworkError("Cannot create capture state.") }
        defer { Darwin.close(file); unlinkat(fd, temporary, 0) }
        try Self.writeAll(data, fd: file)
        guard renameat(fd, temporary, fd, name) == 0 else { throw VPhoneNetworkError("Cannot publish capture state.") }
    }

    static func writeAll(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: sent), bytes.count - sent)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw VPhoneNetworkError("Capture write failed: " + String(cString: strerror(errno))) }
                sent += count
            }
        }
    }

    func workerLease() throws -> Int32 {
        let file = openat(fd, "worker.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0, Self.safeLock(file) else {
            if file >= 0 { Darwin.close(file) }
            throw VPhoneNetworkError("Cannot open a private capture worker lock.")
        }
        return file
    }

    private static func safeLock(_ file: Int32) -> Bool {
        var st = stat()
        return fstat(file, &st) == 0 && st.st_mode & S_IFMT == S_IFREG && st.st_uid == geteuid()
            && st.st_nlink == 1 && st.st_mode & 0o077 == 0
    }

    func status() throws -> VPhoneCaptureStatus {
        var st = stat()
        if fstatat(fd, "state.json", &st, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT { return .init() }
            throw VPhoneNetworkError("Cannot inspect capture state.")
        }
        var state = try read("state.json", as: VPhoneCaptureStatus.self)
        try state.validate()
        let lease = try workerLease()
        defer { Darwin.close(lease) }
        if flock(lease, LOCK_EX | LOCK_NB) == 0 {
            defer { flock(lease, LOCK_UN) }
            if state.active, !(state.phase == .starting && Date().timeIntervalSince1970 - state.startedAt < 5) {
                state.phase = .interrupted; state.reason = "Worker ended without completing capture. Counters may be stale."
                state.endedAt = Date().timeIntervalSince1970
                try write(state, to: "state.json")
            }
        }
        return state
    }

    func start(_ request: VPhoneCaptureRequest) throws -> VPhoneCaptureStatus {
        try request.validate()
        guard if_nametoindex(request.interface) != 0 else { throw VPhoneNetworkError("The guest interface does not exist.") }
        let previous = try status()
        guard previous.phase == .idle else { throw VPhoneNetworkError("Save or discard the previous capture before starting another.") }
        let lease = try workerLease()
        defer { Darwin.close(lease) }
        guard flock(lease, LOCK_EX | LOCK_NB) == 0 else { throw VPhoneNetworkError("Another capture worker is active.") }
        // Management remains locked until start returns; the child cannot
        // inspect state until this lease and the management lock are released.
        defer { flock(lease, LOCK_UN) }
        var state = VPhoneCaptureStatus()
        state.id = UUID().uuidString; state.phase = .starting; state.request = request
        try write(state, to: "state.json")
        let path = CommandLine.arguments[0]
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for descriptor: Int32 in 0...2 { posix_spawn_file_actions_addopen(&actions, descriptor, "/dev/null", O_RDWR, 0) }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        var argv = [path, "worker", state.id].map { strdup($0) } + [nil]
        defer { for value in argv { free(value) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, path, &actions, &attributes, &argv, environ)
        if spawned != 0 {
            state.phase = .failed; state.error = "Cannot spawn capture worker: " + String(cString: strerror(spawned))
            state.endedAt = Date().timeIntervalSince1970; try write(state, to: "state.json")
        }
        return state
    }

    func stop(_ id: String) throws -> VPhoneCaptureStatus {
        let state = try status()
        guard state.id == id, UUID(uuidString: id) != nil else { throw VPhoneNetworkError("Capture identity changed. Reload status.") }
        if state.active { try write(id, to: "stop.json") }
        return state
    }

    func discard(_ id: String) throws -> VPhoneCaptureStatus {
        let state = try status()
        guard state.id == id, !state.active else { throw VPhoneNetworkError("Stop the current capture before discarding it.") }
        let lease = try workerLease()
        defer { Darwin.close(lease) }
        guard flock(lease, LOCK_EX | LOCK_NB) == 0 else { throw VPhoneNetworkError("The capture worker is still finishing.") }
        defer { flock(lease, LOCK_UN) }
        for name in ["capture.pcap", "stop.json", "state.json"] {
            if unlinkat(fd, name, 0) != 0, errno != ENOENT { throw VPhoneNetworkError("Cannot remove capture artifact: " + name) }
        }
        return .init()
    }

    func worker(_ id: String) throws {
        guard UUID(uuidString: id) != nil else { throw VPhoneNetworkError("Invalid worker identity.") }
        let lease = try workerLease()
        defer { Darwin.close(lease) }
        guard flock(lease, LOCK_EX | LOCK_NB) == 0 else { throw VPhoneNetworkError("Another capture worker is active.") }
        defer { flock(lease, LOCK_UN) }
        var state = try read("state.json", as: VPhoneCaptureStatus.self)
        try state.validate()
        guard state.id == id, state.phase == .starting, let request = state.request else { throw VPhoneNetworkError("Capture request changed before worker startup.") }
        // Only this worker writes status from now until it releases its lease.
        unlockManagement()
        var bpf: Int32 = -1, output: Int32 = -1
        defer { if bpf >= 0 { Darwin.close(bpf) }; if output >= 0 { Darwin.close(output) } }
        do {
            var length: UInt32 = 0, dlt: UInt32 = 0
            var error = [CChar](repeating: 0, count: 512)
            bpf = vp_capture_open(request.interface, &length, &dlt, &error, error.count)
            guard bpf >= 0 else { throw VPhoneNetworkError(String(cString: error)) }
            guard [0, 1, 12].contains(dlt) else { throw VPhoneNetworkError("Unsupported guest BPF link type \(dlt). Choose en0 or lo0.") }
            let link: UInt32 = dlt == 12 ? 101 : dlt
            state.linkType = link
            output = openat(fd, "capture.pcap", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard output >= 0 else { throw VPhoneNetworkError("Cannot create a private capture file.") }
            try Self.writeAll(VPhonePCAP.header(snapLength: UInt32(request.snapLength), linkType: link), fd: output)
            state.bytes = 24; state.phase = .running
            try write(state, to: "state.json")
            let deadline = ProcessInfo.processInfo.systemUptime + Double(request.seconds)
            var lastStatus = ProcessInfo.processInfo.systemUptime
            var buffer = [UInt8](repeating: 0, count: Int(length))
            capture: while true {
                if (try? read("stop.json", as: String.self)) == id { state.reason = "Stopped by user"; break }
                if ProcessInfo.processInfo.systemUptime >= deadline { state.reason = "Duration limit reached"; break }
                var event = pollfd(fd: bpf, events: Int16(POLLIN), revents: 0)
                let ready = poll(&event, 1, 200)
                if ready < 0, errno == EINTR { continue }
                if ready < 0 { throw VPhoneNetworkError("BPF poll failed.") }
                if event.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 { throw VPhoneNetworkError("BPF device disconnected.") }
                if ready > 0 {
                    let count = Darwin.read(bpf, &buffer, buffer.count)
                    if count == 0 { throw VPhoneNetworkError("BPF device ended capture unexpectedly.") }
                    if count < 0, errno != EAGAIN, errno != EINTR { throw VPhoneNetworkError("BPF read failed.") }
                    if count > 0 {
                        var offset = 0
                        while offset < count {
                            var record = VPhoneBPFRecord()
                            let result = buffer.withUnsafeBufferPointer { vp_capture_next($0.baseAddress, count, &offset, &record) }
                            if result == 0 { break }
                            guard result == 1 else { throw VPhoneNetworkError("Malformed guest BPF record.") }
                            state.seen += 1
                            let packet = Data(buffer[record.dataOffset..<(record.dataOffset + Int(record.capturedLength))])
                            guard request.matches(packet, linkType: dlt) else { continue }
                            state.matched += 1
                            let saved = Data(packet.prefix(request.snapLength))
                            let data = VPhonePCAP.record(seconds: record.seconds, microseconds: record.microseconds, packet: saved, originalLength: record.originalLength)
                            if state.bytes + Int64(data.count) > request.maximumBytes { state.reason = "Size limit reached"; break capture }
                            try Self.writeAll(data, fd: output)
                            state.bytes += Int64(data.count); state.packets += 1
                            if saved.count < record.originalLength { state.truncated += 1 }
                        }
                    }
                }
                if ProcessInfo.processInfo.systemUptime - lastStatus >= 0.5 {
                    counters(bpf, state: &state)
                    try write(state, to: "state.json"); lastStatus = ProcessInfo.processInfo.systemUptime
                }
            }
            guard fsync(output) == 0 else { throw VPhoneNetworkError("Cannot flush capture file.") }
            counters(bpf, state: &state)
            state.phase = .completed
        } catch {
            state.phase = .failed; state.error = error.localizedDescription
        }
        state.endedAt = Date().timeIntervalSince1970
        try write(state, to: "state.json")
    }

    private func counters(_ bpf: Int32, state: inout VPhoneCaptureStatus) {
        var received: UInt32 = 0, dropped: UInt32 = 0
        if vp_capture_stats(bpf, &received, &dropped) == 0 { state.receivedByBPF = received; state.droppedByBPF = dropped }
    }
}
