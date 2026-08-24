# Issue #40 v5 R3 Minimal Architecture Amendment

## 1. Decision and scope

This amendment repairs only these implementation blockers against the current uncommitted v5 candidate in
`/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`:

- correctness review `R10`: the last target/security validation is before pair construction;
- correctness review `R9` and security review `R2`: cancellation/deadline checkpoints are above, rather than
  between, concrete AX calls;
- security review `R1`: an application-bound ordinary miss can outlive the security sample that authorized
  it; and
- security review `R3`: an admitted record that expires before start remains active forever.

This is an amendment to `architecture-blueprint-v5.md`, not a replacement. All previously approved v5
contracts remain binding: zero output before a real current-preview confirmation, fixed captured application,
one immutable UTF-16 pair, no activation, no ambient retarget, no pasteboard/Cmd+V, no global Return, one
down followed by mandatory up, no resend after down, nonblocking MainActor, and independent recording and
recognition roots.

Correctness `R11` (the keyboard matrix bypasses the production panel arbiter) is intentionally outside this
amendment and remains a separate blocking TDD repair. This document must not be cited as closing R11 or the
whole Issue #40 review.

Measured implementation evidence comes from:

- `.cache/code-review-v5-r3.md`;
- `.cache/security-review-v5-r3.md`;
- `FeishuSpeech/Services/ReviewSubmissionExecutor.swift` current `prepareRawAttempt` and `processStart`; and
- `FeishuSpeech/Services/AccessibilityClient.swift` current System AX validation/helpers.

No new dependency, entitlement, schema, build tool, output mode, or generalized accessibility framework is
authorized.

## 2. Required end-to-end ordering

### 2.1 One raw-attempt sequence

The raw executor owns the following strict sequence for both bindings. Steps may fail closed early, but they
must not be reordered:

```text
claim exact admitted value record and immutable deadline
  -> validate capturedTargetID in raw serial target registry
  -> early preflight needed for safe exact restoration
  -> stabilize relevant modifiers
  -> early binding validation/restoration
  -> establish combined-epoch baseline
  -> mark preparing
  -> optional second pre-pair validation
  -> cancellation + deadline checkpoint
  -> construct and read back the complete immutable Unicode down/up pair
  -> cancellation + deadline checkpoint
  -> begin bounded commit-attempt loop:
       FINAL cancellation-aware binding + target + security composite validation
       -> cancellation + deadline checkpoint
       -> final relevant-modifier sample
       -> cancellation + deadline checkpoint
       -> try to reserve expected combined epoch
       -> try to acquire value/commit lock
       -> if either reservation is unavailable:
            release anything acquired; checkpoint; bounded backoff;
            repeat from FINAL composite validation without reconstructing pair
  -> raw cancellation + absolute-deadline + phase + epoch comparison
  -> post down; mark boundary crossed; mandatory post up
```

Earlier target validation remains because exact-cursor restoration cannot safely begin without it. It is not
the final authorization. Pair construction/readback must finish before the final composite validation, and
no pair construction, target mutation, target/security sampling, modifier sleep, or other AX call may occur
between successful final composite validation and the final modifier/epoch reservation sequence.

An unavailable epoch reservation or value lock invalidates that iteration's final proof. Every retry must
repeat the complete final binding/trailing-security composite before sampling modifiers and reserving again.
It is forbidden to loop only over modifier/lock acquisition with a stale target/security proof. The immutable
pair is retained executor-locally across bounded retries and is constructed/read back only once.

The unavoidable public-API last-sample-to-down micro-window remains. This amendment narrows it to the period
after the required trailing composite sample; it does not claim an atomic WindowServer/Secure Input/process
transaction. Drift observed after down remains terminal submitted-unverified with no retry.

### 2.2 Prepared-pair ownership on a final-validation failure

Pair creation yields one executor-confined `prepared` capability. Exactly one terminal consumer is allowed:

- commit consumes it once and attempts down/up; or
- any cancellation, deadline, target, security, modifier, or epoch failure before down explicitly discards
  it once and posts neither event.

The raw executor must discard the pair before it submits `TerminalCleanupValue(.notStarted(...))` to the
control plane. The control plane may emit the terminal event only after no raw pair remains post-capable.
No pair, event source, `CGEvent`, or `AXUIElement` crosses the raw executor boundary.

## 3. Final composite target/security validation

### 3.1 One production operation

Add one raw-executor-only operation with this semantic result:

