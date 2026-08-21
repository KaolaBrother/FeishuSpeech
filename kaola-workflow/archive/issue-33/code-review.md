# Issue #33 code review

Date: 2026-08-21
Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-33`
Baseline: `89b9395d4a528d30dbc2c4bc07e9e6c6e8e566dd`
Candidate: uncommitted delta in `FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift` and `FeishuSpeech/Services/TransportAttemptContext.swift`

Oracle: `kaola-workflow/issue-33/test-red.md`
GREEN receipt: `kaola-workflow/issue-33/implement-green.md`
Issue: https://github.com/KaolaBrother/FeishuSpeech/issues/33

Tests read only (not edited): `FeishuSpeechTests/DirectFeishuKeepAliveSessionTests.swift`, `FeishuSpeechTests/TransportAttemptContextTests.swift`

## Verdict

approve

No candidate-caused correctness defect was admitted. Keep-alive is primary with `prohibitedInterfaceTypes = [.other]`, URLSession is connect-class fallback, completed HTTP and CancellationError do not hop, both sticky modes hold for one `TransportAttemptContext`, and first-send keep-alive miss leaves the URLSession alive.

## Surface

Production changed:

- `FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift` — `nonisolated protocol DirectKeepAliveTransport`; `makeParameters()` adds `.other`
- `FeishuSpeech/Services/TransportAttemptContext.swift` — injectable keep-alive, send-order invert, `stickyURLSession`, conditional invalidate on direct miss

Unchanged callers checked: `FeishuAPIService.makeStreamingSession` / `getAccessToken` / `sendTokenRequest` / `sendStreamingRequest` / `recognizeSpeech`; `FeishuStreamingSession.cancel` invalidates first then best-effort abort.

`git diff --check` on the two production files: clean.

GREEN receipt already records focused 13/13 and full 352/352; this review did not re-run that suite.

## Send order versus tests

`TransportAttemptContext.send` now:

1. Invalidated -> `CancellationError`
2. `stickyDirect` -> keep-alive only (`sendDirect`), no URLSession hop
3. `stickyURLSession` or `phase == .abort` -> URLSession slice only
4. Else primary keep-alive with `directSliceNanoseconds`; `CancellationError` / `Task.isCancelled` rethrown; other errors hop once with `urlSessionSliceNanoseconds`

That matches the RED oracle and the focused suite:

- `test_completedHTTPDoesNotInvalidateSession` — keep-alive HTTP 200 wins; URLSession 500 decoy never starts
- `test_keepAliveConnectClassErrorHopsOnceToURLSession` — connectionFailed / timeout / networkError hop once; context stays valid
- `test_keepAliveCompletedHTTP4xxDoesNotHopToURLSession` — 400/401/403/407 return as completed HTTP
- `test_keepAliveCancellationErrorDoesNotHopToURLSession` — CancellationError rethrown; URLSession unused
- `test_stickyDirectLeavesURLSessionUnusedAcrossTwoSends`
- `test_stickyURLSessionDoesNotCallKeepAliveAgain`
- `test_newTransportAttemptContextStartsOnKeepAliveAgain`
- `test_sliceTimerCancelsHungDataForAndInvalidates` — hop uses the 40 ms URLSession slice, not the 2 s direct slice, then invalidates

Primary deadline is `policy.directSliceNanoseconds(for:)`. Fallback deadline is `policy.urlSessionSliceNanoseconds(for:)`. Slice budgets were not changed.

## First-send keep-alive miss must not invalidate URLSession

`sendDirect` snapshots `wasStickyDirect` before the POST. On error it always `forceCancel`s the keep-alive, nils the stored transport, and clears `stickyDirect`. `invalidate()` runs only when `wasStickyDirect` is already true.

First primary send starts with `stickyDirect == false`, so a connect-class miss returns to `send()` and hops on the still-live `URLSession`. `test_keepAliveConnectClassErrorHopsOnceToURLSession` pins `isInvalidatedForTesting == false` after the hop succeeds.

URLSession slice miss still calls `invalidate()` (session plus keep-alive), which is the inverted counterpart of the old URLSession-first miss.

## Mid-attempt sticky-direct drop still invalidates

After a keep-alive HTTP success, `stickyDirect = true`. Later `send` takes the `useDirect` branch and returns `sendDirect` without a hop catch. A later keep-alive error therefore cannot reach URLSession.

That later error has `wasStickyDirect == true`, so `invalidate()` runs: `isInvalidated = true`, sticky flags cleared, `URLSession.invalidateAndCancel()`, keep-alive already force-cancelled in the catch. Matches D-28-01: mid-attempt socket death fails the attempt; no silent reconnect on the same stream.

## CancellationError / completed HTTP do not hop

Completed HTTP, including 4xx, is a `DirectHTTPResponse` return from `sendDirect`, which sets `stickyDirect` and returns to the caller. It never enters the hop `catch`.

Keep-alive `CancellationError` is rethrown from `sendDirect` before `mapTransportError`. The outer `catch is CancellationError` / `Task.isCancelled` path rethrows and does not start URLSession. Generation cancel still hits `isInvalidated` first because `FeishuStreamingSession.cancel()` calls `invalidateTransport()` before abort.

## Abort still URLSession unless sticky-direct

If `stickyDirect` is set, abort uses keep-alive (sticky covers remaining POSTs of the attempt, including action=3).

Otherwise `phase == .abort` joins the URLSession-only branch. Abort does not set `URLRequest.timeoutInterval`; the slice timer is still `urlSessionSliceNanoseconds(.abort)` (1 s). That preserves the pre-invert abort budget.

Production cancel invalidates the context before `attemptBestEffortAbort`, so a live abort POST is a no-op on an already-dead context (existing D-28-01 rule: do not delay invalidate for abort).

## `sendURLSessionSlice` setting `stickyURLSession` on abort is not a defect

`sendURLSessionSlice` sets `stickyURLSession = true` on any URLSession HTTP win, including abort.

This is not a reachable production bug:

- Sticky-direct abort never enters `sendURLSessionSlice`.
- Non-sticky abort is URLSession-only by contract; if it completed, the streaming session is already terminal (`didAttemptAbort`, `terminalState` cancelled). No later factory/packet POST runs on that context.
- `FeishuStreamingSession.cancel()` invalidates first, so abort `send` throws `CancellationError` at the invalidated guard and never reaches the sticky assignment.

If abort were somehow the first successful URLSession send and a later POST reused the same context, sticky-URLSession would skip keep-alive. That follow-on does not exist on the current caller. Broadening sticky assignment to "any URLSession HTTP" is consistent with sticky-URLSession and does not invert abort back onto keep-alive.

## No `en0`; TLS still SNI plus no custom verify block

`DirectFeishuKeepAliveSession.makeParameters()` still sets SNI `open.feishu.cn` via `sec_protocol_options_set_tls_server_name`, builds `NWParameters(tls:)`, and sets `preferNoProxies = true`. The only added line is `parameters.prohibitedInterfaceTypes = [.other]`.

There is no `en0`, `requiredInterfaceType`, `localEndpoint`, named BSD bind, CDN IP list, or `sec_protocol_options_set_verify_block`. Host and SNI remain the compile-time `open.feishu.cn`. `NWConnection` is still hostname:443.

`file_recognize` / `recognizeSpeech` still use `getAccessToken` without a `TransportAttemptContext` and `executeURLRequest`. Production `TransportAttemptContext` is constructed as `TransportAttemptContext(policy:)` with nil keep-alive; the app builds `DirectFeishuKeepAliveSession` on first `sendDirect`.

## Concurrency and locks

`TransportAttemptContext` and `DirectFeishuKeepAliveSession` each use an `NSLock`. `invalidate()` copies `session` / `keepAlive` then unlocks before `invalidateAndCancel` / `forceCancel`. `sendDirect` does not hold the context lock across `keepAlive.send`. The two locks are never nested.

`SliceWinnerGate` remains the URLSession-versus-timer winner. Sticky flags are mutated only under the context lock.

`FeishuStreamingSession` serializes POSTs with `requestInFlight`. Factory token runs in `makeStreamingSession` before the session exists. Token refresh inside `sendWithInitialTokenRefreshIfNeeded` is sequential with the packet POST. Concurrent first-send races that could set both sticky flags are not on the production caller.

## MainActor isolation of `DirectKeepAliveTransport`

App and test targets set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. The RED oracle required a `nonisolated` protocol so the keep-alive class and the test mock can conform.

The candidate declares `nonisolated protocol DirectKeepAliveTransport: AnyObject, Sendable` with `send` and `forceCancel`. `DirectFeishuKeepAliveSession` is already `nonisolated final class` and conforms. The mock is `private nonisolated final class`. `TransportAttemptContext` stays `nonisolated final class` and stores `(any DirectKeepAliveTransport)?`.

That keeps `forceCancel()` off the MainActor. NWConnection callbacks run on `com.feishuspeech.direct-keepalive`; cancel/miss from `sendDirect` can call `forceCancel` without a MainActor hop. GREEN compile of the test target is the isolation proof.

## Logging

New/changed logs are the literals `transport=direct` and `transport=urlsession` (plus the existing connecting / invalidated lines). No tokens, PCM, transcripts, stream IDs, IPs, or interface names.

## Coverage note (not a finding)

There is no injected test that fails keep-alive after a prior sticky-direct success and asserts `invalidate()` plus no URLSession hop. The production branch is direct (`useDirect` returns `sendDirect`; `wasStickyDirect` invalidates). That is an oracle gap, not a demonstrated misbehavior.

verdict: pass
findings_blocking: 0
review_conclusion: Keep-alive-primary send order, sticky modes, first-send hop without killing URLSession, and sticky-direct invalidate all match the issue 33 contract with no admitted defect.
