# Issue 26 independent multi-partial code review

## Verdict

PASS. Prior finding R1 is resolved, and no new defect is admitted from the repair delta. The held-output ledger and the separate recognition-availability latch now satisfy the supplied contract without reopening terminal output paths.

## R1 closure - resolved

- Prior failure class: output-disabled lifecycle regression.
- Repair anchors: `FeishuSpeech/ViewModels/MainViewModel.swift:188,391` initializes a generation-scoped boolean only; `:944-965,1038-1046` records recognition availability before output classification but only for a packet-indexed, active, unsealed, non-contentless held response; `:808-824,1066-1108` uses that boolean for recoverable and normal completion instead of using the output frontier as recognition evidence; `:1399-1424,1483-1499` clears it on every normal or abnormal lifecycle exit.
- Trigger 1 closure: with `autoInsert == false`, a usable held packet response now sets `hasUsableHeldRecognition`, while classification still returns `outputDisabled`. A later nonempty action-2 final is never recorded or offered, completion returns idle, and no empty-result feedback is published.
- Trigger 2 closure: the same usable held response survives as boolean availability through recoverable retry/backoff. Release cancels retry admission, finalizes no output owner, and completes normally rather than reporting a stream failure.
- Safety proof: action-2 bypasses `handlePacketResponse`; stale identities fail `isActive` before routing; sealed responses fail the latch guards; contentless responses fail the latch guard; callbacks without a journal packet index cannot set it. The latch stores no transcript and does not participate in owner setup, ledger claims, cursor replacement, append posting, copy, or retry admission.
- Negative behavior retained: no-recognition recoverable factory and first-packet failures still take the fixed stream-error branch at `:810-820`; Secure Input and nonrecoverable failures retain their dedicated abnormal termination paths.
- Test anchors: `FeishuSpeechTests/StreamingMainViewModelTests.swift:464-508` covers normal output-disabled release plus action-2 and late callbacks; `:1044-1103` covers release during recoverable backoff and asserts zero AX, one-shot, current-focus, synthetic-input, clipboard, feedback, and late-callback effects. Existing no-recognition controls remain at `:1717` and `:1753`.

## Full reviewed frontier

- Packet-index stability: `packetJournal` remains append-only for a generation, and live and replay paths use the same zero-based index identity.
- Replay: historical indices cannot re-own output, while a previously failed unowned index can be claimed exactly once.
- Release races: ledger and retry admission close synchronously before recorder shutdown. In-flight, tail, action-2, stale, sealed, and directly injected late callbacks cannot advance the output frontier.
- Owner and target safety: assembled frontiers preserve the AX owned-range path and the fixed-PID, focused-element, Secure Input, and delivery-uncertainty gates of `CurrentFocusAppendSession`.
- Final-only and manual recovery: their removal remains consistent with the explicit release-only-seals contract. The R1 repair restores completion classification only and does not restore release-time insert, rewrite, append, copy, or retarget behavior.
- Privacy: the new state is one boolean. Receipt logs remain transcript-free and expose only fixed classifications, indices, and counts.
- Memory and performance: no new unbounded storage was added by the R1 repair. The previously reviewed frontier duplication remains bounded in interaction duration and is not admitted as a defect.

## Validation

- `xcodebuild -quiet -scheme FeishuSpeech -destination 'platform=macOS' build-for-testing`: exit 0. This built the current production SHA-256 `0fb593aac555ed3d109e709c727f70c0482d85fc80e31f180cfaf43ec09b130e` without launching the app lifecycle.
- Direct lifecycle-free XCTest selection: 5 executed, 0 failures. The selection covered both R1 tests, sealed/stale/contentless output admission, and the two no-recognition recoverable error controls.
- `git diff --check 7396a7c --`: clean.
- The supplied reconciliation evidence records 71 coordinator tests and 272 directly runnable bundle tests green on the same production SHA-256; the review used those results as corroboration, not as a substitute for code-path inspection.
- No application launch, Fn event, microphone, credentials, permission prompt, or installed-bundle interaction was performed.

## Assumptions and unknowns

- Feishu intermediate scalar semantics remain unknown. This verdict concerns the explicit local response-index policy, not a vendor cumulative or delta guarantee.
- Unsafe non-contentless held text counts as recognition availability but remains ineligible for output. This matches the supplied reconciliation contract and does not weaken the automatic-output safety gate.
- Whether an invalidated live AX owner should additionally show preservation feedback after a recoverable release remains unspecified; the R1 repair delta does not change that boundary.

finding: id=R1 scope=in_scope action=none status=resolved severity=P2 fix_role=tdd-guide rationale=recognition-availability-is-now-independent-of-output-eligibility-and-frontier-state
verdict: pass
findings_blocking: 0
review_conclusion: R1 is resolved and the current repair delta passes the complete independent review frontier.
