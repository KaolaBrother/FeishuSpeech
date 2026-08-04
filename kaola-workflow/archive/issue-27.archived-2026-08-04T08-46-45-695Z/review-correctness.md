# Issue #27 correctness and concurrency review

## Review binding

- Candidate: `26825b829cd654f46a445b0505d82b165dc27e40..62832ad`
- Surface: `StreamingSpeechModels.swift`, `CurrentFocusAppendSession.swift`, `MainViewModel.swift`, and both changed test files, including the release-contract migrations.
- Evidence read: `diagnostic-logs.md`, `lifecycle-trace.md`, `release-drain-blueprint.md`, both RED/test-contract receipts, both GREEN receipts, and the full candidate diff.
- Validation note: `git diff --check 26825b829cd654f46a445b0505d82b165dc27e40..HEAD` passed. The existing receipt records 308/308 tests green, but no expensive suite rerun was used to override the source-proven findings below.

## Findings

### R1 - P2 - AX terminal replacement failure is reported as normal success

Failure class: terminal acknowledgement / silent truncation.

Precondition and input: a live AX owner has already emitted a partial; after Fn-up, before the action-2 final is applied, the focused element, selected range, owned text, or security state changes so `CursorTextSession` cannot verify and commit the final replacement.

Expected: the terminal route must detect that the authoritative final was not committed, preserve the already visible partial, and publish a typed non-success/preservation outcome. Normal cleanup is valid only after terminal output finalization settles successfully.

Observed: `finalizeExistingOutputOwner` calls `cursorSession.handle(.final(...))` with `try?` and unconditionally returns `(true, "authoritativeFinalOffered")` (`FeishuSpeech/ViewModels/MainViewModel.swift:1585-1590`). `CursorTextSession` internally converts destination/security/write/verification failures to `.invalid` and returns without throwing (`FeishuSpeech/Services/CursorTextSession.swift:98-124`). The coordinator therefore closes admission and completes normally even though the final tail was not written.

Proof: this is reachable with an already provisional AX range followed by focus/range/text drift before action 2. Existing guards prevent an unsafe write, but they do not communicate success; the caller ignores the resulting `.invalid` state. The new happy-path AX test at `FeishuSpeechTests/StreamingMainViewModelTests.swift:231-256` does not exercise this terminal drift boundary.

Required repair: inspect the AX owner's post-final state/result and map invalid/preserved terminal settlement to a transcript-free preservation outcome rather than ordinary success. Add a coordinator test that mutates the captured AX destination after Fn-up and before a differing action-2 final.

### R2 - P2 - Drain expiry cannot distinguish safe committed output from rejected or uncertain output

Failure class: terminal-state misclassification.

Precondition and input: during a generation, Feishu returns a non-contentless snapshot that is later rejected for the active route, such as LF on the fixed-PID keyboard route, or the output poster returns delivery uncertainty; the post-release drain then expires.

Expected: unsafe/rejected text that never reached the target must not be described as preserved output. Delivery uncertainty must produce `.provisionalOutputPreserved`; no safe usable snapshot must produce the fixed streaming failure.

Observed: `recordUsableRecognitionIfEligible` sets `hasUsableHeldRecognition` before packet reservation, route-safety classification, ledger claim, and output result (`MainViewModel.swift:1320-1345`, `1474-1480`). `expirePostReleaseDrain` reduces the complete output state to that boolean and always emits `.emptyFinalPreservedPartial` when it is true (`MainViewModel.swift:1895-1927`). It cannot represent `unsafeTextSuppressed`, an unavailable owner, or `deliveryUncertain`.

Proof: LF passes the all-routes check but fails the current-focus keyboard-event check, so no keyboard transaction is issued while the boolean is already true. A drain expiry then takes the preserved-partial branch. Likewise, `CurrentFocusAppendOutcome.deliveryUncertain` is locally recorded but not retained for expiry classification. The sole expiry test at `StreamingMainViewModelTests.swift:1667-1728` covers only a successfully committed AX partial; the blueprint's no-output and uncertain-delivery expiry legs are absent.

Required repair: track terminal preservation state from actual safe claim/output outcomes, including delivery uncertainty, and choose expiry feedback from that typed state. Add expiry tests for no safe output, route-rejected LF, and uncertain keyboard delivery.

### R3 - P2 - The overall drain deadline is not part of the operation admission gate

Failure class: deadline race / post-expiry mutation.

Precondition and input: a packet or action-2 operation completes after the monotonic post-release deadline, but its completion reaches `MainActor` before the independently sleeping `postReleaseDrainTask` executes `expirePostReleaseDrain`.

Expected: once the deadline has elapsed, no operation result may claim response ownership or mutate the target; cleanup must deterministically win and report a non-success terminal outcome.

Observed: `performWatchedOperation` samples remaining budget only to choose a timeout duration (`MainViewModel.swift:1032-1035`). Its success path claims the race gate and calls `admitSuccess` without rechecking the drain clock (`1037-1054`). The separate drain task invalidates admission only when it later gets actor time (`1885-1892`). A completion queued after the clock deadline can therefore win the operation gate, apply packet/final text, and schedule normal completion before expiry runs. A newly started operation with `remainingDrainNanoseconds() == 0` is also launched and races a zero-duration timeout instead of failing synchronously.

Proof: generation and attempt checks do not encode the deadline and remain true until `expirePostReleaseDrain` executes. The late-packet test releases its result only after identity cleanup, so it proves stale suppression after cleanup but not deadline ordering before cleanup (`StreamingMainViewModelTests.swift:1710-1728`).

