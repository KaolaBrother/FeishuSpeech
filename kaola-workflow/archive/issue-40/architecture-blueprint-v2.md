# Issue #40 architecture blueprint v2 — one durable preview, one explicit output gate

Date: 2026-08-23

Repository: `/Users/ylpromax5/Workspace/feishuspeech`

Implementation worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`

Candidate inspected: `60090c955fbd57d4b6e875acb8a9bdc42d61f032`

Authority: the current GitHub Issue #40 body and its local mirror
`kaola-workflow/issue-40/.cache/github-issue-body-v2.md`. This blueprint supersedes
`architecture-blueprint.md`, D-38/D-40 wording that retains compatibility direct output, and every
test expectation that automatically copies a transcript after presenter or delivery failure.

## 1. Selected outcome and non-negotiable invariants

Every accepted Fn interaction uses exactly this product route:

```text
capture/recorder root ----\
                           +--> one generation-scoped preview authority
recognition/replay root ---/       streaming -> sealing -> editablePending -> editable
                                                                             |
                                                             explicit Send or bare Return
                                                                             |
                                                                    one delivery attempt
```

The implementation is complete only when all of these invariants hold:

1. Capture/recorder and recognition/provider/retry/replay stay separate asynchronous roots. They
   share generation identity, journal/ledger facts, and the preview model, but neither awaits the
   panel, editor readiness, acknowledgement, delivery, or the other root.
2. Both persisted values of legacy `reviewBeforeInsert`, and both persisted values of
   `autoInsert`, enter the same preview route. Neither setting may authorize a direct writer.
3. Before explicit confirmation, transcript text causes zero AX setters, zero target keyboard
   events, zero pasteboard writes, zero direct insert calls, and zero recovery copies.
4. Fn release only closes capture and projects the latest snapshot into `sealing` on the same
   `NSPanel`. Recognition may continue after the recorder barrier.
5. Action 2 and the recorder barrier freeze the best authoritative result into coordinator-owned
   draft authority. AppKit readiness is a projection of that authority, not its owner.
6. Activation rejection, inactive application, non-key panel, delayed editor materialization,
   failed first-responder assignment, readiness cancellation, and readiness timeout are typed,
   non-terminal presentation outcomes. They retain the exact draft, destination, generation,
   revision, panel, and retry/discard authority.
7. Only a Send click, bare Return, keypad Enter, or a Command-modified Return from the current
   editable draft may consume a confirmation gate. Shift-only Return/Enter inserts one LF.
   Option/Control Return and marked-text Return stay with the editor. Escape and window close
   discard with zero output.
8. One confirmation freezes the exact current untrimmed draft and creates at most one delivery
   task. A delivery implementation never retries, retargets, or recaptures automatically.
9. A current delivery failure or uncertainty restores the same frozen draft to a retryable review
   state with fixed non-sensitive feedback. It performs no recovery copy and no automatic second
   delivery. A second delivery exists only after a later explicit Send/Return.
10. Exact AX cursor authority remains preferred. The non-secure strict-AX-miss route remains bound
    to the complete original application identity. Secure Input, trust loss, incomplete identity,
    PID/launch identity drift, target change, unsafe text, and uncertain post all fail closed.
11. No transcript, edited draft, draft length/hash, target control value, clipboard payload,
    credential, token, audio/stream bytes, PID, bundle identifier, executable path, or window title
    is emitted by readiness/failure telemetry.
12. A stale generation, revision, readiness attempt, confirmation attempt, view callback, or
    delivery callback cannot mutate current authority or deliver text.

## 2. Candidate evidence and the exact defect boundary

Candidate `60090c9` already provides useful foundations that v2 must retain:

- destination capture is typed as exact cursor versus original-application current focus;
- the original complete application identity is captured before panel/audio/provider startup;
- exact delivery restores and verifies the captured AX element/selection;
- application-bound delivery uses the fixed captured PID and consecutive Secure/PID/identity
  samples;
- successful review delivery uses one multiline-safe paste transaction and guarded restoration;
- capture/journal and recognition/retry/replay remain independent; and
- review IDs/revisions already reject several stale callbacks.

The installed candidate failed because `finishReviewTransition` tears down the completed speech
session and resets the hot key before `renderEditableWhenReady` proves readiness. The presenter then
collapses every readiness miss into `.failed`, dismisses the only panel, and
`recoverReviewSurfaceFailure` copies the draft and revokes its authority. Delivery failures follow
the same destructive copy/revoke pattern in `completeReviewDelivery`.

The v2 fix is therefore not an audio, transport, retry, replay, recognition, or destination-capture
redesign. It changes four authority boundaries:

1. all settings enter review;
2. speech-session cleanup cannot revoke a frozen draft;
3. presenter readiness cannot own or destroy the draft; and
4. failure recovery returns to the draft instead of creating a clipboard/direct-output route.

## 3. Three independent axes

The coordinator must preserve three axes rather than serializing them into one state machine:

```text
capture axis
  idle -> capturing -> captureClosed -> recorderBarrierComplete -> released

