import AppKit
import Darwin
import Foundation

@main
enum NetworkFlowInspectorTests {
    @MainActor
    static func main() async {
        let mock = MockNetworkFlowGuestControl()
        let model = VPhoneNetworkFlowModel(control: mock)

            // 1. Initial State
            precondition(model.flows.isEmpty, "Initial flows must be empty")
            precondition(model.selectedFlow == nil, "No flow initially selected")
            precondition(model.isRecording, "Recording should default to true")

            // 2. Ingest Request Event
            let reqID = UUID().uuidString
            model.ingest(event: [
                "type": "network_flow_request",
                "id": reqID,
                "method": "POST",
                "url": "https://api.example.com/v1/auth/login",
                "headers": ["Content-Type": "application/json", "User-Agent": "VPhone/1.0"],
                "body": "{\"username\":\"admin\",\"password\":\"secret123\"}",
                "body_bytes": 38
            ])

            precondition(model.flows.count == 1, "Must have 1 flow after request event")
            guard let flow1 = model.flows.first else { preconditionFailure("Flow missing") }
            precondition(flow1.method == "POST", "Method must be POST")
            precondition(flow1.host == "api.example.com", "Host must be parsed: \(flow1.host)")
            precondition(flow1.path == "/v1/auth/login", "Path must be /v1/auth/login")
            precondition(flow1.isPending, "Flow should be pending before response")

            // 3. Ingest Response Event
            model.ingest(event: [
                "type": "network_flow_response",
                "id": reqID,
                "status": 200,
                "status_text": "OK",
                "headers": ["Content-Type": "application/json; charset=utf-8"],
                "body": "{\"token\":\"jwt-test-token-12345\"}",
                "body_bytes": 32,
                "duration_ms": 142.5
            ])

            guard let flowCompleted = model.flows.first else { preconditionFailure("Flow missing after response") }
            precondition(!flowCompleted.isPending, "Flow must not be pending after response")
            precondition(flowCompleted.responseStatus == 200, "Status must be 200")
            precondition(flowCompleted.durationMs == 142.5, "Duration must be 142.5 ms")
            precondition(flowCompleted.statusDisplay == "200", "Status display must be 200")

            // 4. Ingest Second Request with 404
            let reqID2 = UUID().uuidString
            model.ingest(event: [
                "type": "network_flow_request",
                "id": reqID2,
                "method": "GET",
                "url": "https://api.example.com/v1/user/unknown",
                "headers": [:]
            ])
            model.ingest(event: [
                "type": "network_flow_response",
                "id": reqID2,
                "status": 404,
                "status_text": "Not Found",
                "headers": [:],
                "body": "{\"error\":\"Not Found\"}",
                "duration_ms": 68.0
            ])

            precondition(model.flows.count == 2, "Must have 2 flows")

            // 5. Test Filters
            model.selectedMethodFilter = "POST"
            precondition(model.filteredFlows.count == 1, "Filtered flows by POST must be 1")
            precondition(model.filteredFlows.first?.method == "POST")

            model.selectedMethodFilter = "GET"
            precondition(model.filteredFlows.count == 1, "Filtered flows by GET must be 1")
            precondition(model.filteredFlows.first?.method == "GET")

            model.selectedMethodFilter = "ALL"
            model.selectedStatusFilter = "2xx"
            precondition(model.filteredFlows.count == 1, "Filtered flows by 2xx must be 1")

            model.selectedStatusFilter = "4xx"
            precondition(model.filteredFlows.count == 1, "Filtered flows by 4xx must be 1")

            model.selectedStatusFilter = "ALL"
            model.searchQuery = "auth/login"
            precondition(model.filteredFlows.count == 1, "Search query must filter to 1")

            model.searchQuery = ""

            // 6. Test cURL Generation
            let curl = flowCompleted.curlCommand
            precondition(curl.contains("curl -X POST 'https://api.example.com/v1/auth/login'"), "cURL must contain method and URL: \(curl)")
            precondition(curl.contains("-H 'Content-Type: application/json'"), "cURL must contain header")
            precondition(curl.contains("--data-raw"), "cURL must contain post data")

            // 7. Test HAR Export
            let harData = model.exportHAR()
            precondition(!harData.isEmpty, "HAR data must not be empty")
            let harJSON = (try? JSONSerialization.jsonObject(with: harData)) as? [String: Any]
            guard let log = harJSON?["log"] as? [String: Any],
                  let entries = log["entries"] as? [[String: Any]]
            else {
                preconditionFailure("Invalid HAR structure")
            }
            precondition(entries.count == 2, "HAR must have 2 entries")

            // 8. Test JSON Export
            let jsonData = model.exportJSON()
            let parsedList = (try? JSONSerialization.jsonObject(with: jsonData)) as? [[String: Any]]
            precondition(parsedList?.count == 2, "JSON export must contain 2 items")

            // 9. Test Frida Hook Script Generation
            let script = model.fridaHookScript
            precondition(script.contains("VPhone In-App Network & API Flow Inspector"), "Script must contain header")
            precondition(script.contains("NSURLSession"), "Script must reference NSURLSession")
            precondition(script.contains("dataTaskWithRequest:completionHandler:"), "Script must hook dataTaskWithRequest")
            precondition(script.contains("dataTaskWithURL:completionHandler:"), "Script must hook dataTaskWithURL")
            precondition(script.contains("uploadTaskWithRequest:fromData:completionHandler:"), "Script must hook uploadTask")
            precondition(script.contains("vphone_control"), "Script must support live control channel")
            precondition(script.contains("applyRewriteRule"), "Script must include response rewriter")
            precondition(script.contains("makeHTTPResponse"), "Script must construct NSHTTPURLResponse")

            // 9b. Test Response Rewrite Rule Engine (JSON dot-path, removal, regex, status, headers)
            let rewriteRule = VPhoneNetworkMockRule(
                name: "Premium & Admin Rewrite",
                urlPattern: "api/v1/profile",
                methodFilter: "GET",
                ruleType: .rewriteResponse,
                jsonPatches: [
                    VPhoneJSONPatchOperation(keyPath: "user.isPremium", valueLiteral: "true"),
                    VPhoneJSONPatchOperation(keyPath: "user.role", valueLiteral: "\"admin\""),
                    VPhoneJSONPatchOperation(keyPath: "user.balance", valueLiteral: "999999"),
                    VPhoneJSONPatchOperation(keyPath: "error", valueLiteral: "", removeKey: true)
                ],
                bodyFindPattern: "free_tier",
                bodyReplaceWith: "enterprise_tier",
                bodyUseRegex: false,
                overrideStatusCode: 200,
                responseHeadersToAdd: ["X-VPhone-Rewritten": "1"],
                responseHeadersToRemove: ["X-RateLimit-Remaining"]
            )
            let rewritten = rewriteRule.applyResponseRewrite(
                statusCode: 403,
                headers: ["Content-Type": "application/json", "X-RateLimit-Remaining": "0"],
                body: "{\"error\":\"forbidden\",\"plan\":\"free_tier\",\"user\":{\"isPremium\":false,\"role\":\"guest\",\"balance\":10}}"
            )
            precondition(rewritten.modified, "Rewrite rule must mark response as modified")
            precondition(rewritten.statusCode == 200, "Status must be overridden to 200")
            precondition(rewritten.headers["X-VPhone-Rewritten"] == "1", "Injected response header missing")
            precondition(rewritten.headers["X-RateLimit-Remaining"] == nil, "Removed header must be stripped")
            precondition(rewritten.body.contains("\"isPremium\":true"), "Nested boolean JSON patch failed: \(rewritten.body)")
            precondition(rewritten.body.contains("\"role\":\"admin\""), "Nested string JSON patch failed: \(rewritten.body)")
            precondition(rewritten.body.contains("\"balance\":999999"), "Nested numeric JSON patch failed: \(rewritten.body)")
            precondition(!rewritten.body.contains("\"error\""), "Key removal patch failed: \(rewritten.body)")
            precondition(rewritten.body.contains("enterprise_tier"), "Body find/replace failed: \(rewritten.body)")

            // 9c. Test Live Response Breakpoint Ingestion & Resolution
            let bpFlowID = UUID()
            model.ingest(event: [
                "type": "network_flow_request",
                "id": bpFlowID.uuidString,
                "method": "POST",
                "url": "https://api.example.com/v1/checkout"
            ])
            model.ingest(event: [
                "type": "network_breakpoint_hit",
                "phase": "response",
                "id": bpFlowID.uuidString,
                "method": "POST",
                "url": "https://api.example.com/v1/checkout",
                "status": 402,
                "headers": ["Content-Type": "application/json"],
                "body": "{\"paid\":false}",
                "rule_name": "Checkout Breakpoint",
                "duration_ms": 55.0
            ])
            precondition(model.pendingResponseBreakpoints.count == 1, "Must queue 1 paused breakpoint")
            precondition(model.activeBreakpoint?.id == bpFlowID, "Active breakpoint must match flow ID")
            model.resolveResponseBreakpoint(
                id: bpFlowID,
                drop: false,
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: "{\"paid\":true}"
            )
            precondition(model.pendingResponseBreakpoints.isEmpty, "Breakpoint queue must be empty after resolution")
            if let resolvedFlow = model.flows.first(where: { $0.id == bpFlowID }) {
                precondition(resolvedFlow.responseStatus == 200, "Resolved flow status must be 200")
                precondition(resolvedFlow.responseBody == "{\"paid\":true}", "Resolved flow body must match edited payload")
                precondition(resolvedFlow.isMocked, "Edited breakpoint response must be flagged isMocked")
                precondition(!resolvedFlow.isIntercepted, "Resolved flow must clear isIntercepted")
            } else {
                preconditionFailure("Resolved breakpoint flow missing")
            }

            // 9d. Test 1-Click Create Rule From Flow
            let generatedRule = model.createRuleFromFlow(flowCompleted, ruleType: .rewriteResponse)
            precondition(generatedRule.urlPattern == "api.example.com/v1/auth/login", "Generated pattern mismatch: \(generatedRule.urlPattern)")
            precondition(generatedRule.methodFilter == "POST", "Generated method filter mismatch")
            precondition(!generatedRule.jsonPatches.isEmpty, "Generated rewrite rule should extract starter JSON patches")
            model.removeMockRule(id: generatedRule.id)

            // 10. Test Request Tampering & Replay Engine
            var replayCaughtError = false
            do {
                _ = try await model.replayRequest(
                    method: "POST",
                    urlString: "http://127.0.0.1:59999/test-unreachable",
                    headers: ["X-Test": "1", "Content-Type": "application/json"],
                    body: "{\"tampered\":true}"
                )
            } catch {
                replayCaughtError = true
            }
            precondition(replayCaughtError, "Expected unreachable replay request to fail gracefully")
            precondition(model.flows.count == 4, "Failed replayed flow must be prepended to stream (total 4)")
            guard let replayedFlow = model.flows.first else { preconditionFailure("Missing replayed flow") }
            precondition(replayedFlow.isReplayed, "Flow must be marked isReplayed: true")
            precondition(replayedFlow.method == "POST", "Replayed method must be POST")
            precondition(replayedFlow.requestHeaders["X-Test"] == "1", "Replayed headers must be preserved")
            precondition(replayedFlow.requestBody.contains("tampered"), "Replayed body must be preserved")

            // 11. Clear Flows
            model.clearFlows()
            precondition(model.flows.isEmpty, "Flows must be empty after clear")

        print("Network Flow Inspector checks passed: transaction ingestion, request/response matching, status/method filters, HAR export, cURL synthesis, Frida hook engine, and Request Tampering & Replay.")
    }
}

// MARK: - Mock Guest Controller

@MainActor
private final class MockNetworkFlowGuestControl: VPhoneGuestControlling {
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
