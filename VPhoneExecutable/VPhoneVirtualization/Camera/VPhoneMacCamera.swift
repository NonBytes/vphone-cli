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
    private var cameraPicker: NSPopUpButton?
    private var discovery: AVCaptureDevice.DiscoverySession?
    private var deviceSnapshot: [String] = []
    private var selectedDeviceID: String?
    private var selectedDeviceName = ""
    private var nextDiscovery = Date.distantPast

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
                if granted {
                    discovery = AVCaptureDevice.DiscoverySession(
                        deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                        mediaType: .video, position: .unspecified)
                    refreshDevices()
                }
                updateCapture()
            }
        }
    }

    private func showWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 220),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = NSLocalizedString("VPhone — Mac Camera", comment: "Camera companion title")
        let status = NSTextField(
            labelWithString: NSLocalizedString("Waiting for Camera permission…", comment: "Camera permission pending"))
        status.frame = NSRect(x: 20, y: 166, width: 480, height: 38)
        status.maximumNumberOfLines = 2
        window.contentView?.addSubview(status)
        let picker = NSPopUpButton(frame: NSRect(x: 20, y: 118, width: 480, height: 28))
        picker.addItem(withTitle: NSLocalizedString("Select Camera", comment: "Camera device picker"))
        picker.isEnabled = false
        picker.target = self
        picker.action = #selector(cameraChanged(_:))
        window.contentView?.addSubview(picker)
        cameraPicker = picker
        let hint = NSTextField(labelWithString: NSLocalizedString(
            "iPhone: enable Continuity Camera and connect to this Mac.", comment: "Continuity Camera hint"))
        hint.frame = NSRect(x: 20, y: 12, width: 480, height: 30)
        hint.maximumNumberOfLines = 2
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        window.contentView?.addSubview(hint)
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
        if Date() >= nextDiscovery {
            nextDiscovery = Date().addingTimeInterval(1)
            refreshDevices()
        }
    }

    private func refreshDevices() {
        guard let discovery, let picker = cameraPicker else { return }
        let devices = discovery.devices
        let snapshot = devices.map { $0.uniqueID + "\n" + $0.localizedName + "\n" + String($0.isConnected) }
        guard snapshot != deviceSnapshot || selectedDeviceID == nil else { return }
        deviceSnapshot = snapshot
        if selectedDeviceID == nil, let device = devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? devices.first {
            selectedDeviceID = device.uniqueID
            selectedDeviceName = device.localizedName
        }
        picker.removeAllItems()
        for device in devices {
            picker.addItem(withTitle: device.localizedName)
            picker.lastItem?.representedObject = device.uniqueID
        }
        if let id = selectedDeviceID {
            if !devices.contains(where: { $0.uniqueID == id }) {
                picker.addItem(withTitle: String(format: NSLocalizedString(
                    "%@ (Disconnected)", comment: "Selected camera disconnected"), selectedDeviceName))
                picker.lastItem?.representedObject = id
            }
            picker.select(picker.itemArray.first { $0.representedObject as? String == id })
            // Reconfigure after a disconnect/reconnect, keeping the user's choice.
            capture?.selectDevice(id)
        } else {
            picker.addItem(withTitle: NSLocalizedString("No camera found", comment: "No capture devices"))
        }
        picker.isEnabled = !devices.isEmpty
    }

    @objc private func cameraChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem, let id = item.representedObject as? String else { return }
        selectedDeviceID = id
        selectedDeviceName = item.title
        capture?.selectDevice(id)
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
    private var selectedDeviceID: String?

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
        }
    }

    func selectDevice(_ id: String) {
        queue.async { [self] in
            guard !state.shuttingDown else { return }
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            session.commitConfiguration()
            selectedDeviceID = id
            state.configured = false
            // Clear the previous source while switching or waiting for reconnection.
            _ = try? channel.publish(Data(count: VPhoneMacCameraChannel.pixelCount))
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
        guard !state.configured, !state.shuttingDown, state.permission == .granted,
            channel.control() == .streaming, let selectedDeviceID else { return }
        do {
            let devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                mediaType: .video, position: .unspecified
            ).devices
            guard let device = devices.first(where: { $0.uniqueID == selectedDeviceID }), device.isConnected else {
                report(NSLocalizedString("Selected camera disconnected — reconnect it or choose another camera.",
                                        comment: "Selected device unavailable"))
                return
            }
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            guard session.canAddInput(input) else {
                report(NSLocalizedString("Cannot configure capture", comment: "Unsupported camera configuration"))
                return
            }
            session.addInput(input)
            if session.canSetSessionPreset(.hd1280x720) {
                session.sessionPreset = .hd1280x720
            } else if session.canSetSessionPreset(.high) {
                session.sessionPreset = .high
            }
            if output == nil {
                let output = AVCaptureVideoDataOutput()
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.alwaysDiscardsLateVideoFrames = true
                guard session.canAddOutput(output) else {
                    session.removeInput(input)
                    report(NSLocalizedString("Cannot configure capture", comment: "Unsupported camera configuration"))
                    return
                }
                output.setSampleBufferDelegate(self, queue: queue)
                session.addOutput(output)
                self.output = output
            }
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