Required repair: make remaining-drain validation part of the same winner gate immediately before success admission, and fail synchronously when the remaining budget is zero. Add deterministic tests where packet and finish completions become ready at/after the deadline before the expiry task runs.

### R4 - P3 - External cancellation leaves the watchdog gate open for a late factory success

Failure class: attempt teardown / late-resource cancellation.

Precondition and input: reset, permission/security invalidation, lifecycle cleanup, or drain expiry cancels the consumer while a session factory ignores task cancellation and later returns a session.

Expected: parent cancellation must settle the operation race, so any later factory success takes `onLateSuccess` and the returned session is cancelled exactly once.

Observed: when cancellation makes `AsyncStream.Iterator.next()` return `nil`, `performWatchedOperation` substitutes `.failure(.cancelled)` but never claims `StreamingOperationRaceGate` (`MainViewModel.swift:1076-1080`). The late factory task can then claim the still-open gate, take the ordinary `admitSuccess` branch, and yield into an abandoned stream instead of invoking the factory-specific cancellation callback at `MainViewModel.swift:690-693`.

Proof: a local Swift runtime probe confirmed that cancelling a task waiting in `AsyncStream.Iterator.next()` returns `nil` with `Task.isCancelled == true`. The current hanging-factory test covers watchdog timeout with a cancellation-cooperative provider (`StreamingMainViewModelTests.swift:1620-1665`, `4164-4211`), not external cancellation with a noncooperative late success.

Required repair: settle the shared gate on parent/stream cancellation before returning, then let any later success execute `onLateSuccess`. Add reset and drain-expiry tests using a factory that deliberately returns a session after cancellation.

finding: id=R1 scope=in_scope action=fix status=open severity=medium fix_role=implementer rationale=p2_ax_terminal_failure_is_misreported_as_success
finding: id=R2 scope=in_scope action=fix status=open severity=medium fix_role=implementer rationale=p2_drain_expiry_conflates_rejected_uncertain_and_committed_output
finding: id=R3 scope=in_scope action=fix status=open severity=medium fix_role=implementer rationale=p2_deadline_is_not_atomic_with_operation_success_admission
finding: id=R4 scope=in_scope action=fix status=open severity=low fix_role=implementer rationale=p3_external_cancellation_leaves_factory_late_success_uncancelled
verdict: fail
findings_blocking: 4
review_conclusion: The release drain is directionally correct, but four lifecycle boundaries still permit silent truncation, incorrect expiry reporting, or stale attempt settlement.

## Final Re-review

- Candidate: `62832ad..cbbbf2f`, including test commit `25aa505` and production repair `cbbbf2f`.
- Evidence read: `review-green-r1-r4.md`, the exact repair diff, all changed production paths in context, the new focused tests, their test doubles, and the existing output-session implementations consumed by the repair.
- Validation: `git diff --check 62832ad..cbbbf2f` passed. An independent direct XCTest run of `FeishuSpeechTests.StreamingMainViewModelTests` executed 91 tests with 0 failures.

### R1 closure

Resolved. The AX finalization path now inspects `CursorTextSession.state` after action-2 handling. Only `.committed` records a successful authoritative final; `.invalid` and other uncommitted terminal states preserve the visible partial and publish `.provisionalOutputPreserved`. The new destination-drift test exercises the original trigger and asserts both preserved text and non-success feedback.

### R2 closure

Resolved. Drain expiry now uses output state derived from actual AX or keyboard delivery outcomes. It distinguishes verified committed output, delivery uncertainty, and no safe output, mapping them respectively to preserved-partial feedback, provisional-preservation feedback, and the fixed streaming failure. The new tests cover both the no-output/route-rejected case and uncertain keyboard delivery, while existing coverage retains the committed-output case.

### R3 closure

Resolved. Operation success now checks the live monotonic drain deadline inside the same lock-backed race gate that settles success versus timeout/cancellation, so a completion at or after the deadline cannot reach output admission. A zero remaining budget returns timeout before starting the operation. Deterministic packet, finish, and zero-budget tests cover each boundary.

### R4 closure

Resolved. Parent cancellation now settles the shared gate and closes the result stream before cancelling the operation and timeout tasks. A noncooperative factory that later returns therefore follows `onLateSuccess`, where its session is cancelled exactly once. Reset and drain-expiry tests exercise both original teardown triggers.

### Regression scan

No new P0-P3 defect was found in the repair delta. The output-state transitions remain conservative after uncertainty because the production current-focus session suspends permanently on delivery uncertainty, and AX final failures cannot be misreported as committed success. Deadline expiry and external cancellation both suppress late packet/final mutation and cancel late factory resources.

finding: id=R1 scope=in_scope action=none status=resolved severity=medium fix_role=implementer rationale=ax_terminal_failure_now_preserves_partial_and_reports_non_success
finding: id=R2 scope=in_scope action=none status=resolved severity=medium fix_role=implementer rationale=drain_expiry_now_uses_typed_actual_output_state
finding: id=R3 scope=in_scope action=none status=resolved severity=medium fix_role=implementer rationale=deadline_check_is_atomic_with_operation_success_admission
finding: id=R4 scope=in_scope action=none status=resolved severity=low fix_role=implementer rationale=parent_cancellation_now_settles_gate_and_cancels_late_factory_session
verdict: pass
findings_blocking: 0
review_conclusion: The repair closes all four recorded lifecycle defects with deterministic boundary tests, and the full streaming coordinator suite passes without a new candidate-caused regression.
