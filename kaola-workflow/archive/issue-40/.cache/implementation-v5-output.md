# Issue #40 v5 output-lane implementation evidence

Date: 2026-08-24 (Asia/Shanghai)

Baseline: `b321ac5d6c04c91ced9afeb2240f9566d9b8d305`, with the previously recorded one-line
`ReviewDeliveryMonitoringSession` visibility seam. Test custody remains with the TDD lane; no test,
UI, MainViewModel, documentation, workflow, recording, or recognition file was edited here.

## Implemented surface

- Added value-only `ReviewTargetCaptureRequestDescriptor`, `CapturedReviewTargetDescriptor`, opaque
  `CapturedReviewTargetID`, `ReviewSubmissionRequestDescriptor`, `ReviewSubmissionAttemptHandle`, immutable
  admission envelope, phase record, typed control events, cancellation results, and phase-aware commit
  receipts in `CursorTextModels.swift`.
- Added `ReviewSubmissionControlPlane` and `ReviewSubmissionExecutor` in the owned new executor file.
  Admission/start/cancellation/cleanup are FIFO asynchronous value commands. Raw target registry, AX state,
  prepared pair, and serial executor state remain off MainActor; final gate admission uses bounded `NSLock.try`
  and the same value-only record store. Pre-boundary branches retire through cleanup; post-boundary always
  attempts key-up and reports `submittedUnverified` without resend.
- Added executor-confined raw AX runtime in `AccessibilityClient.swift`. Every fresh AX object is assigned
  `min(500 ms, remaining deadline)` immediately before each AX message; capture uses a separate 500 ms budget.
- Added a combined physical/lifecycle epoch primitive. Event-tap/local/global monitor handling advances it for
  interfering input and observability loss, while exact synthetic tag plus own source PID remains exempt;
  activation notifications advance it as lifecycle drift. Existing recording/provisional output behavior is
  preserved.
- Repaired the diagnostic final-pair seam so the monitor callback only records entry and no epoch getter or
  arbitrary pair work runs under the nonrecursive epoch gate. Removed that callback-gated API from the accepted
  `SystemReviewDestinationDelivery` path and removed target activation/retargeting; stale frontmost identity
  now fails closed.
- Prepared pair construction uses the exact full UTF-16 payload (including LF), modifier-free flags, fixed target
  PID, exact tag, own source PID, and down/up readback before any post. The review cap remains 16,384 UTF-16 units.
- Added the unmistakable v5 production integration seam in `ReviewSubmissionExecutor.swift`:
  `ReviewSubmissionFacade` exposes `snapshotFrontmostApplication()`, asynchronous exact-descriptor
  `captureTarget(_:completion:)` (plus a one-snapshot `captureTarget(generation:completion:)` convenience),
  `issueAttemptHandle()`, `makeAdmissionEnvelope(handle:request:)`,
  immediate `enqueueAdmission`, `enqueueStart`, `enqueueCancellation`, typed event-handler installation, and
  asynchronous `releaseCapturedTarget`. `SystemReviewSubmissionFacade` owns the value-only control plane, raw
  executor, and MainActor ticket issuer. Its relay is installed after helper initialization without capturing
  partially initialized `self`; capture returns only `CapturedReviewTargetDescriptor` and no raw AX token.
  The accepted facade does not call legacy delivery/`FinalTextOutput`, activate a target, or carry
  `ReviewDestinationToken`. It becomes effective only after the coordinator/MainViewModel integration lane wires
  the facade into production review gestures.

## Verification

Verification tier: **build-green** for the owned production files plus strict lint; full target build is blocked
by concurrent UI-lane edits outside this ownership.

Before (recorded v5 step-0 baseline):

- Focused existing output/current-focus/delivery/security tests: exit 0, 83 tests passed.
- Debug build: exit 0, `BUILD SUCCEEDED`.
- `git diff --check`: exit 0.

After:

