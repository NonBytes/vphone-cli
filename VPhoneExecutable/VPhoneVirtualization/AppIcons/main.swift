import Foundation
import UIKit
import ObjectiveC

struct IconResult: Codable {
    let bundleID: String
    let png: String?
}

do {
    guard CommandLine.arguments.count == 2, CommandLine.arguments[1].utf8.count <= 8192 else { throw NSError(domain: "AppIcons", code: 1) }
    let identifiers = try JSONDecoder().decode([String].self, from: Data(CommandLine.arguments[1].utf8))
    guard identifiers.count <= 12, identifiers.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 255 && $0.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0) } }) else { throw NSError(domain: "AppIcons", code: 2) }
    let selector = NSSelectorFromString("_applicationIconImageForBundleIdentifier:format:scale:")
    typealias GetIcon = @convention(c) (AnyObject, Selector, NSString, Int, Double) -> Unmanaged<AnyObject>?
    let method = class_getClassMethod(UIImage.self, selector)
    let getter = method.map { unsafeBitCast(method_getImplementation($0), to: GetIcon.self) }
    let results = identifiers.map { identifier in
        autoreleasepool {
            guard let getter, let image = getter(UIImage.self, selector, identifier as NSString, 0, 2)?.takeUnretainedValue() as? UIImage else {
                return IconResult(bundleID: identifier, png: nil)
            }
            let format = UIGraphicsImageRendererFormat(); format.scale = 2; format.opaque = false
            let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: 32, height: 32))
            }
            let png = thumbnail.pngData().flatMap { $0.count <= 262144 ? $0.base64EncodedString() : nil }
            return IconResult(bundleID: identifier, png: png)
        }
    }
    FileHandle.standardOutput.write(try JSONEncoder().encode(results))
} catch {
    FileHandle.standardError.write(Data("Invalid app icon request.\n".utf8)); exit(1)
}
