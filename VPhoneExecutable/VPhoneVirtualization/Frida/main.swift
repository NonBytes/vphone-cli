import Darwin
import Foundation

#if !os(iOS)
#error("Frida management is guest-only")
#endif

let directory = "/private/var/vphone-frida"
let server = directory + "/usr/sbin/frida-server"

struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
func text(_ name: String) -> String {
    guard let handle = FileHandle(forReadingAtPath: directory + "/" + name) else { return "" }
    defer { try? handle.close() }
    do {
        let end = try handle.seekToEnd()
        try handle.seek(toOffset: end > 8000 ? end - 8000 : 0)
        return String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
    } catch { return "" }
}
func write(_ value: String, _ name: String) throws {
    try Data(value.utf8).write(to: URL(fileURLWithPath: directory + "/" + name), options: .atomic)
    chmod(directory + "/" + name, 0o600)
}
func ownedPID() -> pid_t? {
    guard let pid = pid_t(text("pid")), pid > 1, kill(pid, 0) == 0,
          let library = dlopen("/usr/lib/libproc.dylib", RTLD_NOW) else { return nil }
    defer { dlclose(library) }
    typealias PIDPath = @convention(c) (Int32, UnsafeMutableRawPointer, UInt32) -> Int32
    guard let symbol = dlsym(library, "proc_pidpath") else { return nil }
    var bytes = [CChar](repeating: 0, count: 4096)
    let count = bytes.withUnsafeMutableBytes { unsafeBitCast(symbol, to: PIDPath.self)(pid, $0.baseAddress!, 4096) }
    guard count > 0, String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) == server else { return nil }
    return pid
}
func run() throws {
    let fm = FileManager.default
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count == 1, ["prepare", "status", "start", "stop"].contains(args[0]) else { throw Failure("Expected prepare, status, start or stop") }
    for path in [directory, directory + "/usr", directory + "/usr/sbin", directory + "/usr/lib", directory + "/usr/lib/frida-1.0"] {
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var st = stat()
        guard lstat(path, &st) == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_uid == geteuid() else { throw Failure("Unsafe Frida installation directory") }
        chmod(path, 0o700)
    }
    if args[0] == "prepare" {
        guard ownedPID() == nil else { throw Failure("Stop Frida before installing another version.") }
        // A partial upload must never be reported as an installed release.
        try? fm.removeItem(atPath: directory + "/version")
    }
    if args[0] == "stop", let pid = ownedPID() {
        guard kill(pid, SIGTERM) == 0 else { throw Failure("Could not stop Frida") }
        for _ in 0..<20 { if ownedPID() == nil { break }; usleep(100_000) }
        if ownedPID() == pid {
            guard kill(pid, SIGKILL) == 0 else { throw Failure("Could not terminate the managed Frida process") }
            for _ in 0..<30 { if ownedPID() == nil { break }; usleep(100_000) }
        }
        guard ownedPID() == nil else { throw Failure("Frida has not stopped yet. Try again.") }
        try? fm.removeItem(atPath: directory + "/pid")
    }
    if args[0] == "start", ownedPID() == nil {
        guard access(server, X_OK) == 0, !text("version").isEmpty,
              access(directory + "/usr/lib/frida-1.0/frida-agent.dylib", R_OK) == 0 else { throw Failure("Install Frida first.") }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        try write(token, "token")
        let arguments = [server, "--listen=0.0.0.0:27042", "--token=" + token, "--directory=" + directory + "/cache"]
        var argv = arguments.map { strdup($0) } + [nil]
        defer { for p in argv { free(p) } }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, directory + "/server.log", O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var pid: pid_t = 0
        let result = posix_spawn(&pid, server, &actions, &attr, &argv, environ)
        guard result == 0 else { throw Failure("Cannot start Frida: " + String(cString: strerror(result))) }
        try write(String(pid), "pid")
        usleep(750_000)
        guard ownedPID() != nil else { throw Failure("Frida exited. " + text("server.log").suffix(2000)) }
    }
    let installed = access(server, X_OK) == 0 && !text("version").isEmpty && access(directory + "/usr/lib/frida-1.0/frida-agent.dylib", R_OK) == 0
    let pid = ownedPID()
    let status = VPhoneFridaStatus(installed: installed, running: pid != nil, version: text("version").trimmingCharacters(in: .whitespacesAndNewlines), pid: pid, token: pid != nil ? text("token") : "", log: String(text("server.log").suffix(8000)))
    print(String(decoding: try JSONEncoder().encode(status), as: UTF8.self))
}
do { try run() } catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
