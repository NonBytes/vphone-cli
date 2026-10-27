import CoreImage
import Foundation

/// Capture policy is independent of AVCapture and can be tested without
/// requesting Camera consent or opening the user's camera.
struct VPhoneMacCameraState {
    enum Permission {
        case pending
        case granted
        case denied
    }

    enum Action: Equatable {
        case idle
        case start
        case stop
        case exit
    }

    var permission = Permission.pending
    var configured = false
    var shuttingDown = false

    func action(control: VPhoneMacCameraChannel.Control, ownerAlive: Bool, running: Bool) -> Action {
        guard ownerAlive, !shuttingDown, control != .terminated else { return .exit }
        let shouldRun = control == .streaming && permission == .granted && configured
        if shouldRun { return running ? .idle : .start }
        return running ? .stop : .idle
    }
}

enum VPhoneMacCameraRotation: Int, CaseIterable {
    case upright
    case clockwise
    case upsideDown
    case counterclockwise

    var title: String {
        switch self {
        case .upright: NSLocalizedString("Rotation: 0°", comment: "Camera rotation")
        case .clockwise: NSLocalizedString("Rotation: 90° clockwise", comment: "Camera rotation")
        case .upsideDown: NSLocalizedString("Rotation: 180°", comment: "Camera rotation")
        case .counterclockwise: NSLocalizedString("Rotation: 90° counterclockwise", comment: "Camera rotation")
        }
    }

    var orientation: CGImagePropertyOrientation {
        switch self {
        case .upright: .up
        case .clockwise: .right
        case .upsideDown: .down
        case .counterclockwise: .left
        }
    }

    func fittedImage(_ image: CIImage) -> CIImage {
        let image = image.oriented(orientation)
        let bounds = image.extent
        let width = CGFloat(VPhoneMacCameraChannel.width)
        let height = CGFloat(VPhoneMacCameraChannel.height)
        let scale = min(width / bounds.width, height / bounds.height)
        let fitted =
            image
            .transformed(by: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(
                by: CGAffineTransform(
                    translationX: (width - bounds.width * scale) / 2,
                    y: (height - bounds.height * scale) / 2
                ))
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        return fitted.composited(over: CIImage(color: .black).cropped(to: canvas)).cropped(to: canvas)
    }
}
