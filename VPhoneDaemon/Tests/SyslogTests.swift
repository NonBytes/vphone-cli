import Foundation

@main
enum SyslogTests {
    static func main() {
        precondition((try? GuestSyslog.Filter(process: nil, level: "all", subsystem: nil, category: nil, messageContains: nil))?.streamFlags == 0x03)
        precondition((try? GuestSyslog.Filter(process: nil, level: "debug", subsystem: nil, category: nil, messageContains: nil))?.streamFlags == 0x03)
        precondition((try? GuestSyslog.Filter(process: nil, level: "info", subsystem: nil, category: nil, messageContains: nil))?.streamFlags == 0x01)
        precondition((try? GuestSyslog.Filter(process: nil, level: "notice", subsystem: nil, category: nil, messageContains: nil))?.streamFlags == 0x00)
        precondition((try? GuestSyslog.Filter(process: nil, level: "default", subsystem: nil, category: nil, messageContains: nil))?.streamFlags == 0x00)
        precondition((try? GuestSyslog.Filter(process: nil, level: "error", subsystem: nil, category: nil, messageContains: nil))?.streamFlags == 0x00)
        precondition((try? GuestSyslog.Filter(process: nil, level: "fault", subsystem: nil, category: nil, messageContains: nil))?.streamFlags == 0x00)
        precondition((try? GuestSyslog.Filter(process: nil, level: "bogus", subsystem: nil, category: nil, messageContains: nil)) == nil)

        precondition((try? GuestSyslog.capture(seconds: 0.05)) == nil)
        precondition((try? GuestSyslog.capture(seconds: 61)) == nil)
        precondition((try? GuestSyslog.capture(seconds: 0.2, maxLines: 0)) == nil)
        precondition((try? GuestSyslog.capture(seconds: 0.2, maxLines: 5001)) == nil)

        let infoFilter = try! GuestSyslog.Filter(
            process: "app",
            level: "info",
            subsystem: "com.example.app",
            category: "net",
            messageContains: "ok",
        )
        precondition(infoFilter.matches(process: "MyApp", subsystem: "com.example.app.http", category: "net", logType: 0x01, message: "marker ok"))
        precondition(!infoFilter.matches(process: "MyApp", subsystem: "com.example.app", category: "net", logType: 0x02, message: "marker ok"))
        precondition(!infoFilter.matches(process: "MyApp", subsystem: "com.example.other", category: "net", logType: 0x01, message: "marker ok"))
        precondition(!infoFilter.matches(process: "Other", subsystem: "com.example.app", category: "net", logType: 0x01, message: "marker ok"))

        let sessionID = "syslog-test-\(UUID().uuidString)"
        let infoBatch = try! GuestSyslog.capture(seconds: 0.6, level: "info", maxLines: 300, session: sessionID)
        let levels = Set(infoBatch.entries.map(\.level))
        precondition(levels.contains("info"), "Live Info-level events must be delivered when level=info")
        if let first = infoBatch.entries.first {
            let obj = first.jsonObject
            precondition(obj["process"] is String && obj["pid"] is Int && obj["message"] is String && obj["level"] is String)
            precondition(JSONSerialization.isValidJSONObject(["entries": [obj]]))
        }

        // Second poll on the same session continues without error.
        let followUp = try! GuestSyslog.capture(seconds: 0.3, level: "info", maxLines: 300, session: sessionID)
        precondition(followUp.entries.count >= 0)
        print("GuestSyslog tests passed: flags, bounds, filter matching, live info delivery (\(infoBatch.entries.count) entries), session reuse.")
    }
}
