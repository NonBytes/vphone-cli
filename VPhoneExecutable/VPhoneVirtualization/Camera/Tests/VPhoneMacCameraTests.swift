import CoreImage
import Darwin
import Foundation

private struct VPhoneCameraTestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw VPhoneCameraTestFailure(description: message) }
}

@main
struct VPhoneMacCameraTests {
    static func main() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--publish" {
            let channel = try VPhoneMacCameraChannel(path: CommandLine.arguments[2])
            for value in UInt8(1)...UInt8(12) {
                let pixels = Data(repeating: value, count: VPhoneMacCameraChannel.pixelCount)
                while try !channel.publish(pixels) { usleep(1000) }
            }
            return
        }
        let tests: [(String, () throws -> Void)] = [
            ("permission and lifecycle", lifecycle),
            ("private channel and frame validation", channel),
            ("pause and terminate", stop),
            ("fresh channel on restart", restart),
            ("reject symlinks and malformed mappings", invalidMapping),
            ("cross-process frame consistency", crossProcess),
            ("rotation and letterbox geometry", rotation),
        ]
        for (name, test) in tests {
            try test()
            print("PASS: \(name)")
        }
        print("\(tests.count) camera regression tests passed; no camera access requested.")
    }

    static func lifecycle() throws {
        var state = VPhoneMacCameraState()
        try expect(
            state.action(control: .streaming, ownerAlive: true, running: false) == .idle,
            "pending permission must not start capture")
        state.permission = .denied
        state.configured = true
        try expect(
            state.action(control: .streaming, ownerAlive: true, running: false) == .idle,
            "denied permission must not start capture")
        try expect(
            state.action(control: .streaming, ownerAlive: true, running: true) == .stop,
            "permission revocation must stop capture")
        state.permission = .granted
        state.configured = false
        try expect(
            state.action(control: .streaming, ownerAlive: true, running: false) == .idle,
            "unconfigured capture must not start")
        state.configured = true
        for _ in 0..<20 {
            try expect(
                state.action(control: .streaming, ownerAlive: true, running: false) == .start, "capture must resume")
            try expect(
                state.action(control: .streaming, ownerAlive: true, running: true) == .idle, "start must be idempotent")
            try expect(
                state.action(control: .paused, ownerAlive: true, running: true) == .stop, "paused capture must stop")
            try expect(
                state.action(control: .paused, ownerAlive: true, running: false) == .idle, "stop must be idempotent")
        }
        try expect(
            state.action(control: .streaming, ownerAlive: false, running: true) == .exit, "VM exit must end capture")
        try expect(
            state.action(control: .terminated, ownerAlive: true, running: true) == .exit, "terminated channel must exit"
        )
        state.shuttingDown = true
        try expect(
            state.action(control: .streaming, ownerAlive: true, running: false) == .exit,
            "late permission callback must not restart capture")
    }

    static func channel() throws {
        let writer = try VPhoneMacCameraChannel()
        let reader = try VPhoneMacCameraChannel(path: writer.path)
        var info = stat()
        try expect(stat(writer.path, &info) == 0 && info.st_mode & 0o077 == 0, "camera channel must be private")
        try expect(reader.readFrame(after: 0) == nil, "empty channel must not expose a frame")
        writer.setControl(.streaming)
        do {
            try writer.publish(Data([1, 2, 3]))
            throw VPhoneCameraTestFailure(description: "invalid frame size was accepted")
        } catch VPhoneMacCameraChannel.ChannelError.invalidFrameSize {}
        let pixels = Data(repeating: 0xA5, count: VPhoneMacCameraChannel.pixelCount)
        try expect(tryPublish(writer, pixels), "frame publication failed")
        guard let frame = reader.readFrame(after: 0) else {
            throw VPhoneCameraTestFailure(description: "reader missed published frame")
        }
        try expect(frame.sequence == 1 && frame.pixels == pixels, "frame content mismatch")
        try expect(reader.readFrame(after: frame.sequence) == nil, "duplicate frame must be dropped")
    }

    private static func tryPublish(_ channel: VPhoneMacCameraChannel, _ pixels: Data) -> Bool {
        (try? channel.publish(pixels)) == true
    }

    static func stop() throws {
        let writer = try VPhoneMacCameraChannel()
        let reader = try VPhoneMacCameraChannel(path: writer.path)
        let pixels = Data(repeating: 7, count: VPhoneMacCameraChannel.pixelCount)
        writer.setControl(.streaming)
        try expect(tryPublish(writer, pixels), "initial frame failed")
        writer.setControl(.paused)
        try expect(!tryPublish(writer, pixels), "paused channel accepted capture")
        try expect(reader.readFrame(after: 0) == nil, "paused channel exposed stale pixels")
        writer.setControl(.terminated)
        try expect(!tryPublish(writer, pixels), "terminated channel accepted capture")
        try expect(reader.control() == .terminated, "termination not visible across descriptors")
    }

    static func restart() throws {
        var oldOwner: VPhoneMacCameraChannel? = try VPhoneMacCameraChannel()
        let oldPath = oldOwner!.path
        let lateHelper = try VPhoneMacCameraChannel(path: oldPath)
        oldOwner?.setControl(.streaming)
        oldOwner = nil
        try expect(!FileManager.default.fileExists(atPath: oldPath), "old camera buffer was not removed")
        try expect(lateHelper.control() == .terminated, "old helper was not signalled")
        let newOwner = try VPhoneMacCameraChannel()
        newOwner.setControl(.streaming)
        try expect(newOwner.path != oldPath, "restart reused the old helper's mapping")
        try expect(newOwner.readFrame(after: 0) == nil, "new stream contains stale pixels")
        let pixels = Data(repeating: 9, count: VPhoneMacCameraChannel.pixelCount)
        try expect(!tryPublish(lateHelper, pixels), "late helper wrote after shutdown")
        try expect(newOwner.readFrame(after: 0) == nil, "late helper contaminated new stream")
    }

    static func invalidMapping() throws {
        let owner = try VPhoneMacCameraChannel()
        let link = owner.path + ".link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: owner.path)
        defer { try? FileManager.default.removeItem(atPath: link) }
        do {
            _ = try VPhoneMacCameraChannel(path: link)
            throw VPhoneCameraTestFailure(description: "symlink accepted")
        } catch is CocoaError {}
        let invalid = owner.path + ".invalid"
        FileManager.default.createFile(atPath: invalid, contents: Data([0]))
        defer { try? FileManager.default.removeItem(atPath: invalid) }
        do {
            _ = try VPhoneMacCameraChannel(path: invalid)
            throw VPhoneCameraTestFailure(description: "malformed mapping accepted")
        } catch is CocoaError {}
    }

    static func crossProcess() throws {
        let owner = try VPhoneMacCameraChannel()
        owner.setControl(.streaming)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--publish", owner.path]
        try child.run()
        var sequence: UInt64 = 0
        var reads = 0
        let deadline = Date().addingTimeInterval(15)
        while child.isRunning && Date() < deadline {
            if let frame = owner.readFrame(after: sequence) {
                sequence = frame.sequence
                reads += 1
                let first = frame.pixels.first!
                try expect(frame.pixels.allSatisfy { $0 == first }, "torn frame while another process wrote")
            }
            usleep(1000)
        }
        if child.isRunning {
            child.terminate()
            child.waitUntilExit()
            throw VPhoneCameraTestFailure(description: "cross-process writer timed out")
        }
        child.waitUntilExit()
        try expect(child.terminationStatus == 0, "child publisher failed")
        guard let final = owner.readFrame(after: 0) else {
            throw VPhoneCameraTestFailure(description: "final child frame missing")
        }
        try expect(final.sequence == 12 && final.pixels.allSatisfy { $0 == 12 }, "final child frame mismatch")
        try expect(reads > 0, "no frames read during concurrent publication")
    }

    static func rotation() throws {
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(
            to: CGRect(x: 0, y: 0, width: 2, height: 2))
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(
            to: CGRect(x: 2, y: 0, width: 2, height: 2))
        let image = red.composited(over: blue).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 2))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let expected: [(VPhoneMacCameraRotation, CGPoint, CGPoint)] = [
            (.upright, CGPoint(x: 320, y: 360), CGPoint(x: 960, y: 360)),
            (.upsideDown, CGPoint(x: 960, y: 360), CGPoint(x: 320, y: 360)),
            (.clockwise, CGPoint(x: 640, y: 540), CGPoint(x: 640, y: 180)),
            (.counterclockwise, CGPoint(x: 640, y: 180), CGPoint(x: 640, y: 540)),
        ]
        for (rotation, redPoint, bluePoint) in expected {
            let fitted = rotation.fittedImage(image)
            try expect(fitted.extent == CGRect(x: 0, y: 0, width: 1280, height: 720), "rotation changed wire geometry")
            func sample(_ point: CGPoint) -> [UInt8] {
                var bytes = [UInt8](repeating: 0, count: 4)
                context.render(
                    fitted, toBitmap: &bytes, rowBytes: 4,
                    bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1),
                    format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                return bytes
            }
            let redPixel = sample(redPoint)
            let bluePixel = sample(bluePoint)
            try expect(redPixel[0] > 240 && redPixel[2] < 10, "red marker rotated incorrectly: \(rotation)")
            try expect(bluePixel[2] > 240 && bluePixel[0] < 10, "blue marker rotated incorrectly: \(rotation)")
            if rotation == .clockwise || rotation == .counterclockwise {
                let border = sample(CGPoint(x: 10, y: 360))
                try expect(border[0] < 10 && border[1] < 10 && border[2] < 10, "aspect-fit border must be black")
            }
        }
    }
}
