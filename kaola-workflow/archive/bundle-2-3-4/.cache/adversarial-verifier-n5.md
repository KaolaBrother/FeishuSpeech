verdict: pass
findings_blocking: 0
findings_advisory: 1

probe: 1-cancellation-race-double-resume
result: not-refuted
confidence: high
description: Could not produce a double-resume. Both CancelBox.cancel() (onCancel) and the stateUpdateHandler funnel through the SAME finish() closure; finish()'s own NSLock+isFinished flag is the single arbiter of continuation.resume. The CancelBox lock and the finish() lock are separate, but that is harmless because cancel() never resumes directly — it only invokes abort() which calls finish(), which re-checks isFinished. Verified with: (a) 2000-iteration concurrent cancel-vs-finish harness (maxResume=1), (b) 5000-iteration store-after-cancel race (0 double-resume, 0 zero-resume), (c) 200-iteration stress against a REAL NWConnection hitting .waiting in ~1ms while onCancel fired at a random 0-2ms offset (maxResume=1, zeroResume=0). After forceCancel(), the later .cancelled state hits `case .cancelled: break` (no finish) — safe; and any later .failed/.waiting short-circuits on isFinished. No crash path found.

probe: 2-nwconnection-leak-on-timeout
result: not-refuted
confidence: high
description: On normal timeout (queue.asyncAfter), finish(.failure(.timeout)) runs and calls connection.cancel() exactly once (verified teardown invariant: resumeCount==1, connCancel==1 across all finish paths). The abort closure stored in CancelBox is captured by the CancelBox instance, which is captured by the withTaskCancellationHandler operation, alive until send() returns — no early dealloc. cancelBox.cancel() after a timeout-driven finish is a safe no-op (forceCancel on an already-cancelled connection + abort()->finish() short-circuits on isFinished). No leak or post-timeout crash found.

probe: 3-waiting-onCancel-race
result: not-refuted
confidence: high
description: Simultaneous .waiting and parent-task cancellation both route to finish() via separate paths; the isFinished guard inside finish() correctly admits exactly one. The locks are SEPARATE (CancelBox.lock vs the send()-local finish lock) but there is no window: finish()'s lock alone gates resume, and both racers call finish(). Verified empirically with the real-NWConnection concurrent stress above.

probe: 4-urlsession-fallback-deadlock
result: not-refuted
confidence: high
description: No actor deadlock. Swift actors suspend (not block) on await; sendViaURLSession awaiting URLSession.shared.data(for:) releases the actor executor (verified: actor bump() interleaved with a suspended async call, counter advanced, no deadlock). URLSession runs off the actor. On an already-cancelled task, URLSession.shared.data threw NSURLError(-999) in ~0.009s rather than completing the request — cancellation honored promptly, no real network I/O kicked off, no hang.

probe: 5-withRetry-cancellationError
result: not-refuted
confidence: medium
description: CancellationError CAN re-enter the retry loop, but it cannot cause a real network attempt or a hang. Two sub-paths: (a) sendDirectRequest's per-IP catch and the URLSession fallback do NOT check Task.isCancelled, so on a cancelled task all 5 NWConnection objects + the URLSession fallback are churned — but each resumes immediately (measured 0.0001s for the 5-IP loop; URLSession threw in 0.009s). Wasteful connection churn, not a hang. (b) The error surfaced by a cancelled sendDirectRequest is APIError.connectionFailed (isRetriable=true), so withRetry's APIError branch does not throw and reaches `try await Task.sleep`, which throws CancellationError immediately on the cancelled task, propagating out — at most one extra operation() body per cancellation. On the FINAL (3rd) attempt there is no sleep, so the surfaced error is APIError.connectionFailed rather than CancellationError; this is cosmetic only — MainViewModel.withTimeout returns the TimeoutError from its own sleep task at the 30s mark and discards recognizeSpeech's eventual error, so the user-facing outcome and timing (~30s, not ~150s) are unaffected. Issue #4's claim holds. Logged advisory R1 (matches design-node finding): add explicit `if error is CancellationError { throw error }` in withRetry and/or break the IP loop on cancellation to avoid connection churn. Non-blocking.

probe: 6-waiting-case-placement
result: not-refuted
confidence: high
description: Confirmed against real NWConnection: a closed-port connect produced .waiting(ECONNREFUSED) in 0.001s, so `case .waiting(let error): finish(.failure(error))` makes issue #2 fail in ~1ms instead of 30s. If .waiting fires AFTER .ready (briefly connected then lost), the second finish() short-circuits on isFinished and the connection is already torn down by the first finish()'s connection.cancel() (teardown-once invariant verified). No leak, no double-resume.

finding: id=R1 scope=in_scope action=follow_up status=open severity=advisory fix_role=implementer rationale=withRetry generic catch and sendDirectRequest IP loop do not short-circuit CancellationError; on a cancelled task all 5 IPs + URLSession fallback are churned (each resolves in ms, no hang). Cosmetic error-type mismatch on final retry. Recommend explicit `if error is CancellationError { throw error }`. Non-blocking — user-facing timeout behavior is correct.