- Strict lint on all six owned existing files plus the new executor: exit 0, 0 violations.
- `git diff --check`: exit 0.
- Focused post-change test command (`FinalTextOutputSecurityTests`, `CurrentFocusAppendSessionTests`,
  `ReviewDestinationDeliveryTests`) could not start its test bundle and exited 65 for the same two concurrent
  `MainViewModel.swift` non-exhaustive switches; no owned-file diagnostic was emitted.
- Debug build command:
  `xcodebuild -scheme FeishuSpeech -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v5-output-build8 build`
  reached compilation of all owned output/security files successfully, then exited 65 because concurrent
  `MainViewModel.swift:464` and `MainViewModel.swift:2094` switches do not yet handle the UI lane's
  `preparingSubmission` and `submittedUnverifiedTerminal` cases. Those files are outside this lane and were not
  modified.
- Compile repair follow-up: `ReviewSubmissionAttemptHandle` now keeps its stored identity private, exposes only
  internal read-only identity accessors to the control plane, and retains a fileprivate initializer used only by
  the co-located `@MainActor ReviewAttemptTicketIssuer`; the duplicate control-plane minting helper was removed.
  The executor's bounded lock-contention yield is `Thread.sleep(forTimeInterval: 0.0005)`. The build above confirms
  those owned compile errors are gone; strict lint and diff check remain exit 0.
- Facade follow-up build command:
  `xcodebuild -scheme FeishuSpeech -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v5-facade-build2 build`
  compiled the new facade, relay, control-plane event-handler API, and all other owned output/security files;
  it exited 65 only for concurrent `MainViewModel.swift:464` and `MainViewModel.swift:2094` exhaustiveness errors.
- Static accepted-path scan: no `NSPasteboard`, change-count, or Cmd+V implementation in the owned review
  delivery/executor path; only compatibility initializer labels remain in `TextInputSimulator.swift` and no
  compatibility writer performs a pasteboard operation.

No commit was created.

## Compatibility gate and combined-epoch audit (2026-08-24)

- Repaired the legacy/test `SystemReviewDestinationDelivery` binding-specific final paths to use
  `ReviewDeliveryMonitoringSession.performFinalPair`. The monitor's nonrecursive epoch reservation
  now records gate entry only; destination validation and the immediate-before-post modifier/epoch
  checks run outside that reservation, and the actual legacy pair is posted only after those checks.
  Exact and application-bound modifier transitions therefore return pre-boundary `deliveryFailed`
  with zero synthetic posts. The accepted v5 facade remains executor-only and does not regain target
  activation, pasteboard, Cmd+V, or the legacy callback path.
- Confirmed a real v5 TOCTOU in the prior gate: the shared combined epoch was sampled before the
  value-store lock, while observers advanced only the shared epoch and the local baseline could remain
  stale. The final gate now uses deadline-aware `try()` admission in fixed order (combined epoch,
  then value store), rejects an already-observed drift before any post, and holds that reservation
  through the direct down/up pair. The value baseline is refreshed from the shared epoch when a raw
  attempt is claimed. No epoch getter, monitor callback, AX validation, or arbitrary work is performed
  by the gate while the value lock is held; postflight sampling remains outside both reservations.

Current verification:

- Debug build: exit 0, `BUILD SUCCEEDED` (`/tmp/issue40-v5-epoch-build`).
- Combined-epoch/gate selectors (`test_combinedEpochDriftBeforeCommitPostsNothing`,
  `test_physicalInputAtGateOrdersAfterCompleteMandatoryPair`,
  `test_productionCommitGateCompletesBeforeDeadlineWithRealEpochAndBackend`,
  `test_productionCommitGateNeverReentersNonrecursiveEpochLock`): exit 0, all passed.
- AppKit provenance selector `test_workspaceInputMonitorExemptsTaggedSyntheticEventsAndFnTransitions`:
  exit 0, passed. Event exemption remains conjunctive exact tag plus own source PID; foreign, missing,
  zero-PID, and wrong-tag events interfere.
