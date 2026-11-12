import Foundation
import IcliKit

// MARK: - Unified Log and Crash Reports

extension GuestAPI {
    static func executeLog(_ m: LogMethod, _ params: [String: Any]) throws -> [String: Any] {
        switch m {
        case .logsSyslog:
            let seconds = number(params, "seconds", default: 2)
            let batch = try GuestSyslog.capture(
                seconds: seconds,
                process: optionalString(params, "process"),
                level: optionalString(params, "level") ?? "all",
                maxLines: (params["max_lines"] as? NSNumber)?.intValue ?? 500,
                subsystem: optionalString(params, "subsystem"),
                category: optionalString(params, "category"),
                messageContains: optionalString(params, "message_contains"),
                session: optionalString(params, "session"),
            )
            return [
                "entries": batch.entries.map(\.jsonObject),
                "count": batch.entries.count,
                "truncated": batch.truncated,
                "source": "unified_log",
                "seconds": seconds,
            ]
        case .logsCrashes:
            let paths = try crashLogs(bundleID: optionalString(params, "bundle_id"))["crashes"] as? [String] ?? []
            let reports = paths.map { path -> [String: Any] in
                let name = (path as NSString).lastPathComponent
                let attributes = try? FileManager.default.attributesOfItem(atPath: path)
                return [
                    "path": path,
                    "name": name,
                    "process": crashProcessName(name),
                    "size": attributes?[.size] as? Int ?? 0,
                    "mtime": (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
                ]
            }
            return ["crashes": reports, "count": reports.count]
        case .logsCrash:
            return try readCrashLog(string(params, "path"))
        }
    }

    /// Crash report names start with the process name, then a date or a kind:
    /// `SpringBoard-2026-09-25-101500.ips`, `JetsamEvent-2026-….ips`.
    private static func crashProcessName(_ name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        if let range = stem.range(of: #"-\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return String(stem[..<range.lowerBound])
        }
        return stem.split(separator: "-").first.map(String.init) ?? stem
    }
}
