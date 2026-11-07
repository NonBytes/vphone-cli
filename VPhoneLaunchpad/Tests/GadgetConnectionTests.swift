import Foundation
import Security
@main struct GadgetConnectionTests {
    static func rejects(_ body:() throws -> Void) { do { try body(); fatalError("Invalid endpoint accepted") } catch {} }
    static func main() throws {
        for address in ["127.0.0.1:27043","host.local:27043","[::1]:27043"] {
            let normalized = try VPhoneGadgetConnection.endpoint(" "+address+"\n")
            precondition(normalized == address)
        }
        for address in ["", "host", "host:0", "host:65536", "http://host:1234", "user:secret@host:1234", "host:1234/path", "host:1234?token=secret", "host:1234#secret", "host name:1234", "host:1234\nother"] {
            rejects { _ = try VPhoneGadgetConnection.endpoint(address) }
        }
        let a=VPhoneGadgetConnection(directory:URL(fileURLWithPath:"/private/tmp/gadget-vm-a"))
        let b=VPhoneGadgetConnection(directory:URL(fileURLWithPath:"/private/tmp/gadget-vm-b"))
        precondition(a.machine != b.machine)
        let qa=a.query("127.0.0.1:27043"), qb=b.query("127.0.0.1:27043"), qc=a.query("127.0.0.1:27044")
        let account=kSecAttrAccount as String
        precondition(qa[account] as? String != qb[account] as? String && qa[account] as? String != qc[account] as? String)
        let sensitive="quoted\"token\\value/secret"
        let raw="error "+sensitive
        let json=String(data:try JSONSerialization.data(withJSONObject:["payload":sensitive],options:[.withoutEscapingSlashes]),encoding:.utf8)!
        precondition(VPhoneGadgetConnection.redact(raw,token:sensitive) == "error [REDACTED TOKEN]")
        precondition(VPhoneGadgetConnection.redact(json,token:sensitive).contains("[REDACTED TOKEN]"))
        let escapedJSON=String(data:try JSONSerialization.data(withJSONObject:["payload":sensitive]),encoding:.utf8)!
        precondition(VPhoneGadgetConnection.redact(escapedJSON,token:sensitive).contains("[REDACTED TOKEN]"))
        if CommandLine.arguments.contains("--keychain") {
            let unique=VPhoneGadgetConnection(directory:URL(fileURLWithPath:"/private/tmp/gadget-test-"+UUID().uuidString))
            let endpoint="127.0.0.1:27043", token=UUID().uuidString
            defer { try? unique.forget(endpoint:endpoint) }
            try unique.save(endpoint:endpoint,token:token)
            let loaded=try unique.load(endpoint:endpoint); precondition(loaded == token && unique.savedEndpoint == endpoint)
            rejects { _ = try unique.load(endpoint:"127.0.0.1:27044") }
            try unique.forget(endpoint:endpoint)
            precondition(unique.savedEndpoint == nil)
            rejects { _ = try unique.load(endpoint:endpoint) }
        }
        print("PASS: Gadget endpoint validation, per-VM/per-endpoint credential scope and optional disposable Keychain round trip")
    }
}