- Compatibility selector plus `ReviewDestinationDeliveryTests`: modifier oracle and all delivery tests
  except the pre-v5 activation-timeout compatibility expectation passed. The remaining failure is the
  old `test_systemReviewDelivery_activationTimeoutIsBoundedAndDoesNotRetarget`, which expects an
  activation call and `.activationFailed`; v5 explicitly forbids activation/retargeting and correctly
  returns the nonactivating path's submitted/identity result. No activation was restored.
- Strict lint on all owned production files: exit 0, 0 violations.
- No commit was created.

Final committer/gate rerun after the concrete production-post adjustment:

- Strict lint: exit 0, 0 violations.
- `xcodebuild -quiet -scheme FeishuSpeech -configuration Debug -derivedDataPath
  /tmp/issue40-v5-final-build2 build`: exit 0. Production `ReviewUnicodeCommitter` now uses direct
  prepared-event down/up posting; the injectable backend is retained only as a test seam and is not
  dynamically dispatched by the accepted production pair.
- Focused epoch/gate plus exact/application modifier selectors with derived data
  `/tmp/issue40-v5-epoch-tests2`: exit 0, all five passed.
- `git diff --check`: exit 0.

## Corrected cross-thread physical-input oracle repair (2026-08-24)

- Replaced the prior `NSRecursiveLock` epoch reservation with a nonrecursive `NSLock`.
- `CurrentFocusCombinedInterferenceEpoch.advance()` now increments a separate pending-advance counter
  before waiting for the commit reservation, then advances the raw epoch and clears the pending count.
  This does not call callbacks or block MainActor.
- Added the typed `CurrentFocusEpochSnapshot`/`captureSnapshot()` primitive. It samples pending state
  before and after the raw read without holding the pending and epoch locks together, avoiding lock
  inversion. Postflight stability is false if any advance was pending or if the raw value changed.
- Corrected physical-input selector now proves the observer callback contends during down, cannot advance
  before mandatory up, completes after reservation release, and reports `postflightStable == false`.
  Exact own-tag plus own-PID exemption remains unchanged.

Final corrected-oracle verification:

- Corrected physical-input selector: exit 0, passed.
- Full `FinalTextOutputSecurityTests`: exit 0, all passed.
- Full `CurrentFocusAppendSessionTests`: exit 0, all passed.
- Debug build (`/tmp/issue40-v5-final-build3`): exit 0.
- Strict lint on all owned production files: exit 0, 0 violations.
- `git diff --check`: exit 0.

Final rerun after the UI lane settled:

- `xcodebuild -quiet -scheme FeishuSpeech -configuration Debug -derivedDataPath /tmp/issue40-v5-final-build build`:
  exit 0, `BUILD SUCCEEDED` (only pre-existing Swift concurrency warnings outside this lane plus
  non-fatal actor-isolation warnings on the facade defaults).
- `xcodebuild -quiet -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath
  /tmp/issue40-v5-final-security test -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests`:
  exit 0, all FinalTextOutputSecurityTests passed.
- `xcodebuild -quiet -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath
  /tmp/issue40-v5-final-current-focus test -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests`:
  exit 0, all CurrentFocusAppendSessionTests passed.
- The combined compatibility command still reports only the pre-v5 activation-timeout expectation as
  incompatible; its modifier exact/application selector and all other ReviewDestinationDeliveryTests pass.

Integration note: the combined epoch is advanced by the existing HotKey event-tap path and by the
`WorkspaceCurrentFocusInputMonitor`/`WorkspaceCurrentFocusActivationMonitor` implementations. The
new facade itself does not instantiate the AppKit activation monitor; if the coordinator requires
activation/frontmost notifications independently of a legacy provisional-output session, that observer
ownership remains a UI/coordinator-lane wiring item rather than part of this compatibility-only repair.

