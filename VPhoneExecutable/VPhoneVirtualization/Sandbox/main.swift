import Darwin
import Foundation

#if !os(iOS)
#error("Sandbox capture is guest-only")
#endif

do {
    guard CommandLine.arguments.count == 2, let data = CommandLine.arguments[1].data(using: .utf8), data.count <= 16384 else {
        throw VPhoneSandboxError("Expected one sandbox identity JSON argument.")
    }
    let request = try JSONDecoder().decode(VPhoneSandboxIdentity.self, from: data)
    let root = try VPhoneSandboxIdentity.canonicalRoot(request.root)
    let base = "/private/var/mobile/Containers/Data/Application"
    let parent = open(base, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard parent >= 0 else { throw VPhoneSandboxError("Cannot open the app data-container directory.") }
    defer { Darwin.close(parent) }
    let fd = openat(parent, (root as NSString).lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw VPhoneSandboxError("Cannot open the data container without following symlinks.") }
    defer { Darwin.close(fd) }
    var actual = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard fcntl(fd, F_GETPATH, &actual) != -1, String(cString: actual) == root else {
        throw VPhoneSandboxError("The opened directory does not match the selected data container.")
    }
    let identity = VPhoneSandboxIdentity(machineID: request.machineID, bundleID: request.bundleID,
        name: request.name, version: request.version, build: request.build, root: root)
    var scanner = VPhoneSandboxScanner()
    let snapshot = try scanner.scan(rootFD: fd, identity: identity)
    var opened = stat(), current = stat()
    guard fstat(fd, &opened) == 0, fstatat(parent, (root as NSString).lastPathComponent, &current, AT_SYMLINK_NOFOLLOW) == 0,
          opened.st_dev == current.st_dev, opened.st_ino == current.st_ino, current.st_mode & S_IFMT == S_IFDIR else {
        throw VPhoneSandboxError("The data-container directory was replaced during capture.")
    }
    let encoded = try snapshot.encoded()
    FileHandle.standardOutput.write(encoded)
    FileHandle.standardOutput.write(Data([10]))
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
