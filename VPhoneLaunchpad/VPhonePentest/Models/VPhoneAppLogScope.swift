import Foundation

/// Process names can be shared by apps. This is an executable filter, not
/// proof of bundle identity; extensions and system services are separate.
struct VPhoneAppLogScope: Equatable, Sendable {
    let bundleID: String
    let process: String

    init(bundleID: String, executable: String) throws {
        let process = (executable as NSString).lastPathComponent
        guard !bundleID.isEmpty, !process.isEmpty, process != ".", process != "..",
              process.utf8.count <= 255, !process.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw VPhoneProxyError("The app has no usable executable name. Refresh Apps and try again.")
        }
        self.bundleID = bundleID; self.process = process
    }

    func includes(process name: String) -> Bool {
        name == process
    }
}

enum VPhoneCrashIdentity {
    /// Only explicit report metadata establishes a bundle ID. Filenames and
    /// process names are deliberately not treated as identity evidence.
    static func bundleID(in text: String) -> String? {
        func identifier(_ object: Any?) -> String? {
            guard let json = object as? [String: Any] else { return nil }
            let bundle = json["bundleInfo"] as? [String: Any]
            let value = json["bundleID"] as? String ?? bundle?["CFBundleIdentifier"] as? String
            return value.flatMap { $0.isEmpty ? nil : $0 }
        }
        // Bound identity parsing independently of the raw report viewer.
        let prefix = String(text.prefix(65536))
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        if let first = lines.first, let id = identifier(try? JSONSerialization.jsonObject(with: Data(first.utf8))) { return id }
        if text.utf8.count <= 4 * 1024 * 1024 {
            if let id = identifier(try? JSONSerialization.jsonObject(with: Data(text.utf8))) { return id }
            if let newline = text.firstIndex(of: "\n"),
               let id = identifier(try? JSONSerialization.jsonObject(with: Data(text[text.index(after: newline)...].utf8))) { return id }
        }
        // Legacy .crash text has an explicit Identifier field.
        for line in lines where line.hasPrefix("Identifier:") {
            let value = line.dropFirst("Identifier:".count).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }
}
