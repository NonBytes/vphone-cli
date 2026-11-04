import Darwin
import Foundation

// Test-only guest traffic: bind an exclusive random UDP source port on lo0,
// send a known canary to the loopback discard port, then exit.
let port = UInt16(CommandLine.arguments[1])!
let fd = socket(AF_INET, SOCK_DGRAM, 0)
guard fd >= 0 else { exit(1) }
defer { close(fd) }
var local = sockaddr_in()
local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); local.sin_family = sa_family_t(AF_INET)
local.sin_port = port.bigEndian; local.sin_addr.s_addr = inet_addr("127.0.0.1")
let bound = withUnsafePointer(to: &local) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
guard bound == 0 else { exit(2) }
var destination = local; destination.sin_port = UInt16(9).bigEndian
let payload = Data("vphone-network-fixture-canary".utf8)
for _ in 0..<3 {
    let sent = payload.withUnsafeBytes { bytes in
        withUnsafePointer(to: &destination) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    }
    guard sent == payload.count else { exit(3) }
    usleep(20000)
}
print("fixture traffic sent")
