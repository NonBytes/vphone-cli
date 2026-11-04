import Darwin
import Foundation

#if !os(iOS)
#error("Guest network tools must run inside iOS")
#endif

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let verb = args.first, args.count <= 2 else { throw VPhoneNetworkError("Invalid guest network operation.") }
    if verb == "diagnose", args.count == 2 {
        guard args[1].utf8.count <= 4096 else { throw VPhoneNetworkError("Diagnostic request exceeds its limit.") }
        let target = try JSONDecoder().decode(VPhoneNetworkTarget.self, from: Data(args[1].utf8))
        let result = try VPhoneNetworkProbe.run(target, origin: "Guest")
        FileHandle.standardOutput.write(try JSONEncoder().encode(result))
    } else {
        let store = try VPhoneGuestCapture()
        let state: VPhoneCaptureStatus
        switch verb {
        case "status" where args.count == 1: state = try store.status()
        case "start" where args.count == 2:
            guard args[1].utf8.count <= 4096 else { throw VPhoneNetworkError("Capture request exceeds its limit.") }
            state = try store.start(JSONDecoder().decode(VPhoneCaptureRequest.self, from: Data(args[1].utf8)))
        case "stop" where args.count == 2: state = try store.stop(args[1])
        case "discard" where args.count == 2: state = try store.discard(args[1])
        case "worker" where args.count == 2: try store.worker(args[1]); exit(0)
        default: throw VPhoneNetworkError("Invalid guest network operation.")
        }
        try state.validate()
        FileHandle.standardOutput.write(try JSONEncoder().encode(state))
    }
    FileHandle.standardOutput.write(Data([10]))
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
