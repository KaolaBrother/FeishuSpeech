# Issue #40 v5 Architecture Blueprint

## 0. Status, objective, and evidence

- **Status:** approved repair design for the owner-rejected installed candidate at
  `b321ac5d6c04c91ced9afeb2240f9566d9b8d305`.
- **Implementation baseline:**
  `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`.
- **Objective:** keep the application that owned the user's original insertion target active while a
  nonactivating FeishuSpeech preview becomes the key/editor receiver; authorize exactly one fixed-target
  Unicode submission attempt only from the preview's real Send action or qualified local Return/Enter.
- **This file is architecture only.** Production, tests, product docs, Release installation, and issue
  closure remain separate workflow tasks.

Measured installed-runtime evidence:

- `/tmp/FeishuSpeech_2026-08-24_084734_25BZ.sample.txt` sampled PID `99976` 2,620 times.
- Every main-thread sample was blocked in
  `MainViewModel.handleReviewConfirmation -> SystemReviewDestinationDelivery.deliver ->
  ReviewDeliveryMonitoringSession.performFinalPair ->
  WorkspaceCurrentFocusInputMonitor.postCompleteSyntheticPairIfInterferenceEpochIsUnchanged ->
  CurrentFocusInputMonitoring.interferenceEpoch.getter -> NSLock` (sample lines 23-40).
- The hot-key tap thread simultaneously waited in
  `CurrentFocusInputInterferenceEpoch.observePreDispatch -> NSLock` (sample lines 52-72).
- Source matches the sample: `CurrentFocusInputInterferenceEpoch.performIfUnchanged` holds its private
  `NSLock` while invoking an arbitrary closure, and that production closure reads the same epoch through
  `WorkspaceCurrentFocusInputMonitor.interferenceEpoch`. `NSLock` is nonrecursive; the main thread
  self-deadlocks before either Unicode event is posted.
- The old `activationLock` does not serialize with
  `WorkspaceCurrentFocusActivationMonitor.epochLock`, so it supplies no atomic activation guarantee and
  must not be preserved as a purported proof.

The rejected candidate therefore fails two user-visible acceptance points:

1. Send enters `confirming`/"正在发送…" and never returns.
2. Plain Return is available only when the native text editor is first responder, while the v4 focus
   attempt was treated as telemetry and explicitly activated FeishuSpeech. That focus model conflicts
   with the user's original active target.

## 1. Non-negotiable v5 boundary

Before explicit confirmation, all speech paths may capture/read state and render/edit local preview
state, but may not perform any target mutation or output:

- no `CGEventPost`/`CGEventPostToPid`;
- no AX setter, focus/caret restoration, selected-text mutation, or target activation;
- no pasteboard read, write, snapshot, restore, copy, or paste;
- no synthetic character, key, mouse, Return, or other target signal;
- no delivery call, output retry, retarget, or automatic confirmation.

The only two confirmation gestures are:

- the real visible Send button in the current editable preview; and
- exact unmodified, nonrepeating main Return/keypad Enter routed locally by the current key preview, with
  the native editor's IME and multiline rules satisfied.

The Fn release, final recognition action 2, and recorder barrier remain independent facts. A durable
draft can become confirmation-capable only when action 2 and the recorder barrier have both completed
for the same generation. No recognition timeout, partial result, focus event, view render, error path,
or lifecycle callback may mint confirmation authority.

Confirmation authorizes one attempt to the originally captured target. It never authorizes selection
of whatever application happens to be frontmost later.

## 2. AppKit focus topology

### 2.1 Local SDK contract

The installed macOS 26.5 SDK supplies the required primitive without a dependency:

- `NSWindowStyleMaskNonactivatingPanel` is documented in
  `AppKit.framework/Headers/NSWindow.h:39-67` as a panel that does not activate its owning application.
- `NSPanel` exposes `becomesKeyOnlyIfNeeded` in
  `AppKit.framework/Headers/NSPanel.h:13-17`.
- `NSWindow` separately exposes `isKeyWindow`, `canBecomeKeyWindow`, and `makeKeyWindow` in
  `AppKit.framework/Headers/NSWindow.h:435-445`.

These are distinct concepts and v5 must model them separately:

```text
targetFrontmostIdentity
    NSWorkspace.shared.frontmostApplication == captured target

previewKeyReceiver
    ReviewPanel.isKeyWindow == true
    ReviewPanel.firstResponder == editable NSTextView

FeishuSpeechActivation
    NSRunningApplication.current.isActive == false
```

A valid editable presentation proves all three simultaneously. The target application remains the
active/frontmost application underneath; the nonactivating panel receives keyboard input without
making FeishuSpeech the active application.

### 2.2 ReviewPanel construction

Create the panel with the nonactivating style at initialization; do not add/remove the style after a
WindowServer window exists:

```text
styleMask = [.titled, .closable, .resizable, .nonactivatingPanel]
isFloatingPanel = true
becomesKeyOnlyIfNeeded = true
hidesOnDeactivate = false
canBecomeKey = allowsKeyInteraction
canBecomeMain = false
```

Read-only streaming/sealing behavior remains non-key and mouse-transparent. When the current generation
becomes editable:

1. install the real editor and callbacks;
2. set `allowsKeyInteraction = true` and `ignoresMouseEvents = false`;
3. call `makeKeyAndOrderFront` on the panel, never
   `NSRunningApplication.current.activate` and never `NSApp.activate`;
4. materialize/layout the hosting view;
5. make the native editor first responder; and
6. prove panel key/editor first-responder status while the captured target is still frontmost and
   FeishuSpeech is still inactive.

`ReviewPresentationFocusOutcome` is presentation evidence, not confirmation authority. Its result may
control a focus hint and telemetry but may not mutate the draft, call delivery, dismiss the panel, or
create a confirmation permit.

### 2.3 WindowServer fallback

Unit/AppKit tests establish the local contract; the installed Release must separately prove the actual
WindowServer behavior. If the installed environment cannot make the nonactivating panel key with the
editor first responder while preserving target-frontmost identity:

- keep the preview and visible Send button available for a real click;
- show a concise local focus hint if needed;
- do not activate FeishuSpeech as a fallback;
- do not install a global Return monitor;
- do not capture or suppress Return typed in the target application; and
- do not deliver until a real Send click or an already-qualified preview-local Return creates intent.

A future dedicated shortcut may be designed separately, but v5 adds none. Visible Send is the bounded
fallback. Target Return always belongs to the target.

## 3. Target contract

### 3.1 Capture

At accepted Fn start, MainActor snapshots only a Sendable application identity descriptor and asks the
dedicated `ReviewSubmissionExecutor` to capture one immutable target. The executor creates, owns, uses,
and releases every raw `AXUIElement`; no raw AX object crosses back to MainActor:

```text
ReviewTargetCaptureRequestDescriptor (Sendable)
    generation
    stable application identity descriptor
    captureUptime

CapturedReviewTargetDescriptor (Sendable; MainActor-visible)
    targetID: CapturedReviewTargetID
    generation: UInt64
    application: StableApplicationIdentity
        pid + bundleIdentifier + executableURL + launchDate
    binding:
        exactCursor
        | applicationBoundCurrentFocus
    securityAtCapture: safe

Executor-owned CapturedReviewTargetState (never Sendable; never escapes executor)
    descriptor
    raw application AXUIElement
    raw captured cursor/focused AXUIElement when exact
    original selection/focus facts
    process-generation observation
```

Capture has its own executor-owned 500 ms absolute capture deadline beginning at `captureUptime`; queue wait
and every capture AX message spend that same budget. Submission later has the separate two-second permit
deadline defined below. Both deadlines and all raw capture/submission objects remain in the same executor
ownership domain.

The target is captured before FeishuSpeech shows or keys the preview. No later frontmost application may
replace it. `CapturedReviewTargetID` is an opaque random identifier, not a PID alias. MainActor may retain
the descriptor and ID for authority checks and UI-neutral telemetry, but cannot dereference or mutate the
executor-owned target.

### 3.2 Exact cursor and application-bound fallback

The owner-authorized v5 policy retains the existing application-bound fallback only under all existing
proofs:

- same positive PID;
- exact stable application identity, including launch date;
- captured application remains running and frontmost;
- Secure Input is disabled at every preflight sample;
- Accessibility trust remains available where required;
- the combined interference epoch has not drifted since the final baseline; and
- no target mutation occurred before confirmation.

For `exactCursor`, post-confirmation preflight may restore/validate only the captured cursor. For
`applicationBoundCurrentFocus`, v5 may address only the captured PID's current responder while that same
captured application remains frontmost. It must never use an ambient/new PID and must never silently
retarget.