## Final nonrecursive cross-thread epoch repair (2026-08-24)

- Rechecked the corrected physical-input oracle after removing the accidental legacy-epoch reference.
- `CurrentFocusCombinedInterferenceEpoch` now uses a nonrecursive `NSLock`. An observer increments a
  separate pending counter before a bounded `try()`/sleep wait for the reservation. A normal mandatory
  down/up pair releases the reservation before that bounded wait expires; if it does not, the pending
  marker is retained for the typed postflight snapshot to drain. Reservation release itself performs no
  callback or unbounded wait.
- `captureSnapshot()` is the single typed postflight stability primitive. It accounts for pending
  observer advancement before and after the raw read, and for raw-value drift. Exact own-tag plus own-PID
  synthetic events remain exempt before the observer announces its advance.

Latest verification:

- Baseline immediately before this repair: corrected selector exit 65 at
  `FinalTextOutputSecurityTests.swift:598` because the observer callback returned
  before mandatory up; the first compile attempt also exposed one accidental
  `drainPendingAdvances` reference in the legacy epoch accessor. Both were
  corrected without test changes.
- Corrected selector `test_physicalInputAtGateOrdersAfterCompleteMandatoryPair`: exit 0, passed
  (`/tmp/issue40-v5-final-physical5`).
- Full `FinalTextOutputSecurityTests`: exit 0, all passed (`/tmp/issue40-v5-final-security5`).
- Full `CurrentFocusAppendSessionTests`: exit 0, all passed (`/tmp/issue40-v5-final-current5`).
- Debug build: exit 0, `BUILD SUCCEEDED` (`/tmp/issue40-v5-final-build6`).
- Strict lint on all seven owned production files: exit 0, 0 violations.
- `git diff --check`: exit 0; no `NSRecursiveLock` remains in the owned epoch/executor files.

No tests, UI, docs, workflow, or commit were changed by this repair.

## v5 R1-R4 and security R1-R2 production repair (2026-08-24)

Implemented only in the assigned output/security files:

- `AccessibilityClient.swift`: executor-confined raw state now retains the exact
  focused AX element and decoded original `CursorTextRange` for `.exactCursor`.
  Confirmation validation restores focus and range on that captured element,
  rereads exact focus/range equality, and rechecks security and PID before pair
  construction/post. Ordinary nonsecure focused/role/selection capability misses
  produce an application-bound descriptor with no raw focus/range authority;
  secure, untrusted, malformed, or otherwise unverifiable evidence fails closed.
- `ReviewSubmissionExecutor.swift`: relevant combined-session modifiers
  (Command, Shift, Control, Option, Fn, Caps) require consecutive empty samples
  within the shared deadline and cancellation latch. A final empty modifier
  sample runs immediately before gate admission. Raw target validation is repeated
  after pair preparation, with combined-epoch baseline refresh only after the
  stabilized/validated preflight and drift rejection before final gate admission.
  The accepted facade now owns a fail-closed lifecycle observer for activation,
  termination, launch/process-generation, local/global AppKit input, and observer
  installation loss. All lifecycle/input signals advance the shared epoch; exact
  own-tag plus own-PID synthetic events remain exempt. No activation, clipboard,
  Cmd+V, retargeting, or legacy delivery path was introduced.
- `CurrentFocusAppendSession.swift`: MainActor lifecycle callbacks announce epoch
  pending state without waiting on the nonrecursive commit reservation; background
  physical observers retain bounded reservation ordering and typed postflight
  instability detection.

Static verification after this repair:

- Strict lint on the five assigned production files: exit 0, 0 violations.
- `git diff --check`: exit 0.
- No `NSRecursiveLock` in assigned output/security files.
- Accepted executor/facade scan contains no `NSPasteboard`, change-count,
  Cmd+V, activation call, or target-retargeting path.
- Per instruction, no `xcodebuild` command was run; root must serialize the
  Debug build and focused test matrix.

