import Foundation

struct VPhoneFridaStatus: Codable {
    var installed: Bool
    var running: Bool
    var version: String
    var pid: Int32?
    var token: String
    var log: String
}