Every raw target lookup, including each newly created system-wide/application/focused AX object, is created
and messaged only on the submission executor. Before **every** AX message, the executor sets that exact
object's messaging timeout to `min(500 ms, remaining positive budget)` for the active capture or submission
deadline. A timeout set on a captured element is not inherited by a fresh system-wide object or even
another equal AX object. If no positive budget remains, the executor makes no AX call and returns capture
timeout or terminalizes the admitted permit as `notStarted(.deadline)`.

If any identity, frontmost, security, or binding proof fails, the attempt ends before Unicode key-down,
the exact draft is retained, and the preview becomes editable/key again. Application-bound fallback is
not a fallback to a different application or restarted process.

## 4. Authority types

The existing structures should be narrowed into the following responsibilities. Names may be adjusted
to existing conventions, but authority must not be collapsed.

### 4.1 `ReviewDraftAuthority`

```text
reviewID
generation
capturedTargetDescriptor + capturedTargetID (Sendable only)
terminalRecognitionProof(action2, generation)
recorderBarrierProof(generation)
draft(text, possiblyIncomplete, feedback)
revision
nextAttemptOrdinal
```

Only the action-2-plus-recorder-barrier convergence path may populate both proofs and publish an ordinary
`.editable` state.

### 4.2 `ReviewConfirmationIntent`

Opaque UI capability with a fileprivate initializer in `TranscriptionReviewView.swift`:

```text
source = sendButton | qualifiedPreviewReturn
```

It contains no draft, PID, target, generation, or mutable state. Only real production UI gesture sites
can construct it.

### 4.3 Admission envelope, handle, and one-shot permit

One real intent creates one immutable value-only admission envelope. MainActor performs only local value
work: it freezes the request, computes the one absolute deadline by checked monotonic addition, creates and
stores the exact opaque ticket, and then nonblocking-enqueues the envelope to a dedicated fast control-plane
context. It never touches or waits for the commit lock, raw executor, or target registry:

```text
ReviewSubmissionRequestDescriptor (Sendable)
reviewID
generation
revision
attemptOrdinal
frozenDraft
capturedTargetID
confirmationUptime

ReviewSubmissionAttemptHandle (Sendable; opaque)
controlPlaneInstanceNonce + never-reused attemptID

ReviewSubmissionAdmissionEnvelope (Sendable; immutable)
exact handle
exact request descriptor
absolute preBoundaryDeadline = confirmationUptime + 2 seconds

CancellationSignalResult (Sendable)
latched | observedAfterBoundary | notCurrent

AdmissionResult (Sendable)
accepted | rejected(reason)
```

`ReviewAttemptTicketIssuer` is MainActor-confined value state initialized with the control plane's immutable
process-instance nonce. It advances a checked `UInt64` counter synchronously on MainActor and never reuses
an ID within that nonce; overflow fails closed. Creating/storing a handle therefore needs no lock, queue hop,
raw reference, or awaited/interleavable point. The handle initializer is internal to this issuer, so views
and target applications cannot forge tickets.

Required guards before construction:

- current review ID and generation;
- exact callback revision;
- both terminal-recognition and recorder-barrier proofs;
- `.editable` state;
- nonempty, safe text at most 16,384 UTF-16 code units;
- no existing permit/delivery task for this authority; and
- destination generation equals authority generation.

The public API is direct nonblocking enqueue plus asynchronous typed events, not a synchronous queue/lock
call and not an unstructured `Task` whose scheduling could reorder commands:

```text
controlPlane.enqueueAdmission(ReviewSubmissionAdmissionEnvelope)  // returns immediately
controlPlane.enqueueStart(ReviewSubmissionAttemptHandle)           // returns immediately
controlPlane.enqueueCancellation(ReviewSubmissionAttemptHandle)    // returns immediately
controlPlane.enqueueRawCleanupComplete(handle, TerminalCleanupValue) // internal; returns immediately

ReviewSubmissionControlEvent (Sendable)
admissionAccepted(handle) | admissionRejected(handle, reason)
cancellationResolved(handle, CancellationSignalResult)
terminal(handle, ReviewCommitReceipt)

TerminalCleanupValue (Sendable; internal)
handle + exact notStarted/submittedUnverified receipt payload; no raw reference
```

MainActor first sets `admissionPending`, creates/stores its sole current handle and frozen envelope, and only
then calls `enqueueAdmission`; there is no `await` or callback between those operations. A close, Escape, or
lifecycle callback can therefore always enqueue cancellation for the exact handle. Calls made from the same
MainActor context use direct `DispatchQueue.async` submission to the one serial control context, so admission,
start, and cancellation are FIFO in caller invocation order. The control plane emits events asynchronously
to MainActor; MainActor never waits for an event or queue drain.

The control plane accepts admission only if the handle nonce/ID matches its issuer contract, the immutable
absolute deadline has not elapsed, and its lock-protected store has no active record. Expired admission
terminalizes as `notStarted(.deadline)` without raw enqueue. MainActor's `admissionPending/currentHandle`
fence also rejects duplicate gestures before enqueue. Thus async admission completion cannot create sibling
permits: a duplicate queued envelope is rejected by the store, and a new real gesture is not locally
admissible until the prior terminal event. Queue delay spends the immutable deadline already present in the
envelope; no layer reconstructs or renews it.

Only after MainActor receives `admissionAccepted(handle)`, proves the handle is still current and no local
cancellation intent is pending, may it enqueue `start(handle)`. If cancellation was invoked after admission
enqueue but before this event is applied, MainActor enqueues cancellation and never enqueues start. FIFO
control processing terminalizes that unclaimed record as `notStarted(.cancellation)` with zero raw-executor
work. If a late start is nevertheless queued, the exact phase/cancellation check rejects it.

MainActor retains the handle, frozen envelope, and noneditable authority until the matching terminal event.
It has no independent timeout task. It may restore `.editable` or admit a later request only after terminal
cleanup proves that the old record, claimed permit, raw pair, and source can no longer reach key-down.

### 4.4 Value-only control record and cancellation linearization

`ReviewSubmissionControlPlane` owns a dedicated non-MainActor serial context and one store whose records are
protected by the same nonrecursive attempt/commit lock used at the final boundary. A record is pure Sendable
value state and is the sole pre-claim permit metadata:

```text
ReservedAttemptControlRecord (lock-protected; value-only)
controlPlaneInstanceNonce
never-reused attemptID
exact immutable ReviewSubmissionRequestDescriptor
exact immutable absolutePreBoundaryDeadline
phase = admitted | startQueued | claimed | preparing | committing | boundaryCrossed | terminalizing | terminal
cancellationRequested = false | true
```

The record contains no `AXUIElement`, `CGEvent`, event source, posting backend, closure/continuation, target-
registry entry, or reference to raw serial state. The control context is the sole processor of admission,
start, and cancellation commands. The raw executor may access this store only through concrete lock-owned
claim/check/phase/terminal operations; it never accesses the control queue itself. This shared lock-protected
value cell is therefore not raw-executor state and does not violate raw serial confinement.

`enqueueCancellation(handle)` returns immediately on MainActor. Its queued operation may synchronously wait
for the commit lock **only on the dedicated control context**, compares nonce plus exact attempt ID, and
linearizes one of these outcomes:

- if the exact attempt is in an output-capable pre-boundary phase, set its raw
  `cancellationRequested` bit and return `latched`;
- if its phase is `boundaryCrossed`, record only `observedAfterBoundary` and return that advisory result;
- if it is already `terminalizing` with no remaining post authority, terminal, stale, foreign, or no longer active,
  return `notCurrent` without mutating anything.

Cancellation never queues behind occupied AX/preparation work on the raw serial executor. It can wait behind
the commit section only on the control context while MainActor remains live. If commit owns the lock and
crosses down first, cancellation is post-boundary advisory; if cancellation acquires the lock and sets the
bit first, the final gate must reject down. Caller initiation or enqueue time alone does **not** outrank a
commit already lock-linearized. No arbitrary work may lengthen the lock hold.

On `start`, the control context marks only the matching uncancelled admitted record `startQueued`, then
nonblocking-enqueues its handle to the raw executor. When that handle reaches the raw serial context, the raw
executor first acquires the commit lock, rejects foreign/stale/cancelled/wrong-phase handles, changes the
exact record to `claimed`, and copies its immutable request descriptor and absolute deadline. It then
releases the lock and validates `capturedTargetID` against its own serial-confined target registry **before**
any AX setter/mutation, exact-cursor restoration, event-source/event construction, or preparation. It never
accepts a replacement descriptor and never recomputes or renews the deadline.