recognition axis
  idle -> sessionFactory/retry/replay/live -> action2Terminal -> released

review axis
  idle -> streaming -> sealing -> editablePending -> editable -> confirming
                                                        ^             |
                                                        |--- failure --|
```

Allowed synchronization edges are deliberately narrow:

- capture packets enter `ByteBoundedAudioIngress` and `HoldPacketJournal` without UI awaits;
- recognition snapshots enter `ResponseOutputLedger` and then enqueue a cancellable, fire-and-
  forget presentation projection;
- Fn release closes capture and starts the existing recorder barrier without waiting for action 2;
- action 2 may arrive before or after the barrier; draft freeze waits for both facts;
- after both facts, speech-session resources may be torn down while draft authority remains live;
- readiness and delivery tasks read only the frozen coordinator authority and never feed back into
  capture, journal, retry, replay, or recognition scheduling.

Prohibited edges include presenter waits in `drainCapturedAudio`, `consumeAudio`, factory/retry,
journal replay, packet ACK, recorder stop, and action-2 receipt handlers. No UI condition may apply
backpressure to either asynchronous root.

## 4. Durable authority and state model

### 4.1 Coordinator-owned authority

Keep authority on `@MainActor` in `MainViewModel`. Extend the existing private
`ReviewSurfaceAuthority` rather than adding a new service or dependency:

```swift
private struct ReviewSurfaceAuthority {
    let identifier: UUID
    let generation: UInt64
    let destination: ReviewDestinationToken
    var draft: ReviewDraft?
    var revision: UInt64
    var readinessAttempt: UInt64
    var confirmationAttempt: UInt64
}

private struct ReviewDraft {
    var text: String
    let isPossiblyIncomplete: Bool
    var feedback: ReviewDraftFeedback?
}
```

These declarations are an implementation shape, not a persisted schema. `reviewDraftText` may stay
`@Published` as the editor binding, but after terminal freeze it must be a projection of
`authority.draft.text`; it cannot be a separate lifetime owner. Every accepted draft mutation must
update both under one current identifier/revision check.

Authority invariants:

- it is created only after a valid destination token is captured for the current positive
  generation and before preview/audio/provider startup;
- `draft == nil` during streaming/sealing;
- action 2 selects the authoritative final, or the latest non-empty snapshot marked incomplete,
  then the recorder barrier freezes it exactly once into `draft`;
- clearing speech-session resources, setting `status = .idle`, and resetting `HotKeyService` do
  not clear an existing frozen draft;
- a readiness attempt increments `readinessAttempt`; a confirmation increments
  `confirmationAttempt`; callbacks require exact identifier plus attempt equality;
- only explicit discard/close/Escape, explicit service/lifecycle cancellation, contentless terminal
  completion with no usable draft, successful delivery, or app cleanup may revoke authority; and
- transient presenter failure and current delivery failure are not revocation events.

Split the candidate's broad cleanup into two named responsibilities:

- `finishSpeechSessionForReview(...)`: closes retry admission, cancels post-release timeout,
  invalidates the active streaming identity, releases capture/consumer/session/journal state,
  stops overlay/timer, and resets the hot key. It does not call `revokeReviewAuthority`, dismiss the
  panel, blank the draft, or cancel the current readiness authority.
- `revokeReviewAuthority(...)`: cancels review/readiness/delivery tasks, increments revision,
  clears destination/draft/callback authority, dismisses the panel, and returns the review state to
  idle. Call it only for the terminal reasons listed above.

This separation is the core correction. A hot-key idle state and a live review draft are allowed
to coexist; the existing `handleHotKeyState(.idle)` guard and “ignore new Fn while review owns the
interaction” behavior remain.

### 4.2 Published state

Replace the payloadless/failure-collapsing review states in
`FeishuSpeech/Models/TranscriptionReviewState.swift` with:

```swift
nonisolated enum TranscriptionReviewState: Equatable, Sendable {
    case idle
    case streaming(preview: String)
    case sealing(preview: String)
    case editablePending(
        draft: String,
        isPossiblyIncomplete: Bool,
        readiness: ReviewEditableReadinessState,
        feedback: ReviewDraftFeedback?
    )
    case editable(
        draft: String,
        isPossiblyIncomplete: Bool,
        feedback: ReviewDraftFeedback?
    )
    case confirming(draft: String, isPossiblyIncomplete: Bool)
}
```

The supporting values are internal, equatable, sendable, and content-free:

```swift
nonisolated enum ReviewEditableReadinessPredicate: String, Equatable, Sendable {
    case activationRequest
    case applicationActive
    case panelKey
    case editorMaterialized
    case editorAttachedToPanel
    case editorFirstResponder
}

nonisolated enum ReviewEditableReadinessFailure: Equatable, Sendable {
    case activationRejected
    case timedOut(lastUnmet: ReviewEditableReadinessPredicate)
    case cancelled(lastUnmet: ReviewEditableReadinessPredicate?)
    case surfaceInvalidated
}

nonisolated enum ReviewEditableReadinessState: Equatable, Sendable {
    case preparing(attempt: UInt64)
    case blocked(attempt: UInt64, failure: ReviewEditableReadinessFailure)
}

