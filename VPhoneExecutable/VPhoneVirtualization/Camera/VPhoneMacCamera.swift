import AVFoundation
import AppKit
import CoreImage
import Darwin

/// Independently launched application: Camera consent belongs to this helper,
/// without replacing or re-signing the user's installed Launchpad.
@MainActor
final class VPhoneMacCameraAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var status: NSTextField?
    private var timer: Timer?
    private var channel: VPhoneMacCameraChannel?
    private var capture: VPhoneMacCameraCapture?
    private var owner: pid_t = 0
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        guard arguments.count == 3, let owner = Int32(arguments[2]), owner > 1 else {
            NSApp.terminate(nil)
            return
        }
        do {
            channel = try VPhoneMacCameraChannel(path: arguments[1])
        } catch {
            NSApp.terminate(nil)
            return
        }
        guard let channel, channel.control() == .streaming, kill(owner, 0) == 0 else {
            NSApp.terminate(nil)
            return
        }
        self.owner = owner
        showWindow()
        capture = VPhoneMacCameraCapture(channel: channel) { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, !isTerminating else { return }
                status?.stringValue = message
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateCapture() }
        }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self, !isTerminating else { return }
                capture?.setPermission(granted)
                updateCapture()
            }
        }
    }

    private func showWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 160),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = NSLocalizedString("VPhone — Mac Camera", comment: "Camera companion title")
        let status = NSTextField(
            labelWithString: NSLocalizedString("Waiting for Camera permission…", comment: "Camera permission pending"))
        status.frame = NSRect(x: 20, y: 106, width: 480, height: 38)
        status.maximumNumberOfLines = 2
        window.contentView?.addSubview(status)
        let rotation = NSPopUpButton(frame: NSRect(x: 20, y: 52, width: 290, height: 28))
        rotation.addItems(withTitles: VPhoneMacCameraRotation.allCases.map(\.title))
        rotation.target = self
        rotation.action = #selector(rotationChanged(_:))
        window.contentView?.addSubview(rotation)
        let stop = NSButton(
            title: NSLocalizedString("Stop Camera", comment: "Stop capture and close companion"),
            target: self, action: #selector(stopCamera)
        )
        stop.frame = NSRect(x: 330, y: 52, width: 170, height: 28)
        window.contentView?.addSubview(stop)
        self.window = window
        self.status = status
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateCapture() {
        guard !isTerminating, let channel else { return }
        let control = channel.control()
        guard kill(owner, 0) == 0, control != .terminated else {
            NSApp.terminate(nil)
            return
        }
        capture?.update(control: control)
    }

    @objc private func rotationChanged(_ sender: NSPopUpButton) {
        guard let rotation = VPhoneMacCameraRotation(rawValue: sender.indexOfSelectedItem) else { return }
        capture?.setRotation(rotation)
    }

    @objc private func stopCamera() {
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        timer?.invalidate()
        timer = nil
        channel?.setControl(.terminated)
        capture?.shutdown()
        capture = nil
        channel = nil
    }
}

/// All mutable capture state and sample callbacks are confined to queue.
/// shutdown drains that queue before releasing the shared channel.
final class VPhoneMacCameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.vphone.mac-camera.capture")
    private let context = CIContext()
    private let channel: VPhoneMacCameraChannel
    private let report: @Sendable (String) -> Void
    private var output: AVCaptureVideoDataOutput?
    private var state = VPhoneMacCameraState()
    private var rotation = VPhoneMacCameraRotation.upright

    init(channel: VPhoneMacCameraChannel, report: @escaping @Sendable (String) -> Void) {
        self.channel = channel
        self.report = report
    }

    func setPermission(_ granted: Bool) {
        queue.async { [self] in
            guard !state.shuttingDown else { return }
            state.permission = granted ? .granted : .denied
            guard granted else {
                report(
                    NSLocalizedString(
                        "Camera denied — enable in Privacy & Security → Camera.", comment: "Camera permission denied"))
                return
            }
            configure()
        }
    }

    func setRotation(_ rotation: VPhoneMacCameraRotation) {
        queue.async { [self] in self.rotation = rotation }
    }

    func update(control: VPhoneMacCameraChannel.Control) {
        queue.async { [self] in
            switch state.action(control: control, ownerAlive: true, running: session.isRunning) {
            case .start: session.startRunning()
            case .stop, .exit:
                if session.isRunning { session.stopRunning() }
            case .idle: break
            }
        }
    }

    func shutdown() {
        queue.sync {
            state.shuttingDown = true
            output?.setSampleBufferDelegate(nil, queue: nil)
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() {
        guard !state.configured, !state.shuttingDown, channel.control() == .streaming else { return }
        do {
            let devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified
            ).devices
            guard let device = devices.first ?? AVCaptureDevice.default(for: .video) else {
                report(NSLocalizedString("No Mac camera found", comment: "Camera unavailable"))
                return
            }
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            guard session.canSetSessionPreset(.hd1280x720) else {
                report(NSLocalizedString("Cannot configure capture", comment: "Unsupported camera configuration"))
                return
            }
            session.sessionPreset = .hd1280x720
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            guard session.canAddInput(input), session.canAddOutput(output) else {
                report(NSLocalizedString("Cannot configure capture", comment: "Unsupported camera configuration"))
                return
            }
            output.setSampleBufferDelegate(self, queue: queue)
            session.addInput(input)
            session.addOutput(output)
            self.output = output
            state.configured = true
            report(
                String(
                    format: NSLocalizedString("Camera: %@ — local VM feed", comment: "Selected Mac camera"),
                    device.localizedName))
        } catch {
            report(error.localizedDescription)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        guard !state.shuttingDown, channel.control() == .streaming,
            let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        let image = rotation.fittedImage(CIImage(cvPixelBuffer: buffer))
        var pixels = Data(count: VPhoneMacCameraChannel.pixelCount)
        pixels.withUnsafeMutableBytes { bytes in
            context.render(
                image, toBitmap: bytes.baseAddress!, rowBytes: VPhoneMacCameraChannel.bytesPerRow,
                bounds: CGRect(x: 0, y: 0, width: VPhoneMacCameraChannel.width, height: VPhoneMacCameraChannel.height),
                format: .BGRA8, colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        do { try channel.publish(pixels) } catch { report(error.localizedDescription) }
    }
}