After claim, the active raw attempt briefly takes the same lock to check exact ID, phase, deadline, and
cancellation after **every** synchronous dependency return and before starting the next step. During gate
admission, every successful lock acquisition reads those raw value fields before doing anything else; a
failed `try()` cannot hide a cancellation because cancellation cannot itself linearize until the lock is
free. Inside final commit there is no getter: the committer compares record fields directly alongside the
combined epoch immediately before down.

Cancellation before down terminalizes as `notStarted(.cancellation)`. For a claimed attempt, the raw executor
first destroys every prepared event/source and other post-capable object, then nonblocking-enqueues a
Sendable cleanup-complete value to the control context. That context retires the exact record and only then
emits the terminal event. An unclaimed cancelled record is terminalized by the control context with zero raw
work. Cancellation after down cannot suppress mandatory up, turn the outcome into `notStarted`, re-expose
Send, or authorize retry; it contributes only to terminal `submittedUnverified` uncertainty.

### 4.5 `PreparedReviewUnicodePair`

Opaque executor-confined output capability produced only after post-confirmation preflight. Its raw
`CGEvent` handles never cross an actor, queue, continuation, MainActor boundary, or public protocol:

```text
fixedTargetPID
exact frozen UTF-16 payload
modifier-free keyDown and keyUp from one private event source
exact FeishuSpeech tag
own source PID
readback proof for phase, payload, flags, tag, source PID, and target PID
```

No construction failure may post either event.

### 4.6 `ReviewCommitReceipt`

```text
notStarted(PreBoundaryFailure)
submittedUnverified(PostBoundaryObservation)
```

`PreBoundaryFailure` includes the exact case `.cancellation`, deadline, target identity/frontmost loss,
security rejection, modifier instability, input/activation drift, AX timeout/failure,
construction/readback failure, and gate rejection.

`PostBoundaryObservation` records whether mandatory key-up was attempted, whether cancellation was observed
after down, and whether postflight was stable. Any cancellation observed after down makes the terminal
outcome uncertain. It never claims target consumption because `CGEventPostToPid` is void and supplies no
receipt.

## 5. State machine

```text
idle
  -> pendingFn
  -> recording/streaming(read-only preview)
  -> sealing(Fn released; no confirmation authority)

sealing
  -- action2 + recorder barrier, same generation -->
editablePreview(key receiver, target remains frontmost, draft authority)

editablePreview
  -- edit --> editablePreview(new revision)
  -- discard/close/Escape --> idle
  -- real Send or qualified preview Return --> preparingSubmission(controlAdmissionPending; one local handle)

preparingSubmission
  -- async admission reject/deadline --> editablePreview(exact draft; handle retired)
  -- admission accepted + same current uncancelled handle --> rawStartQueued(one control record)
  -- cancellation before raw claim --> notStarted(.cancellation; zero raw work) --> editablePreview

rawStartQueued/preparingSubmission
  -- foreign/stale/wrong phase/target mismatch --> editablePreview(zero raw mutation/preparation)
  -- claim exact descriptor/deadline --> rawPreparing

rawPreparing
  -- cancel/deadline/identity/security/focus/AX/modifier/gate failure before down -->
     editablePreview(exact frozen draft + typed feedback + preview refocus)
  -- prepared pair + all final gates valid --> committing

committing
  -- rejected before keyDown --> editablePreview
  -- keyDown call attempted = irreversible character-submission boundary -->
     mandatory keyUp call attempted synchronously --> submittedUnverifiedTerminal

submittedUnverifiedTerminal
  -- no ordinary Send/Return capability --> dismiss/idle according to product presentation
```

MainActor applies an admission/cancellation/terminal event only when its handle, review ID, generation, and
revision match the retained current authority. A foreign/stale test event is recorded without mutating the
current preview. Internal control/raw phases remain one visible `.preparingSubmission` UI state.

The approved one-time-send policy is: after a complete down/up attempt, dismiss the ordinary editable
preview and return the hot-key axis to idle. Keep content-free telemetry/recovery evidence, but do not
re-expose ordinary Send or Return. Any post-boundary fault remains terminal submitted-unverified; it does
not become a retryable `.editable` state.

## 6. Non-reentrant submission gate

### 6.1 Rejected API

Delete the final-review use of this shape:

```text
postCompleteSyntheticPairIfInterferenceEpochIsUnchanged(expectedEpoch, arbitraryClosure)
```

No synchronization primitive may invoke arbitrary caller work that can call an epoch getter, monitor,
activation sampler, coordinator, or itself.

### 6.2 Required gate

Use two explicit confinement domains:

1. `ReviewSubmissionControlPlane`, a dedicated fast non-MainActor serial context for FIFO value-only
   admission/start/cancellation commands and typed control events; and
2. `ReviewSubmissionExecutor`, a different private serial context that alone owns the target registry, raw
   AX objects, raw event source/CGEvents, prepared pair, epoch baseline, and fixed production posting backend
   from capture through terminal cleanup.

They share only the section 4.4 value-only record store and combined epoch under the attempt/commit lock.
The control plane has no raw reference; the raw executor cannot synchronously dispatch to or wait on the
control queue. MainActor exchanges only Sendable envelopes/IDs/opaque handles/events/receipts and waits on
neither context.

The executor owns a narrow concrete gate/committer. There is no protocol callback inside the gate:

```text
ReviewSubmissionExecutor.capture(SendableCaptureDescriptor)
    -> CapturedReviewTargetDescriptor

ReviewSubmissionControlPlane.enqueueAdmission(ReviewSubmissionAdmissionEnvelope)
    -> immediate return; later ReviewSubmissionControlEvent

ReviewSubmissionControlPlane.enqueueStart(ReviewSubmissionAttemptHandle)
    -> immediate return

ReviewSubmissionControlPlane.enqueueCancellation(ReviewSubmissionAttemptHandle)
    -> immediate return; later typed cancellation/terminal event

internal ReviewSubmissionControlPlane.enqueueRawCleanupComplete(handle, TerminalCleanupValue)
    -> immediate return; later terminal event after FIFO control processing

ReviewSubmissionExecutor.release(CapturedReviewTargetID)
    -> terminal cleanup acknowledgement

executor-confined ReviewUnicodeCommitter.prepare(
    frozenDraft,
    fixedPID,
    absoluteDeadline
) -> PreparedReviewUnicodePair | failure

ReviewUnicodeCommitter.commit(
    preparedPair,
    attemptID,
    expectedCombinedEpoch,
    absoluteDeadline
) -> ReviewCommitReceipt
```

Production behavior:

1. MainActor stores the exact locally issued handle and immutable envelope, then nonblocking-enqueues
   admission. The control context FIFO-admits one value record or asynchronously rejects it; accepted start
   is a later FIFO command and only enqueues the handle to raw execution.
2. The raw executor claims/copies the exact record under the commit lock, then validates its captured target
   ID against the raw serial registry. Foreign/stale/cancelled/wrong-phase handles or target mismatch produce
   zero AX mutation/preparation. The copied descriptor and deadline must byte/value-equal the admitted
   envelope and are never reconstructed.
3. On the raw serial executor, check the exact attempt cancellation latch after every synchronous return,
   including monitor installation, modifier samples/sleeps, AX timeout-setting calls, every AX copy/set
   message, target/security/process samples, event-source/event construction, every event-field set, and
   every readback call. A multi-call helper such as preparation must expose a cancellation checkpoint after
   each underlying synchronous return rather than only after the helper returns.
4. Check cancellation immediately before combined-epoch baseline capture. A cancellation already latched
   cannot be absorbed into a new expected baseline.
5. Check cancellation immediately before and after prepared-pair construction/readback. If latched, destroy
   any raw pair without posting.
6. Use deadline-aware lock admission. Do not call an unbounded `lock()`: repeatedly use bounded `try()`
   admission against monotonic uptime (with a short scheduler yield/backoff). On each successful acquisition,
   read the exact attempt's raw cancellation bit before deciding whether to release/retry or enter commit;
   after the queued cancellation operation lock-linearizes `latched`, no later acquisition may miss it. Stop on
   cancellation or deadline.
7. Once the nonrecursive attempt/commit critical section is owned, immediately read raw state directly:
   current monotonic uptime, exact attempt ID/phase and cancellation latch, and combined epoch.
