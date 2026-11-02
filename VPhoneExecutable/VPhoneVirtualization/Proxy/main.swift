import Darwin
import Foundation

// A narrowly scoped guest tool. Reuses script.eval/proc.run so existing guests
// can configure their network without updating vphoned or installing a shell.
typealias Preferences = CFTypeRef
typealias Create = @convention(c) (CFAllocator?, CFString, CFString?) -> Unmanaged<CFTypeRef>?
typealias Get = @convention(c) (Preferences, CFString) -> Unmanaged<CFPropertyList>?
typealias Set = @convention(c) (Preferences, CFString, CFPropertyList) -> UInt8
typealias Operation = @convention(c) (Preferences) -> UInt8
typealias Lock = @convention(c) (Preferences, UInt8) -> UInt8

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args == ["read"] || (args.count == 2 && args[0] == "apply") else {
        throw VPhoneProxyError("Usage: vphone-guest-proxy read | apply <JSON>")
    }
    let request = args[0] == "apply"
        ? try JSONDecoder().decode(VPhoneProxyRequest.self, from: Data(args[1].utf8)).validated() : nil
    guard let library = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_NOW) else {
        throw VPhoneProxyError("SystemConfiguration is unavailable in this guest.")
    }
    defer { dlclose(library) }
    func symbol<T>(_ name: String, _: T.Type) throws -> T {
        guard let address = dlsym(library, name) else { throw VPhoneProxyError("SystemConfiguration symbol unavailable: \(name)") }
        return unsafeBitCast(address, to: T.self)
    }
    let create = try symbol("SCPreferencesCreate", Create.self)
    let get = try symbol("SCPreferencesGetValue", Get.self)
    let set = try symbol("SCPreferencesSetValue", Set.self)
    let commit = try symbol("SCPreferencesCommitChanges", Operation.self)
    let apply = try symbol("SCPreferencesApplyChanges", Operation.self)
    let lock = try symbol("SCPreferencesLock", Lock.self)
    let unlock = try symbol("SCPreferencesUnlock", Operation.self)
    guard let preferences = create(nil, "VPhone guest proxy" as CFString, nil)?.takeRetainedValue() else {
        throw VPhoneProxyError("Cannot open guest network preferences.")
    }
    guard lock(preferences, 0) != 0 else { throw VPhoneProxyError("Network preferences are busy. Try again.") }
    defer { _ = unlock(preferences) }
    guard var services = get(preferences, "NetworkServices" as CFString)?.takeUnretainedValue() as? [String: [String: Any]] else {
        throw VPhoneProxyError("Guest network services are unavailable.")
    }
    let ids = services.keys.filter { (services[$0]?["Interface"] as? [String: Any])?["DeviceName"] as? String == "en0" }.sorted()
    guard !ids.isEmpty else { throw VPhoneProxyError("No guest network interface was found.") }
    if let request {
        for id in ids {
            let previous = services[id]?["Proxies"] as? [String: Any] ?? [:]
            services[id]?["Proxies"] = try request.updating(previous)
        }
        guard set(preferences, "NetworkServices" as CFString, services as CFDictionary) != 0,
              commit(preferences) != 0 else { throw VPhoneProxyError("Failed to save guest proxy settings.") }
        guard apply(preferences) != 0 else { throw VPhoneProxyError("Proxy settings were saved but could not be activated. Reload and retry.") }
    }
    let current = get(preferences, "NetworkServices" as CFString)?.takeUnretainedValue() as? [String: [String: Any]] ?? services
    let status = try VPhoneProxyStatus(proxies: ids.map { current[$0]?["Proxies"] as? [String: Any] ?? [:] })
    print(String(decoding: try JSONEncoder().encode(status), as: UTF8.self))
}

do { try run() } catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