No tests, UI/coordinator files, docs, workflow sources, or commits were changed.

## v5 serialized-build compile repair (2026-08-24)

- `ReviewSubmissionExecutor.performRawAttempt` now resolves both the value-only
  `CapturedReviewTargetDescriptor` and the executor-confined
  `ReviewSubmissionRawTargetState`. Pair preparation uses the descriptor while
  preflight uses the raw state's descriptor/focus provenance, removing the
  descriptor/raw-state type mismatch and restoring generation/security checks.
- Workspace lifecycle observer callbacks use `MainActor.assumeIsolated` for the
  documented `.main` notification queue, preserving synchronous epoch signalling
  without actor-isolation warnings. The facade capture bridge now captures the
  MainActor facade weakly rather than a non-Sendable lifecycle protocol existential.
- Facade default arguments are nil sentinels; production runtime/committer
  construction occurs inside the MainActor initializer, removing default-argument
  actor-isolation warnings without changing injected test seams or accepted-path
  behavior.

Verification for this repair:

- Baseline serialized Debug build: exit 65, with the descriptor/raw-state errors
  and concurrency warnings recorded in `/tmp/issue40-debug-build-v5.log`.
- `swiftc -parse` on all five owned production files: exit 0.
- `swiftc -typecheck` on the executor/output dependency slice
  (`CursorTextModels`, `TextInputSimulator`, `CurrentFocusAppendSession`,
  `AccessibilityClient`, `ReviewDestinationDelivery`, and
  `ReviewSubmissionExecutor`): exit 0, with no diagnostics.
- `swiftlint lint --strict` on all five owned production files: exit 0, 0 violations.
- `git diff --check`: exit 0.
- Per root's serialization instruction, no `xcodebuild` command was run in this
  repair; root must rerun the Debug build and focused tests.

## v5 focused RED follow-up (2026-08-24)

- Fixed cancellation precedence in `ReviewSubmissionControlPlane.beginTerminalizing`.
  The terminalization transition now evaluates the latched cancellation bit while
  holding the value-store lock and returns an effective `.cancellation` failure
  before any pre-boundary fallback such as `.inputDrift`, while preserving zero
  backend posts. This covers cancellation latched while raw AX validation is
  blocked and released before the deadline.
- Audited the R4 source oracle requiring the literal `case .accessibilityTimeout`.
  The production raw AX runtime already distinguishes ordinary capability misses
  from timeout/security outcomes: `copyAttribute` and `stringAttribute` map
  `kAXErrorNoValue`/`kAXErrorAttributeUnsupported` to `.unavailable`, and capture
  maps focused `.unavailable` to `applicationBoundCurrentFocus`; failed/expired
  messaging maps to typed `.accessibilityTimeout`, while secure/unverifiable
  assessment maps to `.securityRejected`. The exact internal enum switches are
  `case .unavailable`/`case .failed`, not a synthetic `.accessibilityTimeout`
  internal case. The oracle's literal-string assertion is therefore stale; no
  no-op source marker was added to game it.

Verification for this follow-up:

- Baseline focused matrix: cancellation test returned `.notStarted(.inputDrift)`
  instead of expected `.notStarted(.cancellation)`; R4 literal-string oracle also
  failed. Full matrix had unrelated concurrent UI/coordinator failures recorded
  in `/tmp/issue40-focused-v5-r4.log`.
- Owned executor dependency `swiftc -typecheck`: exit 0.
- Strict SwiftLint on all five owned production files: exit 0, 0 violations.
- `git diff --check`: exit 0.
- Per instruction, no `xcodebuild` command was run in this follow-up.

## v5 fixed-target AX validation repair (2026-08-24)

- `SystemReviewSubmissionAXRuntime.validate` no longer creates or reads a
  system-wide AX element at confirmation. It first verifies the fixed captured
  application identity/frontmost/security and the captured application AX root
  PID, then branches by binding.