8. If cancellation is latched, deadline elapsed, attempt ID/phase is stale, or combined epoch differs, mark
   `terminalizing` under the lock so no later commit can claim authority, unlock, destroy all post-capable
   state, then enqueue a value-only cleanup-complete command. The control context terminalizes/retires the
   record and only afterward emits the corresponding `notStarted` terminal event with zero posts. A
   cancellation branch uses exactly `notStarted(.cancellation)`.
9. If all are valid, call the fixed private backend's key-down post exactly once and atomically set that
   attempt phase to `boundaryCrossed` under the same lock.
10. Attempt key-up synchronously exactly once regardless of cancellation/fault state after down.
11. Leave the critical section.
12. Perform postflight observation outside the lock, destroy/release the raw prepared pair, then
    nonblocking-enqueue only the Sendable postflight value to the control context. After all earlier FIFO
    cancellation commands have resolved, that context marks/retires the value record terminal exactly once
    and asynchronously delivers the terminal event to MainActor. The raw executor never waits for this queue.

Every `notStarted` branch follows the same terminal ordering: no raw prepared pair/source remains capable of
posting, the permit is terminal, the attempt-specific control mapping is retired, and only then is its
receipt exposed to MainActor. This ordering is the proof that coordinator re-enable cannot overlap an old
live post capability. A later cancellation carrying the retired handle returns `notCurrent` and cannot
mutate the next attempt.

The commit path has no callback parameter and performs no cancellation getter, epoch getter,
target/application getter, modifier sampler, validation, event construction/readback, logging, protocol
dispatch, async hop, UI callback, continuation resume, or allocation while the lock is held. The only work
under the lock is direct raw attempt-ID/phase/cancellation/deadline/epoch comparison, direct concrete
`CGEventPostToPid` calls for down then mandatory up, phase bookkeeping, and unlock.

“Executor owns every raw CGEvent” means every event source/event created for submission. A physical event
tap still receives the OS-owned raw event callback-scoped in `HotKeyService`; it classifies provenance there,
does not retain or transfer the raw event, and sends only a Sendable interference signal to the combined
epoch.

### 6.3 Combined interference epoch

Replace the final-review input-only epoch with one monotonically advancing combined epoch. Before the
submission baseline it installs all required observation; after the baseline, any of these signals advances
the same raw value:

- interfering physical keyboard, mouse, drag, or relevant modifier input;
- target activation/frontmost change, including programmatic application activation;
- captured target termination;
- captured process-generation/identity change, including a newly observed launch identity for the PID;
- failure/loss of an activation, termination, process, AppKit, or event-tap observer; and
- event-tap disabled-by-timeout or disabled-by-user-input loss of observability.

The event-tap callback classifies synthetic output before epoch admission. Only an event carrying the exact
FeishuSpeech tag **and** `eventSourceUnixProcessID == getpid()` is exempt. Foreign, missing, zero-PID, or
wrong-tag events advance the combined epoch. Target lifecycle/activation signals are never exempt.

The executor captures `expectedCombinedEpoch` only after the nonactivating preview-local confirmation
gesture, all monitors are live, the captured target is still frontmost/stable, and modifier stabilization
has completed. It samples stable target identity/frontmost/security immediately before requesting gate
admission; the gate then compares the combined epoch again immediately before Unicode down.

The executor owns one thread-safe `CombinedInterferenceEpoch` primitive whose tiny nonrecursive lock is the
commit lock. Signal observers synchronously call only `advance(classifiedSignal)` on that primitive from
their callback thread; they do not enqueue advancement behind AX/preparation work on the serial executor.
This makes an already-delivered physical/lifecycle/loss signal visible even while the executor is in a
bounded AX call. Observer callbacks cannot call back into executor state, query the epoch while advancing,
log under the lock, inspect UI, retain a raw event, or perform output.

### 6.4 Public-API residual window

The combined epoch closes every signal that has become observable before gate comparison, but public macOS
APIs cannot make `NSWorkspace` notification delivery, process termination/PID reuse observation,
WindowServer frontmost state, and `CGEventPostToPid` one atomic transaction. A target may change in the
micro-window after the final synchronous sample/epoch comparison but before the OS dispatches key-down, or
a notification may arrive late. A numeric PID can theoretically be reused after the last process-generation
sample.

This is an explicit platform limit, not a zero-race claim. If the change becomes observable after down,
postflight advances/detects the epoch and the executor returns terminal
`submittedUnverified(.uncertain)`. It never retries, never retargets, and never re-exposes ordinary Send.
If product/security review cannot accept this bounded fixed-PID residual, the only honest alternative is to
disable synthetic output; an unrelated lock cannot eliminate it.

Synthetic own-PID/exact-tag events remain exempt before attempting to advance the epoch, so event-tap
observation of our pair does not reenter the critical section.

Do not add an atomics dependency. If the active standard library supplies a deployment-compatible atomic
primitive, an atomic compare/load may replace the tiny lock; it does not change the ownership contract.
The first working rung is the existing epoch plus a non-reentrant owned commit operation.

Delete `ReviewDeliveryMonitoringSession.activationLock`. Activation/frontmost/process evidence advances the
combined epoch; it is not made atomic by an unrelated lock. Public macOS APIs also cannot prove target
consumption, so every boundary-crossed result retains submitted-unverified vocabulary.

## 7. Bounded send lifecycle and UI responsiveness

### 7.1 Deadline

One monotonic **2-second whole pre-boundary deadline** begins when the coordinator consumes the qualifying
UI intent. MainActor performs the pure checked calculation
`absoluteDeadline = confirmationUptime + 2 seconds` once and places both values in the immutable admission
envelope before enqueue.
Every pre-boundary step receives the same absolute deadline; nested steps do not each get a fresh timeout.
The control record preserves it exactly and the raw executor alone resolves expiry/output consequences;
MainActor has no deadline timer or timeout authority. Control admission delay, raw queue wait, every AX
message, monitor/baseline setup, modifier stabilization, event preparation/readback, lock admission, and the
final under-lock check all spend the same budget.

Budgeted existing operations remain stricter within that envelope:

- modifier stabilization: at most 500 ms;
- target/identity/frontmost and security samples: immediate, repeated before commit;
- every AX object actually messaged, including each fresh system-wide, application, focused, and captured
  element: set that exact object's timeout to `min(500 ms, remaining positive budget)` immediately before
  each message with
  `AXUIElementSetMessagingTimeout`, whose local SDK contract is in
  `ApplicationServices.framework/Frameworks/HIServices.framework/Headers/AXUIElement.h:387-402`;
- event construction/readback: synchronous and before the gate; and
- commit lock admission: monotonic deadline-aware `try()` loop; and
- commit critical section: deadline + combined-epoch check immediately before only two fixed post calls.

Expiry before key-down returns `notStarted(.deadline)` and preserves the exact draft. The deadline must
never race a second attempt into existence. There is no MainActor timeout task and no detached timeout
worker. MainActor waits only logically for the asynchronous matching terminal control event and cannot
re-enable confirmation while the old control record/claimed permit is admitted/preparing/committing or while
any old raw prepared pair can still post.
Swift task cancellation alone is never treated as proof that synchronous AX/gate work has stopped.

### 7.2 MainActor heartbeat

`MainViewModel` renders `.preparingSubmission` and receives Sendable control events asynchronously. It must
never call `lock`, `tryLock`, `queue.sync`, wait for a queue drain, semaphore, condition, raw AX operation,
raw CGEvent operation, or blocking cancellation/admission API. Modifier sleeps, commit-lock waits, and
deadline waits occur only off MainActor.

`ReviewSubmissionControlPlane` and `ReviewSubmissionExecutor` are separate nonisolated `@unchecked Sendable`
confinement boundaries. The control plane's queue owns command/event sequencing and accesses only the
lock-protected value record store. The executor's queue alone constructs, accesses, and releases non-Sendable
raw `State` (target registry, AX objects, event source/events, prepared pair, epoch baseline, and backend).
Neither unchecked conformance permits cross-domain raw access. Public calls accept only Sendable values and
enqueue with immediate return; the fixed event sink dispatches typed events asynchronously to MainActor and
is not stored inside an attempt record. MainActor only:

- validates current coordinator authority;
- snapshots Sendable scalar/value identity needed by capture/attempt admission;
- sets `admissionPending`, creates/stores the exact handle plus frozen envelope, then immediately enqueues
  admission with no awaited/interleavable point before handle ownership;
- on accepted admission, enqueues start only if the same handle remains current and uncancelled locally;
- on close, Escape, lifecycle/security revocation, or task cancellation, marks local cancellation pending and
  nonblocking-enqueues cancellation for the retained exact handle;