```text
validateForImmediateCommit(rawTarget, exactHandle, absoluteDeadline)
    -> success(FinalBindingProof) | failure(ReviewPreBoundaryFailure)
```

`FinalBindingProof` is ephemeral executor-confined value evidence. It is consumed immediately by the
modifier/epoch reservation sequence and is never stored in MainActor, the value control record, or a future
attempt. The operation uses the lowest-level checkpoint contract in section 4.

The proof is valid for one reservation iteration only. If epoch or value-lock reservation is unavailable,
discard the proof value, release any partial reservation, checkpoint/back off within the same absolute
deadline, and invoke `validateForImmediateCommit` again before the next reservation attempt.

Each invocation is one composite sandwich:

1. take the same cancellation/deadline + Secure Input + trust + full-identity + frontmost composite as a
   **leading** sample before any final exact focus/selection mutation or binding-specific AX message;
2. execute the binding-specific checkpointed AX sequence; and
3. repeat the complete composite as a **trailing** sample after the last binding-specific AX message.

The leading sample prevents final exact restoration from mutating a target that was already observably
secure/untrusted/stale. The trailing sample closes changes during the AX sequence. Success requires both.
The trailing composite is ordered as follows:

1. exact attempt cancellation is not latched and monotonic time is below the immutable deadline;
2. `IsSecureEventInputEnabled()` is false;
3. exact attempt cancellation/deadline still pass;
4. `AXIsProcessTrusted()` is true;
5. exact attempt cancellation/deadline still pass;
6. `NSRunningApplication` still produces the complete captured PID, bundle ID, executable URL, and launch
   date identity;
7. exact attempt cancellation/deadline still pass;
8. `NSWorkspace.shared.frontmostApplication` still has the captured positive PID; and
9. one last exact attempt cancellation/deadline checkpoint passes.

Secure Input, lost Accessibility trust, missing/malformed identity, different launch generation, different
frontmost PID, cancellation, or deadline failure destroys the pair and posts zero. The trailing sample may
not be replaced by the two-second permission poll, lifecycle epoch alone, cached capture security, or a
preclassified fake result.

### 3.2 Exact-cursor final binding semantics

The exact binding remains pinned to the captured raw focused element and original selected range. Final
validation must prove, through checkpointed System AX steps:

- captured element PID equals the captured application PID;
- focus/selection restoration, if still required, targets only that captured element and original range;
- the current focused-element readback equals the captured element;
- selected-range readback exactly equals the captured range;
- role/subrole/editability remains safely verifiable; and
- the trailing composite sample in section 3.1 passes.

For exact binding, `noValue` or `attributeUnsupported` on any required focus, selection, PID, role, subrole,
or editability proof is a typed fail-closed result. It must never downgrade the admitted attempt to
application-bound, choose the current responder, or select another PID. Timeout, malformed value, invalid
element, API failure, cancellation, and deadline are also failures.

### 3.3 Application-bound final binding and ordinary misses

Application-bound authority remains deliberately bound to the captured application, not a captured control.
Final validation reads the current responder only from the captured application/system AX objects and never
from an ambient frontmost PID. A different same-process current responder is allowed only because this
binding explicitly means current focus within the same captured application.

The final binding-specific AX sequence returns one of:

- `verifiedEditable`: current focused element exists, its PID is the captured PID, and role/subrole/security
  assessment is safely editable;
- `ordinaryCapabilityMiss`: and only when focused-element, role, or subrole access returns exactly
  `kAXErrorNoValue` or `kAXErrorAttributeUnsupported`; or
- failure.

An ordinary miss is provisional. It becomes a successful application-bound `FinalBindingProof` only if the
trailing Secure Input/trust/full-identity/frontmost composite in section 3.1 passes afterward. A security
failure may never be reclassified as an ordinary miss. `cannotComplete`, timeout, invalid element, malformed
type/value, API disabled, cancelled, expired, PID mismatch, identity mismatch, or unknown AX error fails
closed.

This preserves the already approved application-bound fallback without expanding it. If product/security
policy later rejects ordinary misses even with the trailing global proof, the honest alternative is to
disable that fallback; it is not acceptable to activate, retarget, or use the clipboard.

## 4. Lowest-level AX step and checkpoint contract

### 4.1 Production seam

Refactor the System runtime around a small executor-confined `SystemReviewAXStepRunner`. This is not a new
output abstraction; it is the single lowest-level sequencing point for the AX calls already present in
`AccessibilityClient.swift`.

