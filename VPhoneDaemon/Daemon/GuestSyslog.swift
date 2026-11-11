import Foundation
import ObjectiveC

/// Captures live unified log events via `LoggingSupport.framework`.
///
/// Configures `OSLogEventLiveStream` flags from the requested severity level so
/// `info`, `debug`, and `all` captures actually receive volatile Info and Debug
/// entries from `diagnosticd`, and keeps named `session` streams active across
/// consecutive polls to avoid inter-batch gaps.
enum GuestSyslog {
    struct Entry: Sendable {
        let process: String
        let pid: Int
        let message: String
        let subsystem: String
        let category: String
        let level: String
        let date: Date?

        var jsonObject: [String: Any] {
            [
                "process": process,
                "pid": pid,
                "message": message,
                "subsystem": subsystem,
                "category": category,
                "level": level,
                "date": date.map { Self.formatDate($0) } ?? "",
            ]
        }

        private static func formatDate(_ date: Date) -> String {
            date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        }
    }

    struct Batch: Sendable {
        let entries: [Entry]
        let truncated: Bool
    }

    struct Filter: Equatable, Sendable {
        let process: String?
        let subsystem: String?
        let subsystemPrefix: String?
        let category: String?
        let messageContains: String?
        let minRank: Int

        init(
            process: String?,
            level: String,
            subsystem: String?,
            category: String?,
            messageContains: String?,
        ) throws {
            guard let rank = GuestSyslog.levelRank(level) else {
                throw GuestAPIError.invalidRequest("unknown log level: \(level)")
            }
            self.process = Self.nonEmpty(process)
            let normalizedSubsystem = Self.nonEmpty(subsystem)
            self.subsystem = normalizedSubsystem
            subsystemPrefix = normalizedSubsystem.map { $0 + "." }
            self.category = Self.nonEmpty(category)
            self.messageContains = Self.nonEmpty(messageContains)
            minRank = rank
        }

        var streamFlags: UInt64 {
            switch minRank {
            case 0: 0x01 | 0x02 // Info | Debug
            case 1: 0x01 // Info
            default: 0x00 // Notice, Error, Fault
            }
        }

        func matches(
            process: String?,
            subsystem: String?,
            category: String?,
            logType: UInt64,
            message: String,
        ) -> Bool {
            if GuestSyslog.typeRank(logType) < minRank { return false }
            if let processFilter = self.process {
                guard let process, process.range(of: processFilter, options: .caseInsensitive) != nil else {
                    return false
                }
            }
            if let subsystemFilter = self.subsystem {
                guard let subsystem,
                      subsystem == subsystemFilter || (subsystemPrefix.map { subsystem.hasPrefix($0) } ?? false)
                else {
                    return false
                }
            }
            if let categoryFilter = self.category {
                guard category == categoryFilter else { return false }
            }
            if let messageFilter = self.messageContains {
                guard message.range(of: messageFilter, options: .literal) != nil else { return false }
            }
            return true
        }

        private static func nonEmpty(_ value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            return value
        }
    }

    static func capture(
        seconds: TimeInterval,
        process: String? = nil,
        level: String = "all",
        maxLines: Int = 500,
        subsystem: String? = nil,
        category: String? = nil,
        messageContains: String? = nil,
        session: String? = nil,
    ) throws -> Batch {
        guard seconds.isFinite, (0.1 ... 60).contains(seconds), (1 ... 5000).contains(maxLines) else {
            throw GuestAPIError.invalidRequest("seconds must be 0.1–60 and max_lines 1–5000")
        }
        let filter = try Filter(
            process: process,
            level: level,
            subsystem: subsystem,
            category: category,
            messageContains: messageContains,
        )
        let sessionID = session.flatMap { $0.isEmpty ? nil : $0 }
        if let sessionID {
            let ttl = max(seconds * 4, 15)
            let capture = try SessionStore.shared.acquire(id: sessionID, filter: filter, ttl: ttl)
            let batch = capture.drain(maxLines: maxLines, timeout: seconds, coalesce: true)
            SessionStore.shared.scheduleExpiry(id: sessionID, capture: capture, ttl: ttl)
            return batch
        }
        let capture = try LiveCapture(filter: filter, maxBuffer: maxLines, overflowKeepsNewest: false)
        defer { capture.stop() }
        return capture.drain(maxLines: maxLines, timeout: seconds, coalesce: false)
    }

