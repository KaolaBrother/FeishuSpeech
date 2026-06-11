Q1: withTaskCancellationHandler + NWConnection.cancel()
- onCancel fires immediately and concurrently with the suspended operation body (not at next suspension point).
- NWConnection.cancel() is thread-safe and callable from onCancel (which may run on any thread/executor).
- stateUpdateHandler reliably delivers .cancelled after cancel() is called.
- The existing finish() helper (NSLock + isFinished guard) already prevents double-resume; onCancel must call finish(.failure(CancellationError())) through the same guard, NOT call continuation.resume() directly.
- Pattern: wrap send() with withTaskCancellationHandler; store NWConnection in an NSLock-protected box accessible from onCancel.

Q2: Swift structured concurrency child cancellation + double-resume risk
- Task group cancellation is cooperative — child tasks must hit a suspension point or checkCancellation() to stop.
- A child suspended inside withCheckedThrowingContinuation wrapping NWConnection callbacks will NOT stop until the callback fires or its own timeout triggers.
- Double-resume race IS real: onCancel could call resume(.failure(CancellationError())) concurrently with normal NWConnection callback calling resume(.success(...)). Mitigation: route ALL resumes through finish() with the NSLock guard.

Q3: NWConnection .waiting semantics
- .waiting(error) = connection cannot reach endpoint; system will retry on network path change. This state can persist 30–75 seconds before .failed — exact root cause of issue #2.
- Safe to treat .waiting as immediate failure for hardcoded IP direct-connect (no DNS involved, IP is simply wrong/unreachable).
- Fix: add case .waiting in stateUpdateHandler → call connection.forceCancel() (skips TLS teardown for unestablished connection) OR call finish(.failure(error)) directly.
- forceCancel() preferred over cancel() for unestablished connections (faster, no TLS close_notify handshake).
- NWProtocolTCP.Options().connectionTimeout can also set a belt-and-suspenders short per-connection timeout.

Q4: DNS/URLSession fallback for Feishu on macOS
- URLSession.shared.data(for:) is the idiomatic fallback — uses system DNS, HTTP/2, respects ATS.
- open.feishu.cn uses HTTPS; no ATS exceptions needed in Info.plist.
- Existing com.apple.security.network.client entitlement already covers URLSession outbound connections.
- URLSession + Swift Concurrency (macOS 12+) handles task cancellation natively — no withTaskCancellationHandler wrapper needed for the fallback path.
- Implementation: after all 5 IP attempts fail, make one URLSession request to https://open.feishu.cn<path>, wrap HTTPURLResponse as DirectHTTPResponse.

SUMMARY_FOR_ARCHITECT:
- Issue #4: wrap DirectFeishuHTTPClient.send() with withTaskCancellationHandler; onCancel must call existing finish(.failure(CancellationError())) to ensure single-resume semantics via NSLock.
- Issue #2: add case .waiting in stateUpdateHandler → forceCancel() or finish(.failure); eliminates 30-75s per-IP stall.
- Issue #3: after IP loop exhaustion, attempt URLSession fallback to https://open.feishu.cn; no ATS/entitlement changes needed.
- Double-resume: structurally safe as long as all resume paths go through finish() with NSLock guard.