nonisolated enum ReviewEditableTransitionResult: Equatable, Sendable {
    case ready
    case pending(ReviewEditableReadinessFailure)
}

nonisolated enum ReviewDraftFeedback: Equatable, Sendable {
    case activationFailed
    case destinationChanged
    case securityRejected
    case unsafeText
    case deliveryFailed
    case deliveryUncertain
    case deliveryCancelled
}
```

`ReviewDraftFeedback` is intentionally a fixed category, not an `Error`, free-form string, target
description, or transcript-derived value. The view maps it to fixed localized copy. Delivery's
existing more detailed internal result may map many cases to one safe UI category.

`InteractionOutputMode` is obsolete and must be removed from the model. There is no compatibility
case after this issue.

### 4.3 Transition table

| Current | Event | Next | Authority/output rule |
|---|---|---|---|
| `idle` | accepted Fn + safe captured destination | `streaming("")` | create authority; zero text output |
| `streaming` | changed owned snapshot | `streaming(snapshot)` | replace preview only |
| `streaming` | Fn release | `sealing(latest)` | close capture/start barrier only |
| `sealing` | later changed owned snapshot | `sealing(snapshot)` | recognition remains independent |
| `sealing` | action 2 + barrier, usable draft | `editablePending(.preparing)` | freeze draft; tear down speech session only |
| `sealing` | action 2 + barrier, no usable draft | `idle` | revoke; zero output |
| `editablePending` | readiness ready for current attempt | `editable` | same authority/draft/panel |
| `editablePending` | readiness pending/failure | `editablePending(.blocked)` | keep authority/panel; zero output |
| `editablePending` | explicit readiness retry | `editablePending(.preparing)` | increment readiness attempt only |
| `editablePending` or `editable` | edit callback | same phase with new draft | current ID/revision only |
| `editable` | Send/bare Return/compatible confirm | `confirming(frozenDraft)` | consume gate; one task |
| `confirming` | inserted | `idle` | revoke/dismiss after success |
| `confirming` | current failure/uncertainty/cancel | `editablePending(.preparing)` then `editable` or blocked | same frozen draft + safe feedback; no copy/retry |
| draft state | Escape/close/cancel/reset/sleep/cleanup | `idle` | explicit discard; zero output |
| any | stale callback | unchanged | no mutation/output |

The return from a delivery failure goes through readiness again because destination activation has
usually made FeishuSpeech inactive/non-key. It is a presentation retry, not a delivery retry. The
delivery count remains one until a later explicit confirmation.

## 5. Presenter readiness contract

### 5.1 Protocol boundary

Refactor the current presenter boundary so rendering and readiness are separate operations:

```swift
@MainActor
protocol ReviewSurfacePresenting: AnyObject {
    func renderReadOnly(phase: ReviewReadOnlyPhase, preview: String)
    func renderDraft(
        state: TranscriptionReviewState,
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor () -> Void,
        onRetryReadiness: @escaping @MainActor () -> Void,
        onDiscard: @escaping @MainActor () -> Void
    )
    func requestEditableReadiness() async -> ReviewEditableTransitionResult
    func dismiss()
}
```

`renderDraft` accepts only `editablePending`, `editable`, or `confirming`; other cases are a
programmer error and should fail closed without output. Remove the synchronous
`renderEditable(...)` fallback and the runtime cast to `ReviewEditableReadinessPresenting`: every
presenter, including fakes, must declare readiness explicitly.

The coordinator always renders `editablePending` first so the `NSTextView` is materialized before
`requestEditableReadiness` tries to assign first responder. A fake presenter returning `.ready`
does not prove production AppKit behavior; production controller tests and installed UAT remain
separate gates.

### 5.2 `ReviewWindowController` behavior

Retain one `ReviewPanel` instance across streaming, sealing, pending, editable, confirming, and
failure return. `renderDraft` updates the existing `NSHostingView.rootView`; it must not replace or
order out the panel merely because readiness is pending.

For pending/editable phases:

- `allowsKeyInteraction = true`, mouse events enabled, close enabled;
- callbacks remain generation/revision guarded by `MainViewModel`;
- the native `NSTextView` is installed before readiness probing;
- pending UI shows the draft, a fixed readiness message, Retry Editing, and Cancel; Send and Return
  confirmation are disabled/ignored until coordinator state is `editable`;
- editable UI enables editing and confirmation; and
- confirming UI keeps the frozen draft visible, disables editing/actions, and shows fixed progress.

For one readiness attempt, probe in deterministic order:

1. `NSRunningApplication.current.activate(options: [])` accepted;
2. `NSApp.isActive`;
3. current panel identity still matches and `panel.isKeyWindow`;
4. editable `NSTextView` exists;
5. `editor.window === panel`; and
6. `panel.makeFirstResponder(editor)` succeeds and `panel.firstResponder === editor`.

Notification-assisted probes for application-active and window-key may remain, with the existing
bounded polling/deadline. A probe returns the first unmet typed predicate. At timeout return
`.pending(.timedOut(lastUnmet: ...))`. Activation refusal returns
`.pending(.activationRejected)`. Cancellation returns typed pending unless explicit authority
revocation has already invalidated the surface; surface replacement/dismissal returns
`.pending(.surfaceInvalidated)` and is ignored by a stale coordinator attempt.

On every non-ready result:

- cancel only that attempt's sleeper/observers;
- do not call `dismiss`;
- do not clear draft/confirm/discard/retry callbacks;
- do not set `isEditable = false` merely to hide the surface;
- do not order out or detach the content view; and
- return the typed result to the coordinator.

An explicit Retry Editing click increments the coordinator readiness attempt and executes the same
bounded sequence. Readiness retries may repeat because they cannot touch an external destination.
They never trigger confirmation or delivery.

### 5.3 Testable AppKit seam

The candidate's readiness predicates are hard-coded against global AppKit state. Add the minimum
test seam inside `ReviewWindowController.swift`: an internal environment value composed of closures
for activation request, application-active sample, key-window sample, editor lookup/attachment,
first-responder assignment/verification, monotonic time, and bounded sleep. The default environment
uses AppKit and `ContinuousClock`; tests supply deterministic closures. Do not add a package,
global singleton, or second window implementation.

Keep one running-controller integration test using a real `ReviewPanel`/`NSHostingView` to prove the
native editor materializes and is attached. Deterministic tests own individual failure reasons;
installed `LSUIElement` Release UAT owns real accessory-app activation behavior.

## 6. The sole output gate and failure return

### 6.1 Confirmation consumption

`MainViewModel.confirmReviewDraft(reviewID:)` must guard all of:

- current authority identifier;
- state exactly `editable`;
- no confirmation in flight;
- non-contentless exact current draft;
- callback revision equals current authority revision; and
- no stale readiness task owns the surface.

Before creating the task, synchronously:

1. freeze the exact current text without trimming/normalizing;
2. increment `confirmationAttempt` and capture its value;
3. set `reviewConfirmationInFlight = true`;
4. cancel readiness work only;
5. publish/render `confirming(frozenDraft, ...)`; and
6. disable editor/confirm/retry callbacks for that projection.

Do not dismiss the panel before delivery. `ReviewDestinationDelivery.deliver` may activate the
captured app while the non-key floating panel remains visible. Only successful delivery or explicit
discard revokes/dismisses.

The delivery task captures immutable `reviewID`, `confirmationAttempt`, frozen text, and the
already-captured destination token. Completion must match both IDs before state mutation.

### 6.2 Delivery outcome mapping

| `ReviewDeliveryResult` | Coordinator result |
|---|---|
| `.inserted` | revoke authority, dismiss, reset hot key, idle |
| `.activationFailed` | retain draft, feedback `.activationFailed`, start presenter readiness |
| `.identityChanged`, `.destinationInvalid` | retain draft, feedback `.destinationChanged`, start readiness |
| `.securityRejected` | retain draft, feedback `.securityRejected`, start readiness |
| `.unsafeText` | retain draft, feedback `.unsafeText`, start readiness |
| `.deliveryFailed` | retain draft, feedback `.deliveryFailed`, start readiness |
| `.deliveryUncertain` | retain draft, feedback `.deliveryUncertain`, start readiness |
| `.cancelled` while authority is current | retain draft, feedback `.deliveryCancelled`, start readiness |
| any completion after explicit revoke | stale no-op |

For every current non-success result, set `reviewConfirmationInFlight = false`, restore the exact
frozen text as authoritative, increment revision, and enter `editablePending(.preparing)` before
requesting FeishuSpeech readiness. There is no call to delivery until a later explicit Send/Return.

Uncertainty deserves fixed UI wording that the prior attempt may have reached the target and an
explicit retry may duplicate text. That warning is a human decision aid, not an automatic action.

### 6.3 Remove clipboard recovery and direct output authority

Remove `copyForManualRecovery` from:

- `ReviewDestinationDelivering`;
- `SystemReviewDestinationDelivery`;
- `FinalTextOutput`;
- `SystemFinalTextOutput`; and
- `TextInputSimulator` if no independent call remains.

Delete `reviewCopyRecoveryIssued`, `recoverReviewSurfaceFailure`, both coordinator copy calls, and
obsolete tests/feedback that expect `manualRecoveryCopied`. No failure path may issue a second
pasteboard write to preserve the draft.

The confirmation transaction may still use the pasteboard after explicit confirmation. A
post/key-event uncertainty may leave that one transaction's pasteboard value in place because the
app cannot prove safe restoration; this is not a recovery copy. There must be no second write,
retry, fallback notification, or alternate target.

Remove direct-output authority from accepted interactions:

- delete `InteractionOutputMode`, `activeInteractionOutputMode`, `isReviewFirstMode`, and
  `sampledAutoInsert`;
- `beginStreaming` always calls `prepareReviewDestination` and always renders streaming preview;
- packet/final handlers always use `handleReviewSnapshot`/`handleReviewTerminal` for an accepted Fn
  generation;
- `beginSealing` always projects the review sealing state;
- no settings value may call `prepareCursorTarget`, `offerChangedSnapshot`,
  `finalizeExistingOutputOwner`, `CursorTextSession`, or `CurrentFocusAppendSession`; and
- remove coordinator compatibility helpers/fields when they become unreachable, but do not edit
  capture/journal/provider/retry/replay implementations merely to delete historical types.

The minimum safe stopping point is zero construction/call sites from the accepted hot-key path.
Standalone compatibility service types may remain temporarily if deleting them would expand this
bug fix into an unrelated mechanical purge. Record them as dormant, prove no production caller,
and schedule deletion separately only if desired. They are not an allowed route.

## 7. Legacy settings migration

This issue uses a behavioral migration, not a persisted-schema migration:

- continue decoding `reviewBeforeInsert` when present and defaulting it when absent;
- continue decoding/preserving `autoInsert` so an unrelated preference rewrite does not corrupt an
  older payload;
- ignore both fields when choosing interaction output behavior;
- remove the `输入前预览` route toggle and conditional `自动插入文字` control from `SettingsView`;
- replace the conditional help copy with one statement that every interaction opens preview and
  requires Send/Return; and
- preserve credentials, Keychain migration, `playSound`, and `launchAtLogin` unchanged.

Do not remove Codable keys in this issue. Both legacy boolean values must round-trip without decode
failure, but runtime tests must prove identical preview behavior. Removing the dead stored keys is
a future schema-cleanup decision, not required for Issue #40.

`MainViewModel.updateSettings` may retain the two legacy parameters for source/test compatibility,
or receive the existing stored values unchanged from the view; either way it must not restore a
runtime branch. Prefer the smaller diff. The settings UI is no longer an authority surface.

## 8. Destination security and exact-once rules retained

No change may weaken candidate `60090c9` security:

### Exact cursor binding

- token generation and cursor generation match;
- captured application PID and cursor PID match;
- complete application identity remains running and becomes frontmost after one bounded activation;
- Accessibility trust and Secure Input are checked before mutation;
- only the captured element is focused;
- original selection is restored and reread exactly;
- one process-targeted Cmd+V transaction occurs;
- postflight revalidates element/selection/security/application; and
- postflight failure is uncertain and never automatically retried.

### Application-current-focus binding

- used only after a non-secure strict AX capability miss;
- carries the complete application identity captured before preview/audio/provider startup;
- never stores or discovers a replacement AX element/caret;
- activation targets that exact identity once;
- two consecutive pre-mutation composite samples keep Secure Input off, raw frontmost PID fixed,
  and running/frontmost identities complete and equal to the captured identity;
- one Cmd+V transaction targets the captured PID, never an ambient sampled PID;
- one equivalent postflight composite sample follows; and
- any drift or uncertainty fails closed.

### Shared exact-once layers

1. Coordinator gate: one current `confirmationAttempt` task.
2. Delivery router: one activation/routing pass, no retry/recapture/retarget.
3. Final output transaction: one pasteboard replacement and one complete Cmd+V pair.
4. Callback fence: result applies only to matching review and confirmation attempt.

An explicit user retry after a reported failure creates a new confirmation attempt. This is not an
automatic retry. The UI must preserve the uncertainty warning until the user edits, retries, or
discards.

## 9. Privacy-safe telemetry

Add typed readiness telemetry at the coordinator/controller boundary. Permitted fields:

- event name: `review_readiness_started`, `review_readiness_pending`,
  `review_readiness_ready`, `review_readiness_cancelled`;
- interaction generation number;
- readiness attempt ordinal;
- predicate enum raw value;
- result enum raw value; and
- bounded elapsed milliseconds or timeout bucket.

Example log shape, with only fixed/public values:

```text
review_readiness_pending generation=7 attempt=2 result=timedOut predicate=panelKey elapsedMs=2000
```

Forbidden fields include transcript/draft text, text length/hash, preview, target field contents,
AX value/selection, clipboard contents/change payload, PID, bundle ID, executable path, application
name, window title, credentials, tokens, request/response bodies, and audio/stream bytes.

Do not emit one log per 20 ms poll. Emit attempt start, the final typed outcome, and optionally one
predicate transition when it changes. This keeps evidence useful without producing a timing trace
of user content. Existing transcript-free lifecycle logs may remain.

UI feedback is also fixed and non-sensitive. It may name the failure category (“无法激活预览”,
“目标已变化”, “投递状态不确定”) but never echo the draft or target application.

## 10. File ownership and changes

### Production files to modify

| File | Required change |
|---|---|
| `FeishuSpeech/Models/TranscriptionReviewState.swift` | Remove compatibility output mode; add pending/confirming payloads, typed readiness predicates/failures/state, and fixed draft feedback. |
| `FeishuSpeech/ViewModels/MainViewModel.swift` | Make review unconditional; make draft authority durable; split speech cleanup from authority revoke; run typed readiness attempts; keep same panel on confirming; return failures to the same draft; remove copy/direct-output route authority. |
| `FeishuSpeech/Controllers/ReviewWindowController.swift` | Separate render from readiness; retain one panel/callback set on failures; materialize editor before first responder; return typed reasons; add minimal deterministic AppKit seam and retry-safe cleanup. |
| `FeishuSpeech/Views/TranscriptionReviewView.swift` | Render pending/editable/confirming from the same draft; add Retry Editing and fixed feedback; disable confirmation until editable; preserve D-39 keyboard behavior and discard gestures. |
| `FeishuSpeech/Services/ReviewDestinationDelivery.swift` | Remove recovery-copy API; retain exact/application-bound capture, delivery, activation, identity, security, and result typing unchanged. |
| `FeishuSpeech/Services/TextInputSimulator.swift` | Remove recovery-copy surface and any now-unused automatic paste fallback; retain the explicit-confirmation review paste transaction and exact-once uncertainty behavior. |
| `FeishuSpeech/Views/SettingsView.swift` | Remove legacy route/direct-output controls and conditional copy; show the one preview route while preserving unrelated settings. |
| `FeishuSpeech/Models/AppSettings.swift` | No schema removal; at most clarify that legacy booleans are decode/preservation inputs only. Do not touch credential migration. |

`CursorTextModels.swift` and `AccessibilityClient.swift` should not change unless compilation or a
new security test proves a candidate defect. Their v2 destination authority is already useful.

### Test files to add or update

| File | Required coverage |
|---|---|
| `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift` | Durable pending authority; typed readiness failures; exact draft retention; explicit retry; one task per confirmation; no copy/direct output; both legacy settings values; stale fences. |
| `FeishuSpeechTests/TranscriptionReviewViewTests.swift` | Pending/retry/confirming UI; Send/Return-only gate; Shift-only newline; IME/modifier routing; fixed feedback; Escape/close discard. |
| `FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift` (new) | Deterministic predicate/result matrix, no dismissal/callback clearing, same panel across retry, real editor materialization/attachment. |
| `FeishuSpeechTests/ReviewDestinationDeliveryTests.swift` | Exact/application-bound security stays intact; no recovery-copy API or second output after failure. |
| `FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift` | Application fallback preview independence, current failure preserves draft, no copy, explicit retry only. |
| `FeishuSpeechTests/ReviewPasteboardLifecycleTests.swift` | Preflight failure zero writes; success restoration; uncertainty has one transaction write, no recovery write/retry/automatic restore. |
| `FeishuSpeechTests/FinalTextOutputSecurityTests.swift` | Fixed PID, consecutive samples, unsafe text before mutation, exact-once post, removed legacy direct/recovery expectations. |
| `FeishuSpeechTests/AppSettingsCredentialStorageTests.swift` | Both legacy values decode/round-trip without credential impact. |
| `FeishuSpeechTests/StreamingMainViewModelTests.swift` | Accepted interactions no longer construct compatibility writers; capture/journal/retry/replay topology remains green. |

### Protected production surfaces

Do not edit these without separate, source-backed evidence of a defect:

- `FeishuSpeech/Services/AudioRecorder.swift`
- `FeishuSpeech/Services/ByteBoundedAudioIngress.swift`
- `FeishuSpeech/Services/HoldPacketJournal.swift`
- `FeishuSpeech/Services/FeishuStreamingSession.swift`
- streaming transport/socket/provider/session files
- retry/replay, capture drain, packet journal, and recognition consumer loops in
  `MainViewModel.swift`
- hot-key state/generation semantics
- credentials, Keychain store, entitlements, Info.plist, dependencies, and Xcode build settings

## 11. Dependency-safe TDD build sequence

Test artifacts remain under a test custodian. Production implementers may read/run but never edit
those tests.

### Task 1 — RED coordinator authority and sole-gate contract (test custodian)

Owned tests:

- `ReviewFirstMainViewModelTests.swift`
- the review-route cases in `StreamingMainViewModelTests.swift`

Add failing cases for every readiness reason, same draft/authority after failure, false/true legacy
settings convergence, no compatibility writer construction, explicit confirmation exact-once,
delivery failure return, explicit second confirmation, and stale attempt suppression. Every case
records clipboard writes, AX setters, keyboard posts, direct inserts, presenter dismissals, and
delivery calls separately.

### Task 2 — RED AppKit presentation contract (test custodian)

Owned tests:

- `TranscriptionReviewViewTests.swift`
- new `ReviewWindowControllerReadinessTests.swift`

Add the typed predicate matrix, timeout/cancellation behavior, same-panel retention, callbacks after
retry, pending/confirming UI, D-39 key matrix, and real editor materialization/attachment.

### Task 3 — RED delivery/no-copy security contract (test custodian)

Owned tests:

- `ReviewDestinationDeliveryTests.swift`
- `ReviewFirstApplicationFallbackTests.swift`
- `ReviewPasteboardLifecycleTests.swift`
- `FinalTextOutputSecurityTests.swift`

Replace all one-copy recovery expectations with zero-copy/draft-retention expectations. Preserve
exact/application identity, Secure/PID samples, fixed PID, text safety, one post, uncertainty, and
clipboard restoration or non-restoration rules.

### Task 4 — RED settings migration contract (test custodian)

Owned test:

- `AppSettingsCredentialStorageTests.swift`

Prove absent/true/false legacy review values decode, preserve unrelated preferences/credentials,
and cannot affect the runtime route. The runtime half may be asserted in Task 1 to avoid duplicate
fixtures.

Tasks 1–4 are genuinely independent test writes: they touch disjoint test files, and none produces
an artifact consumed by another. They may be authored in parallel. All four RED receipts must land
before production behavior changes.

### Task 5 — typed state model (production implementer)

Owned production file:

- `FeishuSpeech/Models/TranscriptionReviewState.swift`

Implement section 4.2 only. This task blocks controller/view and coordinator compilation.

### Task 6 — presenter and view (production implementer)

Owned production files:

- `FeishuSpeech/Controllers/ReviewWindowController.swift`
- `FeishuSpeech/Views/TranscriptionReviewView.swift`

Depends on Task 5. Implement section 5 and the pending/editable/confirming UI. Run Tasks 2 tests;
do not edit them.

### Task 7 — delivery API cleanup (production implementer)

Owned production files:

- `FeishuSpeech/Services/ReviewDestinationDelivery.swift`
- `FeishuSpeech/Services/TextInputSimulator.swift`

Remove recovery copy while preserving the candidate's security and exact-once transaction. This
task is genuinely independent of Task 6 after Task 5: it touches different files and neither
implementation consumes the other's output. Run Task 3 tests; do not edit them.

### Task 8 — settings UI migration (production implementer)

Owned production files:

- `FeishuSpeech/Views/SettingsView.swift`
- `FeishuSpeech/Models/AppSettings.swift` only if a decode/preservation clarification is required

This task is genuinely independent of Tasks 6 and 7 because it touches different files and keeps
the existing `MainViewModel.updateSettings` call shape. Do not remove Codable keys or touch
credential migration. Run Task 4 tests; do not edit them.

### Task 9 — coordinator convergence and durable authority (production implementer)

Owned production file:

- `FeishuSpeech/ViewModels/MainViewModel.swift`

Depends on Tasks 5–8. Implement sections 3, 4, and 6: unconditional review route, split cleanup,
durable draft, typed readiness/retry, confirming projection, failure return, exact attempt fences,
and removal of recovery/direct-output authority. Do not edit protected async loops. Run Task 1 and
all focused suites; do not edit tests.

### Task 10 — independent correctness and security review

Correctness review checks:

- state exhaustiveness and legal transitions;
- same panel/draft across every readiness reason;
- speech cleanup cannot revoke draft;
- confirm is synchronous and exact-once;
- failure return creates no automatic delivery;
- explicit retry uses a new confirmation attempt;
- all stale identifiers/attempts are fenced; and
- capture/recognition roots gained no UI await/backpressure.

Security review checks:

- zero output before explicit confirmation;
- no recovery copy or compatibility route;
- exact cursor preference and restore/revalidation;
- complete application identity and fixed-PID fallback;
- consecutive Secure/PID/identity sampling;
- unsafe text before mutation;
- uncertainty never retries/retargets;
- telemetry contains only permitted enum/numeric fields; and
- no transcript/target/clipboard/credential data in logs or fixed UI.

Behavior/test-oracle gaps return to the test custodian. Production correctness/security fixes return
to the owning implementer. Build/type/lint/tool failures route to the build-error resolver.

### Task 11 — verified documentation and release docking

After tests, reviews, installed UAT, and final implementation are stable, the documentation owner
updates:

- `README.md`
- `CHANGELOG.md`
- `docs/README.md`
- `docs/architecture.md`
- `docs/streaming-speech-design.md`
- D-38/D-39/D-40 decisions, with a new superseding decision or an explicit D-40 amendment

Dock the measured readiness reason and final UAT evidence into Issue #40. `docs/api.md` has no
impact unless the Feishu API/transport contract changes; this blueprint does not authorize that.

## 12. Validation commands

Run from `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`.

### Focused review/readiness/security gate

```bash
xcodebuild \
  -scheme FeishuSpeech \
  -destination 'platform=macOS,arch=arm64' \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests \
  -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests \
  -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests \
  -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests \
  -only-testing:FeishuSpeechTests/AppSettingsCredentialStorageTests \
  test
