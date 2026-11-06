import AppKit
import ImageIO

/// Window-local, bounded icon cache. The guest renders thumbnails from its
/// installed icon service, including icons stored in asset catalogs.
@MainActor
@Observable
final class VPhoneAppIconLoader {
    struct Result: Decodable { let bundleID: String; let png: String? }
    private let control: VPhoneGuestControl
    private let maximumEntries: Int
    private var images: [String: NSImage] = [:]
    private var attempted = Set<String>()
    private var pending: [String: VPhoneAppRecord] = [:]
    private var task: Task<Void, Never>?
    private(set) var revision = 0

    init(control: VPhoneGuestControl, maximumEntries: Int = 128) {
        self.control = control
        self.maximumEntries = min(512, max(1, maximumEntries))
    }
    func image(for app: VPhoneAppRecord) -> NSImage? { images[app.iconKey] }

    func reset() {
        revision += 1; task?.cancel(); task = nil
        images = [:]; attempted = []; pending = [:]
    }

    func request(_ app: VPhoneAppRecord) {
        guard control.isConnected, !attempted.contains(app.iconKey), pending.count < maximumEntries else { return }
        pending[app.iconKey] = app
        guard task == nil else { return }
        let generation = revision
        task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            guard let self else { return }
            defer { if revision == generation { task = nil } }
            while !Task.isCancelled, revision == generation, !pending.isEmpty {
                let batch = Array(pending.values.prefix(12))
                for app in batch { pending[app.iconKey] = nil; attempted.insert(app.iconKey) }
                do {
                    let request = String(decoding: try JSONEncoder().encode(batch.map(\.bundleID)), as: UTF8.self)
                    let results = try await control.guestTool("vphone-guest-icons", arguments: [request], as: [Result].self)
                    guard !Task.isCancelled, revision == generation else { return }
                    for app in batch {
                        guard let encoded = results.first(where: { $0.bundleID == app.bundleID })?.png,
                              let image = Self.decode(encoded) else { continue }
                        if images.count >= maximumEntries, let key = images.keys.first { images[key] = nil; attempted.remove(key) }
                        images[app.iconKey] = image
                    }
                } catch {
                    // Icon failures must never block app browsing or actions.
                }
                if attempted.count > maximumEntries * 4 { attempted = Set(images.keys) }
            }
        }
    }

    static func decode(_ encoded: String) -> NSImage? {
        guard encoded.utf8.count <= 350000, let data = Data(base64Encoded: encoded), data.count <= 262144,
              data.starts(with: [137,80,78,71,13,10,26,10]),
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...128).contains(width), (1...128).contains(height),
              let bitmap = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return NSImage(cgImage: bitmap, size: NSSize(width: 32, height: 32))
    }
}

extension VPhoneAppRecord {
    var iconKey: String { [bundleID, version, build, bundlePath].joined(separator: "\u{0}") }
}
