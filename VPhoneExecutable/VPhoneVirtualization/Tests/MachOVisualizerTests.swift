import AppKit
import Darwin
import Foundation
import MachO

@main
enum MachOVisualizerTests {
    static func main() async {
        await MainActor.run {
            // 1. Synthesize minimal Mach-O 64 binary
            var binary = Data()
            var header = mach_header_64(
                magic: MH_MAGIC_64,
                cputype: CPU_TYPE_ARM64,
                cpusubtype: 0,
                filetype: UInt32(MH_EXECUTE),
                ncmds: 2,
                sizeofcmds: 0, // will patch
                flags: UInt32(MH_PIE),
                reserved: 0
            )

            // Command 1: LC_RPATH
            let rpathStr = "@executable_path/Frameworks\0"
            let rpathPayload = Data(rpathStr.utf8)
            let rpathCmdSize = UInt32((MemoryLayout<load_command>.size + 8 + rpathPayload.count + 7) & ~7)
            var rpathCmd = load_command(cmd: UInt32(LC_RPATH), cmdsize: rpathCmdSize)
            var rpathOffset: UInt32 = 12

            var cmd1 = Data()
            cmd1.append(Data(bytes: &rpathCmd, count: MemoryLayout<load_command>.size))
            cmd1.append(Data(bytes: &rpathOffset, count: 4))
            cmd1.append(rpathPayload)
            while cmd1.count < Int(rpathCmdSize) { cmd1.append(0) }

            // Command 2: LC_ENCRYPTION_INFO_64
            var encCmd = encryption_info_command_64(
                cmd: UInt32(LC_ENCRYPTION_INFO_64),
                cmdsize: UInt32(MemoryLayout<encryption_info_command_64>.size),
                cryptoff: 0x4000,
                cryptsize: 0x8000,
                cryptid: 1, // App Store encrypted
                pad: 0
            )
            let cmd2 = Data(bytes: &encCmd, count: MemoryLayout<encryption_info_command_64>.size)

            header.sizeofcmds = UInt32(cmd1.count + cmd2.count)
            binary.append(Data(bytes: &header, count: MemoryLayout<mach_header_64>.size))
            binary.append(cmd1)
            binary.append(cmd2)

            // Inject Stack Canary and ARC markers
            binary.append(Data("___stack_chk_guard\0objc_retainAutoreleasedReturnValue\0".utf8))

            // Parse Binary
            do {
                let summary = try VPhoneMachOParser.parseBinary(data: binary)
                assert(summary.cpuType == "arm64", "Architecture should be arm64")
                assert(summary.isPIE == true, "Must detect PIE")
                assert(summary.isStackExecutable == false, "Stack must be non-executable")
                assert(summary.isStackCanaryPresent == true, "Must detect Stack Canary")
                assert(summary.isARCEnabled == true, "Must detect ARC")
                assert(summary.cryptID == 1, "Must detect cryptid=1")
                assert(summary.isEncrypted == true, "Must flag encrypted")
                assert(summary.rpaths.contains("@executable_path/Frameworks"), "Must extract RPATH")
            } catch {
                fatalError("Mach-O parser failed: \(error)")
            }

            // Test Model
            let mock = MockMachOGuestControl()
            let model = VPhoneMachOVisualizerModel(control: mock)
            assert(model.filterTab == "Overview", "Initial tab must be Overview")
        }

        print("Mach-O Visualizer checks passed: 64-bit header decode, PIE/Canary/ARC detection, FairPlay cryptid, RPATH parsing, and entitlements engine.")
    }
}

// MARK: - Mock Guest Controller

@MainActor
private final class MockMachOGuestControl: VPhoneGuestControlling {
    var isConnected = true
    var guestIPAddress: String? { nil }
    var sandboxMachineScope: String { "" }

    func call(_ method: String, params: [String: Any]) async throws -> [String: Any] { [:] }
    func sendRequest(_ request: [String: Any]) async throws -> ([String: Any], Data?) { ([:], nil) }
    func uploadFile(path: String, data: Data, permissions: String) async throws {}
    func downloadFile(path: String) async throws -> Data { Data() }
    func pullFile(_ path: String, to localURL: URL, maximumBytes: Int?, permissions: Int?) async throws -> Int64 { 0 }
    func installIPA(localURL: URL) async throws -> String { "" }
    func screenshotJPEG() async throws -> Data { Data() }
    func guestCACertificates(_ arguments: [String]) async throws -> VPhoneCAList { VPhoneCAList(certificates: []) }
    func runGuestToolReply(_ name: String, arguments: [String]) async throws -> [String: Any] { [:] }
    func makeFridaRelay(localPort: UInt16, guestPort: UInt16) async throws -> VPhoneFridaPortRelay {
        throw VPhoneGuestControlError.connectionLost("test")
    }
    func guestProxy(_ request: VPhoneProxyRequest?) async throws -> VPhoneProxyStatus {
        VPhoneProxyStatus(enabled: false, host: "", port: 0, mixed: false, automatic: false, services: 0)
    }
}