- `.exactCursor` restores the executor-confined captured element and original
  selection, and reads back focus and selection through the fixed captured
  application AX root. Ambient preview-panel/system-wide focus is not required
  to already be the target.
- `.applicationBoundCurrentFocus` reads `kAXFocusedUIElementAttribute` from the
  fixed captured application AX root, then validates the responder PID and
  editable security state. It never samples an ambient system-wide responder.
- Per-object AX messaging deadlines remain applied before every root, focus, and
  selection message.

Verification:

- Owned executor/AX dependency `swiftc -typecheck`: exit 0.
- Strict SwiftLint on all five owned production files: exit 0, 0 violations.
- `git diff --check`: exit 0.
- No tests or `xcodebuild` run, per instruction.

## v5 correctness-review R8/R9 repair (2026-08-24)

- Added opaque `ReviewSubmissionLifecycleLease` value authority and exact lease
  operations. The production observer now stores multiple lease-to-identity
  entries, advances the shared epoch for any live lease's relevant lifecycle
  event, and retires only the exact lease. The facade maps successful target IDs
  to leases, rejects stale raw success before exposing its descriptor, checks the
  lease again before admission/start, and releases only the matching target
  lease. Compatibility defaults preserve existing injected lifecycle fakes while
  tracking their exact current lease, so stale A cleanup cannot disarm B.
- Application-bound validation now preserves ordinary unavailable focused
  responders and ordinary role/subrole capability misses as approved fallback;
  failed/malformed/timeout and secure/unverifiable outcomes remain fail closed.
- Added an attempt-scoped cancellation probe to the raw validation API. The
  production AX runtime checks it after every synchronous fixed-root PID, focus
  setter, selection setter, focus readback, selection readback, and role/subrole
  message before continuing. Exact validation returns `.cancellation` before
  any subsequent AX mutation, readback, pair construction, or post.
- Moved the second raw target validation and a combined-epoch pre-pair gate before
  Unicode pair preparation, so lifecycle drift rejects with zero backend work.

Focused RED verification:

- Initial five-selector command in `/tmp/issue40-focused-v5-r8-r9-final.log`:
  exit 65; ordinary fallback, exact/application validation source, and both
  lifecycle lease selectors passed; lifecycle overlap initially exposed pair
  preparation before the post-validation epoch check, and the legacy raw
  cancellation test double continued its uninterrupted synchronous sequence.
- After the pre-pair gate, the lifecycle overlap recheck in
  `/tmp/issue40-focused-v5-r8-r9-recheck.log`: exit 65 overall because the
  cancellation selector remained the sole failure; lifecycle overlap passed.
- The remaining cancellation failure is confined to the existing test double's
  old `validate(target, deadline)` implementation: it blocks after recording
  `.setFocused`, ignores the new cancellation-probe overload, and records
  `.setSelectedRange`/`.readback` after the test resumes it. Production's
  `SystemReviewSubmissionAXRuntime` uses the new probe and checkpoints after
  each AX message. Preventing an arbitrary legacy synchronous implementation
  from mutating after cancellation would require escaping raw target state to a
  second queue or editing/migrating the test double, neither of which is allowed
  by the owner contract.

Static verification after final repair:

- Owned output dependency `swiftc -typecheck`: exit 0.
- Strict SwiftLint on all five owned production files: exit 0, 0 violations.
- `git diff --check`: exit 0.
- No tests, UI/coordinator, docs, workflow, or test files were edited.

## v5-r3 pair/final-composite/AX-checkpoint repair (2026-08-24)

Production changes are confined to the owned output/security lane:

- `AccessibilityClient.swift` now exposes a value-only `ReviewAXStepID` /
  `ReviewAXResultCategory` observer seam (with compatibility aliases) and
  injectable `ReviewAXSecuritySamples`. `SystemReviewSubmissionAXRuntime`
  runs every timeout, copy/get/set, AXValue construction/readback, and
  security sample through cancellation/deadline checkpoints; the observer
  runs after the synchronous operation and before the next message. No AX
  object, event, draft, or target token crosses the seam.
