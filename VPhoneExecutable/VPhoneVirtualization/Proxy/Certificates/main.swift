import Darwin
import Foundation
import Security

#if !os(iOS)
#error("This tool modifies only an iOS guest trust store; never run it on the host.")
#endif

typealias StoreForDomain = @convention(c) (UInt32) -> OpaquePointer?
typealias CopyAll = @convention(c) (OpaquePointer, UnsafeMutablePointer<Unmanaged<CFArray>?>) -> Int32
typealias SetTrust = @convention(c) (OpaquePointer, SecCertificate, CFTypeRef?) -> Int32
typealias Remove = @convention(c) (OpaquePointer, SecCertificate) -> Int32

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args == ["list"] || (args.count == 2 && ["import", "remove"].contains(args[0])) else {
        throw VPhoneProxyError("Usage: vphone-guest-ca list | import <base64> | remove <sha256>")
    }
    guard let library = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW) else { throw VPhoneProxyError("Security framework unavailable.") }
    defer { dlclose(library) }
    func symbol<T>(_ name: String, _: T.Type) throws -> T {
        guard let pointer = dlsym(library, name) else { throw VPhoneProxyError("Trust store API unavailable: \(name)") }
        return unsafeBitCast(pointer, to: T.self)
    }
    let forDomain = try symbol("SecTrustStoreForDomain", StoreForDomain.self)
    let copyAll = try symbol("SecTrustStoreCopyAll", CopyAll.self)
    let setTrust = try symbol("SecTrustStoreSetTrustSettings", SetTrust.self)
    let remove = try symbol("SecTrustStoreRemoveCertificate", Remove.self)
    // User-installed roots only. No command accepts another domain or RemoveAll.
    guard let store = forDomain(2) else { throw VPhoneProxyError("Guest user trust store is unavailable.") }
    func entries() throws -> [(SecCertificate, VPhoneCACertificate)] {
        var result: Unmanaged<CFArray>?
        let status = copyAll(store, &result)
        guard status == errSecSuccess else { throw VPhoneProxyError("Cannot read guest CA certificates (\(status)).") }
        guard let array = result?.takeRetainedValue() else { return [] }
        var certificates: [(SecCertificate, VPhoneCACertificate)] = []
        for row in (array as NSArray) {
            guard let pair = row as? [Any], pair.count == 2, let der = pair[0] as? Data,
                  let (_, cert, metadata) = try? VPhoneCACertificate.parse(der, requireValidDates: false) else { continue }
            var info = metadata
            if let settings = pair[1] as? [[String: Any]] {
                // Only an unconditional root grant can be labelled fully trusted.
                info.trusted = settings.isEmpty || (settings.count == 1 &&
                    settings[0].count == 1 && (settings[0]["kSecTrustSettingsResult"] as? Int) == 1)
            }
            certificates.append((cert, info))
        }
        return certificates
    }
    if args[0] == "import" {
        guard args[1].utf8.count <= VPhoneCACertificate.maximumSize * 2,
              let raw = Data(base64Encoded: args[1]) else { throw VPhoneProxyError("Invalid certificate data.") }
        let (_, cert, info) = try VPhoneCACertificate.parse(raw)
        let status = setTrust(store, cert, ["kSecTrustSettingsResult": 1] as CFDictionary)
        guard status == errSecSuccess else { throw VPhoneProxyError("Cannot trust CA in guest (\(status)).") }
        guard try entries().contains(where: { $0.1.sha256 == info.sha256 && $0.1.trusted }) else {
            throw VPhoneProxyError("CA was installed but full trust could not be confirmed.")
        }
    } else if args[0] == "remove" {
        let hash = args[1].lowercased()
        guard hash.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw VPhoneProxyError("Invalid certificate fingerprint.")
        }
        guard let entry = try entries().first(where: { $0.1.sha256 == hash }) else { throw VPhoneProxyError("The CA is no longer installed. Reload the list.") }
        let status = remove(store, entry.0)
        guard status == errSecSuccess else { throw VPhoneProxyError("Cannot remove CA from guest (\(status)).") }
        guard try !entries().contains(where: { $0.1.sha256 == hash }) else { throw VPhoneProxyError("CA removal could not be confirmed.") }
    }
    let list = VPhoneCAList(certificates: try entries().map(\.1).sorted { $0.name < $1.name })
    print(String(decoding: try JSONEncoder().encode(list), as: UTF8.self))
}

do { try run() } catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