```

### Full serialized regression gate

```bash
xcodebuild \
  -scheme FeishuSpeech \
  -destination 'platform=macOS,arch=arm64' \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  test
```

### Build, lint, and diff hygiene

```bash
xcodebuild -scheme FeishuSpeech -configuration Debug build
xcodebuild -scheme FeishuSpeech -configuration Release build
swiftlint --strict
git diff --check
```

### Protected topology and forbidden-route guards

```bash
git diff --exit-code 60090c9 -- \
  FeishuSpeech/Services/AudioRecorder.swift \
  FeishuSpeech/Services/ByteBoundedAudioIngress.swift \
  FeishuSpeech/Services/HoldPacketJournal.swift \
  FeishuSpeech/Services/FeishuStreamingSession.swift

rg -n 'copyForManualRecovery|reviewCopyRecoveryIssued|recoverReviewSurfaceFailure' \
  FeishuSpeech FeishuSpeechTests

rg -n 'InteractionOutputMode|activeInteractionOutputMode|sampledAutoInsert|isReviewFirstMode' \
  FeishuSpeech

rg -n 'reviewBeforeInsert.*\?|compatibility\(|prepareCursorTarget\(' \
  FeishuSpeech/ViewModels/MainViewModel.swift

rg -n 'captureDrainTask|consumerTask|holdPacketJournal|retrySleepTask|sessionCreationTask' \
  FeishuSpeech/ViewModels/MainViewModel.swift

