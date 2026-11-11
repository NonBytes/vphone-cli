import CryptoKit
#if canImport(VPhonePentestKit)
import VPhonePentestKit
#endif
import Darwin
import Foundation
import Security

struct VPhoneCACertificate: Codable, Identifiable {
    var name: String
    var sha256: String
    var expires: Date
    var trusted: Bool = false
    var id: String { sha256 }

    static let maximumSize = 64 * 1024

    static func parse(_ input: Data, requireValidDates: Bool = true) throws -> (Data, SecCertificate, Self) {
        guard !input.isEmpty, input.count <= maximumSize else { throw VPhoneProxyError("Select one CA certificate smaller than 64 KB.") }
        var der = input
        if let text = String(data: input, encoding: .utf8), text.contains("-----BEGIN") {
            let begin = "-----BEGIN CERTIFICATE-----", end = "-----END CERTIFICATE-----"
            let parts = text.components(separatedBy: begin)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VPhoneProxyError("Select one PEM certificate, without a private key or certificate chain.")
            }
            let body = parts[1].components(separatedBy: end)
            guard body.count == 2, body[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let data = Data(base64Encoded: body[0].components(separatedBy: .whitespacesAndNewlines).joined()) else {
                throw VPhoneProxyError("Invalid PEM certificate.")
            }
            der = data
        }
        // Require exactly one complete DER sequence, without trailing content.
        let bytes = [UInt8](der)
        guard bytes.count >= 2, bytes[0] == 0x30 else { throw VPhoneProxyError("Invalid certificate file.") }
        var offset = 2, length = Int(bytes[1])
        if length >= 128 {
            let count = length & 0x7f
            guard (1...4).contains(count), bytes.count >= 2 + count else { throw VPhoneProxyError("Invalid DER length.") }
            length = 0
            for value in bytes[2..<(2 + count)] { length = length * 256 + Int(value) }
            offset += count
        }
        guard offset + length == bytes.count, let cert = SecCertificateCreateWithData(nil, der as CFData) else {
            throw VPhoneProxyError("Invalid certificate file.")
        }
        guard let library = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW) else {
            throw VPhoneProxyError("Security framework unavailable.")
        }
        defer { dlclose(library) }
        typealias IsRoot = @convention(c) (SecCertificate) -> Bool
        typealias CertificateDate = @convention(c) (SecCertificate) -> CFAbsoluteTime
        guard let rootSymbol = dlsym(library, "SecCertificateIsSelfSignedCA"),
              let beforeSymbol = dlsym(library, "SecCertificateNotValidBefore"),
              let afterSymbol = dlsym(library, "SecCertificateNotValidAfter") else {
            throw VPhoneProxyError("Certificate inspection is unavailable on this system.")
        }
        guard unsafeBitCast(rootSymbol, to: IsRoot.self)(cert) else {
            throw VPhoneProxyError("Select a self-signed root CA certificate, not a server certificate.")
        }
        let before = unsafeBitCast(beforeSymbol, to: CertificateDate.self)(cert)
        let after = unsafeBitCast(afterSymbol, to: CertificateDate.self)(cert)
        let now = CFAbsoluteTimeGetCurrent()
        guard after > 0, after > before else { throw VPhoneProxyError("Invalid certificate validity dates.") }
        if requireValidDates, now < before || now > after { throw VPhoneProxyError("The CA certificate has expired or is not yet valid.") }
        let info = Self(name: SecCertificateCopySubjectSummary(cert) as String? ?? "CA Certificate",
                        sha256: SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined(),
                        expires: Date(timeIntervalSinceReferenceDate: after))
        return (der, cert, info)
    }
}

struct VPhoneCAList: Codable { var certificates: [VPhoneCACertificate] }