    static func levelRank(_ level: String) -> Int? {
        switch level {
        case "all", "debug": 0
        case "info": 1
        case "default", "notice": 2
        case "error": 3
        case "fault": 4
        default: nil
        }
    }

    static func typeRank(_ type: UInt64) -> Int {
        switch type {
        case 0x02: 0
        case 0x01: 1
        case 0x10: 3
        case 0x11: 4
        default: 2
        }
    }

    static func severity(_ type: UInt64) -> String {
        switch type {
        case 0x00: "notice"
        case 0x01: "info"
        case 0x02: "debug"
        case 0x10: "error"
        case 0x11: "fault"
        default: "default"
        }
    }
}

// MARK: - LoggingSupport Runtime Bridge

private enum LoggingSupport {
    typealias SendObject = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
    typealias SendUInt64 = @convention(c) (AnyObject, Selector) -> UInt64
    typealias SendInt32 = @convention(c) (AnyObject, Selector) -> Int32
    typealias SendVoid = @convention(c) (AnyObject, Selector) -> Void
    typealias SendSetUInt64 = @convention(c) (AnyObject, Selector, UInt64) -> Void
    typealias SendSetBlock = @convention(c) (AnyObject, Selector, AnyObject) -> Void

    struct DispatchTable: @unchecked Sendable {
        let streamClass: NSObject.Type
        let sendObject: SendObject
        let sendUInt64: SendUInt64
        let sendInt32: SendInt32
        let sendVoid: SendVoid
        let sendSetUInt64: SendSetUInt64
        let sendSetBlock: SendSetBlock
    }

    private static let table: DispatchTable? = {
        _ = dlopen("/System/Library/PrivateFrameworks/LoggingSupport.framework/LoggingSupport", RTLD_NOW)
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let sym = dlsym(rtldDefault, "objc_msgSend"),
              let cls = NSClassFromString("OSLogEventLiveStream") as? NSObject.Type
        else {
            return nil
        }
        return DispatchTable(
            streamClass: cls,
            sendObject: unsafeBitCast(sym, to: SendObject.self),
            sendUInt64: unsafeBitCast(sym, to: SendUInt64.self),
            sendInt32: unsafeBitCast(sym, to: SendInt32.self),
            sendVoid: unsafeBitCast(sym, to: SendVoid.self),
            sendSetUInt64: unsafeBitCast(sym, to: SendSetUInt64.self),
            sendSetBlock: unsafeBitCast(sym, to: SendSetBlock.self),
        )
    }()

    static let setFlagsSelector = NSSelectorFromString("setFlags:")
    static let setEventHandlerSelector = NSSelectorFromString("setEventHandler:")
    static let setInvalidationHandlerSelector = NSSelectorFromString("setInvalidationHandler:")
    static let activateSelector = NSSelectorFromString("activate")
    static let invalidateSelector = NSSelectorFromString("invalidate")
    static let composedMessageSelector = NSSelectorFromString("composedMessage")
    static let processSelector = NSSelectorFromString("process")
    static let subsystemSelector = NSSelectorFromString("subsystem")
    static let categorySelector = NSSelectorFromString("category")
    static let dateSelector = NSSelectorFromString("date")
    static let logTypeSelector = NSSelectorFromString("logType")
    static let processIdentifierSelector = NSSelectorFromString("processIdentifier")

    static func dispatch() throws -> DispatchTable {
        guard let table else {
            throw GuestAPIError.operationFailed("unified log stream unavailable")
        }
        return table
    }

    static func sanitizedString(_ object: Unmanaged<AnyObject>?) -> String? {
        guard let ns = object?.takeUnretainedValue() as? NSString else { return nil }
        return String(decoding: (ns as String).utf16, as: UTF16.self)
    }
}

// MARK: - Live Stream Capture