rg -n 'renderEditable|requestEditableReadiness|await .*reviewSurface|await .*present' \
  FeishuSpeech/ViewModels/MainViewModel.swift
```

The first command must be silent. The next three route/recovery searches must return no production
authority/call sites; historical test names must be renamed rather than left asserting obsolete
behavior. The final two searches are human review aids: verify no presenter await entered capture,
journal, provider, retry, replay, or consumer loops.

### Installed Release UAT gate

Automated green is insufficient. Build a fresh Release from the final Issue #40 commit, install
that artifact, terminate stale copies, and verify the running executable is the intended
`/Applications/FeishuSpeech.app/Contents/MacOS/FeishuSpeech` before interaction evidence.

Run at least these flows in two third-party editable targets, including one exact-AX target and one
ordinary non-secure strict-AX-miss target:

1. hold Fn: one panel streams; clipboard/target remain unchanged;
2. release Fn: same panel stays in sealing while recorder closes and recognition may continue;
3. action 2 + barrier: same panel becomes editable; edit text and confirm with bare Return;
4. repeat with Send and with multiline Shift+Return then confirmation;
5. force each measurable readiness blocker/timeout where practical; record typed telemetry and
   prove the draft/panel survive with zero copy/output;
6. force activation/identity/security/preflight/postflight failures; prove same draft returns with
   fixed feedback, no copy, no automatic retry, and no alternate target;
7. after an uncertain result, exercise explicit discard and separately an explicit retry while
   observing the duplication warning; and
8. switch applications and enable Secure Input to prove fail-closed, application-bound behavior.

Evidence must include timestamps, final commit SHA, built/installed bundle version, running path/PID,
typed readiness outcomes, state sequence, delivery attempt count, and clipboard/target mutation
counts. It must not include transcript, target control contents, clipboard contents, credentials,
tokens, or audio/stream bytes.

Issue #40 stays open and the candidate stays unpublished until both target flows complete from
streaming through editable and explicit delivery, all failure gates preserve the draft, and final
correctness/security reviews accept the exact implementation.

## 13. Migration, rollback, and failure routing

### Migration

- No database, network, keychain, dependency, entitlement, or Xcode project migration.
- Legacy settings booleans remain decodable/preserved but behaviorally inert.
- Existing users see the preview route regardless of the stored value on their first run of the new
  build; no manual action is required.
- Draft authority is memory-only and generation-scoped; the issue does not add disk persistence.

### Rollback

The technical rollback is a source/test/docs revert because no stored schema is removed. Do not
roll back by re-enabling direct output or recovery copy inside Issue #40; that contradicts the
canonical product contract. If release UAT still cannot obtain editable readiness, keep the issue
open, preserve `editablePending`, and use the typed telemetry to repair the measured predicate.

### Failure routing

- If the exact readiness predicate remains unmeasured, improve only the typed probe/telemetry and
  rerun installed UAT; do not infer from a generic timeout.
- If AppKit cannot make the current panel ready, retain the panel/draft and expose Retry/Discard;
  do not create a clipboard, notification, alternate window, or direct-output fallback.
- If application identity or Secure Input cannot be proven, fail delivery closed and retain the
  draft; do not weaken completeness, sample count, ordering, or fixed target PID.
- If a post may have happened, report uncertainty and require a human decision before a later
  explicit retry; do not restore/retry automatically.
- If removing the compatibility branch changes capture/retry/replay behavior, revert that hunk and
  route snapshots to review at the existing decision point; do not rewrite protected roots.
- If deterministic readiness tests pass but installed accessory-app UAT fails, treat the UAT as the
  higher-fidelity fact and keep Issue #40 open.

## 14. Deliberate limits

- The application-bound fallback proves the original application, not an unavailable original
  control/caret inside that application. Exact AX authority remains the only route that restores a
  specific element/selection.
- The draft survives transient readiness and delivery failures only in process memory. Crash-safe
  transcript persistence is not requested and would create a new privacy/storage decision.
- Legacy setting keys and standalone compatibility service types may remain dormant for one
  release if they have zero production construction/call sites. Removing stored keys or performing
  a broad source purge is separate work.
- Local event submission cannot prove that every third-party control consumed Cmd+V. Installed UAT
  is required and postflight uncertainty remains explicit.

These limits do not weaken the core contract: one durable in-memory draft, one panel, one explicit
output gate, application-bound security, and no automatic recovery route.
