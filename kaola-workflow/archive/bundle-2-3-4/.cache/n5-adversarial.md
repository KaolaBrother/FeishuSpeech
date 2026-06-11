verdict: pass
findings_blocking: 0
findings_advisory: 1

Adversarially probed 6 async failure modes against the CancelBox + withTaskCancellationHandler + .waiting + URLSession changes. All probes NOT-REFUTED at high/medium confidence.

probe: 1-cancellation-race-double-resume
result: not-refuted
confidence: high
description: 2000-iter cancel-vs-finish and 5000-iter store-after-cancel races both produced maxResume=1. Separate CancelBox lock and finish() lock are harmless — all resume paths funnel through single isFinished guard. After forceCancel(), .cancelled state hits case .cancelled: break (no finish call) — safe.

probe: 2-nwconnection-leak-on-timeout
result: not-refuted
confidence: high
description: finish() calls connection.cancel() once on winning path. Post-timeout cancelBox.cancel() is a safe no-op (connection nil, abort nil, already cleaned up).

probe: 3-waiting-plus-oncancel-race
result: not-refuted
confidence: high
description: .waiting and onCancel can both fire concurrently; both route through finish() isFinished guard. NSLock inside finish() is separate from CancelBox lock but that's fine — only finish()'s lock gates continuation.resume.

probe: 4-urlsession-actor-deadlock
result: not-refuted
confidence: high
description: Actor suspends (does not block) on await URLSession.shared.data(for:). On cancelled task URLSession threw NSURLError(-999) in ~0.009s — no hang, no real request sent.

probe: 5-withretry-cancellationerror
result: not-refuted
confidence: medium
description: withRetry generic catch does not short-circuit CancellationError; all 5 IPs + URLSession fallback are churned but each resolves in ~0.1ms on cancelled task. Advisory: user-visible timing (~30s) unchanged because MainViewModel.withTimeout(30s) is the binding constraint. Non-blocking.

probe: 6-waiting-after-ready
result: not-refuted
confidence: high
description: .waiting(ECONNREFUSED) fired in 0.001s in real NWConnection test to closed port — new case reduces per-IP latency from 30s to ~1ms. If .waiting fires after .ready, isFinished=true causes safe no-op in finish().

Advisory R1 (non-blocking): withRetry + sendDirectRequest do not short-circuit CancellationError — cosmetic churn but not a hang. Matches code-reviewer R1.
