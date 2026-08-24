# Issue #40 architecture blueprint v4 — confirmation authority is not focus readiness

Date: 2026-08-23

Repository: `/Users/ylpromax5/Workspace/feishuspeech`

Implementation worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`

Baseline and installed candidate inspected: `4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a`

Authority: the Issue #40 v2 one-preview/explicit-confirm contract, the second installed-UAT receipt
in `kaola-workflow/issue-40/.cache/github-v3-uat-failure-v4.md`, and the owner's subsequent
zero-side-effect/output-transaction correction. V4 supersedes both the v2/v3 readiness gate and
the review pasteboard/Cmd+V transaction. Exact/application identity, PID, live AX trust, Secure
Input, unsafe-text, stale-generation, and exact-once gates remain mandatory.

## 1. Installed fact, correction, and success boundary

The second installed Release UAT is decisive:

- the v3 titlebar/traffic-light correction is visibly successful;
- 18pt transcript typography is visibly successful;
- the retained panel contains a real editor which is visible, typeable, and usable;
- the footer contains only Cancel; Send is absent; Return does nothing; and
- the coordinator is still in `editablePending`, so `TranscriptionReviewView` passes
  `canConfirm: false` and `MainViewModel.confirmReviewDraft` rejects the callback unless the state
  has later become `.editable`.

The residual machine diagnosis also establishes a second independent defect boundary:

- the FeishuSpeech process and helper were absent after the owner stopped the failed candidate;
- combined-session modifier flags were raw `0`, so no stuck Command/Shift/Control/Option state was
  present;
- the general pasteboard at change count 132 contained image types only:
  `public.png`, `Apple PNG pasteboard type`, `public.tiff`, and `NeXT TIFF v4.0 pasteboard type`;
- current `performReviewPaste` snapshots every prior item/type, replaces the pasteboard with text,
  posts a targeted Cmd+V pair without target-consumption acknowledgement, then restores the prior
  snapshot after one second when `changeCount` is unchanged.

The source proves the transaction and the measured image-only snapshot. The explanation for the
reported image paste is a high-confidence inference: `CGEvent.postToPid` only queues events, while
pasteboard reads are performed later by the target. A delayed target can therefore process queued
Cmd+V after the one-second restore and consume the restored image, possibly when the next physical
input advances its event handling. Pasteboard `changeCount` does not acknowledge reads, so the
current code cannot prove text consumption before restoring.

This is an authority error, not evidence that the draft or editor is unavailable. The correction is:

```text
capture/recorder root ----\
                           +--> same panel and coordinator-owned draft
recognition/replay root ---/       streaming -> sealing -> editable -> confirming
                                                  ^           |          |
                                                  |           |          +-- one delivery attempt
                                  action 2 + recorder barrier  +-- explicit Send/Return only

