import Foundation
import CryptoKit
import Darwin

/// Immutable, reviewed bytes. Source filenames and host paths are deliberately omitted.
struct VPhoneEvidenceArtifact: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let data: Data
    let isText: Bool
}

struct VPhoneEvidencePackage {
    static let maximumFileBytes = 32 * 1024 * 1024
    static let maximumTotalBytes = 128 * 1024 * 1024
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func read(_ url: URL) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw VPhoneSandboxError("Choose a regular file, not a symlink.") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size <= maximumFileBytes else { throw VPhoneSandboxError("Each evidence file must be regular and no larger than 32 MiB.") }
        let data = try file.read(upToCount: maximumFileBytes + 1) ?? Data()
        guard data.count <= maximumFileBytes else { throw VPhoneSandboxError("Evidence file grew beyond 32 MiB.") }
        return data
    }

    /// Best effort common credential patterns plus explicit literal replacements.
    /// JSON is treated as text; resulting redacted evidence need not remain valid JSON.
    static func redact(_ text: String, literals: [String]) -> String {
        var result = text
        for secret in Set(literals.filter { !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
        let patterns = [
            #"(?im)(authorization\s*[:=]\s*|bearer\s+)[^\r\n]+"#,
            #"(?i)([\"']?(?:access_token|refresh_token|id_token|token|password|passwd|secret|api[_-]?key|cookie|set-cookie)[\"']?\s*[:=]\s*)(?:\"[^\"]*\"|'[^']*'|[^\s&,}\r\n]+)"#,
            #"(?i)([?&](?:code|session|credential)=)[^&#\s]+"#,
            #"(?i)(https?://)[^/@\s]+:[^/@\s]+@"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1[REDACTED]")
        }
        return result
    }

    /// Creates a new private directory only; never merges into or overwrites a case folder.
    static func write(_ artifacts: [VPhoneEvidenceArtifact], to parent: URL) throws -> URL {
        guard !artifacts.isEmpty, artifacts.count <= 40,
              artifacts.reduce(0, { $0 + $1.data.count }) <= maximumTotalBytes else { throw VPhoneSandboxError("Evidence exceeds 40 files or 128 MiB.") }
        var names = Set<String>()
        for artifact in artifacts {
            guard artifact.data.count <= maximumFileBytes,
                  !artifact.name.isEmpty, artifact.name != ".", artifact.name != "..",
                  !artifact.name.contains("/"), !artifact.name.contains("\0"),
                  artifact.name != "manifest.json", names.insert(artifact.name).inserted else { throw VPhoneSandboxError("Invalid evidence filename.") }
        }
        let folder = parent.appendingPathComponent("vphone-evidence-" + UUID().uuidString, isDirectory: true)
        guard mkdir(folder.path, 0o700) == 0 else { throw VPhoneSandboxError("Could not create evidence directory.") }
        do {
            let entries = artifacts.map { ["file": $0.name, "bytes": $0.data.count, "sha256": hash($0.data)] as [String: Any] }
            let manifest = try JSONSerialization.data(withJSONObject: ["formatVersion": 1, "createdAt": ISO8601DateFormatter().string(from: Date()), "files": entries], options: [.prettyPrinted, .sortedKeys])
            for artifact in artifacts { try VPhoneSandboxSnapshot.writeReport(artifact.data, to: folder.appendingPathComponent(artifact.name)) }
            try VPhoneSandboxSnapshot.writeReport(manifest, to: folder.appendingPathComponent("manifest.json"))
            return folder
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}