- Validation is a leading security/trust/identity/frontmost composite, the
  binding-specific fixed-target AX sequence, and a trailing complete security
  composite. Ordinary application-bound noValue/unsupported misses remain
  provisional and are accepted only after the trailing composite; exact
  misses remain fail closed.
- `ReviewSubmissionExecutor.swift` constructs/readbacks one immutable pair,
  then invokes the final composite before every epoch/value-lock reservation
  attempt. Reservation contention retries the composite without rebuilding
  the pair. Every pre-boundary failure explicitly discards the pair through a
  compatibility-safe backend discard hook and performs zero posts.
- `processStart` now retires an admitted exact record and clears the matching
  active handle under the value-store lock when its immutable deadline has
  expired, then emits exactly one `.terminal(.notStarted(.deadline))` outside
  the lock without invoking raw start work.

Verification:

- Baseline r3 RED receipts: pair/final-composite selectors reported 3 tests /
  24 failures in `/tmp/issue40-r3-pair-red3.ohv3B0`; expired-start reported a
  missing terminal and retained active record in `/tmp/issue40-r3-expired-start-red.TOWuq0`.
- Pair/final-composite GREEN command: exit 0, 3 tests / 0 failures;
  receipt `/tmp/issue40-r3-pair-green/Logs/Test/Test-FeishuSpeech-2026.08.24_16-29-26-+0800.xcresult`.
- Expired-start GREEN command: exit 0, 1 test / 0 failures;
  receipt `/tmp/issue40-r3-expired-green/Logs/Test/Test-FeishuSpeech-2026.08.24_16-29-44-+0800.xcresult`.
- Existing exact cancellation checkpoint selector: exit 0, 1 test / 0
  failures; receipt `/tmp/issue40-r3-cancel/Logs/Test/Test-FeishuSpeech-2026.08.24_16-34-59-+0800.xcresult`.
- Debug build with code signing disabled: exit 0 (`/tmp/issue40-r3-owned-finalbuild2`).
- Strict SwiftLint on both changed output files: exit 0, 0 violations.
- `git diff --check`: exit 0.
- No tests, UI/coordinator, docs, workflow, recording, or recognition files
  were edited. Accepted output code contains no pasteboard or Cmd+V path and
  no activation/retarget operation.

Final serialized output/security verification after the last code change:

- `xcodebuild ... -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests test`:
  exit 0, 63 tests / 0 failures; receipt
  `/tmp/issue40-r3-full-security/Logs/Test/Test-FeishuSpeech-2026.08.24_16-36-58-+0800.xcresult`.
- Debug build with `CODE_SIGNING_ALLOWED=NO`: exit 0 (`/tmp/issue40-r3-final-verify`).
- Strict SwiftLint on `AccessibilityClient.swift` and
  `ReviewSubmissionExecutor.swift`: exit 0, 0 violations.
- `git diff --check`: exit 0.

## v5-r4 exact focus readback cancellation repair (2026-08-24)

R4 review found that exact focus readback called the AX focused-element copy
helper without the live attempt cancellation probe. The helper's former
default `{ false }` could therefore allow one validation-critical AX message
after cancellation latched between restoration and readback. The production
repair passes the live `cancellationProbe` and immutable `deadline` through
`validateExactFocusReadback` into `copyAttribute`.

The validation-sensitive AX helper signatures now require an explicit probe;
capture-only paths use explicitly named capture helpers and `{ false }`, while
all executor exact/application validation calls carry the live probe. A source
audit found no remaining default probe on `copyAttribute`, `attributeSettable`,
`selectedRange`, or `stringAttribute`; the only remaining false probes are
capture-only or the compatibility overload that is not used by the production
executor.

Verification:

