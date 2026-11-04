import Foundation

/// Opt-in contract check. Reads Settings executable metadata, uses a unique
/// process filter with no real app events, and reads/removes only its own
/// synthetic crash report. Never launches or crashes an installed app.
@main struct AppLogsGuestSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass the test VM name") }
        let machine = CommandLine.arguments[1]
        let cli = "/Applications/vphone-launchpad.app/Contents/MacOS/vphone-launchpad-cli"
        func rpc(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
            let process = Process(), output = Pipe(), errors = Pipe()
            process.executableURL = URL(fileURLWithPath: cli)
            process.arguments = ["guest", "rpc", machine, method, String(decoding: try JSONSerialization.data(withJSONObject: params), as: UTF8.self)]
            process.standardOutput = output; process.standardError = errors
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile(), stderr = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  reply["ok"] as? Bool == true, let result = reply["result"] as? [String: Any] else {
                throw VPhoneProxyError("Guest contract check failed: \(method): " + String(decoding: stderr, as: UTF8.self))
            }
            return result
        }
        let identifier = "com.vphone.logsfixture." + UUID().uuidString
        let path = "/private/var/mobile/Library/Logs/CrashReporter/" + identifier + "-2026-11-05-000000.ips"
        let text = "{\"app_name\":\"VPhoneLogsFixture\",\"bundleID\":\"\(identifier)\",\"bug_type\":\"309\"}\n{\"fixture\":true}"
        var created = false
        do {
            let info = try rpc("apps.info", ["bundle_id":"com.apple.Preferences"])
            _ = try VPhoneAppLogScope(bundleID: "com.apple.Preferences", executable: info["executable"] as? String ?? "")
            let log = try rpc("logs.syslog", ["process":identifier, "seconds":0.2, "max_lines":5, "level":"all"])
            guard let entries = log["entries"] as? [[String: Any]], entries.isEmpty else { throw VPhoneProxyError("Unexpected log fixture result") }
            _ = try rpc("files.write", ["path":path, "content":text]); created = true
            let list = try rpc("logs.crashes", ["bundle_id":identifier])
            guard let reports = list["crashes"] as? [[String: Any]], reports.count == 1,
                  let reportPath = reports.first?["path"] as? String,
                  (reportPath as NSString).lastPathComponent == (path as NSString).lastPathComponent else { throw VPhoneProxyError("Crash fixture list mismatch") }
            let report = try rpc("logs.crash", ["path":reportPath])
            guard report["content"] as? String == text, VPhoneCrashIdentity.bundleID(in: text) == identifier else { throw VPhoneProxyError("Crash fixture content mismatch") }
            _ = try rpc("files.remove", ["path":path]); created = false
            print("Live app logs contract passed: Settings executable, filtered log response, synthetic crash list/read/identity. Fixture removed; no app launched or crashed.")
        } catch {
            if created {
                do { _ = try rpc("files.remove", ["path":path]) }
                catch { FileHandle.standardError.write(Data(("Fixture cleanup failed: " + path + "\n").utf8)) }
            }
            throw error
        }
    }
}
