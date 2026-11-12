import AppKit
import Foundation

@MainActor
private final class PhotosMockGuestControl: VPhoneGuestControlling {
    var isConnected = true
    var guestIPAddress: String? { nil }
    var sandboxMachineScope: String { "" }

    func call(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        if method == "files.list" {
            let path = params["path"] as? String ?? ""
            if path == "/var/mobile/Media/DCIM" {
                return [
                    "entries": [
                        ["name": "100APPLE", "type": "dir", "is_directory": true],
                    ],
                ]
            } else if path == "/var/mobile/Media/DCIM/100APPLE" {
                return [
                    "entries": [
                        ["name": "IMG_0001.PNG", "type": "file", "size": 1024, "mtime": 1700000000],
                        ["name": "IMG_0002.HEIC", "type": "file", "size": 2048, "mtime": 1700000020],
                        ["name": "IMG_0003.MOV", "type": "file", "size": 8192, "mtime": 1700000030],
                        ["name": "IMG_0002.AAE", "type": "file", "size": 256, "mtime": 1700000020],
                    ],
                ]
            }
        }
        return [:]
    }

    func downloadFile(path: String) async throws -> Data {
        // Return minimal 1x1 PNG image data
        let base64PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        return Data(base64Encoded: base64PNG) ?? Data([0x89, 0x50, 0x4e, 0x47])
    }

    func sendRequest(_: [String: Any]) async throws -> ([String: Any], Data?) { ([:], nil) }
    func uploadFile(path: String, data: Data, permissions: String) async throws {}
    func pullFile(_: String, to: URL, maximumBytes: Int?, permissions: Int?) async throws -> Int64 { 0 }
    func installIPA(localURL: URL) async throws -> String { "" }
    func screenshotJPEG() async throws -> Data { Data() }
    func guestProxy() async throws -> VPhoneProxyStatus { fatalError() }
    func runGuestToolReply(_: String, arguments: [String]) async throws -> [String: Any] { [:] }
    func makeFridaRelay(localPort: UInt16, guestPort: UInt16) async throws -> VPhoneFridaPortRelay { fatalError() }
    func appList() async throws -> [String: Any] { [:] }
    func appURLSchemes() async throws -> [String: Any] { [:] }
    func appOpenURL(_: String, bundleID: String) async throws -> [String: Any] { [:] }
}

@main
struct PhotosBrowserTests {
    @MainActor
    static func main() async throws {
        // 1. Kind inference
        precondition(VPhonePhotoItem.inferKind(name: "IMG_0001.png", folder: "100APPLE") == .screenshot)
        precondition(VPhonePhotoItem.inferKind(name: "IMG_0002.HEIC", folder: "100APPLE") == .photo)
        precondition(VPhonePhotoItem.inferKind(name: "photo.jpg", folder: "100APPLE") == .photo)
        precondition(VPhonePhotoItem.inferKind(name: "clip.mov", folder: "100APPLE") == .video)
        precondition(VPhonePhotoItem.inferKind(name: "meta.aae", folder: "100APPLE") == .other)

        // 2. Scan & Model Refresh
        let control = PhotosMockGuestControl()
        let model = VPhonePhotoBrowserModel(control: control)
        await model.refresh()

        precondition(model.photos.count == 3, "Non-media file .AAE must be excluded from photo browser")
        // Sorted newest first
        precondition(model.photos[0].name == "IMG_0003.MOV")
        precondition(model.photos[1].name == "IMG_0002.HEIC")
        precondition(model.photos[2].name == "IMG_0001.PNG")

        // 3. Filtering
        model.filter = .screenshots
        precondition(model.filteredPhotos.count == 1 && model.filteredPhotos[0].name == "IMG_0001.PNG")

        model.filter = .videos
        precondition(model.filteredPhotos.count == 1 && model.filteredPhotos[0].name == "IMG_0003.MOV")

        model.filter = .photos
        precondition(model.filteredPhotos.count == 1 && model.filteredPhotos[0].name == "IMG_0002.HEIC")

        model.filter = .all
        precondition(model.filteredPhotos.count == 3)

        // 4. Search
        model.search = "0001"
        precondition(model.filteredPhotos.count == 1 && model.filteredPhotos[0].name == "IMG_0001.PNG")
        model.search = ""

        // 5. Preview & Selection
        model.selectedPhotoID = model.photos[2].id // IMG_0001.PNG
        // Wait briefly for preview task to finish
        for _ in 0..<10 {
            if model.previewImage != nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        precondition(model.previewImage != nil, "Selected image must load previewImage")
        precondition(model.copySelectedImage(), "copySelectedImage must succeed when preview is loaded")

        // 6. Fast In-Memory Cache Verification
        // Switching away and switching back must load preview immediately without task delay
        model.selectedPhotoID = model.photos[0].id // Switch to IMG_0003.MOV
        model.selectedPhotoID = model.photos[2].id // Switch back to cached IMG_0001.PNG
        precondition(model.previewImage != nil, "Cached image must load synchronously with zero delay")
        precondition(!model.isLoadingPreview, "Cached image must not trigger isLoadingPreview")

        // 7. Cleanup
        model.close()
        precondition(model.previewImage == nil)

        print("Photos Browser checks passed: DCIM folder scan, media filtering, sorting, preview loading, search and clipboard export.")
    }
}