private final class LiveCapture: @unchecked Sendable {
    static let sessionBufferLimit = 10000
    static let coalesceWindow: TimeInterval = 0.25

    let filter: GuestSyslog.Filter
    private let dispatch: LoggingSupport.DispatchTable
    private let maxBuffer: Int
    private let overflowKeepsNewest: Bool
    private let condition = NSCondition()
    private var stream: NSObject?
    private var buffer: [GuestSyslog.Entry] = []
    private var overflowed = false
    private var stopped = false

    init(filter: GuestSyslog.Filter, maxBuffer: Int, overflowKeepsNewest: Bool) throws {
        let dispatch = try LoggingSupport.dispatch()
        let stream = dispatch.streamClass.init()
        guard stream.responds(to: LoggingSupport.setEventHandlerSelector),
              stream.responds(to: LoggingSupport.activateSelector),
              stream.responds(to: LoggingSupport.invalidateSelector)
        else {
            throw GuestAPIError.operationFailed("unified log stream unavailable")
        }
        self.filter = filter
        self.dispatch = dispatch
        self.maxBuffer = max(1, maxBuffer)
        self.overflowKeepsNewest = overflowKeepsNewest
        self.stream = stream

        if stream.responds(to: LoggingSupport.setFlagsSelector) {
            dispatch.sendSetUInt64(stream, LoggingSupport.setFlagsSelector, filter.streamFlags)
        }
        let handler: @convention(block) (AnyObject) -> Void = { [weak self] event in
            self?.handle(event: event)
        }
        dispatch.sendSetBlock(stream, LoggingSupport.setEventHandlerSelector, handler as AnyObject)
        if stream.responds(to: LoggingSupport.setInvalidationHandlerSelector) {
            let invalidated: @convention(block) () -> Void = { [weak self] in
                self?.markInvalidated()
            }
            dispatch.sendSetBlock(stream, LoggingSupport.setInvalidationHandlerSelector, invalidated as AnyObject)
        }
        dispatch.sendVoid(stream, LoggingSupport.activateSelector)
    }

    deinit {
        stop()
    }

    var isStopped: Bool {
        condition.lock()
        defer { condition.unlock() }
        return stopped
    }

    func drain(maxLines: Int, timeout: TimeInterval, coalesce: Bool) -> GuestSyslog.Batch {
        let finalDeadline = Date().addingTimeInterval(timeout)
        condition.lock()
        var coalesceDeadline: Date? = buffer.isEmpty ? nil : finalDeadline
        if coalesce, !buffer.isEmpty {
            coalesceDeadline = min(finalDeadline, Date().addingTimeInterval(Self.coalesceWindow))
        }
        while !stopped && buffer.count < maxLines {
            if coalesce, !buffer.isEmpty, coalesceDeadline == nil {
                coalesceDeadline = min(finalDeadline, Date().addingTimeInterval(Self.coalesceWindow))
            }
            let deadline = coalesce ? (coalesceDeadline ?? finalDeadline) : finalDeadline
            if deadline.timeIntervalSinceNow <= 0 {
                break
            }
            _ = condition.wait(until: deadline)
        }
        let take = min(buffer.count, maxLines)
        let drained = Array(buffer.prefix(take))
        buffer.removeFirst(take)
        let truncated = overflowed || !buffer.isEmpty
        if buffer.isEmpty {
            overflowed = false
        }
        condition.unlock()
        return GuestSyslog.Batch(entries: drained, truncated: truncated)
    }

    func stop() {
        condition.lock()
        guard !stopped else {
            condition.unlock()
            return
        }
        stopped = true
        let activeStream = stream
        stream = nil
        condition.broadcast()
        condition.unlock()
        if let activeStream {
            dispatch.sendVoid(activeStream, LoggingSupport.invalidateSelector)
        }
    }

    private func markInvalidated() {
        condition.lock()
        stopped = true
        stream = nil
        condition.broadcast()
        condition.unlock()
    }