presentation focus aid: bounded async activation/key/editor-focus attempt -> telemetry only
```

Completion requires all of the following:

1. Action 2 plus the recorder barrier synchronously freezes the best authoritative draft in the
   existing `ReviewSurfaceAuthority`, projects `.editable` into the same panel, and installs live
   edit/confirm/discard callbacks before starting any presentation-focus await.
2. Send and the D-39 Return/Enter gestures are immediately enabled for every non-whitespace frozen
   draft. AppKit activation rejection, inactive app state, non-key panel, delayed editor lookup,
   failed first-responder assignment, timeout, cancellation, and surface invalidation cannot hide
   or disable confirmation.
3. A presentation-focus request is a best-effort aid. Its typed result may be logged, but cannot
   mutate draft text, authority, review phase, revision, feedback, confirmation admission, or
   delivery count.
4. External output still begins only in the current generation/revision's explicit `onConfirm`
   callback after action 2 and the recorder barrier. Recording, recognizing, retry/replay,
   previewing, sealing, freezing, rendering, focus assistance, every character edit, feedback,
   cancellation, discard, failure, and cleanup perform zero AX setters, target keyboard/CGEvent
   posts, pasteboard reads, pasteboard writes/restores, copy/paste, delivery calls, retries,
   retargets, or other synthetic output signals.
5. Confirmation freezes the exact coordinator-owned, untrimmed draft and creates at most one
   delivery task. A failure returns that frozen draft directly to `.editable` with fixed feedback;
   a later attempt requires a new explicit Send/Return.
6. Exact application identity, PID, exact AX element/selection where available, live Accessibility
   trust, Secure Input, unsafe-text, stale generation/revision, and exact-once delivery gates stay
   unchanged and fail closed after explicit confirmation.
7. The authorized delivery is exactly one tagged, modifier-free Unicode key-down/key-up pair whose
   UTF-16 payload equals the final frozen text, including LF. It is posted only to the captured PID
   after final live gates. Review delivery performs no pasteboard access and no Cmd+V.
8. There is no automatic delivery, delivery retry, target recapture, retarget, recovery copy,
   direct insert, ambient-focus output, or focus-triggered output.
9. Capture/journal production and recognition/factory/retry/replay/consumer remain independent
   asynchronous roots. Neither awaits the panel, focus aid, confirmation, delivery, or the other
   root.

## 2. Chosen authority model

### 2.1 Durable product state

`TranscriptionReviewState` becomes:

```text
idle
streaming(preview)
sealing(preview)
editable(draft, isPossiblyIncomplete, feedback)
confirming(draft, isPossiblyIncomplete)
```

`editablePending` is deleted rather than reinterpreted. Keeping a second draft phase would preserve
the possibility that a presentation observation becomes a product authority gate again. This enum
is internal and not persisted, so removal has no data migration or public API cost.

The only authority required to admit confirmation is:

- a current `ReviewSurfaceAuthority` with the current positive generation and captured destination;
- a non-nil coordinator-owned `ReviewDraft`;
- current review ID/revision callback fences;
- `.editable` state;
- non-whitespace draft content; and
- no confirmation already in flight.

Presentation focus is intentionally absent from that list.

`ReviewSurfaceAuthority.readinessAttempt` is removed. Presentation attempt counters belong to the
presenter/telemetry lane, not to durable draft or delivery authority. `confirmationAttempt` remains
because it fences exact-once delivery callbacks.

### 2.2 Exact draft source

`ReviewSurfaceAuthority.draft.text` is the confirmation source of truth. `reviewDraftText` remains
only the existing observable/test/UI projection and must be kept synchronized by the current
generation/revision-scoped edit callback. `confirmReviewDraft` freezes `authority.draft.text`, not
an AppKit readiness result and not an ambient view lookup. The D-39 native editor ordering remains:
the text-change callback updates coordinator authority before the Return callback is consumed.

### 2.3 Presentation-focus result

The existing readiness types are narrowed and renamed so their names cannot imply confirmation
authority:

- `ReviewEditableTransitionResult` -> `ReviewPresentationFocusResult` with `.focused` and
  `.notFocused(ReviewPresentationFocusFailure)`;
- `ReviewEditableReadinessPredicate` -> `ReviewPresentationFocusPredicate`;
- `ReviewEditableReadinessFailure` -> `ReviewPresentationFocusFailure`; and
- `ReviewEditableReadinessState` is deleted because focus status is no longer rendered product
  state.

The returned failure remains typed: timeout with the last unmet predicate, cancellation with an
optional last unmet predicate, and surface invalidation. `activationRejected` is removed as a
terminal result: the activation request remains advisory, and the controller continues its bounded
poll to report the actual unmet predicate. The controller may still record an
`activationAdvisoryRejected` telemetry event.

No new dependency, abstraction layer, setting, schema, entitlement, or build-system mechanism is
needed.

### 2.4 Confirmation intent is a UI capability

Delete both current programmatic confirmation seams:

- the zero-argument `confirmReviewDraft()` entry; and
- `confirmReviewDraft(reviewID:callbackRevision:)` with an optional revision.

Replace them with one private coordinator handler that requires a non-optional review ID, exact
callback revision, and a `ReviewConfirmationIntent`. The intent is an internal value whose explicit
initializer is `fileprivate` to `TranscriptionReviewView.swift`; the compiler-generated memberwise
initializer must not remain accessible. Only two production sites in that file may create it:

- the actual Send button action; and
- `ReviewDraftTextView.keyDown` after the existing D-39 checks prove main Return/keypad Enter,
  supported modifiers, no Option/Control, and no marked text.

The intent records only a fixed source enum (`sendButton` or `qualifiedReturn`), never transcript,
length, target, PID, or key contents. Presenter and coordinator protocols may pass the opaque value
but cannot manufacture one. Tests drive the real button/native editor rather than invoking a
coordinator testing shortcut. This makes the UI gesture a capability, not a boolean callback any
internal caller can synthesize.

## 3. Fate of the four v3 readiness surfaces

| v3 surface | v4 decision | Required semantics |
| --- | --- | --- |
| `editablePending` | Delete | Action 2 + recorder barrier transitions directly from `.sealing` to `.editable`. Delivery failure also returns directly to `.editable`. |
| `requestEditableReadiness()` | Rename to `requestPresentationFocus()` | One bounded, cancellable AppKit activation/key/editor-focus attempt returning typed telemetry. It starts only after `.editable` and callbacks are rendered. Its result cannot alter product state or confirmation authority. |
| `retryReviewReadiness(...)` | Delete without replacement | There is no user retry control and no coordinator readiness state to retry. Each new editable presentation may start one focus aid; that is presentation work, never a delivery retry. |
| presenter callbacks | Retain `onDraftChange`, typed `onConfirm(ReviewConfirmationIntent)`, and `onDiscard`; remove `onRetryReadiness` | The typed intent is the sole external-output ingress and is installed immediately with `.editable`. All callbacks retain exact review-ID/revision fences. Confirming renders no confirmation capability; discard keeps its existing policy. |

`ReviewSurfacePresenting.renderDraft` therefore accepts only the state plus edit, confirm, and
discard callbacks. `ReviewWindowController` removes the stored retry callback. The view removes its
unused retry property/initializer parameter and never derives `canConfirm` from focus state.

## 4. Dependency-safe coordinator flow

### 4.1 Action 2 and recorder barrier

`reviewTransitionTask` remains the action-2/recorder-barrier task. It is not reused for focus aid.
Once both inputs are satisfied, `finishReviewTransition` performs this ordered main-actor sequence:

1. Revalidate active streaming identity, current review authority ID/generation, terminal-pending
   status, and transition ID.
2. Finish the speech session exactly as today. This may reset the hot-key axis to idle but does not
   revoke review authority.
3. If neither action 2 nor the latest snapshot yields usable text, revoke review authority and
   dismiss as today.
4. Otherwise store the exact chosen draft and incomplete flag in `ReviewSurfaceAuthority`, clear
   feedback, increment the authority and surface revisions, and update `reviewDraftText` as a
   projection.
5. Publish `.editable` immediately.
6. Render that `.editable` state into the already-retained panel with current edit, confirm, and
   discard callbacks. The render exposes Send and the native Return handler immediately.
7. Clear the terminal transition task/ID. Do not await AppKit focus.
8. Start a separate main-actor `reviewPresentationFocusTask` which awaits
   `requestPresentationFocus()` only for typed telemetry.

The focus task captures the current review ID and generation. On completion it may log a
content-free result only if still current. It must not increment `reviewSurfaceRevision`, rerender,
change feedback/state, revoke authority, or call delivery. New draft renders, confirmation,
discard, cleanup, and a successor generation cancel this task. The presenter's own attempt ID
continues to fence stale polling against a reused panel.

### 4.2 Edit and confirmation

The editable callbacks keep the existing revision handshake:

- `onDraftChange` accepts only the current review ID and callback revision, updates
  `ReviewSurfaceAuthority.draft.text`, clears old delivery feedback, increments revision, and leaves
  the state `.editable`.
- `onConfirm` accepts only the current review ID/revision and `.editable`, freezes the exact
  authority draft, increments `confirmationAttempt`, sets `reviewConfirmationInFlight`, publishes
  `.confirming`, cancels focus aid, and starts exactly one delivery task.
- whitespace-only drafts remain editable but cannot consume confirmation authority.
- duplicate clicks/Return events, old panel callbacks, or a callback after discard cannot create a
  second task.

The editor keeps all D-39 behavior unchanged: main Return and keypad Enter confirm; Command+Return
and the existing Shift+Command variants confirm; Shift-only Return/Enter inserts one LF;
Option/Control Return passes through; marked-text Return stays with the IME; Escape and close
discard with zero output.

The exact production call-site fence is the replacement private
`MainViewModel.handleReviewConfirmation(intent:reviewID:callbackRevision:)` with a non-optional
revision. It is the only method allowed to call `reviewDestinationDelivery.deliver`. Its guard must prove,
before constructing the task:

- the intent was created by the actual production Send button or qualified native Return/Enter;
- the callback review ID equals the current authority ID;
- the callback revision equals the current surface revision;
- the state is `.editable` and action 2/recorder-barrier transition has already installed a
  non-nil authority draft;
- the authority generation is current and equals the destination generation;
- the exact authority draft is non-whitespace, passes review-text safety, and contains at most
  16,384 UTF-16 code units;
- `reviewConfirmationInFlight == false`; and
- no delivery task exists for the current confirmation attempt.

An over-cap draft stays `.editable` with fixed `.draftTooLong` feedback and zero delivery call. Only
after all guards pass may the handler increment `confirmationAttempt`, consume the in-flight gate,
cancel presentation focus, and invoke one delivery. Do not call delivery from state transitions,
`reviewDraftText.didSet`, `updateReviewDraft`, presenter focus completion, failure handlers,
discard/cancel, lifecycle cleanup, security observers, settings, or recovery paths. A source guard
must keep exactly one `reviewDestinationDelivery.deliver` call site in production.

Every pre-confirm test spy must therefore remain at zero through all intermediate steps, including
one callback per typed character. Reading/capturing the destination and live security state is
allowed; AX setters, target signals, and all pasteboard access are not.

### 4.3 Presentation focus

`ReviewWindowController.requestPresentationFocus()` may continue to:

- request accessory-app activation;
- call `makeKeyAndOrderFront`;
- materialize and lay out the existing SwiftUI/AppKit editor;
- check app-active, panel-key, editor-materialized, editor-attached, and first-responder predicates;
- poll for at most the existing two seconds; and
- return a typed focused/not-focused result.

Those predicates describe convenience focus only. The method may never alter `canConfirm`, replace
the view with a non-confirmable state, dismiss the panel, copy text, activate the captured target,
or invoke confirm/delivery callbacks. A focus timeout is not user-facing delivery feedback.

Each focus request carries a coordinator-issued `(reviewID, generation, focusAttemptID)` tuple and
the presenter returns the same tuple with its typed result. Completion is accepted for telemetry
only when all three values still match the current authority/task and the presenter still owns the
same retained panel generation. A newer render, confirmation, discard, cleanup, or successor
generation invalidates the attempt before cancelling its task. Late completion after invalidation
is dropped without log correlation, state/revision mutation, callback replacement, activation,
delivery, or panel remount. Presenter-local readiness UUID alone is insufficient because the shared
panel can be reused by a later generation.

### 4.4 Delivery failure

`completeReviewDelivery` keeps the exact frozen text in the current authority. Every current
`.failedBeforeSubmission` or `.cancelledBeforeSubmission` result returns directly to `.editable`
with fixed feedback and immediately reinstalls edit/confirm/discard callbacks; these outcomes prove
zero event posts. `.submittedUnverified(.postflightValid)` consumes the review authority and may
show only fixed "submitted" completion feedback—never "inserted," "accepted," or "displayed."
`.submittedUnverified(.postflightUncertain(reason))` returns the exact frozen draft to `.editable`
with the existing duplicate-risk warning because a later explicit send may duplicate visible text.
It may start a fresh presentation-focus aid for the newly shown editor, but it does not call
`deliver` again.

Task cancellation is phase-aware. Before the down post it may produce
`.cancelledBeforeSubmission`; after the down post it must be represented as submitted/unverified and
must not overwrite that outcome with cancellation. `SystemReviewDestinationDelivery.deliver` must
therefore remove the current unconditional post-output `Task.isCancelled -> .cancelled` override.

Ambient permission/Secure Input/monitoring changes after freeze also leave `.editable` visible with
safe feedback. They do not hide Send. If the user explicitly confirms, the delivery layer resamples
and fails closed before mutation or reports uncertainty according to the existing post boundary.

## 5. V4 text-only delivery transaction

### 5.1 Decision: redesign the application fallback; remove pasteboard delivery

Do not remove the application-bound fallback solely because safe exact AX cursor capture is absent.
Instead, both exact and application-current-focus bindings converge on one text-only, fixed-PID
event transaction after their binding-specific preflight. The fallback remains bounded to the
complete application identity captured before recording; it does not recapture a control, PID, or
frontmost application.

Remove review pasteboard snapshot, text write, delayed restore, restore scheduler, and targeted
Cmd+V completely. There is no reliable target-consumption acknowledgement for Cmd+V:

- posting the event pair acknowledges only local submission to the event system;
- pasteboard `changeCount` changes on writes, not reads; and
- neither exact postflight AX focus validation nor application identity validation proves which
  pasteboard payload the target eventually consumed.

Waiting longer only moves the race. Restoring conditionally on unchanged `changeCount` still allows
a delayed target to consume restored image/rich content. Leaving the text on the pasteboard avoids
the race but creates an unrequested persistent transcript copy and violates the no-copy boundary.
Therefore neither restore nor leave-behind is accepted.

### 5.2 One review-only Unicode pair

Add one review-only output operation to `FinalTextOutput`/the current Unicode poster. It accepts the
exact frozen text, captured PID, a final pre-post composite validator, and a postflight validator.
Its implementation order is fixed:

1. Require a positive captured PID, non-whitespace exact text, and
   `TextInputSimulator.isSafeForReviewConfirmation`. LF is admitted as Unicode data; NUL, tab, CR,
   DEL, and C1 controls reject before event construction. Enforce a product maximum of **16,384
   UTF-16 code units**, far below CoreGraphics' 65,535-unit length boundary. The 60-second capture
   product cannot reasonably require more; the lower cap bounds event allocation/readback and
   leaves a fourfold margin against any 16-bit length truncation. Count UTF-16 units, not grapheme
   clusters or Unicode scalars. Non-BMP characters count as their intact surrogate pair; the whole
   string is accepted or rejected, never truncated or split. Add a typed `.draftTooLong` result and
   fixed, content-free feedback.
2. Construct one complete Unicode key-down event and one complete Unicode key-up event in memory,
   each carrying the entire exact UTF-16 draft. Do not split by character, line, or packet and do
   not synthesize Return for LF.
3. Apply empty modifier flags and `FeishuSpeechSyntheticEventTag.value` to both. Read back both
   events before posting and require all of: phase is down/up respectively; Unicode payload exactly
   equals the full input UTF-16 sequence; flags are empty; tag equals the configured tag;
   `eventSourceUnixProcessID == getpid()`; both events were created from the same source handle; and
   the one immutable target PID equals the captured positive PID. Tag configuration/readback,
   source-ownership, flag, phase, payload, or PID mismatch is `.failedBeforeSubmission` with zero
   posts. A setter returning no status is not assumed successful; readback is the proof.
   The same tag-plus-source-PID conjunction is the only self-event exemption in both existing input
   filters. A correct tag alone is never sufficient.
4. After target activation, wait for combined-session device-independent modifiers to stabilize as
   empty in two consecutive samples separated by one bounded event-loop/poll interval. A
   Command/Shift confirm may still be physically held when its callback fires, so do not fail on
   the first non-empty sample; poll for at most 500 ms. Non-empty or changing Command, Shift,
   Control, Option, or Caps Lock at the deadline fails before submission and retains the draft.
5. The delivery coordinator must have installed both the existing physical-input interference
   monitor and a workspace-activation epoch monitor **before requesting target activation**. After
   activation and modifier stabilization, capture their current epochs. Enter one synchronous
   critical section shared with both epoch writers. Under that lock, require both epochs unchanged,
   repeat the empty modifier sample, and run the binding-specific final live validator: AX trust,
   Secure Input, captured/frontmost PID, complete running/frontmost identity, generation, and—for
   exact binding—the captured element/selection authority. Any pre-boundary failure posts zero.
6. Inside that critical section, attempt prepared key-down first and mark the phase
   `submissionBoundaryCrossed` immediately when the backend call is made. Once crossed, always
   attempt the prepared key-up to the same PID before leaving the critical section—even if
   cancellation, a fault-injection hook, or a pending interference/activation notification occurs
   after down. There is no cancellation check or epoch recheck between the pair. Complete pair
   construction precedes both attempts; a failure before the down call remains `notStarted`.
7. Release the critical section, then run binding-specific postflight plus epoch/modifier checks.
   Drift, cancellation, or security change after the boundary is
   `.submittedUnverified`, never `.cancelled` or `.failedBeforeSubmission`. Never retry,
   compensate, paste, restore, retarget, or emit another pair.

Use explicit phase-aware results:

- phase `.notStarted`: may return `.failedBeforeSubmission(reason)` or `.cancelledBeforeSubmission`;
  both prove zero target events;
- phase `.submissionBoundaryCrossed`: may return only `.submittedUnverified` (including the normal
  complete-pair/postflight-valid case) or a more specific uncertainty reason nested under that same
  semantic. It can never claim cancellation prevented output.

Do not use `.inserted`/`.posted` as a consumption claim. CoreGraphics submission is not OS-atomic:
the process cannot prove that down and up are consumed together, cannot roll back a down already
submitted, and receives no target-control acceptance/display receipt. The key-up guarantee is
therefore "attempted after down," not "atomically consumed." The successful coordinator outcome is
`submittedUnverified`; installed UAT is the only visible-consumption evidence. The transaction
contains no pasteboard object and no virtual-key V event.

### 5.3 Exact and application-bound preflight

Decision: retain the application-bound fallback, but only with the v4 text-only prepared pair and
combined input/activation critical section. It is safe enough for the already-selected
application-level authority because it can emit text only, carries no action-key Return, targets
only the captured PID, and fails before submission on any observable trust/security/identity,
modifier, activation, or physical-input drift. It still cannot prove the original intra-app control
or caret; users requiring that guarantee receive only the exact binding. This capability limit is
not silently upgraded.

After explicit confirmation only:

- the destination generation and complete captured application identity must still be current;
- the exact binding still activates the captured application, restores and validates only the
  captured AX element and original selection, then posts the one Unicode text pair to that element's
  captured PID;
- the application fallback still activates only the captured complete application identity, takes
  the existing two ordered trust/Secure-Input/raw-PID/running/frontmost identity samples, and posts
  the same one Unicode text pair only to that captured PID;
- no fallback AX recapture, ambient PID discovery, current-app substitution, target-control read, or
  image/rich payload exists;
- exact/fallback live Accessibility trust, Secure Input, PID, bundle, executable, launch-date,
  frontmost, unsafe-text, and postflight uncertainty rules stay fail closed; and
- no result authorizes automatic retry, retarget, direct insert, recovery copy, or compensating
  key event.

If the activation observer cannot be installed, physical-input monitoring cannot be armed, epoch
capture is inconsistent, modifier stabilization fails, or the combined critical section cannot be
entered, both exact and fallback routes fail closed in `.notStarted` and retain the draft. The
fallback is not allowed a weaker monitor path.

Monitor installation precedes `activateAndWait`; the activation caused by delivery is therefore
observed, after which the baseline activation epoch is captured only once the exact captured app is
live/frontmost. This removes the unobserved install-to-activation gap. Observer teardown happens
only after postflight or a proven pre-submission failure.

Presentation focus activates FeishuSpeech's review panel. Delivery activation later targets only
the previously captured application. These authorities share no focus/readiness result. Confirm
must cancel the panel focus task before target activation so a late panel activation cannot race
the final validation/post.

### 5.4 Residual clipboard migration

The failed installed process is stopped, so no in-process delayed restore closure remains. V4 must
not inspect, clear, normalize, or restore the measured image-only pasteboard at startup, migration,
confirmation, failure, or cleanup. The user's current clipboard remains user-owned. Removing the
review pasteboard scheduler is the complete migration; there is no safe cleanup write.

### 5.5 R5 self-event identification in both input filters

Use one shared, non-cryptographic predicate for the two existing filters:

```text
isSelfIdentified(event) =
    event.eventSourceUserData == FeishuSpeechSyntheticEventTag.value
    AND event.eventSourceUnixProcessID == getpid()