Each step carries the exact attempt cancellation probe and immutable absolute deadline. Its mandatory shape
is:

```text
checkpoint before the synchronous operation
  -> perform exactly one AX/AXValue/security sampling operation
  -> optional value-only diagnostic step observer returns
  -> checkpoint cancellation AND monotonic deadline immediately after return
  -> classify the raw result
  -> checkpoint again immediately before the next synchronous operation
```

The post-return checkpoint precedes every later AX mutation, copy, get, set, value construction/readback, or
security sample. No helper may again combine `AXUIElementSetMessagingTimeout` and the following AX message
behind one Boolean return.

The runner must cover at least:

- every exact-object `AXUIElementSetMessagingTimeout`;
- `AXUIElementCopyAttributeValue`;
- `AXUIElementGetPid`;
- `AXUIElementIsAttributeSettable`;
- `AXUIElementSetAttributeValue` for focus and selected range;
- `AXValueCreate` and `AXValueGetValue` used by selection write/readback;
- type/readback validation that precedes another AX call; and
- Secure Input, trust, running-identity, and frontmost samples in the final composite.

Every AX object actually messaged, including fresh system-wide, application, focused, and captured elements,
still receives `min(500 ms, positive remaining whole-attempt budget)` immediately before that object's next
message. After the timeout-setting call returns, the diagnostic seam and checkpoint run before the message.
If cancellation is latched, return `.cancellation`; if time is no longer strictly below the absolute deadline,
return `.accessibilityTimeout`/`.deadline` according to the existing typed boundary. Neither condition may
execute the next AX call.

### 4.2 Testability without weakening confinement

Add a behavior-preserving injectable System-call table and a value-only `ReviewAXStepObserver`. Production
entries invoke the existing ApplicationServices/AppKit functions. The observer receives only a step ID and
raw result category; it receives no `AXUIElement`, `AXValue`, `CGEvent`, backend, draft, or target token.
It runs only on the raw executor and never under the commit/epoch lock.

The deterministic interleaving is:

```text
AXUIElementSetMessagingTimeout returns
  -> step observer pauses
  -> control plane latches exact-handle cancellation or test clock crosses deadline
  -> observer resumes
  -> production checkpoint observes failure
  -> following focus/selection/copy/get/set operation count remains zero
```

A high-level fake that pauses after an entire `setFocused`, `setSelectedRange`, or `validate` helper is not an
acceptance oracle. A source-string assertion is not an acceptance oracle.

## 5. Admitted-then-expired start terminalization

`ReviewSubmissionControlPlane.processStart` owns this repair because the record is still value-only and raw
execution has not begun.

Under the value-store lock, it must perform exactly this state transition:

```text
matching active record + phase admitted + cancellation false
  -> sample monotonic now
  -> if now < immutable deadline:
       phase = startQueued; unlock; enqueue exact handle to raw executor once
  -> else:
       phase = terminal
       remove exact record
       clear activeHandle only if it equals this handle
       form terminal(handle, notStarted(deadline))
       unlock
       emit that terminal event once
       do not invoke startHandler
```

Event dispatch, logging, callbacks, and raw-queue enqueue occur after unlocking. A stale, foreign,
wrong-phase, already-terminal, or missing handle must not mutate another record. Any later start,
cancellation, or cleanup for the retired handle may produce at most a typed `notCurrent` cancellation result;
it must never emit a second terminal event or raw work.

MainActor applies the matching `.notStarted(.deadline)` through the existing terminal path: clear the exact
handle/request/envelope/start/cancellation flags once, preserve the exact frozen draft and revision, restore
`.editable`, and refocus the preview editor. It does not automatically start a replacement attempt. Only a
future real Send or qualified preview Return may mint a new handle.

There remains no MainActor deadline task, blocking wait, or timeout race.

## 6. File ownership and minimal change set

### 6.1 Output/security implementer

- `FeishuSpeech/Services/AccessibilityClient.swift`
  - add the System AX call/step/checkpoint seam;
  - split every timeout/message/value operation into separately checkpointed steps;
  - add final binding-specific validation and trailing composite security sample;
  - preserve raw AX confinement and exact/application-bound classification above.
- `FeishuSpeech/Services/ReviewSubmissionExecutor.swift`
  - reorder pair construction before final composite validation;
  - explicitly discard a prepared pair on every later pre-down failure;
  - keep final modifier then epoch/value-lock commit ordering;
  - terminalize admitted-but-expired start exactly once in the value control plane.
