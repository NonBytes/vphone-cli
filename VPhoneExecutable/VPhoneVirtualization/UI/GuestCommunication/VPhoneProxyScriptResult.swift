import Foundation

/// script.eval success does not imply the child tool succeeded. Check both
/// layers before displaying an applied state in the proxy editor.
enum VPhoneProxyScriptResult {
    private struct ProcessResult: Decodable {
        let status: Int
        let stdout: String
        let stderr: String
        let signal: Int?
    }

    static func decode(_ reply: [String: Any]) throws -> VPhoneProxyStatus {
        guard reply["ok"] as? Bool == true, reply["crashed"] as? Bool != true,
              let text = reply["result"] as? String else {
            throw VPhoneProxyError(reply["error"] as? String ?? "The guest could not read proxy settings.")
        }
        let process = try JSONDecoder().decode(ProcessResult.self, from: Data(text.utf8))
        guard process.status == 0, process.signal == nil else {
            let message = process.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw VPhoneProxyError(message.isEmpty ? "The guest proxy tool failed." : message)
        }
        return try JSONDecoder().decode(VPhoneProxyStatus.self, from: Data(process.stdout.utf8))
    }
}
