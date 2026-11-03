import Foundation

@main struct CACertificateTests {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let der = try Data(contentsOf: root.appendingPathComponent("ca.der"))
        let pem = try Data(contentsOf: root.appendingPathComponent("ca.pem"))
        let a = try VPhoneCACertificate.parse(der).2
        let b = try VPhoneCACertificate.parse(pem).2
        precondition(a.sha256 == b.sha256 && a.sha256.count == 64)
        let invalid = [Data(), Data("invalid".utf8), der + Data([0]), pem + pem,
                       pem + Data("-----BEGIN PRIVATE KEY-----".utf8),
                       try Data(contentsOf: root.appendingPathComponent("leaf.pem")),
                       Data(repeating: 0, count: VPhoneCACertificate.maximumSize + 1)]
        for input in invalid {
            do { _ = try VPhoneCACertificate.parse(input); fatalError("Accepted invalid certificate") }
            catch { }
        }
        print("CA certificate tests passed (DER/PEM identity and 7 invalid inputs)")
    }
}
