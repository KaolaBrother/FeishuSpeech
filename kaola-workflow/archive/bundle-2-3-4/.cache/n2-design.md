Design spec for issues #2, #3, #4 (D-2-01). Read-only node — no files written.

Issue #2 (.waiting fast-fail):
- Add case .waiting(let error): finish(.failure(error)) to stateUpdateHandler in DirectFeishuHTTPClient.send(), before default.
- Route through existing finish() guard (NSLock+isFinished), which also calls connection.cancel().
- Propagate real NWError (not synthesized timeout) for diagnostic fidelity.

Issue #4 (withTaskCancellationHandler wrapping):
- Add private nonisolated final class CancelBox: @unchecked Sendable with NSLock protecting {connection, abort, cancelled}.
- CancelBox.store(connection:abort:) handles already-cancelled-at-entry race by checking cancelled flag.
- CancelBox.cancel() calls connection.forceCancel() + abort().
- Wrap withCheckedThrowingContinuation in withTaskCancellationHandler { ... } onCancel: { cancelBox.cancel() }.
- onCancel calls finish(.failure(CancellationError())) via cancelBox — never calls continuation.resume directly.
- cancelBox.store(...) placed after connection.start(queue:).

Issue #3 (URLSession DNS fallback):
- After for-loop over feishuDirectIPs exhausts, call sendViaURLSession(path:headers:body:) before throwing.
- sendViaURLSession uses URLSession.shared.data(for:) with https://open.feishu.cn<path>.
- No ATS exceptions or entitlement changes required (macOS 13+ target, HTTPS only).
- URLSession.shared handles Swift task cancellation natively — no extra wiring.
- Maps HTTPURLResponse → DirectHTTPResponse(statusCode:body:); forward caller headers only (not Host/Content-Length/Connection).

MainViewModel: NO changes needed. withTimeout(30s)+group.cancelAll() already issues cancellation; #4 makes the service honor it.

Decision record: docs/decisions/D-2-01.md to be authored by n3-implement.

Build order: CancelBox → .waiting case → withTaskCancellationHandler wrap + cancelBox.store → sendViaURLSession + fallback call → D-2-01.md.
