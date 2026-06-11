non_tdd_reason: async Network.framework cancellation / structured-concurrency integration glue — no isolatable failing unit; FeishuSpeechTests not wired into project.pbxproj.
build-green: swiftc -typecheck exit 0, zero new errors or warnings (2 pre-existing warnings unchanged).
regression-green: swiftlint clean (per implementer); swiftc typecheck passed with same pre-existing warnings only.

Changes made:

FeishuSpeech/Services/FeishuAPIService.swift:
1. Issue #4 — CancelBox type (new ~lines 27-58): private final class CancelBox @unchecked Sendable, NSLock-protected store(connection:abort:) and cancel(). Handles already-cancelled-at-entry race in store().
2. Issue #4 — withTaskCancellationHandler wrap (send() restructured ~lines 77-175): cancelBox created, withCheckedThrowingContinuation wrapped in withTaskCancellationHandler { ... } onCancel: { cancelBox.cancel() }. cancelBox.store() registered after connection.start(queue:).
3. Issue #2 — .waiting fast-fail (new case ~line 152): case .waiting(let error): finish(.failure(error)) added to stateUpdateHandler before .failed case. Routes through existing finish() guard.
4. Issue #3 — URLSession DNS fallback in sendDirectRequest (~lines 472-479): do { return try await sendViaURLSession(...) } catch { ... } block after IP loop, before final error throw.
5. Issue #3 — sendViaURLSession method (~lines 488-502): private func sendViaURLSession(path:headers:body:) async throws -> DirectHTTPResponse using URLSession.shared.data(for:), maps HTTPURLResponse to DirectHTTPResponse.

FeishuSpeech/ViewModels/MainViewModel.swift: READ-ONLY. Verified withTimeout(30s)+group.cancelAll() wiring exists (lines 186-208, 292-310). No edits made.

docs/decisions/D-2-01.md: CREATED with full decision record (problem, decisions per issue, alternatives considered, consequences).
