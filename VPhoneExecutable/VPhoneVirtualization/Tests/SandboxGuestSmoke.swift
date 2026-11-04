import Foundation

/// Opt-in live test: only a fresh, synthetic data-container directory and a
/// uniquely named temporary helper are touched. No registered app is scanned.
@main
struct SandboxGuestSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Pass machine name and signed guest helper") }
        let machine = CommandLine.arguments[1]
        let helper = CommandLine.arguments[2]
        let cli = "/Applications/vphone-launchpad.app/Contents/MacOS/vphone-launchpad-cli"
        func run(_ arguments: [String]) throws -> [String: Any] {
            let process = Process(), output = Pipe(), errors = Pipe()
            process.executableURL = URL(fileURLWithPath: cli); process.arguments = arguments
            process.standardOutput = output; process.standardError = errors
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let stderr = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw VPhoneSandboxError("Guest fixture command failed: " + String(decoding: stderr, as: UTF8.self))
            }
            return value
        }
        func rpc(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
            let json = String(decoding: try JSONSerialization.data(withJSONObject: params), as: UTF8.self)
            let reply = try run(["guest", "rpc", machine, method, json])
            guard reply["ok"] as? Bool == true, let result = reply["result"] as? [String: Any] else {
                throw VPhoneSandboxError("Guest fixture RPC failed: " + method)
            }
            return result
        }
        let nonce = UUID().uuidString
        let root = "/private/var/mobile/Containers/Data/Application/" + nonce
        let remote = "/private/var/tmp/vphone-sandbox-fixture-" + nonce
        let identity = VPhoneSandboxIdentity(machineID: String(repeating: "a", count: 64), bundleID: "com.vphone.sandbox-fixture",
            name: "Synthetic fixture", version: "1", build: "1", root: root)
        var created = false, uploaded = false
        func cleanup() throws {
            if created { _ = try rpc("files.remove", ["path": root, "recursive": true]); created = false }
            if uploaded { _ = try rpc("files.remove", ["path": remote]); uploaded = false }
        }
        do {
            // UUID paths avoid existing app containers; mkdir does not replace
            // any files, and no app is registered for this directory.
            _ = try rpc("files.mkdir", ["path": root]); created = true
            _ = try run(["guest", "push", machine, helper, remote, "--mode", "700"]); uploaded = true
            _ = try rpc("files.write", ["path": root + "/same-size.txt", "content": "old"])
            _ = try rpc("files.write", ["path": root + "/removed.txt", "content": "fixture"])
            _ = try rpc("files.symlink", ["target": "/private/etc/hosts", "link": root + "/outside-link"])
            func capture() throws -> VPhoneSandboxSnapshot {
                let argument = String(decoding: try JSONEncoder().encode(identity), as: UTF8.self)
                let args = String(decoding: try JSONEncoder().encode([argument]), as: UTF8.self)
                let path = String(decoding: try JSONEncoder().encode(remote), as: UTF8.self)
                let reply = try rpc("script.eval", ["source": "proc.run(\(path), \(args))", "timeout": 20])
                let value = try VPhoneProxyScriptResult.decode(reply, as: VPhoneSandboxSnapshot.self)
                try value.validate(); return value
            }
            let before = try capture()
            guard before.enumerationComplete, before.entries.allSatisfy(\.isVerified),
                  before.entries.first(where: { $0.path == "outside-link" })?.kind == .symlink,
                  before.entries.first(where: { $0.path == "outside-link" })?.sha256 == nil else {
                throw VPhoneSandboxError("The live baseline or no-follow check failed.")
            }
            _ = try rpc("files.write", ["path": root + "/same-size.txt", "content": "new"])
            _ = try rpc("files.remove", ["path": root + "/removed.txt"])
            _ = try rpc("files.write", ["path": root + "/added.plist", "content": "fixture"])
            let after = try capture()
            let changes = try VPhoneSandboxChange.compare(before, after)
            guard after.enumerationComplete,
                  changes.first(where: { $0.path == "same-size.txt" })?.kind == .changed,
                  changes.first(where: { $0.path == "removed.txt" })?.kind == .removed,
                  changes.first(where: { $0.path == "added.plist" })?.kind == .added,
                  !changes.contains(where: { $0.path == "outside-link" }) else {
                throw VPhoneSandboxError("Live guest diff did not match fixture edits.")
            }
            try cleanup()
            print("Live guest Sandbox Diff passed: signed helper, same-size edit, add/remove, no-follow symlink; synthetic fixture and helper removed")
        } catch {
            do { try cleanup() } catch { FileHandle.standardError.write(Data(("Fixture cleanup failed: " + error.localizedDescription + "\n").utf8)) }
            throw error
        }
    }
}
