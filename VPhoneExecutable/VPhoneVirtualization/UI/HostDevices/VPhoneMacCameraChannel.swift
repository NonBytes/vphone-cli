import Darwin
import Foundation

/// The camera companion and VM exchange only the latest frame in a private,
/// fixed-size mapping. flock coordinates processes; NSLock coordinates threads
/// using the same descriptor (flock alone does not serialize those threads).
final class VPhoneMacCameraChannel: @unchecked Sendable {
    enum ChannelError: Error {
        case invalidFrameSize
    }

    enum Control: UInt32 {
        case paused = 0
        case streaming = 1
        case terminated = 2
    }

    struct Frame {
        let sequence: UInt64
        let pixels: Data
    }

    static let width = 1280
    static let height = 720
    static let bytesPerRow = width * 4
    static let pixelCount = bytesPerRow * height
    static let headerSize = 64
    static let capacity = headerSize + pixelCount

    let path: String
    private let descriptor: Int32
    private let memory: UnsafeMutableRawPointer
    private let ownsFile: Bool
    private let lock = NSLock()

    convenience init() throws {
        var template = Array((NSTemporaryDirectory() + "vphone-camera-XXXXXX").utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let path = String(decoding: template.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self)
        do {
            guard ftruncate(descriptor, off_t(Self.capacity)) == 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
            try self.init(descriptor: descriptor, path: path, ownsFile: true)
        } catch {
            close(descriptor)
            unlink(path)
            throw error
        }
    }

    convenience init(path: String) throws {
        let descriptor = open(path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        do {
            var info = stat()
            guard fstat(descriptor, &info) == 0,
                info.st_uid == getuid(),
                info.st_mode & S_IFMT == S_IFREG,
                info.st_mode & 0o077 == 0,
                info.st_nlink == 1,
                info.st_size == Self.capacity
            else { throw CocoaError(.fileReadCorruptFile) }
            try self.init(descriptor: descriptor, path: path, ownsFile: false)
        } catch {
            close(descriptor)
            throw error
        }
    }

    private init(descriptor: Int32, path: String, ownsFile: Bool) throws {
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
            let memory = mmap(nil, Self.capacity, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0),
            memory != MAP_FAILED
        else { throw CocoaError(.fileReadUnknown) }
        self.descriptor = descriptor
        self.memory = memory
        self.path = path
        self.ownsFile = ownsFile
        if ownsFile { memset(memory, 0, Self.capacity) }
    }

    deinit {
        if ownsFile { setControl(.terminated) }
        munmap(memory, Self.capacity)
        close(descriptor)
        if ownsFile { unlink(path) }
    }

    func setControl(_ control: Control) {
        lock.lock()
        defer { lock.unlock() }
        guard flock(descriptor, LOCK_EX) == 0 else { return }
        defer { flock(descriptor, LOCK_UN) }
        memory.storeBytes(of: control.rawValue, as: UInt32.self)
    }

    func control() -> Control {
        lock.lock()
        defer { lock.unlock() }
        guard flock(descriptor, LOCK_SH) == 0 else { return .terminated }
        defer { flock(descriptor, LOCK_UN) }
        return Control(rawValue: memory.load(as: UInt32.self)) ?? .terminated
    }

    @discardableResult
    func publish(_ pixels: Data) throws -> Bool {
        guard pixels.count == Self.pixelCount else { throw ChannelError.invalidFrameSize }
        lock.lock()
        defer { lock.unlock() }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return false }
        defer { flock(descriptor, LOCK_UN) }
        guard memory.load(as: UInt32.self) == Control.streaming.rawValue else { return false }
        pixels.withUnsafeBytes { bytes in
            memory.advanced(by: Self.headerSize).copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }
        let previous = memory.load(fromByteOffset: 8, as: UInt64.self)
        let sequence = previous == UInt64.max ? 1 : previous + 1
        memory.storeBytes(of: sequence, toByteOffset: 8, as: UInt64.self)
        return true
    }

    func readFrame(after previousSequence: UInt64) -> Frame? {
        lock.lock()
        defer { lock.unlock() }
        guard flock(descriptor, LOCK_SH | LOCK_NB) == 0 else { return nil }
        defer { flock(descriptor, LOCK_UN) }
        let sequence = memory.load(fromByteOffset: 8, as: UInt64.self)
        guard memory.load(as: UInt32.self) == Control.streaming.rawValue,
            sequence != 0, sequence != previousSequence
        else { return nil }
        return Frame(
            sequence: sequence, pixels: Data(bytes: memory.advanced(by: Self.headerSize), count: Self.pixelCount))
    }
}