- `FeishuSpeech/Models/CursorTextModels.swift`
  - change only if a value-only step ID, final proof classification, or typed test seam must be shared;
  - do not add raw references or expand public confirmation authority.

`FeishuSpeech/ViewModels/MainViewModel.swift` should require no behavioral production change: its existing
matching terminal handler already owns draft restoration. If a RED proves otherwise, the coordinator owner
may make only the minimal matching-handle `.notStarted(.deadline)` recovery repair; recording and recognition
roots remain protected.

### 6.2 TDD custody

Only the TDD role edits:

- `FeishuSpeechTests/FinalTextOutputSecurityTests.swift`; and
- an existing System accessibility runtime test file if the project already has a narrower suitable owner.

Do not create a source-text oracle. All ordering assertions must execute the production raw executor,
production control plane, production System AX step runner, and concrete prepared-pair lifecycle with
injectable raw samples/posts.

### 6.3 Protected files

No change is authorized in:

- `FeishuSpeech/Services/AudioRecorder.swift`;
- recognition provider/API/streaming/journal/ingress actors;
- recorder and recognition task-root ownership in `MainViewModel`; or
- clipboard, activation, target selection, Return monitoring, or retry behavior.

## 7. TDD dependency order

1. Output owner adds only behavior-preserving injection points for the concrete System AX calls, value-only
   step observer, monotonic clock, raw security samples, and prepared-pair discard observation. Existing
   production ordering and classifications remain unchanged. Run the existing focused suite.
2. TDD owner adds the selectors below and records RED against that seam. The timeout-to-setter and post-pair
   drift tests must fail behaviorally, not merely fail to compile. The expired-start test must observe the
   missing terminal event without leaving the hosted test process hung.
3. No behavioral fix begins before the RED receipt.
4. Accessibility owner implements the lowest-level checkpoint runner and final composite validator in
   `AccessibilityClient.swift`.
5. Executor/control-plane owner consumes that validator after pair construction, implements explicit pair
   discard, and repairs `processStart` terminalization. Because the two executor repairs touch the same file,
   they are one serialized ownership lane, not parallel write tasks.
6. TDD owner runs the focused GREEN suite and records event/post/AX-step ledgers.
7. Independent correctness and security reviewers falsify the final sample ordering, ordinary-miss table,
   lowest-level System step interleavings, exactly-once cleanup, and all preserved no-output boundaries.
8. Only after R11's separate production-panel keyboard matrix repair and all other reviews pass may the
   investigator rerun full test/build/lint, install Release, and request owner UAT.

Accessibility implementation and control-plane expired-start implementation are logically independent and
touch different regions/files, but the executor's post-pair validator integration depends on the new
Accessibility operation. Execute Accessibility first; keep one owner for all writes in
`ReviewSubmissionExecutor.swift` to avoid semantic and textual conflict.

## 8. Concrete acceptance tests

### 8.1 Pair then final composite validation

Add production-composition selectors:

- `test_pairReadbackPrecedesFinalCompositeValidationAndCommitReservation`
- `test_gateContentionRepeatsFinalCompositeBeforeEveryReservationAttempt`
- `test_targetDriftDuringCommitBackoffFailsRepeatedCompositeAndPostsNothing`
- `test_exactFocusOrSelectionDriftAfterPairWithoutEpochDestroysPairAndPostsNothing`
- `test_applicationBoundSecureResponderDriftAfterPairWithoutEpochDestroysPairAndPostsNothing`
- `test_secureInputEnabledAfterPairWithoutEpochDestroysPairAndPostsNothing`
- `test_accessibilityTrustLostAfterPairWithoutEpochDestroysPairAndPostsNothing`
- `test_runningIdentityOrFrontmostDriftAfterPairWithoutEpochDestroysPairAndPostsNothing`
- `test_exactOrdinaryAXMissAfterPairFailsClosedWithoutApplicationBoundDowngrade`
- `test_applicationBoundOrdinaryFocusedMissRequiresSafeTrailingComposite`
- `test_applicationBoundOrdinaryMissThenSecureInputBeforeTrailingCompositePostsNothing`
- `test_applicationBoundOrdinaryMissThenTrustLossBeforeTrailingCompositePostsNothing`
- `test_applicationBoundOrdinaryRoleOrSubroleMissWithSafeTrailingCompositePreservesFallback`

