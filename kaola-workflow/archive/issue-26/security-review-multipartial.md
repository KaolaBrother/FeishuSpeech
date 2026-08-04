# Issue 26 multi-partial security and privacy review

Date: 2026-08-04

result: PASS
verdict: pass
findings_blocking: 0

## Review outcome

No candidate-caused P0, P1, P2, or P3 security or privacy defect was found in the current full
working-tree diff. The response ledger, release sealing, output-owner routing, lifecycle revocation,
and diagnostic changes preserve the existing fail-closed boundaries. In particular, action 2 and
late callbacks cannot create a first output, append a release-time suffix, invoke Command-V, or copy
recognized content after release.

This review covered the complete production and test diff, the three supplied authority reports,
and the unchanged downstream implementations used by the changed coordinator: `CursorTextSession`,
`CurrentFocusAppendSession`, `AccessibilityClient`, `TextInputSimulator`, and the streaming event
contract. No application was launched, no Fn or microphone path was invoked, and no credentials,
clipboard content, AX content, destination content, or transcript was inspected.

## Generation ledger and replay ownership

`ResponseOutputLedger` is private coordinator state keyed by the active generation. `begin` clears
the frontier, prior response shape, and owned packet-index set before opening admission; `reset`
clears them and closes admission (`MainViewModel.swift:28-87,389-393,1398-1403,1475-1483`).

For live audio, the packet is journaled before transport and the resulting journal index is carried
with the response (`MainViewModel.swift:639-659`). Retry replay enumerates the retained journal with
the same stable indices (`MainViewModel.swift:666-687`). A nonempty, control-safe response for an
active, unsealed generation can claim an index only once. A replay for an already-owned index is
classified as historical and is never re-offered, even if its raw response differs. A previously
failed and therefore unowned index can be claimed once when replay succeeds
(`MainViewModel.swift:942-1050`). All of this state is main-actor isolated, so release and response
admission cannot interleave inside a ledger mutation.

The coordinator selects or rebinds one continuous owner before claiming. It does not claim when no
owner exists, and it never falls through from one owner to a second writer. The locally assembled
UTF-16 frontier is offered either to the captured AX range or to the already-selected current-focus
append session (`MainViewModel.swift:964-1032,1157-1241`).

## Release, terminal, reset, sleep, and wake boundaries

Fn release sets the monotonic seal and closes ledger and retry admission before recorder shutdown or
any await (`MainViewModel.swift:1320-1347`). In-flight packet responses that resume later encounter
closed admission and are logged as sealed without being claimed or offered.

The terminal action-2 response is deliberately not passed to packet-response admission. Its text is
used only for contentless feedback and length-only diagnostics. Output-owner finalization receives
`finalText: nil` and only the already-owned local frontier (`MainViewModel.swift:1053-1120`). For the
AX owner, finalizing the same frontier commits the verified owned range without rewriting it. For the
production append owner, every successful apply has already advanced `emittedUTF16`; any drift,
Secure Input, or delivery uncertainty permanently suspended the owner, so finalization cannot repair
or resend it (`CursorTextSession.swift:42-65,79-124`; `CurrentFocusAppendSession.swift:141-265`).

Abnormal termination snapshots the old transport and barrier, then closes retry authority,
invalidates the generation and both output owners, clears the ledger and journal, fails ingress, and
cancels the consumer before its first await (`MainViewModel.swift:1414-1447,1460-1485`). Manual
reset, sleep, and wake all enter that path before service recovery (`MainViewModel.swift:1578-1594`).
The late-generation guard at event receipt and closed sink states make late partial, final, failure,
retry, and session-creation callbacks no-ops.

The changed coordinator has no call to `insertOnce`, `insertAtCurrentFocusOnce`,
`copyForManualRecovery`, pasteboard APIs, or Command-V posting. The former release-time one-shot and
manual clipboard recovery routes were removed rather than retained as a fallback.

## Destination and Secure Input controls

The live AX writer remains bound to the captured generation, PID, and AX element. Before each
replacement it verifies the frontmost PID, exact focused element, affirmatively safe security state,
expected caret or selection, and previously owned text; after writing it verifies the returned range
and exact owned text (`CursorTextSession.swift:79-215`). A failed or uncertain check invalidates the
owner and there is no rollback or alternate output.

Captured final-only routing creates a fixed-PID append owner with a validator that rechecks the
captured token's security, frontmost PID, and exact `CFEqual` focused element
(`MainViewModel.swift:1223-1241,1291-1317`). `CurrentFocusAppendSession` additionally samples live
Secure Input and frontmost PID twice before each post and once after it; the event poster performs a
last Secure Input sample immediately before the already-constructed down/up pair is posted. Target
drift, security rejection, or uncertain delivery permanently suspends the session and prevents all
later apply or finalize output (`CurrentFocusAppendSession.swift:104-183,185-207,251-321`;
`TextInputSimulator.swift:224-255`). C0, C1, DEL, contentless, stale-generation, and sealed values do
not reach either writer.

## Unified diagnostic privacy

The new response receipt logs only public integers and fixed typed labels: generation, retry ordinal,
journal index, source, event kind, eligibility, raw and assembled UTF-16 counts, response-shape
class, ownership, and typed output outcome (`MainViewModel.swift:1122-1155`). It does not log or hash
the response string. The two `String(describing:)` values are descriptions of payload-free enums, not
descriptions of transcript-bearing objects (`CurrentFocusAppendSession.swift:8-41`).

No new log contains transcript text, a reversible content hash, credentials or token material,
clipboard content, AX values, application or window names, PID, focused-element identity, stream ID,
audio, response body, or destination content. Generation and packet ordinals identify only local
control flow and do not materially expose user content. The UTF-16 counts and coarse shape labels are
the explicitly requested privacy-safe UAT evidence and are not reversible content representations.

## Accepted contract and residual risk

The concatenation of each eligible response once is a user-selected local product policy because
the Feishu intermediate-response relationship remains unknown. If the provider actually returns
cumulative or revisable whole hypotheses, visible duplication or stale semantics are product risks,
not a security-boundary failure in this candidate.

The AX-unavailable current-focus route is intentionally PID-bound rather than exact-element-bound.
It cannot observe same-process caret movement. The captured final-only route does retain exact AX
validation. Both routes also have an irreducible interval between the final validation sample and
target handling, and `CGEventPostToPid` provides no target acknowledgement. These are pre-existing,
documented best-effort residuals. They remain contained by permanent suspension, no retry, no resend,
no alternate writer, and no clipboard fallback after uncertainty.

Release-only sealing intentionally prefers no output over using action 2 as a recovery path. A
generation with no held-response owner may therefore end without inserted text. That is the accepted
contract under review, not a security defect.

## Validation evidence

- `git diff --check` passed on the current three-file candidate.
- The already-built XCTest bundle was exercised directly, without launching the application or its
  lifecycle. All 20 `CurrentFocusAppendSessionTests` and 17 focused coordinator tests passed: 37
  executed, 0 failures, 0 unexpected.
- The focused coordinator set covered multi-partial frontier growth, equal values at distinct packet
  indices, replay exact-once ownership, live AX routing, ineligible values, action-2 and late callback
  suppression, Secure Input revocation, reset, sleep/wake, late session creation, captured-element
  drift, unsafe text, delivery uncertainty, no resend, and no clipboard fallback.

verdict: pass
findings_blocking: 0
review_conclusion: The current candidate preserves fixed output ownership, closes all release and lifecycle admission before asynchronous cleanup, and adds privacy-safe diagnostics without introducing a security or privacy defect.
