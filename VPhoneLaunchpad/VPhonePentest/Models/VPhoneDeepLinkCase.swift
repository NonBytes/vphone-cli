import Foundation
import Darwin

struct VPhoneDeepLinkParameter: Identifiable {
    let id = UUID()
    var name = ""
    var value = ""
}

enum VPhoneDeepLinkURL {
    static func validScheme(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard let first = bytes.first, (65...90).contains(first) || (97...122).contains(first) else { return false }
        return bytes.count <= 128 && bytes.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [43,45,46].contains($0) }
    }
    /// Preserve the raw URL; do not normalize payloads or reject percent
    /// sequences that a researcher may deliberately be testing.
    static func validated(_ text: String) throws -> String {
        guard !text.isEmpty, text.utf8.count <= 8192,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let colon = text.firstIndex(of:":"), validScheme(String(text[..<colon])) else {
            throw VPhoneProxyError("Enter a URL with a valid scheme, no literal control characters, and at most 8 KiB. Percent-encoded test payloads are allowed.")
        }
        return text
    }
    static func append(_ parameters: [VPhoneDeepLinkParameter], to text: String) throws -> String {
        _ = try validated(text)
        guard parameters.count <= 32, var components = URLComponents(string:text) else { throw VPhoneProxyError("The parameter builder needs a parseable base URL and at most 32 parameters. Use raw URL mode for malformed payloads.") }
        let allowed = CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let query = try parameters.map { item -> String in
            guard item.name.utf8.count <= 1024, item.value.utf8.count <= 4096,
                  let name = item.name.addingPercentEncoding(withAllowedCharacters:allowed),
                  let value = item.value.addingPercentEncoding(withAllowedCharacters:allowed) else { throw VPhoneProxyError("Parameter name/value exceeds its limit.") }
            return name + "=" + value
        }.joined(separator:"&")
        if !query.isEmpty { components.percentEncodedQuery = [components.percentEncodedQuery,query].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator:"&") }
        guard let result = components.string else { throw VPhoneProxyError("Cannot build this URL.") }
        return try validated(result)
    }
}

struct VPhoneDeepLinkCase: Codable, Identifiable, Sendable {
    var id = UUID().uuidString
    let name: String
    let bundleID: String
    let appName: String
    let appVersion: String
    let appBuild: String
    let url: String
    let notes: String
    let savedAt: Date
    func validate() throws {
        _ = try VPhoneDeepLinkURL.validated(url)
        guard UUID(uuidString:id) != nil, !name.isEmpty, name.utf8.count <= 512,
              !bundleID.isEmpty, bundleID.utf8.count <= 255, appName.utf8.count <= 1024,
              appVersion.utf8.count <= 256, appBuild.utf8.count <= 256, notes.utf8.count <= 4096,
              savedAt.timeIntervalSince1970.isFinite else { throw VPhoneProxyError("Invalid saved deep-link case.") }
    }
}
struct VPhoneDeepLinkRun: Codable, Identifiable, Sendable {
    var id = UUID().uuidString
    let test: VPhoneDeepLinkCase
    let startedAt: Date
    let elapsedMilliseconds: Int
    let accepted: Bool
    let message: String
    var dateText: String { startedAt.formatted(date:.numeric,time:.standard) }
    var outcome: String { accepted ? "Guest accepted" : "Request failed" }
}
struct VPhoneDeepLinkArchive: Codable {
    var schema = 1
    var cases: [VPhoneDeepLinkCase] = []
    var history: [VPhoneDeepLinkRun] = []
    static let maximumBytes = 4 * 1024 * 1024
    func validate() throws {
        guard schema == 1, cases.count <= 100, history.count <= 100,
              Set(cases.map(\.id)).count == cases.count, Set(history.map(\.id)).count == history.count else { throw VPhoneProxyError("Unsupported deep-link workspace or too many entries (100 cases / 100 runs).") }
        for item in cases { try item.validate() }
        for run in history {
            try run.test.validate()
            guard UUID(uuidString:run.id) != nil, run.startedAt.timeIntervalSince1970.isFinite,
                  run.elapsedMilliseconds >= 0, run.message.utf8.count <= 8192 else { throw VPhoneProxyError("Invalid deep-link history entry.") }
        }
    }
    func data() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw VPhoneProxyError("Workspace exceeds 4 MiB.") }
        return data
    }
    static func read(_ url: URL) throws -> Self {
        let fd = open(url.path,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC)
        guard fd >= 0 else { throw VPhoneProxyError("Cannot open workspace file.") }
        let file = FileHandle(fileDescriptor:fd,closeOnDealloc:true); defer { try? file.close() }
        var st = stat()
        guard fstat(fd,&st) == 0, st.st_mode & S_IFMT == S_IFREG, (1...Int64(maximumBytes)).contains(st.st_size) else { throw VPhoneProxyError("Workspace must be a regular file of at most 4 MiB.") }
        let data = try file.read(upToCount:maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw VPhoneProxyError("Workspace exceeds 4 MiB.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(Self.self,from:data); try result.validate(); return result
    }
}
