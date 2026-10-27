import AppKit
import AVFoundation
import CoreImage
import Darwin

// Separate application: owns Camera consent instead of changing Launchpad's signature.
final class CameraBridge: NSObject, NSApplicationDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "com.vphone.mac-camera.capture")
    let context = CIContext()
    @MainActor var window: NSWindow!
    @MainActor var status: NSTextField!
    var timer: Timer?
    var fd: Int32 = -1
    var memory: UnsafeMutableRawPointer!
    let capacity = 64 + 1280 * 720 * 4
    var sequence: UInt64 = 0
    var rotation = 0
    var path = ""
    var owner: pid_t = 0

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        guard args.count == 3, let pid = Int32(args[2]) else { NSApp.terminate(nil); return }
        path = args[1]; owner = pid
        fd = open(path, O_RDWR | O_NOFOLLOW)
        var st = stat()
        guard fd >= 0, fstat(fd, &st) == 0, st.st_uid == getuid(), st.st_size == capacity else {
            NSApp.terminate(nil); return
        }
        memory = mmap(nil, capacity, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        guard memory != MAP_FAILED else { NSApp.terminate(nil); return }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 160),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "VPhone — Mac Camera"
        status = NSTextField(labelWithString: "Waiting for Camera permission…")
        status.frame = NSRect(x: 20, y: 112, width: 400, height: 24)
        window.contentView!.addSubview(status)
        let rotate = NSPopUpButton(frame: NSRect(x: 20, y: 65, width: 250, height: 28))
        rotate.addItems(withTitles: ["Rotation: 0°", "Rotation: 90° clockwise", "Rotation: 180°", "Rotation: 90° counterclockwise"])
        rotate.target = self; rotate.action = #selector(rotateChanged(_:))
        window.contentView!.addSubview(rotate)
        let stop = NSButton(title: "Stop Camera", target: self, action: #selector(stopCamera))
        stop.frame = NSRect(x: 290, y: 65, width: 130, height: 28)
        window.contentView!.addSubview(stop)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
            guard let self else { return }
            guard kill(self.owner, 0) == 0 else { NSApp.terminate(nil); return }
            flock(self.fd, LOCK_SH)
            let control = self.memory.load(as: UInt32.self)
            flock(self.fd, LOCK_UN)
            if control == 2 { NSApp.terminate(nil); return }
            self.queue.async {
                if control == 0, self.session.isRunning { self.session.stopRunning() }
                if control == 1, !self.session.inputs.isEmpty, !self.session.isRunning { self.session.startRunning() }
            }
            }
        }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                guard granted else { self.status.stringValue = "Camera denied — enable in Privacy & Security → Camera."; return }
                self.queue.async { self.configure() }
            }
        }
    }
    @MainActor @objc func rotateChanged(_ sender: NSPopUpButton) {
        let value = sender.indexOfSelectedItem
        queue.async { self.rotation = value }
    }
    @MainActor @objc func stopCamera() { NSApp.terminate(nil) }
    @MainActor func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    @MainActor func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        queue.sync { if session.isRunning { session.stopRunning() } }
        if memory != nil, memory != MAP_FAILED { munmap(memory, capacity) }
        if fd >= 0 { close(fd) }

    }
    func configure() {
        do {
            let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices
            guard let device = devices.first ?? AVCaptureDevice.default(for: .video) else {
                throw NSError(domain: "VPhoneCamera", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Mac camera found"])
            }
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                throw NSError(domain: "VPhoneCamera", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot configure capture"])
            }
            session.addInput(input); session.addOutput(output); session.commitConfiguration()
            let deviceName = device.localizedName
            DispatchQueue.main.async { self.status.stringValue = "Camera: \(deviceName) — local VM feed" }
        } catch { DispatchQueue.main.async { self.status.stringValue = error.localizedDescription } }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var image = CIImage(cvPixelBuffer: buffer)
        let orientations: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
        image = image.oriented(orientations[rotation])
        let bounds = image.extent
        let scale = min(1280 / bounds.width, 720 / bounds.height)
        image = image.transformed(by: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: (1280 - bounds.width * scale) / 2, y: (720 - bounds.height * scale) / 2))
        image = image.composited(over: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720)))
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return }
        defer { flock(fd, LOCK_UN) }
        guard memory.load(as: UInt32.self) == 1 else { return }
        context.render(image, toBitmap: memory.advanced(by: 64), rowBytes: 5120,
                       bounds: CGRect(x: 0, y: 0, width: 1280, height: 720), format: .BGRA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())
        sequence &+= 1
        memory.storeBytes(of: sequence, toByteOffset: 8, as: UInt64.self)
    }
}
let app = NSApplication.shared
let delegate = CameraBridge()
app.delegate = delegate
app.run()