- applies current-attempt results; and
- renders state.

Task cancellation and destruction of the UI task are advisory wakeups only; they are never the revocation
mechanism. The exact handle and frozen authority remain stored until a matching terminal event proves pair
destruction, permit terminalization, and record retirement. Because MainActor is serial, no UI/lifecycle
callback can interleave inside the pure create/store/enqueue sequence; once one runs, the handle is available
for nonblocking cancellation enqueue.

Cancellation result delivery is asynchronous. Its control-plane operation may be pending on the commit lock
without starving MainActor. A deterministic post-down pause must show close/Escape is processed, repeated
MainActor heartbeat ticks continue, and UI rendering remains live while cancellation awaits lock ownership;
after the pause releases, mandatory up completes and terminal submitted-unverified arrives with no resend.
This test deliberately does not claim that cancellation invocation beats the already lock-linearized down.

Tests must run a repeating MainActor heartbeat while a deliberately delayed pre-boundary dependency is in
flight and prove multiple ticks occur before completion. They must also exercise this non-racing sequence:
the absolute deadline elapses while an injected synchronous dependency is still blocked; a new gesture is
rejected immediately by the local one-active fence and asynchronously by any deliberately injected duplicate
control admission; the dependency is released; the executor immediately
rechecks the expired deadline, posts zero, and returns terminal `notStarted`; only then may a new gesture be
admitted. A heartbeat or stale-worker failure blocks Release even if the attempt eventually returns.

### 7.3 Outcome handling

| Receipt | Coordinator result | Preview behavior | Retry authority |
| --- | --- | --- | --- |
| `notStarted` | safe pre-boundary failure | exact draft retained; `.editable`; panel made key/editor-first-responder again | a future new real gesture may mint a new permit |
| `submittedUnverified` with stable postflight | one fixed pair attempted | ordinary preview dismissed; idle | none |
| `submittedUnverified` with uncertain postflight | boundary crossed; consumption unknown | terminal uncertainty, then dismiss/idle; retain diagnostic evidence | none; no ordinary Send/Return |

Cancellation that linearizes before key-down returns `notStarted(.cancellation)` only after post-capable
state and its latch are retired, preserving the exact draft. Cancellation that linearizes after key-down is
only an uncertainty observation; it cannot suppress key-up, reopen ordinary Send, or start another attempt.

## 8. Preview-local key routing

One concrete `ReviewPreviewReturnArbiter` owns every keyboard-derived confirmation decision. The visible
Send button is **not** an AppKit default button, has no Return/Enter key equivalent, and is never reached via
unrestricted `performKeyEquivalent`. This removes AppKit's Control+Return default-button behavior.

The arbiter is called exactly once from the native event route for the current `ReviewPanel`. It first
proves:

- the event is `.keyDown` for main Return (key code 36) or keypad Enter (76);
- `event.isARepeat == false`;
- the panel is the exact current editable review panel and `panel.isKeyWindow == true`;
- current review state is editable and no confirmation is in flight; and
- device-independent modifiers match one of the explicitly handled cases below.

Routing when the attached native editor is first responder:

- exact unmodified Return/Enter with no marked text -> consume and construct one
  `.qualifiedPreviewReturn` intent;
- Shift-only Return/Enter -> forward to the editor to insert one LF;
- marked-text Return/Enter -> forward to the editor/IME;
- Option, Control, Command, Caps-modified, or any other modifier combination -> forward without constructing
  an intent; and
- repeated Return/Enter -> forward/ignore according to native editing behavior, never confirm.

Routing when another control inside the same key preview is first responder:

- exact unmodified, nonrepeating Return/Enter -> consume and construct one
  `.qualifiedPreviewReturn` intent; and
- every modified/repeated Return/Enter -> forward without confirmation.

Routing when the preview is not the exact key panel always forwards with zero FeishuSpeech intent. A real
mouse click on visible Send is a separate `.sendButton` source and does not pass through the Return arbiter.
Escape/close remains zero-output discard.

The panel and editor must not implement competing Return logic. The panel's native event route invokes the
single arbiter, which returns `consumeAndConfirm` or `forwardToResponder`; forwarding calls the ordinary
AppKit route exactly once. In particular, Control+Return and Control+keypad Enter must yield zero
confirmation intents, zero delivery calls, and zero synthetic output.

No `NSEvent.addGlobalMonitorForEvents`, event tap, Carbon global hot key, or accessibility observer may be
used to turn target Return into confirmation.

## 9. File ownership and interfaces

### 9.1 TDD custody

The TDD role owns all test changes and the RED/GREEN receipts:

- `FeishuSpeechTests/FinalTextOutputSecurityTests.swift`
- `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift`
- `FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift`
- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift`
- `FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift`
- `FeishuSpeechTests/TranscriptionReviewViewTests.swift`
- `FeishuSpeechTests/StreamingMainViewModelTests.swift` only for the unchanged
  action2-plus-recorder-barrier/zero-preconfirm authority ledger

Implementers may read and run these tests but may not edit them.

The baseline deadlock oracle has one explicitly ordered exception described in section 10.1: the output
implementer first lands a behavior-preserving diagnostic/reentrancy seam in production; only then does the
TDD role add the immediate-failing oracle. The seam owner never edits the test, and the TDD owner never
edits production.

### 9.2 Output implementer custody

- `FeishuSpeech/Services/ReviewSubmissionControlPlane.swift` (new)
  - one dedicated fast non-MainActor serial context for FIFO admission/start/cancellation and typed event
    delivery;
  - own the value-only record store and exact attempt-specific latch under the commit lock;
  - never import, retain, or receive a raw AX/CGEvent/backend/target-registry reference;
  - public enqueue methods return immediately and never call MainActor synchronously.
- `FeishuSpeech/Services/ReviewSubmissionExecutor.swift` (new)
  - one nonisolated serial confinement boundary for all raw AX/CGEvent state, executor-owned target IDs,
    claimed immutable request/deadline copy, combined epoch baseline, preparation, commit, and terminal
    cleanup;
  - claim only the matching value record, validate captured target ID against the serial registry before raw
    mutation/preparation, and never reconstruct the request/deadline;
  - Sendable handle/control-event handoff only;
  - no raw handle or live permit escapes.
- `FeishuSpeech.xcodeproj/project.pbxproj`
  - output/build ownership only if the project does not automatically include the new control/executor files;
  - add those files to the existing application target without a new target, dependency, or build-setting
    change.
- `FeishuSpeech/Services/CurrentFocusAppendSession.swift`
  - feed physical input and loss-of-observability into the combined submission epoch;
  - remove arbitrary final-review callback-under-lock API;
  - preserve exact tag plus own-PID exemption and tap-disabled epoch advance.
- `FeishuSpeech/Services/TextInputSimulator.swift`
  - executor-confine prepared readback-validated pair and phase-aware receipt;
  - move the fixed private backend behind deadline-aware non-reentrant gate ownership.
- `FeishuSpeech/Services/ReviewDestinationDelivery.swift`
  - add the behavior-preserving diagnostic seam before RED, then integrate the executor after RED;
  - preserve the admission envelope's one immutable absolute pre-boundary deadline;
  - remove target activation and unrelated activation lock;
  - validate captured target remains frontmost;
  - enforce exact/application-bound rules and result mapping.
- `FeishuSpeech/Models/CursorTextModels.swift`
  - define Sendable opaque target/request/attempt descriptors, immutable admission envelope,
    `ReviewSubmissionAttemptHandle`, control events, `CancellationSignalResult`, and phase-aware receipts;
  - keep raw AX target tokens executor-private.
- `FeishuSpeech/Services/AccessibilityClient.swift`
  - split an executor-confined raw AX runtime from MainActor-facing descriptors;
  - apply `min(500 ms, remaining budget)` to every object actually messaged, including fresh system-wide
    and application/focused elements.
- `FeishuSpeech/Services/HotKeyService.swift`
  - classify physical versus exact own-tag/own-PID synthetic events and synchronously advance the combined
    epoch for physical/loss-of-observability signals without passing raw CGEvent ownership to MainActor.

### 9.3 UI/coordinator implementer custody

- `FeishuSpeech/Controllers/ReviewWindowController.swift`
  - create a true `.nonactivatingPanel`;
  - remove FeishuSpeech activation from presentation focus;
  - prove preview-key versus target-frontmost topology;
  - own the one preview-local Return arbiter and visible-Send fallback without default-button/global Return
    capture.
- `FeishuSpeech/Views/TranscriptionReviewView.swift`
  - real mouse Send action with no Return key equivalent/default action;
  - pass keyboard authority only through the panel arbiter;
  - terminal state has no Send capability.
- `FeishuSpeech/Models/TranscriptionReviewState.swift`
  - distinguish editable, preparing, and terminal submitted-unverified presentation.
- `FeishuSpeech/ViewModels/MainViewModel.swift`
  - mint one permit only after current authority checks;
  - own the checked ticket counter, store exact opaque handle/frozen envelope before nonblocking admission,
    and keep the local plus control-plane one-active fences;
  - enqueue start only after matching admission acceptance and enqueue cancellation without waiting;
  - retain handle/frozen authority until the matching terminal event;
  - keep one delivery call site;
  - preserve draft on pre-boundary failure;
  - never re-expose Send after boundary.

The output and UI production lanes are genuinely independent until the coordinator integration task:
they touch disjoint files and consume the agreed receipt/intent interfaces. Define the shared result types
first to prevent cross-lane churn.

### 9.4 Documentation custody after behavior is green

The documentation role updates only verified behavior in:

- `README.md`
- `CHANGELOG.md`
- `docs/architecture.md`
- `docs/streaming-speech-design.md`
- `docs/decisions/D-40-01.md`
- Issue #40 evidence comments

Do not record installed/UAT success before owner proof.

## 10. TDD RED contract and selectors

### 10.1 Production lock composition

The RED is executable without wedging the hosted XCTest process through this mandatory custody/order:

0. **Diagnostic prerequisite, output custody:** the output implementer exposes a narrowly scoped internal
   injection/diagnostic seam around the existing production
   `ReviewDeliveryMonitoringSession.performFinalPair` composition. The seam changes only visibility or
   dependency injection needed to supply a `CurrentFocusInputMonitoring`; it preserves the rejected
   callback-under-lock algorithm byte-for-byte in behavior. It must not change lock type, remove the nested
   getter, move validation, or alter any output result. Existing tests/build must remain unchanged.
1. **Baseline RED, TDD custody:** after the diagnostic seam exists, the TDD role adds
   `ReentrancyDetectingInputMonitor`. Its gate marks itself owned, invokes the real production orchestration,
   and makes any nested `interferenceEpoch` access record `reentrantAccess` and return immediately instead
   of taking a real lock. The oracle asserts no reentrant access. Against the behavior-preserving baseline
   composition it fails immediately and records the same nested getter proven by the installed sample,
   without hanging XCTest.
2. **No behavioral repair may start before the RED receipt exists.** The output implementer may then remove
   the callback shape and implement the executor-owned committer.
3. **GREEN:** the TDD role keeps the immediate reentrancy oracle and adds the concrete repaired production
   `CurrentFocusInputInterferenceEpoch`/combined-epoch plus `ReviewSubmissionExecutor` committer composition
   with a bounded completion deadline. Both must pass. A fake/no-op closure is not a GREEN substitute.

The RED receipt records both hashes: rejected `b321ac5` plus the behavior-preserving diagnostic-seam commit,
and links `/tmp/FeishuSpeech_2026-08-24_084734_25BZ.sample.txt` as the real nonrecursive-lock runtime proof.
This is the sole production-before-RED exception and does not authorize a behavioral fix.

Add tests with these acceptance surfaces:

- `FinalTextOutputSecurityTests/test_baselineProductionFinalPairDetectsReentrantEpochAccessWithoutHanging`
- `FinalTextOutputSecurityTests/test_productionCommitGateNeverReentersNonrecursiveEpochLock`
- `FinalTextOutputSecurityTests/test_productionCommitGateCompletesBeforeDeadlineWithRealEpochAndBackend`
- `FinalTextOutputSecurityTests/test_combinedEpochDriftBeforeCommitPostsNothing`
- `FinalTextOutputSecurityTests/test_deadlineWhileWaitingForGatePostsNothing`
- `FinalTextOutputSecurityTests/test_deadlineRecheckedUnderGateImmediatelyBeforeDown`
- `FinalTextOutputSecurityTests/test_physicalInputAtGateOrdersAfterCompleteMandatoryPair`
- `FinalTextOutputSecurityTests/test_admissionPreservesExactDescriptorAndAbsoluteDeadlineThroughRawClaim`
- `FinalTextOutputSecurityTests/test_cancelAfterAdmissionEnqueueBeforeRawStartPerformsZeroRawWork`
- `FinalTextOutputSecurityTests/test_foreignOrStaleStartIsRejectedBeforeRawWork`
- `FinalTextOutputSecurityTests/test_occupiedRawExecutorKeepsControlPlaneResponsive`
- `FinalTextOutputSecurityTests/test_cancelWhilePrebaselineAXBlockedThenReleaseBeforeDeadlinePostsNothing`
- `FinalTextOutputSecurityTests/test_cancelAfterBaselineBeforeGatePostsNothing`
- `FinalTextOutputSecurityTests/test_cancelDuringGateAdmissionPostsNothing`
- `FinalTextOutputSecurityTests/test_staleAttemptCancellationCannotCancelLaterAttempt`
- `FinalTextOutputSecurityTests/test_cancellationAfterDownStillAttemptsExactlyOneUpAndReturnsSubmittedUnverified`
- `FinalTextOutputSecurityTests/test_mainActorCloseAfterDownKeepsHeartbeatUntilMandatoryUpAndTerminalNoResend`

The diagnostic RED must exercise the real baseline orchestration, and GREEN must exercise the concrete
repaired production epoch/committer. A test that merely calls `performIfUnchanged` with a closure that does
not re-read the epoch is insufficient.

The admission/cancellation selectors are deterministic production control-plane plus raw-executor
composition tests, not mocks that merely pre-cancel a Swift task:

- the preservation selector admits a descriptor containing all authority fields and a fixed absolute
  deadline, delays raw claim, then proves the claimed copy is exactly equal and neither control plane nor raw
  executor reconstructed/renewed either value;
- the before-start selector stores the ticket, enqueues admission, enqueues cancellation before MainActor
  applies admission acceptance, and proves FIFO terminal `notStarted(.cancellation)` with zero raw queue
  claim, target-registry access, AX call, event construction, or post;
- the start-rejection selector injects foreign-nonce, never-admitted, retired, and wrong-phase handles and
  requires typed rejection before target-registry access or any raw work;
- the occupied-executor selector blocks the raw serial context while leaving the commit lock free, keeps a
  repeating MainActor heartbeat live, and proves the independent control context promptly resolves exact
  cancellation plus an injected duplicate admission rejection without waiting for the raw queue;

- the prebaseline selector blocks an injected synchronous AX return after attempt admission, calls
  nonblocking cancellation enqueue through MainActor, proves the control event reports `latched` while the
  raw executor is still occupied, releases AX before the absolute deadline, and requires zero event
  construction/post, `notStarted(.cancellation)`, and terminal cleanup before re-enable;
- the pre-gate selector pauses after baseline capture and before preparation/gate, enqueues cancellation,
  resumes, and requires zero down/up plus destruction of any partially prepared state;
- the gate-admission selector holds the commit lock using the deterministic production diagnostic seam,
  starts the deadline-aware admission loop, pauses that loop outside the lock before its next `try()`, then
  releases the holder and requires the queued cancellation event to report `latched` before resuming the loop;
  the next acquisition must observe the raw fence and produce zero down/up;
- the stale-handle selector fully terminalizes attempt A, admits attempt B, calls cancellation with A's
  old nonce/ID, and proves B's latch/permit is unchanged and B follows only its own injected outcome; and
- the post-down selector pauses immediately after the concrete down call while the commit lock is still
  owned, routes close/Escape on MainActor, proves multiple heartbeat ticks while control-plane cancellation
  waits for the lock, releases the post seam, and proves exactly one mandatory up, terminal
  `submittedUnverified(.uncertain)`, zero resend, and no Send re-exposure. The assertion orders on lock
  linearization, not the earlier MainActor enqueue time.

Each pre-down cancellation test also asserts the receipt is not exposed until the prepared pair/source,
permit, and attempt-control mapping are no longer post-capable. The gate-admission holder is bounded and
test-only; it cannot add an unbounded production lock path.

Focused command:

```bash
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests \
  -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests test