    private func handle(event: AnyObject) {
        autoreleasepool {
            guard let message = LoggingSupport.sanitizedString(
                dispatch.sendObject(event, LoggingSupport.composedMessageSelector)
            ) else {
                return
            }
            let process = LoggingSupport.sanitizedString(
                dispatch.sendObject(event, LoggingSupport.processSelector)
            )
            let subsystem = LoggingSupport.sanitizedString(
                dispatch.sendObject(event, LoggingSupport.subsystemSelector)
            )
            let category = LoggingSupport.sanitizedString(
                dispatch.sendObject(event, LoggingSupport.categorySelector)
            )
            let logType = dispatch.sendUInt64(event, LoggingSupport.logTypeSelector)
            guard filter.matches(
                process: process,
                subsystem: subsystem,
                category: category,
                logType: logType,
                message: message,
            ) else {
                return
            }
            let pid = Int(dispatch.sendInt32(event, LoggingSupport.processIdentifierSelector))
            let date = dispatch.sendObject(event, LoggingSupport.dateSelector)?.takeUnretainedValue() as? Date
            let entry = GuestSyslog.Entry(
                process: process ?? "",
                pid: pid,
                message: message,
                subsystem: subsystem ?? "",
                category: category ?? "",
                level: GuestSyslog.severity(logType),
                date: date,
            )
            condition.lock()
            defer { condition.unlock() }
            guard !stopped else { return }
            if buffer.count >= maxBuffer {
                overflowed = true
                if overflowKeepsNewest {
                    buffer.removeFirst()
                    buffer.append(entry)
                }
            } else {
                buffer.append(entry)
            }
            condition.broadcast()
        }
    }
}

// MARK: - Continuous Session Store

private final class SessionStore: @unchecked Sendable {
    static let shared = SessionStore()
    private static let maximumSessions = 4

    private struct Record {
        let capture: LiveCapture
        var lastAccess: Date
        var expiresAt: Date
    }

    private let lock = NSLock()
    private let cleanupQueue = DispatchQueue(label: "vphoned.syslog.session-cleanup", qos: .utility)
    private var records: [String: Record] = [:]

    func acquire(id: String, filter: GuestSyslog.Filter, ttl: TimeInterval) throws -> LiveCapture {
        let now = Date()
        let expiresAt = now.addingTimeInterval(ttl)
        var evicted: [LiveCapture] = []

        lock.lock()
        if let existing = records[id], !existing.capture.isStopped, existing.capture.filter == filter {
            records[id]?.lastAccess = now
            records[id]?.expiresAt = expiresAt
            lock.unlock()
            return existing.capture
        }
        if let existing = records.removeValue(forKey: id) {
            evicted.append(existing.capture)
        }
        while records.count >= Self.maximumSessions {
            guard let oldest = records.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key,
                  let removed = records.removeValue(forKey: oldest)
            else {
                break
            }
            evicted.append(removed.capture)
        }
        lock.unlock()

        for capture in evicted {
            capture.stop()
        }

        let created = try LiveCapture(
            filter: filter,
            maxBuffer: LiveCapture.sessionBufferLimit,
            overflowKeepsNewest: true,
        )
        var displaced: LiveCapture?
        lock.lock()
        displaced = records[id]?.capture
        records[id] = Record(capture: created, lastAccess: now, expiresAt: expiresAt)
        lock.unlock()
        displaced?.stop()
        return created
    }

    func scheduleExpiry(id: String, capture: LiveCapture, ttl: TimeInterval) {
        let expiresAt = Date().addingTimeInterval(ttl)
        lock.lock()
        if let existing = records[id], existing.capture === capture {
            records[id]?.lastAccess = Date()
            records[id]?.expiresAt = expiresAt
        }
        lock.unlock()

        cleanupQueue.asyncAfter(deadline: .now() + ttl + 0.2) { [weak self] in
            self?.evictIfExpired(id: id, capture: capture)
        }
    }

    private func evictIfExpired(id: String, capture: LiveCapture) {
        var expired: LiveCapture?
        let now = Date()
        lock.lock()
        if let record = records[id], record.capture === capture, record.expiresAt <= now {
            records.removeValue(forKey: id)
            expired = record.capture
        }
        lock.unlock()
        expired?.stop()
    }
}