- R4 RED baseline: exact readback cancellation selector reported 1 test / 2
  failures (focused-element copy observed after cancellation); the executor
  stop selector reported 1 failure; reachable exact/application cancellation
  matrix was already 1 test / 0 failures.
- Focused R4 selectors after repair: exit 0, 2 tests / 0 failures; receipt
  `/tmp/issue40-r4-focused-green/Logs/Test/Test-FeishuSpeech-2026.08.24_17-26-47-+0800.xcresult`.
- Reachable cancellation/deadline matrix: exit 0, 1 test / 0 failures;
  receipt `/tmp/issue40-r4-step-matrix-green/Logs/Test/Test-FeishuSpeech-2026.08.24_17-27-05-+0800.xcresult`.
- Full `FinalTextOutputSecurityTests`: exit 0, 68 tests / 0 failures; receipt
  `/tmp/issue40-r4-full-security/Logs/Test/Test-FeishuSpeech-2026.08.24_17-28-17-+0800.xcresult`.
- Debug build with `CODE_SIGNING_ALLOWED=NO`: exit 0, `** BUILD SUCCEEDED **`;
  derived data `/tmp/issue40-r4-typecheck`.
- Strict SwiftLint on `AccessibilityClient.swift` and
  `ReviewSubmissionExecutor.swift`: exit 0, 0 violations.
- `git diff --check`: exit 0.
- No tests, UI/coordinator, docs, workflow, recording, or recognition files
  were edited in this R4 repair.

## v5-r5 late AX deadline classification repair (2026-08-24)

The fixed-inventory System AX matrix exposed nine late deadline injections
that were being collapsed into `.failed` and then reported as
`.securityRejected`: exact `messagingTimeout#5`, `copyAttribute#1`,
`messagingTimeout#6`, `getSelectedRange#1`, `readAXValue#1`,
`messagingTimeout#7`, `role#1`, `messagingTimeout#8`, and `subrole#1`.

`AXElementRead`, `AXRangeRead`, `AXStringRead`, and `AXSettableRead` now carry
an explicit `.deadline` case through timeout and post-message checkpoints.
`EditableAssessment` also preserves `.deadline`; exact focus/selection
readback, exact editable-state validation, application-bound responder
validation, and capture-only classification map it to
`.accessibilityTimeout`. Cancellation remains checked and returned before
deadline, actual malformed/secure/unverifiable failures remain security
rejections, and application-bound ordinary no-value/unsupported misses still
return the approved fallback.

The deadline mapping was then extracted into equivalent private helpers to
keep strict cyclomatic-complexity lint clean; no behavior or accepted-path
surface was otherwise changed.

R5 RED baseline:

- Fixed inventory matrix: 1 test / 9 failures, all nine late cases above
  reported `.securityRejected` instead of `.accessibilityTimeout`.
- Late-readback selectors: 2 tests / 0 failures.
- Full `FinalTextOutputSecurityTests`: 68 tests / 9 failures, exactly the
  same nine classification failures.

Final verification after repair and lint refactor:

- Fixed exhaustive inventory matrix: exit 0, 1 test / 0 failures; receipt
  `/tmp/issue40-v5-r5-step-matrix-final.xcresult`.
- Two late-readback selectors: exit 0, 2 tests / 0 failures; receipt
  `/tmp/issue40-v5-r5-readback-final.xcresult`.
- Full `FinalTextOutputSecurityTests`: exit 0, 68 tests / 0 failures; receipt
  `/tmp/issue40-v5-r5-full-security-final.xcresult`.
- Strict SwiftLint on `AccessibilityClient.swift`: exit 0, 0 violations.
- `git diff --check`: exit 0.
- `xcrun swiftc -frontend -parse FeishuSpeech/Services/AccessibilityClient.swift`:
  exit 0.
- No tests, UI/coordinator, docs, workflow, recording, or recognition files
  were edited in this R5 repair.