```

### 10.2 Native AppKit focus and Return

Add native event-routing tests:

- `ReviewWindowControllerReadinessTests/test_nonactivatingEditablePanelBecomesKeyWithoutActivatingFeishuSpeech`
- `ReviewWindowControllerReadinessTests/test_nonactivatingPanelKeepsCapturedTargetFrontmost`
- `ReviewWindowControllerReadinessTests/test_focusFailureKeepsVisibleSendAndDoesNotInstallGlobalReturnCapture`
- `TranscriptionReviewViewTests/test_exactUnmodifiedNonrepeatReturnThroughKeyPanelConfirmsExactlyOnce`
- `TranscriptionReviewViewTests/test_exactUnmodifiedNonrepeatKeypadEnterThroughKeyPanelConfirmsExactlyOnce`
- `TranscriptionReviewViewTests/test_returnOutsideKeyPreviewDoesNotConfirm`
- `TranscriptionReviewViewTests/test_sendClickConfirmsWhenEditorIsNotFirstResponder`
- `TranscriptionReviewViewTests/test_shiftReturnInsertsLFAndIMEOptionReturnDoNotConfirm`
- `TranscriptionReviewViewTests/test_controlReturnAndControlKeypadEnterProduceZeroIntentAndZeroDelivery`
- `TranscriptionReviewViewTests/test_modifiedOrRepeatedReturnOnAnotherPreviewControlDoesNotConfirm`

Do not invoke `editor.keyDown` directly as the sole oracle. Dispatch a native `NSEvent` through the actual
panel/application event path and assert key window, first responder, FeishuSpeech activation, and target
frontmost observations. Assert the Send button has no default-button cell/Return key equivalent and route
Control+Return plus Control+keypad Enter through `NSApplication.sendEvent` to prove zero intent, zero
delivery, and zero output.

Focused command:

```bash
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests test
```

### 10.3 Coordinator, target, and lifecycle

Add tests:

- target may be non-key while preview is key but must remain frontmost/stable;
- exact cursor is restored only after a real permit;
- application-bound fallback uses only captured PID/identity/current responder and never retargets;
- restarted PID/changed launch date/new frontmost app fails before key-down;
- target activation APIs have zero calls on v5 normal path;
- zero output ledger remains zero for Fn, streaming, sealing, every edit character, focus success/failure,
  and all provisional recovery paths;
- duplicate Send/Return while admission is pending/preparing creates one local handle and one active control
  record; deliberately injected duplicate envelopes are asynchronously rejected and mint no sibling permit;
- create/store/enqueue has no awaited gap, and admission/start/cancellation invoked from MainActor reach the
  control queue in FIFO call order;
- exact request descriptor and absolute deadline survive admission through raw claim without reconstruction;
- cancellation after admission enqueue but before raw start produces zero raw executor/registry/AX/event work;
- foreign, stale, never-admitted, and wrong-phase start handles fail before raw work;
- the absolute 2-second deadline cannot be renewed by nested stages;
- executor queue delay consumes the same deadline and can expire with zero AX/event mutation;
- every fresh system-wide/application/focused/captured AX object receives
  `min(500 ms, remaining budget)` before its message;
- a delayed AX call returning after its remaining budget cannot proceed to event preparation or gate;
- a gate held beyond the deadline returns zero posts, and the deadline is rechecked while owned immediately
  before down;
- physical input, target activation/frontmost change, termination, process-generation change, and observer
  loss each advance the combined epoch and suppress pre-down output;
- drift injected after final target sampling but before gate entry with input epoch otherwise unchanged posts
  zero;
- while a delayed worker survives deadline expiry, a new gesture cannot be admitted; after the worker is
  released, the executor rechecks deadline, posts zero, returns terminal, and only then admits a new gesture;
- a close/Escape/lifecycle cancellation uses the currently stored opaque handle and returns immediately after
  enqueue while the raw executor or commit lock is blocked; neither Task cancellation nor a raw-queue
  cancellation command is sufficient;
- cancellation receipt ordering keeps the exact draft noneditable until old post-capable state and the
  exact attempt latch are retired, then restores editable focus only for `notStarted(.cancellation)`;
- MainActor heartbeat ticks during a delayed pre-boundary attempt;
- MainActor heartbeat also ticks during a post-down pause while the control-plane cancellation operation is
  pending on the commit lock; after release, mandatory up and terminal no-resend still hold;
- every pre-boundary failure restores exact draft/revision-safe callbacks and preview key focus;
- after down, terminal submitted-unverified exposes neither ordinary Send nor qualified Return.

Focused command:

```bash
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test
```

## 11. Build and validation order

1. Output implementer lands only the behavior-preserving diagnostic/reentrancy seam described in section
   10.1; no behavioral repair is allowed.
2. TDD role lands and runs the immediate-failing reentrancy oracle plus remaining RED tests, and records the
   rejected baseline hash, diagnostic-seam hash, exact selectors, and failures.
3. Only after the RED receipt, shared Sendable descriptor/result types and executor confinement interfaces
   are reconciled.
4. Output implementer and UI implementer work independently.
5. Coordinator integration consumes both lanes.
6. TDD role runs focused GREEN selectors, including the concrete production epoch/committer composition,
   and writes a receipt.
7. Independent correctness review falsifies focus topology, phase boundary, timeout, exactly-once authority,
   value-record/raw-executor ownership, descriptor/deadline preservation, FIFO async admission, and stale-
   handle isolation.
8. Independent security review falsifies executor confinement, stale-worker authority, combined-epoch
   coverage, attempt-specific cancellation fencing, MainActor lock/queue independence, post-down heartbeat,
   every preconfirm output surface, retargeting, synthetic-event provenance, clipboard/Cmd+V regression, and
   global/default-button Return capture.
9. Documentation docks verified behavior.
10. Investigator runs the complete local matrix serially.
11. Only then build/install one Release and perform owner UAT.

Full local validation:

```bash
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -parallel-testing-enabled NO test
xcodebuild -scheme FeishuSpeech -configuration Debug build
xcodebuild -scheme FeishuSpeech -configuration Release build
swiftlint --strict
git diff --check
```

Static rejection searches must prove the accepted path contains no pasteboard/Cmd+V and no global Return
authorization. Protected recording and recognition paths must remain byte-stable except where coordinator
authority integration requires a reviewed change.

## 12. Installed UAT gate

Use at least one native target with an editable field and repeat with an application-bound target where AX
cannot supply an exact cursor.

1. Start with the target application active/frontmost and its intended field focused.
2. Hold Fn and speak. The read-only preview may render; target receives no text/signal.
3. Release Fn and wait for action 2 plus recorder barrier.
4. Prove the editable preview panel is key and editor-first-responder while the target application remains
   active/frontmost and FeishuSpeech remains inactive.
5. Type several edits. They appear only in the preview; target and pasteboard remain unchanged.
6. Press Shift+Return; one LF appears only in the preview.
7. Press Control+Return and Control+keypad Enter. They produce zero confirmation, delivery, and synthetic
   output.
8. Press exact unmodified plain Return once. The attempt leaves preparing within two seconds, posts at most one tagged
   down/up payload pair to the captured PID, and does not re-expose Send.
9. Repeat with visible Send while another preview control is first responder; then prove exact unmodified
   Return on that control submits while modified/repeated Return does not.
10. Move to another application before confirmation. Send fails closed, preserves the exact draft, and does
   not retarget.
11. Restart the captured target process. Send fails closed on identity/launch-date mismatch.
12. Hold a relevant modifier through confirmation. Zero Unicode events post and the exact draft returns.
13. Block one prebaseline AX call after the UI has stored its exact attempt handle and enqueued the immutable
    admission. Cancel from close/Escape/lifecycle control while the raw serial executor remains occupied;
    MainActor must return immediately and the async control event must report `latched`. Release AX before
    the deadline and prove zero event construction/post,
    `notStarted(.cancellation)`, exact-draft restoration only after terminal cleanup, no stale permit later
    posts, and a responsive MainActor/UI. Repeat cancellation after baseline/before gate and during
    deadline-aware gate admission; both post zero. Then prove cancellation with the retired handle cannot
    affect a later attempt.
14. Pause after down while commit owns the lock; invoke close/Escape on MainActor and prove UI heartbeat
    continues while cancellation is pending. Release the pause and prove mandatory up, terminal
    submitted-unverified, and no resend.
15. Trigger target activation/frontmost/termination/process-generation drift immediately before commit. If
    observed before down, zero events post; if observable only after the public-API micro-window, the result
    is terminal uncertain with no resend.
16. Quit FeishuSpeech and type normally. No delayed image, clipboard mutation, character, Return, or residual
    synthetic event occurs.

Owner UAT evidence must record target app, binding type, target PID/identity, preview key/app-active facts,
attempt outcome, elapsed pre-boundary duration, event count, clipboard change count, installed bundle hash,
and sole-copy/process inventory. Issue #40 remains open until owner PASS.

## 13. Migration, rollback, and failure routing

- Migrate from `b321ac5` in the issue worktree; do not patch the installed bundle in place.
- Remove the final-review callback-under-lock API rather than keeping a compatibility adapter that can
  recreate reentrancy.
- The only allowed pre-RED production change is the behavior-preserving diagnostic seam in section 10.1.
  Do not mix that seam with lock, deadline, output, or state-machine repair before the TDD RED receipt.
- Do not alter the independent audio-recorder and recognition transport topology. The only speech-path
  changes are authority handoff and reviewed lifecycle integration.
- Do not reintroduce clipboard/Cmd+V, target activation, global Return monitoring, automatic retry, or
  ambient retargeting as fallbacks.
- Do not retain a native default Send button or Return key equivalent; all keyboard authority passes through
  the one exact preview-local arbiter.
- Do not move raw AXUIElement/CGEvent/prepared-pair/post-capable permit state across MainActor or the raw
  executor. Only the exact immutable envelope and lock-protected value control record may cross contexts. If
  confinement cannot be proven, stop and route to security/build ownership.
- Do not implement an independent MainActor timeout that can re-enable while an executor permit is live.
- Do not implement cancellation solely as `Task.cancel()`, a descriptor queued to the raw submission
  context, a generation shared by multiple attempts, or a MainActor lock acquisition. It must use the exact
  stored handle and dedicated control context in sections 4.3-4.4; retain handle/frozen authority through
  the terminal event.
- If nonactivating-panel WindowServer proof fails, ship no Return promise for that environment: retain the
  visible Send fallback and fail closed on target drift.
- If the new gate cannot prove non-reentrancy under the production monitor composition, stop and route back
  to architecture/security; do not substitute `NSRecursiveLock`.
- If the complete pair is attempted but consumption is unknown, report terminal submitted-unverified and
  do not retry.
- On installed-candidate UAT failure, stop/remove that candidate and reinstall only the last owner-accepted
  Release. The rejected `b321ac5` build is not a rollback target.

## 14. Deliberate limits

- Public macOS APIs do not provide a target-consumption receipt for `CGEventPostToPid`; v5 guarantees one
  application-issued attempt, not visual consumption.
- The combined epoch is strongest-observable-state fencing, not an impossible atomic WindowServer/process
  transaction. Notification lag, the last-sample-to-post micro-window, and numeric PID reuse after the final
  process-generation sample remain bounded residuals; any drift observed after down produces terminal
  uncertainty and never resend.
- Application-bound fallback proves the captured application, not the original control/caret. It is retained
  only under the explicit same-identity/frontmost/security contract above.
- A true nonactivating panel is locally documented but installed WindowServer behavior remains an explicit
  UAT gate.
- No new dependency, global shortcut, schema, entitlement, build-tool swap, or generalized output framework
  is part of v5.

## 15. Pre-implementation finding closure

This revision closes every finding recorded in:

- `.cache/security-review-v5-pre.md`;
- `.cache/code-review-v5-pre.md`;
- `.cache/security-review-v5-pre-r2.md`;
- `.cache/code-review-v5-pre-r2.md`;
- `.cache/security-review-v5-pre-r3.md`; and
- `.cache/code-review-v5-pre-r3.md`.

| Review finding | Status | Closure in this blueprint |
| --- | --- | --- |
| Security R1 - executor isolation, AX ownership, and stale deadline worker | **closed by design** | Sections 3.1-3.2 and 4.3-4.5 separate value-only admission metadata from all raw state. The raw submission executor remains sole owner of AXUIElement/CGEvent/prepared-pair/backend/target-registry state; the control plane owns only immutable Sendable request/deadline plus phase/cancellation values. Section 7 applies `min(500 ms, remaining budget)` to every fresh AX object, removes independent UI timeout races, and prohibits re-enable until terminal proof. Sections 10.3 and 12 require stale-worker and fresh-system-wide timeout oracles. |
| Security R2 - activation/frontmost/process identity race at key-down | **closed to the strongest public-API boundary** | Sections 6.2-6.3 require deadline-aware lock admission and an under-lock combined-epoch comparison immediately before down. The epoch covers physical input, activation/frontmost, termination, process generation, and observability loss, with only exact own-tag/own-PID output exempt. Section 6.4 explicitly narrows the guarantee for notification lag, PID reuse, and the unavoidable last-sample micro-window and requires terminal uncertainty/no resend after boundary. |
| Security R3 - same-executor cancellation cannot fence key-down | **closed by design** | Sections 4.3-4.4 define an exact handle keyed by control-plane nonce plus never-reused ID and FIFO cancellation on a context independent of raw AX work. Cancellation and commit linearize under the same lock; the raw attempt checks after every synchronous return and immediately before down. Sections 7, 10.1, 10.3, and 12 require blocked-prebaseline, pre-gate, gate-wait, stale-handle, cleanup, and post-down mandatory-up proofs. |
| Security R4 - MainActor cancellation blocks on commit/epoch lock | **closed by design** | Sections 4.3-4.4 (lines 245-395) and 7.2 (lines 685-729) make MainActor cancellation a nonblocking enqueue to a dedicated control context. Only that context may wait for the commit lock, while MainActor retains handle/authority and continues processing heartbeat/UI. Commit-first remains post-boundary advisory; cancel-first rejects down. Sections 10.1 (lines 895-990), 10.3 (lines 1021-1072), and 12 (lines 1133-1143) require a concrete post-down pause, MainActor close/Escape, repeated heartbeat ticks while cancellation is pending, mandatory up, terminal submitted-unverified, and no resend. |
| Correctness R1 - whole deadline absent from AX, executor queue, and lock | **closed by design** | Sections 4.3, 6.2, and 7.1 carry one absolute monotonic deadline through admission queue wait, every AX object/message, preparation, bounded `try()` lock admission, and the final check while the gate is owned. Section 7.2 keeps MainActor live and prevents late-worker authority. Section 10.3 lists queue, AX, gate, heartbeat, and stale-worker executable tests. |
| Correctness R2 - native default button authorizes Control+Return | **closed by design** | Section 8 deletes native default-button/key-equivalent behavior and defines one preview-local arbiter. Only exact unmodified nonrepeat Return/keypad Enter in the exact key panel can confirm; Shift/IME/Option/Control/Command/repeat are forwarded without intent. Sections 10.2 and 12 require full native-route Control+Return and Control+keypad zero-intent/zero-delivery/zero-output proof. |
| Correctness R3 - baseline deadlock RED cannot execute safely under custody/order | **closed by design** | Section 10.1 chooses the behavior-preserving output-owned diagnostic seam, then the TDD-owned immediate-failing `ReentrancyDetectingInputMonitor` oracle, then prohibits behavioral repair until the RED receipt. GREEN uses the concrete repaired production epoch/executor/committer composition. Sections 9 and 11 assign files/custody and exact dependency order. |
| Correctness R4 - queued preboundary cancellation leaves stale authority | **closed by design** | Sections 4.3-4.4 make the exact handle available before any enqueue and serialize admission/start/cancellation FIFO on the value control context rather than the occupied raw executor. Old/foreign/terminal handles cannot affect a later permit. Sections 6.2 and 7 define before-down zero-post cleanup and after-down advisory-only mandatory-up terminal behavior; sections 10.1 and 10.3 provide deterministic composition selectors. |
| Correctness R5 - synchronous reservation has no legal ownership/liveness locus | **closed by design** | Sections 4.3-4.4 (lines 245-395) define the missing `ReservedAttemptControlRecord`: nonce, never-reused ID, exact immutable request, exact absolute deadline, phase, and cancellation bit, with no raw reference. MainActor creates/stores the ticket then nonblocking-enqueues the immutable envelope. Section 6.2 (lines 490-595) makes the raw executor lock-claim/copy that exact value record, validate capturedTargetID against its serial target registry before raw work, and reject foreign/stale starts. Sections 7, 9, and 10 (especially lines 895-990 and 1021-1072) require descriptor/deadline preservation, pre-start cancellation with zero raw work, one-active async admission, occupied-executor liveness, and explicit file ownership. |

Review-ready acceptance for this architecture requires both pre-implementation reviewers to confirm that
these mappings close their findings without weakening the preserved contracts: nonactivating-panel target
frontmost identity, local visible Send fallback, action2 plus recorder barrier, no global Return, zero
preconfirm output, one permit/attempt, mandatory up after down, terminal post-boundary no-resend, and
MainActor heartbeat.