```

This is a narrow self-identification rule inside the process/OS threat model, not authentication or
cryptographic authorization. It prevents ordinary foreign or malformed events carrying only the
public fixed tag from being silently exempted; it does not claim resistance to a privileged process
or platform compromise capable of forging protected event provenance.

Apply the predicate identically at these existing symbols:

- `CurrentFocusInputInterferenceEpoch.observePreDispatch(type:event:)` — after the unconditional
  tap-disabled branch and before advancing an otherwise interfering key/mouse/modifier event;
- `WorkspaceCurrentFocusInputMonitor.isExternalCaretAffectingEvent(_:)` — for events observed by
  both its AppKit local and global monitors; a missing `NSEvent.cgEvent` is external, not self; and
- `FeishuSpeechSyntheticEventTag.value` remains the fixed tag used by the prepared down/up pair;
  add or reuse a single helper beside these symbols so the two filters cannot drift to different
  identity rules.

Exact symbol ownership in `FeishuSpeech/Services/CurrentFocusAppendSession.swift`:

| Symbol | R5 responsibility |
| --- | --- |
| `CurrentFocusInputInterferenceEpoch.observePreDispatch(type:event:)` | Keep tap-disabled first/unconditional; for ordinary events, exempt only shared tag+current-PID self-identification before calling `advance()`. |
| `CurrentFocusInputInterferenceEpoch.isInterferingPhysicalInput(type:event:)` | Preserve event-kind policy, including Fn-only `flagsChanged`; it must not inspect tag/PID or create a second identity rule. |
| `CurrentFocusInputInterferenceEpoch.advance()` | Remains the single locked loss/interference epoch mutation. |
| `WorkspaceCurrentFocusInputMonitor.installMonitoring(_:)` | Both installed AppKit local/global closures must route through the same `isExternalCaretAffectingEvent` classification. |
| `WorkspaceCurrentFocusInputMonitor.isExternalCaretAffectingEvent(_:)` | Missing `cgEvent` is external; otherwise exempt only shared tag+current-PID self-identification. |
| shared self-identification helper | Read exactly `.eventSourceUserData` and `.eventSourceUnixProcessID`; return true only for fixed tag plus `getpid()`. It is used by both filters and nowhere as a delivery authorization check. |

`HotKeyService.handleEvent` remains the event-tap caller of `observePreDispatch`; no HotKey state
machine change is required.

Required behavior for an otherwise interfering event:

- correct tag + current process PID: self-identified, so no interference epoch advance and no
  AppKit monitor callback;
- correct tag + foreign positive PID: external, so advance/callback;
- correct tag + missing or zero PID: external, so advance/callback;
- missing or wrong tag + current process PID: external, so advance/callback;
- missing or wrong tag + foreign/missing/zero PID: external, so advance/callback.

`tapDisabledByTimeout` and `tapDisabledByUserInput` are loss-of-observability signals, not ordinary
events. `observePreDispatch` must advance the epoch and return **before** consulting tag or source
PID. They advance for correct-tag/current-PID, correct-tag/foreign-PID, wrong-tag/current-PID, and
missing/zero provenance alike. The existing Fn-only `flagsChanged` non-interference rule remains a
separate event-kind rule and is not broadened into a tag-only exemption.

## 6. Exact file plan

### 6.1 Production files to modify

| File | Change |
| --- | --- |
| `FeishuSpeech/Models/TranscriptionReviewState.swift` | Delete `editablePending` and `ReviewEditableReadinessState`; rename/narrow focus result, predicate, failure, and telemetry helpers; add fixed `.draftTooLong` feedback; remove terminal activation rejection semantics. |
| `FeishuSpeech/ViewModels/MainViewModel.swift` | Remove readiness from `ReviewSurfaceAuthority`; transition directly to `.editable`; freeze authority draft on typed UI intent; delete pending-state branches, readiness retry, zero-argument confirm, and optional-revision confirm; add a separately cancellable generation/attempt-fenced focus task; enforce the 16,384-unit cap; map phase-aware submission outcomes without post-boundary cancellation override. Preserve action-2/barrier ordering. |
| `FeishuSpeech/Controllers/ReviewWindowController.swift` | Remove stored retry callback; update `renderDraft` to pass opaque typed confirmation intent; rename readiness API/types to presentation focus; carry review/generation/attempt identity through the bounded result; guarantee late results never change authority or invoke output. |
| `FeishuSpeech/Views/TranscriptionReviewView.swift` | Own the `fileprivate` initializer for `ReviewConfirmationIntent`; create it only in the actual Send action or qualified native Return/Enter path. Remove pending/retry UI; `.editable` immediately exposes editor/Cancel/Send. Keep v3 typography/titlebar layout and D-39 key policy. |
| `FeishuSpeech/Services/TextInputSimulator.swift` | Delete pasteboard snapshot/write/restore scheduling and Cmd+V output. Add the 16,384-unit review-only prepared pair, exact down/up payload/phase/flags/tag/source-process readback, same-source/same-PID invariants, modifier sampling seam, explicit submission phase, always-attempt-up rule, and `submittedUnverified` outcomes. |
| `FeishuSpeech/Services/ReviewDestinationDelivery.swift` | Route exact and application-bound delivery through the prepared pair; install/capture a workspace activation epoch and reuse `CurrentFocusInputMonitoring` for physical interference. Hold activation then input epoch locks in a fixed order across final validation and both post attempts. Preserve capture/trust/security/identity/PID/exact-element gates. Remove pasteboard/Cmd+V and post-boundary cancellation override. |
| `FeishuSpeech/Services/CurrentFocusAppendSession.swift` | Close R5 in both existing filters. `CurrentFocusInputInterferenceEpoch.observePreDispatch` and `WorkspaceCurrentFocusInputMonitor.isExternalCaretAffectingEvent` must share the exact fixed-tag **and** `eventSourceUnixProcessID == getpid()` self-identification predicate. Preserve unconditional tap-disabled epoch advancement and existing event-kind/Fn rules. No output/session behavior change is authorized. |

No new production file is justified.

### 6.2 Production files explicitly protected from change

- `FeishuSpeech/Services/AccessibilityClient.swift`
- `FeishuSpeech/Models/CursorTextModels.swift`
- `FeishuSpeech/Services/AudioRecorder.swift`
- `FeishuSpeech/Services/ByteBoundedAudioIngress.swift`
- `FeishuSpeech/Services/HoldPacketJournal.swift`
- `FeishuSpeech/Services/FeishuStreamingSession.swift`
- `FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift`
- provider/factory/retry/replay, capture-drain, and recognition-consumer surfaces in
  `MainViewModel.swift` outside the named review transition methods

If implementation evidence says one of these must change, stop and return to architecture/security
review; do not broaden v4 opportunistically.

### 6.3 Test files to update

Test custody remains separate from production implementation.

| File | RED/updated oracle |
| --- | --- |
| `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift` | Action 2 + barrier renders `.editable` before focus completes; same panel/draft is immediately confirmable through real UI intent; focus timeout/cancel/stale generation completion cannot alter state/revision/feedback/delivery. Prove 16,384/16,385 cap behavior, one delivery call site, phase-aware cancellation, and no post-boundary cancellation override. Remove tests invoking zero-arg confirm. |
| `FeishuSpeechTests/TranscriptionReviewViewTests.swift` | Frozen `.editable` draft visibly has Send and live Return without focus status; only the real Send action and qualified native Return/Enter can construct `ReviewConfirmationIntent`; no public/internal initializer, zero-arg confirm, optional revision, pending, or retry seam remains. Retain D-39, v3 typography/titlebar/panel-size, whitespace, confirming, feedback, cancel, and accessibility oracles. |
| `FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift` | Keep the filename to avoid project churn, but test presentation-focus semantics: advisory activation, bounded predicates, cancellation, same-panel retention, production editor materialization, and exact reviewID/generation/attempt echo. Late completion after new render/generation performs zero log/state/callback/output action. |
| `FeishuSpeechTests/StreamingMainViewModelTests.swift` | Update `ReviewSurfacePresenting` fakes/signatures and remove retry hooks; no streaming oracle changes. |
| `FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift` | Prove fallback retains only application-level authority, fails closed without both monitors, and posts one text pair only when fixed PID/identity, trust, Secure Input, modifiers, input epoch, and activation epoch remain stable. Exercise intra-app control limit without claiming exact caret authority. |
| `FeishuSpeechTests/FinalTextOutputSecurityTests.swift` | Boundary/fault matrix: 16,384 versus 16,385 UTF-16 units; BMP, LF, and non-BMP surrogate pairs; exact down/up readback; empty flags; tag and `eventSourceUnixProcessID`; same source/PID; tag-set/readback failure zero-post; down/up construction failures zero-post; cancellation before down zero-post; cancellation/fault after down still attempts up and returns submitted-unverified; modifier stabilization; input/activation epoch drift and lock ordering; postflight uncertainty/no retry. |
| `FeishuSpeechTests/ReviewPasteboardLifecycleTests.swift` | Replace restoration tests with a prohibition suite. Every phase, including successful explicit confirmation, must record zero pasteboard snapshots, reads, writes, restores, and schedulers; assert no Cmd+V poster is constructed or called. Include an image-only prior-pasteboard fixture to prove it is never read or emitted. |
| `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift` | Add the exact R5 cross-product for `observePreDispatch` and both AppKit monitor channels: only correct tag/current PID is exempt; correct-tag foreign/zero/missing PID and own-PID wrong/missing tag advance/callback. For both tap-disabled event types, every provenance variant advances. Retain tagged-own prepared-pair and Fn-only regressions. |

Update `ReviewDestinationDeliveryTests.swift` so exact and fallback routes expect the single Unicode
text pair rather than Cmd+V, while retaining their existing trust/identity/PID/selection ordering.
Inject faults at before-build, after-build/readback, before-down, immediately-after-down,
before-up, after-up, cancellation, modifier sample, input-epoch, activation-epoch, and postflight
boundaries. No test may interpret local event submission as target consumption.

### 6.4 Documentation files to update after green behavior exists

| File | Docked truth |
| --- | --- |
| `README.md` | Action 2 + barrier immediately exposes editable Send/Return; focus aid is advisory; only real UI intent confirms; review delivery is capped at 16,384 UTF-16 units and submits one provenance-checked text pair with no pasteboard/Cmd+V; call the result submitted/unverified; replace stale v3 UAT status. |
| `CHANGELOG.md` | Record v4 authority correction, image-race diagnosis, removal of review pasteboard/Cmd+V, typed UI capability, cap, phase-aware pair semantics, epoch/modifier gate, and failed installed candidate without claiming replacement UAT success. |
| `docs/architecture.md` | Topology becomes `streaming -> sealing -> editable -> confirming`; separate focus aid from coordinator/delivery authority; define the UI-intent fence, combined critical section, submitted-unverified result, and zero-side-effect pre-confirm boundary. |
| `docs/streaming-speech-design.md` | Remove pending/retry language; document direct freeze-to-editable, generation-fenced focus telemetry, exact UI intent, cap/readback/provenance, phase-aware pair, modifier/epoch gates, and no-pasteboard output. |
| `docs/decisions/D-38-01.md` | Mark pending/readiness-confirmation wording superseded by D-40-01 v4 while retaining D-38 exact-target and independent-root decisions. |
| `docs/decisions/D-40-01.md` | Add v4 amendment, installed `4f9908f` evidence, measured image-only pasteboard/no-modifier facts, inferred delayed-consumption race, final authority/state/output decisions, and open replacement-UAT gate. |
| `docs/README.md` | Update navigation summaries from v2/v3 pending semantics to v4. |

`docs/api.md` has no impact: Feishu requests, responses, auth, transport, and error contracts do not
change. Record that explicit no-impact conclusion in the documentation receipt rather than editing
the file.

## 7. TDD-sized build sequence and dependencies

### Task 1 — coordinator authority RED

Owner: test author only.

Add failing coordinator/view oracles proving direct freeze-to-editable, immediate confirmability
while focus is suspended/not-focused, stale focus-result inertness, and direct delivery-failure
return to editable. Add a phase-by-phase side-effect ledger covering recording, recognition,
preview, sealing, freeze, every edit callback, focus outcome, cancel, failure, and cleanup; every AX
write, target event, pasteboard operation, copy, and delivery count must remain zero until the single
explicit confirm callback. Require actual production Send/native key input to create the opaque
intent and prove the zero-argument/optional-revision seams are gone. Update test fakes to describe
the target protocol without changing production.

Dependency: none. This establishes the behavior boundary before implementation.

### Task 2 — model and coordinator GREEN

Owner: production implementer only.

Modify `TranscriptionReviewState.swift` and the review-only sections of `MainViewModel.swift`.
Delete pending/retry authority, render `.editable` immediately, add the separate focus task, and
freeze coordinator authority on explicit confirm. Run Task 1 tests.

Dependency: Task 1 RED.

### Task 3 — presenter/view contract GREEN

Owner: production implementer only.

Modify `ReviewWindowController.swift` and `TranscriptionReviewView.swift`. Remove retry callback and
pending UI; rename/narrow the focus API; retain v3 layout, editor, and key semantics. Run view,
keyboard, and controller focus suites.

Dependency: Task 1 RED. It is implementation-independent from most of Task 2 because it owns
different production files, but its protocol signature is consumed by Task 2. Implement or land
the signature once, then reconcile the coordinator call sites before compiling.

### Task 4 — text-only output RED

Owner: test author only.

Replace pasteboard-restoration expectations with failing no-pasteboard/no-Cmd+V tests. Add the exact
one-pair cap/readback/provenance oracle; phase-aware cancellation and always-attempt-up behavior;
modifier stabilization; combined input/activation epoch critical-section races; all-or-zero
pre-boundary construction failures; and post-boundary submitted-unverified/no-retry behavior for
exact and application-bound bindings. Add the full R5 two-event-kind × three-observation-path ×
seven-provenance matrix plus both tap-disabled × four-provenance cases before changing either
filter.

Dependency: none; it owns the delivery acceptance surface and can be authored alongside Task 1.

### Task 5 — text-only output GREEN

Owner: production implementer only.

Modify `TextInputSimulator.swift` and `ReviewDestinationDelivery.swift`; remove the accepted-route
pasteboard/Cmd+V machinery and implement the one Unicode pair. Modify only the named R5 symbols in
`CurrentFocusAppendSession.swift` so both filters share tag+current-PID self-identification while
tap-disabled remains unconditional. The implementer may read and run the Task 4 oracle but does not
edit test files.

Dependency: Task 4 RED. This is genuinely independent of Tasks 2/3 until integration because it
owns different production files and consumes only the frozen-text/destination delivery interface.

### Task 6 — test fake migration and integrated oracle

Owner: test author only.

Update remaining presenter/output fakes in streaming, coordinator, and fallback suites after the
production signatures settle. Add the application-fallback focus-independence regression and run
the combined coordinator/output security matrix.

Dependency: Tasks 2, 3, and 5 interfaces.

### Task 7 — documentation docking

Owner: documentation updater.

Update only the files in section 6.4 from verified green behavior. Preserve the installed-v3
failure as historical evidence and do not claim v4 installed UAT before it occurs.

Dependency: focused green behavior and final names.

### Task 8 — independent review, full validation, replacement install, UAT

Correctness review checks authority/revision/task cancellation and independent async roots.
Security review checks that confirm visibility does not bypass delivery gates. Only after both and
all commands pass may finalization build/install a replacement Release and request owner UAT.

Dependency: Tasks 2–7.

Genuinely independent work:

- after Task 1 defines the contract, production changes in the model/coordinator and
  presenter/view can be developed concurrently because they own disjoint files; the one shared
  protocol signature must be agreed first;
- after Task 4 RED, text-only delivery can be implemented concurrently with the coordinator and UI
  correction because no capture/recognition or presenter file is shared;
- correctness and security review are independent after integration because one inspects
  lifecycle/state regressions and the other inspects output/trust boundaries; and
- documentation drafting can start after names settle, but its final status wording depends on
  validation and installed UAT.

The delivery transaction is a real, separately evidenced v4 defect and is therefore an explicit
parallel workstream. Capture, journal, transport, and recognition are not.

## 8. Exact validation commands

Run commands from `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40` and serialize all
Xcode test processes.

### Focused v4 behavior

```bash
set -o pipefail
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-focused-derived -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v4-focused.log
```

### Text-only delivery/security contract

```bash
set -o pipefail
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-security-derived -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v4-security.log
```

### Full suite, builds, lint, and hygiene

```bash
set -o pipefail
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-full-derived test -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 2>&1 | tee /tmp/issue40-v4-full.log
xcodebuild -scheme FeishuSpeech -configuration Debug -derivedDataPath /tmp/issue40-v4-debug-derived build
xcodebuild -scheme FeishuSpeech -configuration Release -derivedDataPath /tmp/issue40-v4-release-derived build
swiftlint --strict
git diff --check
```

### Obsolete-authority and protected-surface guards

```bash
! rg -n 'editablePending|requestEditableReadiness|retryReviewReadiness|onRetryReadiness|ReviewEditableReadinessState' FeishuSpeech FeishuSpeechTests README.md CHANGELOG.md docs
! rg -n 'performReviewPaste|captureReviewPasteboardSnapshot|restoreReviewPasteboardSnapshot|reviewPasteboardRestore|postCommandV' FeishuSpeech
! rg -n 'func confirmReviewDraft\(|callbackRevision: UInt64\?' FeishuSpeech
test "$(rg -n 'reviewDestinationDelivery\.deliver' FeishuSpeech/ViewModels/MainViewModel.swift | wc -l | tr -d ' ')" = 1
test "$(rg -n 'reviewMaximumUTF16CodeUnits[^0-9]*16_384' FeishuSpeech/Services/TextInputSimulator.swift | wc -l | tr -d ' ')" = 1
git diff --exit-code 4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a -- FeishuSpeech/Services/AccessibilityClient.swift FeishuSpeech/Models/CursorTextModels.swift FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/ByteBoundedAudioIngress.swift FeishuSpeech/Services/HoldPacketJournal.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift
```

Also inspect the `MainViewModel.swift` diff manually to prove capture drain, journal admission,
provider factory/retry/replay, recognition consumer, and recorder barrier production were not
coupled to presentation focus.

## 9. Migration, telemetry, security, and failure routing

### Migration

- `TranscriptionReviewState` and focus result types are internal, non-persisted values. No data or
  settings migration is required.
- `reviewBeforeInsert` and `autoInsert` remain decode-only legacy values and continue to converge on
  the single preview route.
- Existing test fakes are the only broad compile migration caused by the presenter signature.
- `FinalTextOutput` test doubles migrate from pasteboard/Cmd+V methods to one review Unicode-pair
  method. Delete snapshot/restore scheduler fixtures rather than retaining compatibility defaults
  that could silently re-enable the race.
- The stopped candidate has no live delayed restore task. Do not perform a clipboard cleanup or
  migration write; the current image-only pasteboard is user-owned and remains untouched.
- No dependency, project-file, entitlement, Info.plist, API, credential, or network migration is
  allowed.

### Telemetry

Rename `review_readiness_*` events to `review_presentation_focus_*` so logs do not imply product
admission. Recommended fixed events are `started`, `activation_advisory_rejected`, `focused`,
`not_focused`, and `cancelled`, with generation, bounded attempt ordinal, elapsed milliseconds,
result, and unmet predicate only. Do not log draft text, length/hash, PID, bundle ID, executable
path, window title, AX value, clipboard data, credentials, token, or stream/audio bytes.

No in-repository telemetry consumer was found. If an external parser exists, the event rename is a
dashboard migration risk; preserve a release note mapping rather than retaining the misleading old
authority name.

### Security risks and required review points

- **Visible confirm versus safe delivery:** Send being visible under Secure Input/trust drift is
  intentional; delivery must resample after the explicit callback and fail closed before mutation.
- **Stale focus task:** a late focus result must not rerender a discarded/newer review or replace
  callbacks. Both coordinator review ID/generation and presenter attempt ID must fence it.
- **Focus stealing during delivery:** confirmation cancels presentation focus before target
  activation; otherwise a late `makeKeyAndOrderFront` could race the fixed-target delivery preflight.
- **Exact-once regression:** removing the pending gate must not remove
  `reviewConfirmationInFlight`, `confirmationAttempt`, callback revision checks, or delivery task
  cancellation.
- **Draft authority regression:** confirm from coordinator authority, not a new AppKit editor lookup
  or target/clipboard read.
- **Clipboard image race:** any surviving review snapshot, pasteboard write/restore scheduler, or
  Cmd+V call is a release blocker. `changeCount` is not a consumption acknowledgement.
- **Pair atomicity:** both Unicode events, exact UTF-16 payload, empty modifiers, and synthetic tags
  must be constructed/read back before the first post. The OS submission is not atomic; after down,
  up must still be attempted and the outcome stays submitted-unverified.
- **Length wrap/truncation:** both coordinator and poster enforce 16,384 UTF-16 units and exact
  event readback. No truncation, chunking, or fallback transport is authorized.
- **Event provenance:** both events must read back the FeishuSpeech tag and current
  `eventSourceUnixProcessID`, originate from the same source, carry empty flags, and target the same
  captured PID. A tag setter without successful readback is failure-before-submission.
- **Multiline semantics:** LF must remain inside the Unicode payload. It must never be converted to
  a physical Return event, split into extra pairs, or normalized to CR.
- **Held modifiers and human interference:** combined-session flags must stabilize empty. Physical
  input and activation epochs are captured after activation and held unchanged under a fixed-order
  critical section through both post attempts.
- **Forgeable confirmation:** no zero-argument or optional-revision entry remains. Only the
  file-scoped UI intent created by actual Send/qualified Return can cross the call-site fence.
- **Application fallback:** it remains application-bound, not control-bound. Final live
  trust/Secure/PID/complete-identity gates are therefore mandatory immediately around the one pair;
  inability to satisfy them posts zero and retains the draft.
- **Uncertainty:** a possible post remains terminal for that attempt; re-exposed Send is a new human
  decision and must retain the duplicate warning.

### Failure routing and rollback

- Focused behavior failure routes to the test author; build/type failures caused by signature
  migration route to the build resolver; security-suite failure routes to security review and stops
  release.
- If implementation cannot expose `.editable` before the focus await, do not add a timeout bypass
  or second confirm path; return to this authority split.
- If v4 installed UAT again shows Cancel-only or inert Return, keep Issue #40 open and capture
  state/focus telemetry without transcript content. Do not reintroduce `editablePending`, automatic
  copy, direct output, or delivery retry.
- The current failed candidate is stopped. Do not relaunch or treat `4f9908f` as a rollback release.
  Finalization must first identify the exact v4 commit and Release product, then perform the normal
  recoverable replacement transaction. Preserve `4f9908f` only as forensic UAT evidence.

## 10. Replacement installed-Release UAT gate

Automated AppKit tests cannot prove accessory-app/WindowServer focus behavior or that a third-party
control consumed the submitted Unicode pair. Finalization must bind the UAT to the exact v4 commit, Release app bundle,
installed path, bundle version, signature, running executable, and PID before testing.

Minimum owner UAT, with transcript content omitted from receipts:

1. In the same target that produced the `4f9908f` screenshot, hold Fn through visible streaming,
   release through sealing, and verify the same panel/editor immediately shows both Cancel and Send
   after action 2 + recorder barrier. Do not wait for a readiness message or hidden state change.
2. Edit the draft and press bare Return; verify one delivery attempt and one visible target result.
3. Repeat with the Send button; repeat with Shift+Return to add an LF before explicit confirmation.
   Verify the target receives the exact multiline text and not a Return/submit action.
4. Exercise an exact-AX target and an ordinary non-secure strict-AX-miss target. Verify the latter
   never retargets another frontmost application.
5. Exercise Secure Input/password rejection, Accessibility trust loss, application/PID/launch
   identity drift, and an application switch during confirmation. Each must fail closed after the
   explicit callback, retain the exact draft, and perform no copy/retry/retarget.
6. Force key-post/postflight uncertainty. Verify fixed duplicate-risk feedback, no automatic second
   delivery, and that only a later explicit Send/Return creates another attempt.
7. Verify Cancel, Escape, and window close discard with zero output; verify a stale callback after
   discard cannot deliver.
8. Seed the clipboard with a known image before the interaction. Verify recording, preview,
   per-character editing, focus attempts, confirmation success/failure, and later ordinary typing
   never paste that image; verify the clipboard change count/types remain untouched by FeishuSpeech.
9. Confirm one explicit confirmation emits exactly one tagged, modifier-free text down/up pair to
   the captured PID and no virtual-key V/Cmd event. Bind this to privacy-safe instrumentation; do
   not log the text payload.
10. Confirm logs contain only focus result/predicate/timing and generation metadata, never transcript
   or target/clipboard content.

Issue #40 may close only after the replacement installed Release passes this matrix. Local green,
source inspection, event submission, or the existence of a usable editor is insufficient by itself.

## 11. Deliberate limits

V4 does not guarantee that the panel is already key or the editor already first responder at the
instant `.editable` is rendered; it guarantees that these best-effort presentation conditions no
longer own Send/Return authority. If macOS never routes keyboard input to a visibly usable editor,
the Send button remains available and the typed focus telemetry supplies the next diagnosis.

V4 also does not strengthen the application-current-focus fallback into original-control/caret
authority. That would require a new platform mechanism and a separate decision. The exact AX route
remains preferred, and the fallback proves only the originally captured complete application.

## 12. Security amendment — pre-implementation R1–R5 closure

This amendment is binding over any earlier v4 wording. Implementation does not start until the RED
oracle records each closure below.

| Finding | Architectural closure | Required falsification |
| --- | --- | --- |
| R1 — unbounded/ambiguous Unicode event payload | Product cap is 16,384 UTF-16 code units in coordinator and poster. Both down/up events must read back the exact full payload, phase, empty flags, tag, source PID, same source, and target PID before submission. LF remains data; non-BMP surrogate pairs remain intact; no truncation/chunking. | 16,384 accepted; 16,385 rejected with zero post; non-BMP boundary counts code units; any down/up readback mismatch is zero-post. |
| R2 — cancellation and partial-submission ambiguity | Results carry `.notStarted` versus `.submissionBoundaryCrossed`. Cancellation is honored only before down. Down crosses the irreversible boundary; up is always attempted afterward; every post-boundary result is `submittedUnverified`, never cancelled/failed-before-submission/inserted. OS non-atomicity and lack of consumption receipt are explicit. | Cancel before down posts zero; cancel/fault immediately after down still records up attempt and submitted-unverified; no coordinator cancellation override after output returns. |
| R3 — event provenance, modifier, and pair-integrity weakness | Prepared pair validates exact down/up, whole UTF-16 readback, empty flags, FeishuSpeech tag, `eventSourceUnixProcessID == getpid()`, common event source, immutable captured PID, and complete construction before down. Tag configuration must be read back. | Inject tag setter/readback, source PID, source identity, flags, phase, payload, down/up construction, and target PID faults; all pre-boundary faults post zero. Verify one down and one up only. |
| R4 — ambient input/activation/focus races | Install physical-input and activation monitors before target activation; after activation, wait up to 500 ms for two empty combined-session modifier samples and capture both baselines. Hold activation lock then existing input-epoch lock across final live validation and both attempts. Postflight checks epochs/modifiers. Focus aid carries reviewID/generation/attempt and late completion is inert. | Held/unstable modifiers, pre-lock epoch drift, observer-arm failure, lock-order fault, activation switch, queued physical input, and stale focus completion are injected. Pre-boundary cases post zero; queued/post-boundary cases are submitted-unverified and never retry. |
| R5 — tag-only self-event exemption | Both `CurrentFocusInputInterferenceEpoch.observePreDispatch` and `WorkspaceCurrentFocusInputMonitor.isExternalCaretAffectingEvent` use one conjunction: fixed FeishuSpeech tag **and** `eventSourceUnixProcessID == getpid()`. Any missing/wrong tag or missing/zero/foreign PID is external. Tap-disabled advances before identity checks. The pair's own events must read back both fields. This is self-identification, not cryptographic authorization. | Run the exact filter/channel/identity matrix below. Only correct-tag/current-PID is exempt. Both tap-disabled types advance for every identity variant. Verify the prepared pair still carries correct tag/current PID and is exempt in both filters. |

### Exact R5 test matrix

For each ordinary interfering event kind `keyDown` and `leftMouseDown`, run every row against all
three observation paths:

1. `CurrentFocusInputInterferenceEpoch.observePreDispatch`;
2. `WorkspaceCurrentFocusInputMonitor` local monitor; and
3. `WorkspaceCurrentFocusInputMonitor` global monitor.

| Tag field | `eventSourceUnixProcessID` | Epoch path | AppKit local/global |
| --- | --- | --- | --- |
| correct fixed tag | `getpid()` | no advance | no callback |
| correct fixed tag | foreign positive PID | advance once | callback once per exercised channel |
| correct fixed tag | zero/missing | advance once | callback once per exercised channel |
| wrong nonzero tag | `getpid()` | advance once | callback once per exercised channel |
| missing/zero tag | `getpid()` | advance once | callback once per exercised channel |
| wrong nonzero tag | foreign positive PID | advance once | callback once per exercised channel |
| missing/zero tag | zero/missing | advance once | callback once per exercised channel |

Then run both `tapDisabledByTimeout` and `tapDisabledByUserInput` through the epoch path with these
four provenance representatives: correct-tag/current-PID, correct-tag/foreign-PID,
wrong-tag/current-PID, and missing-tag/zero-PID. Every case advances exactly once. No AppKit monitor
case exists for tap-disabled because those are CGEventTap lifecycle events.

Finally, construct the production prepared down/up pair and assert both events read back correct
tag/current PID and are exempt in each ordinary filter/channel. Mutate only one field at a time and
assert both filters immediately classify the event as external. Retain the separate tests that
Fn-only `flagsChanged` stays non-interfering and that unrelated non-caret event kinds do not advance.

### Required fault-injection seams

Keep seams internal and dependency-free. Tests need deterministic control over:

- UTF-16 cap/count and down/up Unicode readback;
- event construction phase, flags, tag set/readback, source identity, source Unix PID, and immutable
  target PID;
- before-build, after-build, before-down, immediately-after-down, before-up, after-up, and
  postflight hooks;
- cancellation at every phase;
- combined-session modifier samples and stabilization clock/sleeper;
- input-monitor install/capture, activation-monitor install/capture, each epoch, and fixed lock order;
- final exact/fallback validator and postflight result;
- focus request reviewID/generation/attempt completion; and
- UI generation of Send versus qualified/unqualified Return intent.

Production defaults use CoreGraphics/AppKit/current shared interference mechanisms. Fakes must not
introduce a default success adapter: missing monitor, readback, provenance, or epoch capability is
fail closed.

### Threat-model exclusions and residual limits

- CoreGraphics supplies no target-consumption/display receipt and no atomic two-event transaction.
  V4 proves prepared payload/provenance and submission attempts only; it reports
  `submittedUnverified` and relies on installed UAT for visible consumption.
- After key-down crosses the boundary, the system cannot retract it. Key-up is best-effort mandatory;
  compensation, replay, rollback, paste, or retarget is forbidden.
- The application fallback proves the original complete application and fixed PID, not the original
  intra-app control/caret. Programmatic focus changes inside that app that produce no observable
  activation/input epoch are outside the fallback's proof. Because the payload has no physical
  Return and is text-only, this residual capability remains accepted for Issue #40; an exact-control
  requirement would disable fallback and needs a separate product decision.
- The design does not defend against a compromised target application, privileged/root process,
  malicious Accessibility client, kernel/WindowServer defect, or forged system events capable of
  bypassing macOS process isolation. It does fail closed for all observable trust, Secure Input,
  identity, PID, modifier, input, and activation changes available to this process.
- A target may normalize, reject, or partially render valid Unicode after submission. No local
  success label may claim otherwise, and no automatic second attempt is allowed.
- Telemetry remains content-free: no draft text, Unicode count, payload/hash, PID, application
  identity, control value, clipboard types/data, credentials, token, audio, or stream bytes.
