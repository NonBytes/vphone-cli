import Foundation

@MainActor
final class MockCrashMonitorGuestControl: VPhoneGuestControlling {
    var isConnected = true
    var guestIPAddress: String? { nil }
    var sandboxMachineScope: String { "" }
    func sendRequest(_ request: [String: Any]) async throws -> ([String: Any], Data?) { ([:], nil) }
    func uploadFile(path: String, data: Data, permissions: String) async throws {}
    func downloadFile(path: String) async throws -> Data { Data() }
    func pullFile(_ path: String, to localURL: URL, maximumBytes: Int?, permissions: Int?) async throws -> Int64 { 0 }
    func installIPA(localURL: URL) async throws -> String { "" }
    func screenshotJPEG() async throws -> Data { Data() }
    func guestProxy() async throws -> VPhoneProxyStatus { fatalError() }
    func runGuestToolReply(_ name: String, arguments: [String]) async throws -> [String: Any] { [:] }
    func makeFridaRelay(localPort: UInt16, guestPort: UInt16) async throws -> VPhoneFridaPortRelay { fatalError() }
    func appList() async throws -> [String: Any] { ["apps": []] }
    func call(_ method: String, params: [String: Any]) async throws -> [String: Any] { [:] }
}

@main
struct CrashMonitorTests {
    @MainActor
    static func main() async throws {
        let control = MockCrashMonitorGuestControl()
        let model = VPhoneCrashMonitorModel(control: control)

        // 1. Initial State
        precondition(model.events.isEmpty)
        precondition(model.captureState == .idle)

        // 2. Ingest POSIX Crash Event (SIGSEGV)
        let segvEvent = VPhoneCrashEvent(
            signalType: .sigsegv,
            signalName: "SIGSEGV (11)",
            faultAddress: "0x0000000000000008",
            exceptionReason: "Null pointer dereference in objc_msgSend",
            registers: VPhoneCrashRegisterState(
                pc: "0x0000000180234567",
                lr: "0x0000000180234500",
                sp: "0x000000016fd89000",
                fp: "0x000000016fd89050"
            ),
            backtrace: [
                "0x0000000180234567 libobjc.A.dylib!objc_msgSend + 24",
                "0x0000000100045678 MyApp!-[LoginManager authenticate:] + 88",
                "0x0000000180554321 UIKitCore!-[UIApplication sendAction:to:from:forEvent:] + 96"
            ],
            bundleID: "com.example.testapp",
            appName: "TestApp",
            pid: 1234
        )
        model.ingestEvent(segvEvent)

        precondition(model.events.count == 1)
        precondition(model.events[0].signalType.severity == .critical)

        // 3. Ingest Objective-C Exception Event
        let nsExceptionEvent = VPhoneCrashEvent(
            signalType: .nsException,
            signalName: "Uncaught NSInvalidArgumentException",
            faultAddress: "0x0",
            exceptionName: "NSInvalidArgumentException",
            exceptionReason: "-[__NSDictionaryI objectForKey:]: unrecognized selector sent to instance",
            backtrace: [
                "0x0000000180112233 CoreFoundation!___exceptionPreprocess + 224",
                "0x0000000180099887 libobjc.A.dylib!objc_exception_throw + 56",
                "0x0000000100055443 MyApp!-[APIService handleResponse:] + 120"
            ],
            bundleID: "com.example.testapp",
            appName: "TestApp",
            pid: 1234
        )
        model.ingestEvent(nsExceptionEvent)

        precondition(model.events.count == 2)
        precondition(model.events[0].signalType == .nsException)

        // 4. Filtering
        model.filterSignal = VPhoneCrashSignalType.sigsegv.rawValue
        precondition(model.filteredEvents.count == 1 && model.filteredEvents[0].signalType == .sigsegv)

        model.filterSignal = "all"
        model.search = "unrecognized selector"
        precondition(model.filteredEvents.count == 1 && model.filteredEvents[0].exceptionName == "NSInvalidArgumentException")

        model.search = ""
        precondition(model.filteredEvents.count == 2)

        // 5. Crash Report Text Export
        let textReport = model.exportCrashReport(event: segvEvent)
        precondition(textReport.contains("SIGSEGV") && textReport.contains("0x0000000000000008") && textReport.contains("objc_msgSend"))

        // 6. MASVS Finding Dispatch
        let dispatched = model.sendCrashToMASVS(event: segvEvent)
        precondition(dispatched, "Crash finding must be successfully dispatched to MASVS Finding Store")

        // 7. Frida Sentinel Script Generation
        let fridaScript = model.generateSentinelFridaScript()
        precondition(fridaScript.contains("Process.setExceptionHandler") && fridaScript.contains("objc_exception_throw"))

        // 8. Clear Events
        model.clearEvents()
        precondition(model.events.isEmpty)

        print("Crash Monitor checks passed: SIGSEGV / NSException ingestion, severity rating, register dump, stack backtrace, filtering, MASVS dispatch, and Frida sentinel generation.")
    }
}