The ordering ledger for the success case must show:

```text
pairPrepare -> pairReadback -> finalBindingAX -> trailingSecureInput -> trailingTrust
-> trailingIdentity -> trailingFrontmost -> finalModifier -> epochReservation -> valueLock -> down -> up
```

The full runtime trace also requires the equivalent leading Secure Input/trust/identity/frontmost sample
immediately before `finalBindingAX`.

Every drift/failure case requires one prepared pair, one discard, zero down, zero up, one terminal
`notStarted` receipt, and no retry/retarget/activation/pasteboard calls. The application-bound positive
ordinary-miss case remains fixed to the captured PID and may post only after the safe trailing composite.
The contention tests require one pair construction, two or more final-composite samples, and no reconstruction;
drift injected during backoff must be caught by the next composite before any new reservation can post.

### 8.2 Lowest-level AX cancellation/deadline checkpoints

Add:

- `test_systemAXTimeoutReturnThenCancellationPreventsFocusSetterAndAllLaterWork`
- `test_systemAXTimeoutReturnThenDeadlinePreventsFocusSetterAndAllLaterWork`
- `test_systemAXSelectionTimeoutReturnThenCancellationPreventsSelectionSetterAndPosts`
- `test_systemAXStepMatrixChecksCancellationAndDeadlineAfterEveryUnderlyingReturn`
- `test_systemAXOrdinaryMissClassificationOccursOnlyAfterPostReturnCheckpoint`

The matrix enumerates every production step ID listed in section 4.1. For each row, latch cancellation and,
separately, advance the injected monotonic clock at the post-return observer. Assert the immediately following
operation and all later mutating/preparation/post operations remain zero. The focus-timeout test specifically
requires zero focus setter, selection setter/readback, pair preparation, down, and up.

### 8.3 Expired start and draft recovery

Add:

- `test_admittedBeforeDeadlineStartAfterDeadlineEmitsOneTerminalAndNoRawWork`
- `test_expiredStartRetiresOnlyExactRecordAndClearsActiveHandle`
- `test_lateStartCancelAndCleanupAfterExpiredStartCannotEmitSecondTerminal`
- `test_mainViewModelExpiredStartPreservesDraftRestoresEditableAndRequiresNewGesture`

Use an injected monotonic clock: admit immediately before the deadline, capture the single
`admissionAccepted`, advance past the immutable deadline, then enqueue start. Assert exactly one terminal
`.notStarted(.deadline)`, empty records, nil `activeHandle`, zero `startHandler`, zero target-registry/AX/pair/
post work, and no second terminal after late commands. The coordinator test must assert exact draft text and
revision, editor focus restoration, one-active fence release only after terminal, and zero automatic resend.

Focused command after GREEN:

```bash
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test
```

## 9. Risks, rollback, and completion gates

- Final validation adds AX/security calls inside the existing two-second whole deadline. Deadline exhaustion
  is a safe `notStarted(.deadline/accessibilityTimeout)` with exact draft recovery, not a reason to renew the
  budget or skip validation.
- Exact final restoration may mutate only the captured element/range after explicit confirmation. The
  lowest-level cancellation/deadline checkpoints are required precisely so revoked authority cannot execute
  a later setter.
- Application-bound ordinary capability misses cannot prove a specific control. This amendment retains that
  already approved fallback only under the final global security/identity/frontmost proof and fixed captured
  PID. The remaining public-API micro-window is documented, terminal, and never retried.
- Diagnostic seams must be internal, value-only, raw-executor confined, and absent from the commit lock.
  Shipping behavior must use direct System calls through the same tested step runner.
- Explicit pair discard must not become a second posting path. A pair has one terminal owner and is never
  copied to MainActor/control plane.
- If focused GREEN passes but any System-step matrix row, ordinary-miss row, exactly-once terminal count, or
  protected recording/recognition topology check fails, stop and route back to the owning implementation/TDD
  role. Do not install.
- Roll back only this amendment's scoped production changes to the prior uncommitted v5 candidate; do not
  reinstall rejected `b321ac5` and do not reintroduce legacy output, clipboard, activation, or retargeting.

Completion requires: focused GREEN, independent correctness/security PASS for R10/R9 and R1-R3, separate
R11 PASS, full serial test/build/strict-lint/diff validation, installed WindowServer/UAT proof, sole-copy
inventory, and owner acceptance. Until then Issue #40 remains open.
