# Issue #38 review-first implementation blueprint

Date: 2026-08-22

Implementation worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-38`

Branch: `workflow/issue-38`

Contract authority: GitHub issue #38. The later documentation task must record the accepted
contract in `docs/decisions/D-38-01.md`, superseding the no-preview clauses in D-25/D-27 only when
review-first mode is enabled.

## 1. Outcome and fixed product decisions

Issue #38 adds a default-on review-first route while retaining the present route behind an explicit
compatibility setting:

```text
capture axis:          idle -> streaming -------------> sealing ----------------> idle
recognition axis:      idle -> consuming/retrying ----> draining/action-2 ------> idle
review axis (default): idle -> streaming(read-only) --> sealing(read-only) -----> editable
                                                                                |-> confirming -> idle
                                                                                \-> discard ----> idle

compatibility:          idle -> streaming -> sealing -> idle | error
```

The review state is an independent third axis, matching the useful part of KaolaTerminal's current
`VoiceReviewState`: the read-only surface is visible throughout physical hold and sealing, every
new complete opaque snapshot replaces its preview, action-2 changes that same visual surface into
the editable draft, and only the explicit editable-state action can deliver text. FeishuSpeech must
not copy the iOS/tmux destination type, terminal UI, gesture controller, or transport
implementation.

The following decisions are already made by issue #38 and are not implementation options:

1. `reviewBeforeInsert` (user-facing copy: **“输入前预览”**) defaults to `true`. When it is `true`,
   explicit confirmation is the insertion authority and the existing `autoInsert` preference does
   not disable that confirmation. When it is `false`, the current continuous-output path, including
   the current meaning of `autoInsert`, remains the compatibility behavior.
2. An interaction samples the two preferences once at accepted-Fn start. Changing Settings during
   a hold or while a draft exists affects the next interaction only; it cannot change the active
   output route.
3. In review-first mode no partial, replay, nonterminal final, action-2 final, or late callback may
   instantiate a live cursor writer, an append session, a pasteboard write, or a synthetic key
   event. Recognition text exists only in memory until confirmation.
4. Immediately after strict target capture succeeds for an accepted Fn hold, show a separate
   nonactivating read-only review surface with fixed “正在聆听…” empty-state copy. Each newly owned,
   changed, complete opaque snapshot replaces the visible preview; it is never appended as a delta.
5. Fn release changes that same visible surface to read-only sealing without hiding/recreating it.
   The authoritative non-contentless action-2 value then becomes the initial editable draft. If action-2
   is contentless and a prior usable opaque snapshot exists, that exact snapshot becomes the draft
   with a fixed “可能不完整” warning. If neither exists, return to idle without opening an empty
   editor.
6. The surface remains nonactivating and read-only during streaming/sealing. The transition to
   editable enables key/main-window authority on the existing panel, activates FeishuSpeech, and
   focuses the editor only after action-2 has frozen the draft. It does not query or recapture a
   target.
7. `Command+Return` and the **输入** button confirm. Bare Return edits the multiline draft. Escape,
   the **取消** button, and closing the review window discard. A whitespace-only draft remains
   editable and cannot confirm.
8. Confirmation is consumed before the first `await`; a double click, repeated shortcut, late
   callback, or stale task cannot deliver a second time. Discard performs no target, key-event, or
   pasteboard operation.
9. A pending editable draft blocks a new accepted Fn interaction. The new hot-key identity is reset
   to idle without starting audio/network work and cannot replace the draft.
10. Confirm never targets ambient current focus. It dismisses the editor, activates the captured
   application with a bounded wait, restores and verifies the captured AX element and original
   selection, and only then performs one process-targeted paste transaction.
11. The review route never writes `kAXSelectedTextAttribute`. AX may write only the focused flag and
   `kAXSelectedTextRangeAttribute`; the destination application owns text replacement through
   Cmd+V. The existing compatibility-only `CursorTextSession` is not expanded or reused by the
   review route.
12. Any application-identity, activation, Accessibility, focus, selection, secure-input, safety, or
    delivery uncertainty fails closed. The frozen edited draft is copied once for manual recovery,
    with transcript-free feedback and no automatic retry.
13. Review rendering is fire-and-forget main-actor presentation, never a continuation or awaited
    animation. It adds no buffer, stream, `AsyncSequence`, task dependency, or backpressure edge to
    either `captureDrain`/journal production or recognition consumer/retry/replay consumption.
14. `OverlayWindowController.swift` and `RecordingOverlayView.swift` are outside the issue. Their
    status-only behavior and issue #37 owner-UAT gate remain unchanged.

## 2. Current-code facts that constrain the design

- `MainViewModel` currently selects `CursorTextSession` or
  `CurrentFocusProvisionalOutputSession` before capture. Both can mutate the target while Fn is
  held, so review-first must branch before `prepareCursorTarget` and never arm either writer.
- `ResponseOutputLedger` currently both suppresses journal replay and emits transcript-shape
  metrics. The review branch may reuse its in-memory reservation/claim semantics, but must not call
  the existing receipt logger: issue #38 forbids transcript content, hashes, or transcript-derived
  diagnostics from the review route.
- `CursorDestinationToken` already binds generation, PID, exact `AXUIElement`, and original
  selection. It does not bind process-reuse-safe application identity and its current capture path
  requires `kAXSelectedTextAttribute` to be settable. A review-specific capture is therefore
  required; weakening or repurposing `captureDestination` would risk compatibility mode.
- `SystemFinalTextOutput.insertOnce` already targets Cmd+V to a captured PID and checks a closure
  before and after posting, but the same closure cannot require the original selection both before
  and after paste. Add a two-phase overload instead of a stateful validation closure.
- `AppSettings.load()` decodes private `StoredSettings`. Adding a non-defaulted stored property
  would make every old JSON payload fail wholesale, so migration must use an explicit
  `decodeIfPresent(... ) ?? true` path.
- `HotKeyService` already rejects a press while its own state is `.sealing`, but becomes idle after
  streaming cleanup. The unresolved-review gate therefore belongs to `MainViewModel`, which can
  reject the next `.streaming(identity)` and call `resetToIdle()` without changing the event tap.
- `MainViewModel` currently has two causally separate asynchronous lines: `captureDrainTask` admits
  recorder bytes into `HoldPacketJournal`, while `consumerTask` creates/retries sessions, replays
  journal entries, consumes live packets, and finishes. Review UI is a downstream synchronous
  observation of already-owned events. Neither task topology, journal wakeup, retry admission,
  replay ordering, nor recorder barrier may gain a dependency on review presentation.
- Production and test roots are `PBXFileSystemSynchronizedRootGroup`s. New Swift files join their
  targets automatically; do not edit `FeishuSpeech.xcodeproj/project.pbxproj` for membership.

## 3. Non-goals and forbidden shortcuts

This issue must not:

- modify Feishu transport, retry/journal, PCM ingress, recorder sealing, action sequencing, or
  post-release drain policy;
- make the recording overlay editable or transcript-bearing, or resolve #37 speculatively; the
  visible streaming preview is a separate review surface layered alongside the unchanged overlay;
- retarget to the application focused after review, synthesize navigation/deletion/Return, or fall
  back to current-focus Unicode events;
- persist the draft in UserDefaults, Keychain, files, state restoration, diagnostics, crash reports,
  notification bodies, window titles, logs, hashes, or accessibility labels/help strings;
- retry delivery after confirmation, because a failed postflight may mean the target already
  consumed the paste;
- change dependencies, deployment target, entitlements, bundle identity, Xcode build settings, or
  the public API;
- remove the compatibility route or rewrite `CursorTextSession` merely to share review code.
- make capture/journal or recognition/retry/replay await a window animation, editor readiness,
  layout, focus, dismissal, or any review-surface acknowledgement.

## 4. Chosen types and internal APIs

All APIs below are internal. UI, AX, `NSWorkspace`, window, and delivery ownership stays on
`@MainActor`. No token containing `AXUIElement` is `Sendable` or leaves the main actor.

### 4.1 Review state and authority

Create `FeishuSpeech/Models/TranscriptionReviewState.swift` with:

```swift
nonisolated enum TranscriptionReviewState: Equatable, Sendable {
    case idle
    case streaming(preview: String)
    case sealing(preview: String)
    case editable(draft: String, isPossiblyIncomplete: Bool)
    case confirming
}

nonisolated enum InteractionOutputMode: Equatable, Sendable {
    case reviewFirst
    case compatibility(autoInsert: Bool)
}
```

`TranscriptionReviewState` is a business state, not the recording overlay model. Never interpolate
it with `String(describing:)`, because three cases contain transcript data. The required per-file
logger may emit only fixed lifecycle tags.

State authority is exact:

- accepted Fn plus captured destination opens `.streaming(preview: "")` independently of recorder
  start/session creation;
- each newly owned changed complete snapshot replaces only the preview payload;
- physical release alone changes streaming to `.sealing` while retaining the last preview;
- action-2 terminal authority alone changes sealing to `.editable` (or dismisses when no usable
  text); retry/failure callbacks cannot manufacture editable authority;
- editor mutation is accepted only in `.editable`; recognition callbacks are ignored there;
- review presentation observes this axis but never drives capture or recognition state.

`MainViewModel` owns one private `PendingReviewAuthority`:

```swift
private struct PendingReviewAuthority {
    let reviewIdentifier: UInt64
    let streamingIdentity: StreamingSessionIdentity
    let destination: ReviewDestinationToken
    var bestUsableSnapshot: String?
    var isPossiblyIncomplete: Bool
}
```

The published state owns the editable string for SwiftUI binding; the private authority owns the
destination and identity. There is never a second transcript copy inside the destination token.
`reviewIdentifier` increases monotonically per accepted review interaction and gates window
callbacks and the delivery task.

Expose only these review operations from `MainViewModel`:

```swift
@Published private(set) var transcriptionReviewState: TranscriptionReviewState
var reviewDraftText: String { get set }
func confirmReviewDraft()
func discardReviewDraft()
```

The draft setter mutates only the matching `.editable` case. `confirmReviewDraft` is synchronous at
its authority boundary: validate non-contentless text, freeze the exact untrimmed value, transition
to `.confirming`, dismiss the window, and start the async delivery task. The transition happens
before task creation/await so repeated confirm calls are no-ops.

### 4.2 Captured application and destination identity

Add the following values to `CursorTextModels.swift`, alongside the existing cursor token:

```swift
nonisolated struct ReviewApplicationIdentity: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String
    let executableURL: URL
    let launchDate: Date
}

struct ReviewDestinationToken {
    let cursor: CursorDestinationToken
    let application: ReviewApplicationIdentity
    let capturedSecurityState: DestinationSecurityState
}
```

PID alone is not identity because it can be reused. Capture succeeds only when the running
application supplies a nonempty bundle identifier, executable URL, and launch date. Every later
comparison requires equality of all four fields. Missing values are uncertainty, not a reason to
relax validation.

Add a companion protocol rather than widening every existing `AccessibilityClient` test double:

```swift
@MainActor
protocol ReviewDestinationAccessing: AnyObject {
    func captureReviewCursorDestination(generation: UInt64) throws -> CursorDestinationToken
    func restoreAndValidateBeforeDelivery(_ token: CursorDestinationToken) throws -> Bool
    func validateAfterDelivery(_ token: CursorDestinationToken) throws -> Bool
}
```

`MacAccessibilityClient` conforms to both `AccessibilityClient` and
`ReviewDestinationAccessing`. Extend `AccessibilityRuntime` only with a default-failing
`setFocused(_:on:)` method so old fakes remain source-compatible; the system runtime implements it
with `kAXFocusedAttribute`. Running-application identity lookup belongs to the separately injected
`ReviewApplicationRuntime` in `SystemReviewDestinationDelivery`, not to raw AX. The delivery
service combines the returned cursor token and the exact application identity into
`ReviewDestinationToken`; the AX adapter never has to know bundle/path/launch metadata.

Review capture is read-only and ordered:

1. prove AX trust and Secure Event Input off;
2. query the focused element once, read its PID, and require it to equal the frontmost PID;
3. prove a supported non-secure editable role/subrole using the existing allowlist;
4. read the exact selected range and require `kAXSelectedTextRangeAttribute` settable;
5. require `kAXFocusedAttribute` settable, because the editor will take focus;
6. capture the complete running-application identity and recheck frontmost PID;
7. return a token with `.safe` security state.

It must not query whether `kAXSelectedTextAttribute` is settable and must not call any AX setter.
Capture failure is a fixed startup error before audio/network work, not an unbound-current-focus
fallback.

Before delivery, the composite service first verifies exact running-application identity and
frontmost PID. `restoreAndValidateBeforeDelivery` then performs only the AX/security portion:

1. verifies AX trust and safe security state;
2. writes `kAXFocusedAttribute = true` only to the captured element;
3. re-queries the system focused element and requires `CFEqual` with the captured element;
4. writes the captured `kAXSelectedTextRangeAttribute`;
5. re-reads and requires the exact original selection.

The composite service then samples exact application identity, focus, selection, and security once
more before authorizing pasteboard mutation. This keeps application identity in
`ReviewApplicationRuntime` and AX operations in `ReviewDestinationAccessing`.

`validateAfterDelivery` rechecks exact application identity, frontmost PID, exact focused AX element,
and safe security state. It does not require the original selection after Cmd+V because the target
application owns replacement and caret placement.

### 4.3 Bounded application activation

Create `FeishuSpeech/Services/ReviewDestinationDelivery.swift` with an injected activation seam:

```swift
@MainActor
protocol ReviewApplicationRuntime: AnyObject {
    func identity(for processIdentifier: pid_t) -> ReviewApplicationIdentity?
    func frontmostIdentity() -> ReviewApplicationIdentity?
}

@MainActor
protocol ReviewApplicationActivating: AnyObject {
    func activateAndWait(
        for identity: ReviewApplicationIdentity,
        timeoutNanoseconds: UInt64
    ) async -> ReviewActivationResult
}
```

`SystemReviewApplicationRuntime` maps `NSRunningApplication` into the four-field identity and is
used by both capture composition and delivery revalidation. It returns `nil` when any required
field is absent; callers never compare an optional subset. Tests inject a deterministic runtime and
never depend on the developer machine's frontmost application.

`ReviewActivationResult` has only typed, transcript-free outcomes: `.activated`, `.notRunning`,
`.identityChanged`, `.requestRejected`, `.timedOut`, and `.cancelled`.

`WorkspaceReviewApplicationActivator` uses only AppKit already installed by the project. It:

1. resolves `NSRunningApplication(processIdentifier:)` and verifies the complete identity;
2. installs the `NSWorkspace.didActivateApplicationNotification` observer before requesting
   activation, closing the missed-notification race;
3. returns immediately only if the exact captured app is already frontmost;
4. requests activation once with `NSRunningApplication.activate(options: [])` (the SDK-verified
   no-option form; do not use deprecated `.activateIgnoringOtherApps`);
5. races a matching activation/frontmost verification against a 2-second timeout;
6. removes the observer on success, failure, timeout, or task cancellation;
7. ignores notifications for every other PID and never activates a substitute application.

Two seconds is the bounded implementation constant. A timeout copies for recovery; it is not
extended or retried.

### 4.4 Paste transaction and delivery result

Keep `FinalTextOutput` as the sole pasteboard/key-event primitive. Add, without removing the
existing overload, a two-phase `insertOnce` overload:

```swift
func insertOnce(
    _ text: String,
    destination: CursorDestinationToken,
    validateBeforeMutation: () throws -> Bool,
    validateAfterPosting: () throws -> Bool
) -> FinalTextInsertionResult
```

The new overload performs in this order:

1. reject contentless or unsafe automatic-paste text;
2. run `validateBeforeMutation`;
3. only now replace pasteboard contents;
4. post one complete Cmd+V pair to the captured PID;
5. run `validateAfterPosting` once;
6. return `.inserted` or a typed failure.

Add `.deliveryUncertain` to distinguish any failure after the pasteboard write/key posting boundary
from a certain preflight rejection. Do not retry either result. `copyForManualRecovery` remains the
only recovery primitive and deliberately leaves the exact frozen draft on the general pasteboard.

`SystemReviewDestinationDelivery` composes the activator, review AX access, and
`FinalTextOutput`:

```swift
@MainActor
protocol ReviewDestinationDelivering: AnyObject {
    func capture(generation: UInt64) throws -> ReviewDestinationToken
    func deliver(
        _ frozenText: String,
        to destination: ReviewDestinationToken
    ) async -> ReviewDeliveryResult
    func copyForManualRecovery(_ frozenText: String)
}
```

`ReviewDeliveryResult` separates `.inserted`, `.activationFailed`, `.identityChanged`,
`.destinationInvalid`, `.securityRejected`, `.unsafeText`, `.deliveryFailed`,
`.deliveryUncertain`, and `.cancelled`. It contains no transcript, app name, bundle ID, path, AX
description, or raw error.

`capture(generation:)` first obtains the review cursor token, resolves the exact running identity
for that cursor PID, and requires the same identity to be frontmost before it returns the combined
token. Delivery first waits for activation, requires `ReviewApplicationRuntime` to return the same
running and frontmost identity, then restores/full-validates `destination.cursor`, and finally calls
the two-phase paste overload with that cursor token. Its pre-mutation closure rechecks the exact
running/frontmost application identity plus AX focus/selection/security; its post-posting closure
rechecks exact application identity plus AX focus/security. Every non-`.inserted` result is terminal.
After rechecking that the review ID is still current, `MainViewModel` calls
`copyForManualRecovery` exactly once for a non-cancellation failure and presents existing
`.manualRecoveryCopied` status-only feedback. `.deliveryUncertain` remains distinct internally for
review/testing, but fixed UI feedback must not claim that automatic input definitely failed. A
`.cancelled` result from reset/sleep/termination belongs to revoked authority and performs no copy.

### 4.5 Review surface and safe macOS mode transition

Create `FeishuSpeech/Controllers/ReviewWindowController.swift` and
`FeishuSpeech/Views/TranscriptionReviewView.swift`.

`ReviewSurfacePresenting` is a synchronous, nonthrowing main-actor protocol. “Synchronous” means
each presenter command has bounded immediate AppKit work and no completion continuation; it does
**not** authorize either data line to invoke the presenter directly:

```swift
nonisolated enum ReviewReadOnlyPhase: Equatable, Sendable {
    case streaming
    case sealing
}

nonisolated enum ReviewEditableTransitionResult: Equatable, Sendable {
    case ready
    case failed
}

@MainActor
protocol ReviewSurfacePresenting: AnyObject {
    func renderReadOnly(phase: ReviewReadOnlyPhase, preview: String)
    func renderEditable(
        draft: String,
        isPossiblyIncomplete: Bool,
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor () -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) -> ReviewEditableTransitionResult
    func dismiss()
}
```

None of these methods is `async`, throws, runs a completion callback, or waits for layout/animation.
The editable method returns only immediate AppKit setup success/failure; it is not an awaited
readiness token. `MainViewModel` updates review state first, increments a presentation
revision, and enqueues the matching method in a fire-and-forget `@MainActor` task that no capture or
recognition task stores or awaits. `renderReadOnly` is idempotent and creates the panel if a newer
snapshot command superseded the original empty-preview command before it ran. A failed/stale UI
command cannot stop capture, journal admission, recognition consumption, retry, replay, release
drain, or action-2. If the current editable command returns `.failed`, that presentation task—not
the recognition consumer—calls a review-ID-gated failure handler. That handler copies the frozen
draft exactly once for manual recovery, clears authority, and schedules dismissal. A revoked or
cancelled command copies nothing.

The production controller owns one dedicated `ReviewPanel: NSPanel` for the entire interaction,
never the recording overlay panel. Configure it once with titled/closable/resizable/full-size
content style, initial size 520x320 points, minimum 420x240, maximum 760x600, floating status-bar
level, all-spaces/full-screen-auxiliary behavior, and `hidesOnDeactivate = false`. Do **not** add or
remove `.nonactivatingPanel` dynamically; AppKit/WindowServer activation tags must not depend on a
runtime style-mask flip.

`ReviewPanel` instead overrides `canBecomeKey` and `canBecomeMain` from a controller-owned
`allowsKeyInteraction` flag:

- streaming/sealing: `allowsKeyInteraction = false`, `ignoresMouseEvents = true`, no standard close
  controls, `orderFrontRegardless()` only, and no `NSApp`/running-application activation call;
- editable: keep the same panel instance, window number, frame, `NSHostingView`, and SwiftUI surface;
  replace its presentation with `.editable`, set `allowsKeyInteraction = true`, enable mouse/close
  controls, require `NSRunningApplication.current.activate(options: [])` to accept activation, call
  `makeKeyAndOrderFront`, and require FeishuSpeech to be frontmost, `panel.isKeyWindow == true`, and
  `makeFirstResponder` to have installed the exact editor responder before returning
  `ReviewEditableTransitionResult.ready`; any immediate uncertainty returns `.failed` and routes to
  recovery rather than exposing a nonfunctional editor;
- confirming/discard/lifecycle cleanup: order out, revoke key interaction, clear the hosted root
  model/callbacks, and release all preview/draft strings.

This is one visual surface with a safe authority transition: the read-only phase cannot steal key
focus or accept input, and the editable phase becomes key only after action-2 froze the draft and
response admission closed. The original target token was captured before the first
`orderFrontRegardless()` and is never refreshed during the transition.

`TranscriptionReviewView` renders `TranscriptionReviewState` directly:

- `.streaming(preview: "")`: fixed “正在聆听…” placeholder;
- `.streaming(preview:)`: scrollable read-only full opaque snapshot;
- `.sealing(preview:)`: the same scrollable preview plus fixed “正在完成识别…” status;
- `.editable`: one multiline `TextEditor`, the fixed incomplete warning when applicable, and
  **取消**/**输入** buttons;
- `.confirming`: no editable control; the controller dismisses immediately.

The confirm button is disabled for whitespace-only content.
`.keyboardShortcut(.return, modifiers: .command)` triggers confirm and
`.keyboardShortcut(.cancelAction)` triggers discard; no bare-Return shortcut is registered.
Window close is unavailable read-only and routes to the same discard callback when editable.
Labels, identifiers, title, logger calls, and diagnostics are fixed strings and never include the
preview/draft. Natural accessibility of the visible read-only text/editor is preserved, but the
transcript is not duplicated into an accessibility label, help string, or window title.

## 5. MainViewModel integration and state machine

Add injected defaults for `ReviewDestinationDelivering` and `ReviewSurfacePresenting`, plus:

- `activeOutputMode: InteractionOutputMode?`;
- `transcriptionReviewState`;
- `pendingReviewAuthority`;
- `nextReviewIdentifier`;
- `reviewPresentationRevision`;
- `reviewPresentationTask: Task<Void, Never>?`;
- `reviewDeliveryTask: Task<Void, Never>?`.

Do not group these into a new abstraction with only one implementation; `MainViewModel` remains the
single interaction coordinator.

The integration has a hard task-topology boundary:

- `captureDrainTask`, `drainCapturedAudio`, `HoldPacketJournal` admission/wakeup, recorder callbacks,
  and the recorder barrier contain no review-state or presenter reference;
- `consumerTask`, `consumeAudio`, session creation, retry sleep, journal replay, packet send, finish,
  and watched-operation gates contain no review presenter call or new await;
- only the existing main-actor event receipt/terminal handlers update
  `transcriptionReviewState` and enqueue a revision-gated fire-and-forget presentation task;
- presenter calls never determine event eligibility, retry, replay, journal acknowledgement,
  terminal settlement, release drain, or cleanup ordering.

`enqueueReviewPresentation` accepts `.readOnly`, `.editable`, or `.dismiss`, cancels/releases the
prior not-yet-run presentation task, increments the revision, and creates a new unstructured
main-actor task. The task checks review ID plus revision, invokes the presenter at most once, and
returns; no caller awaits it. Read-only/editable commands require both current review ID and
revision; a dismiss command requires the current revocation revision and is valid specifically
after its review ID has been cleared. Revocation increments the revision before scheduling
`.dismiss`, so a late streaming/sealing/editable command cannot remount secret content. Only the user-confirm path,
which is outside both asynchronous data lines, may call the bounded synchronous `dismiss()` before
starting target activation. Tests use a recorder presenter plus explicit capture/consumer gates to
prove presentation commands are not prerequisites for journal admission, retry/replay, sealing, or
finish.

### 5.1 Accepted Fn start

At `beginStreaming(identity:)`:

1. if `transcriptionReviewState != .idle`, call `hotKeyService.resetToIdle()` and return before
   recorder, provider, overlay, destination capture, or transcript state changes;
2. sample `settings.reviewBeforeInsert` and `settings.autoInsert` into `activeOutputMode`;
3. for `.reviewFirst`, capture `ReviewDestinationToken` before audio/network startup; on failure use
   the existing fixed startup-error cleanup;
4. create `PendingReviewAuthority`, set `.streaming(preview: "")`, enqueue
   `renderReadOnly(phase: .streaming, preview: "")`, and set recording status to `.streaming`;
5. do not call `prepareCursorTarget`, create `CursorTextSession`, set
   `usesCurrentFocusFinalOutput`, or arm any append-session factory;
6. continue through the existing ingress, recorder, transport, retry, and timer sequence unchanged;
7. for `.compatibility(autoInsert:)`, execute the present `prepareCursorTarget` and output route
   without semantic changes.

The review capture performs no target mutation. The newly visible panel is nonactivating,
non-keyable, and ignores input, so the captured target still owns focus and selection. Every later
output eligibility check reads `activeOutputMode`, not the mutable `settings` object; cleanup clears
the sampled mode.

### 5.2 Recognition events while held

Branch at the top of `handlePacketResponse` after generation/journal-index reservation:

- compatibility follows the existing output ledger and writer logic;
- `classifyPacketAdmission` uses the sampled `activeOutputMode`: review-first admits the owned
  journal index regardless of `autoInsert`, while compatibility retains the sampled
  `autoInsert=false` rejection;
- review-first ignores contentless snapshots, suppresses historical replay/duplicates, stores the
  newest changed complete opaque snapshot in memory, updates `.streaming(preview:)` or
  `.sealing(preview:)` according to capture state, and enqueues the matching revision-gated
  `renderReadOnly` command;
- review-first records at most fixed event-kind/lifecycle tags. It does not call
  `logResponseReceipt`, calculate common-prefix/length metrics for diagnostics, or expose preview
  through `RecordingState`, menu, recording overlay, notification, or duplicated accessibility
  copy.

“New snapshot” means a newly owned journal index whose full opaque value differs from the currently
displayed value. Historical replay and exact duplicates remain suppressed; revisions and shorter
complete snapshots replace the preview in full. Event handling only replaces in-memory state and
enqueues a task; the presenter later performs an O(1) model/root-view assignment with no animation
completion or acknowledgement. Neither asynchronous data line waits for it.

### 5.3 Release and action-2 completion

`beginSealing` keeps its existing audio barrier, retry admission, action-2, timeout, and overlay
behavior. In review mode it also changes `.streaming(preview:)` to `.sealing(preview:)` and
enqueues `renderReadOnly(phase: .sealing, preview:)` for the already visible surface before recorder
stop or drain work. It never awaits that presentation.

The terminal `handleFinal` review branch:

1. verifies the current streaming identity and open admission;
2. runs before the compatibility route's automatic-keyboard safety classifiers and selects the
   exact non-contentless action-2 text, or the prior usable snapshot with
   `isPossiblyIncomplete = true`;
3. closes response admission and freezes the chosen draft before allowing editable UI;
4. waits for the existing recorder sealing barrier;
5. invalidates streaming identity and cancels/clears ingress, transport, retry, timer, cursor, and
   response references exactly as normal completion currently does, but preserves only the review
   destination and chosen draft;
6. hides the recording overlay and resets `HotKeyService` to idle;
7. if no usable draft exists, revokes review authority, schedules `.dismiss`, and returns to
   `.idle` without directly invoking the presenter;
8. otherwise sets `.editable(draft:isPossiblyIncomplete:)` and enqueues an `.editable` command for
   `renderEditable(...)` on the same panel, with callbacks gated by `reviewIdentifier`.

Closing response admission and clearing active streaming identity before scheduling the key-capable
mode makes every late partial/final/failure a no-op. The editor is the only code allowed to change
the draft after this transition. The action-2 handler returns after enqueueing; the independent
presentation task performs the bounded same-panel switch and reports immediate failure through the
review-ID gate. Recognition/capture tasks never call or wait for editor focus, readiness, layout, or
dismissal.

Transport failure before authoritative completion keeps the current error/cleanup behavior and
clears in-memory review text. Do not invent a best-effort failure draft in this issue; the only
accepted incomplete-draft rule is contentless action-2 with a usable prior snapshot.

### 5.4 Confirm

`confirmReviewDraft`:

1. accepts only `.editable` plus matching `PendingReviewAuthority` and no existing delivery task;
2. rejects whitespace-only content in place;
3. freezes the exact untrimmed edited value;
4. sets `.confirming` and dismisses/clears the window before the first await;
5. starts one delivery task with the captured review ID and token;
6. on `.inserted`, clears authority/text and returns to `.idle`;
7. on every current non-cancellation typed failure, copies the frozen text once, clears
   authority/text, returns to `.idle`, and presents fixed manual-recovery feedback;
8. ignores completion from a cancelled/stale review task.

No retry is allowed. Even `.deliveryUncertain` is recovery-only because the target may have
consumed the event.

### 5.5 Discard, reset, sleep/wake, termination

Use one `clearReviewAuthority(reason:)` helper that:

- increments/revokes the current review ID;
- increments `reviewPresentationRevision`, cancels/releases `reviewPresentationTask`, and prevents
  every queued stale render from remounting content;
- cancels and clears `reviewDeliveryTask`;
- schedules a latest-revision `.dismiss` command that removes callbacks/content without animation
  or a completion wait; only explicit confirm uses the presenter's bounded synchronous `dismiss()`
  before target activation;
- clears `PendingReviewAuthority`, all preview/draft strings, and incomplete metadata;
- sets `transcriptionReviewState = .idle`;
- performs no copy, AX write, pasteboard mutation, synthetic event, or transcript-bearing log.

Call it from explicit discard, `resetService`, `handleSystemWillSleep`, `handleSystemDidWake`,
permission-loss termination, `cleanup`, and abnormal interaction cleanup. Settings save does not
discard; it only affects the next interaction.

Task cancellation is checked after activation wait and immediately before AX restoration/paste.
The actual final paste transaction is synchronous on `@MainActor`, so reset/termination cannot
interleave halfway through a complete Cmd+V pair. If cancellation is observed after a possible
post, classify it as delivery uncertainty and never retry.

## 6. Settings migration and UI

Modify `AppSettings.swift`:

- add `var reviewBeforeInsert: Bool = true` to `AppSettings` and its initializer;
- add the field to `AppSettings.CodingKeys`, decode it with `decodeIfPresent(... ) ?? true`, and
  encode it alongside the non-secret preferences;
- persist it in `savePreferences`;
- give private `StoredSettings` an explicit `init(from:)` using
  `decodeIfPresent(Bool.self, forKey: .reviewBeforeInsert) ?? true`;
- retain existing defaults for `autoInsert`, `playSound`, and `launchAtLogin` and all credential
  migration/failure behavior;
- encode the new field on the next successful preference save;
- ensure `launchAtLoginPreference(from:)` can still decode a pre-#38 payload without touching
  Keychain.

Modify `SettingsView.swift`:

- add an **输入前预览** toggle, default on, with fixed explanatory copy;
- when enabled, show that recognition waits for editing and explicit input;
- when disabled, show the existing continuous-output compatibility controls;
- retain `autoInsert` rather than deleting or renaming its stored key;
- thread the new value through `MainViewModel.updateSettings`.

No Settings text may include a transcript. A draft already open remains governed by its sampled
mode even if the toggle changes.

## 7. Complete file set

### New production files

| File | Responsibility |
|---|---|
| `FeishuSpeech/Models/TranscriptionReviewState.swift` | Independent review-axis states, read-only phase value, and sampled output mode only. |
| `FeishuSpeech/Services/ReviewDestinationDelivery.swift` | Exact running-app identity, bounded activation, review delivery result, AX/paste composition, and injectable protocols. |
| `FeishuSpeech/Controllers/ReviewWindowController.swift` | One-panel nonactivating read-only to key-capable editable transition, revision-safe rendering, size/focus/close lifecycle, and transcript clearing. |
| `FeishuSpeech/Views/TranscriptionReviewView.swift` | Streaming/sealing read-only full-snapshot preview plus multiline editor, warning, actions, and shortcuts. |

Every new production file declares the repository-required private logger and uses only fixed,
non-transcript messages.

### Existing production files to modify

| File | Required change |
|---|---|
| `FeishuSpeech/Models/AppSettings.swift` | Default-on migration and persistence for `reviewBeforeInsert`. |
| `FeishuSpeech/Models/CursorTextModels.swift` | Review application/destination token and typed results; no persistence. |
| `FeishuSpeech/Services/AccessibilityClient.swift` | Review-only read capture, allowed focus/range restoration, exact pre/post checks; no selected-text write. |
| `FeishuSpeech/Services/TextInputSimulator.swift` | Two-phase process-targeted paste overload and post-boundary uncertainty result. |
| `FeishuSpeech/ViewModels/MainViewModel.swift` | Sampled route, independent review axis, fire-and-forget presentation lane, no-mutation event handling, editor gating, confirmation/discard/lifecycle cleanup. |
| `FeishuSpeech/Views/SettingsView.swift` | Toggle, compatibility copy, and new settings binding. |

### Explicitly unchanged production files

- `FeishuSpeech/Controllers/OverlayWindowController.swift`
- `FeishuSpeech/Views/RecordingOverlayView.swift`
- `FeishuSpeech/Services/AudioRecorder.swift`
- `FeishuSpeech/Services/ByteBoundedAudioIngress.swift`
- `FeishuSpeech/Services/HoldPacketJournal.swift`
- `FeishuSpeech/Services/FeishuStreamingSession.swift`
- `FeishuSpeech/Services/TransportAttemptContext.swift`
- `FeishuSpeech/Services/FeishuAPIService.swift`
- hot-key state/service, permissions, entitlements, Info.plist, and
  `FeishuSpeech.xcodeproj/project.pbxproj`

`HotKeyService` does not need a review state; `MainViewModel` rejects the emitted identity while a
draft is unresolved.

### Test files

The test custodian may create:

- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift`
- `FeishuSpeechTests/ReviewAxisConcurrencyTests.swift`
- `FeishuSpeechTests/ReviewDestinationDeliveryTests.swift`
- `FeishuSpeechTests/TranscriptionReviewViewTests.swift`

and update only where the existing fixture needs the new setting/dependency:

- `FeishuSpeechTests/AppSettingsCredentialStorageTests.swift`
- `FeishuSpeechTests/StreamingMainViewModelTests.swift`
- `FeishuSpeechTests/FinalTextOutputSecurityTests.swift`
- `FeishuSpeechTests/MainViewModelTests.swift`

### Documentation docking after verified implementation

- create `docs/decisions/D-38-01.md`;
- update `README.md`, `CHANGELOG.md`, `docs/README.md`, `docs/architecture.md`, and
  `docs/streaming-speech-design.md`;
- update `docs/api.md` only if its output/error contract currently describes automatic target
  mutation in a way changed by the verified implementation.

The documentation owner must transcribe actual symbols and final test evidence; it must not write
these proposed signatures as verified before implementation.

## 8. Dependency-safe TDD delivery order

Test and production custody remain separate. The TDD owner writes all issue-38 tests and no
production code; production implementers may read and run those tests but never edit them.

### Task 0 — test contract (test custodian only)

Owned files: issue-38 changes under `FeishuSpeechTests/` only.

Add RED coverage for:

- old stored settings payload defaults review-first on, explicit false round-trips, and credential
  migration/launch preference remain intact;
- review capture reads exact app/PID/element/selection/security without checking or writing
  `kAXSelectedTextAttribute`;
- partial, replay, nonterminal final, action-2 final, and late callbacks cause zero AX target text,
  append-session, pasteboard, or synthetic-event mutation before confirmation;
- accepted Fn shows an empty read-only streaming preview immediately after target capture, without
  activating FeishuSpeech or changing the original focus/selection;
- every newly owned changed complete opaque snapshot replaces the read-only preview in full;
  duplicate/historical replay is suppressed while revised/shorter values replace it;
- Fn release keeps the same panel/frame/window identity visible and changes its surface to read-only
  sealing before recorder drain completes;
- action-2 changes that same surface to exact editable text; contentless action-2 uses the last
  usable snapshot and marks incomplete; no usable text dismisses the surface;
- an immediate editable-transition failure leaves the original destination untouched, copies the
  frozen action-2 draft once, clears the panel/authority, and never blocks or re-enters the
  recognition consumer;
- read-only panel cannot become key/main, ignores mouse input, hides close controls, and performs no
  app activation; editable transition enables key/mouse/close, activates FeishuSpeech, and focuses
  the editor without recapturing the destination;
- out-of-order/stale presentation tasks cannot replace a newer snapshot, regress editable to
  sealing, or remount after cleanup;
- gated `captureDrain`/journal and recognition consumer/retry/replay fixtures prove that preview
  render scheduling/readiness is never awaited and cannot change packet, retry, replay, seal, or
  action-2 order;
- edits replace the draft; whitespace confirm is refused; duplicate confirm delivers once;
- discard, close, Escape, reset, sleep/wake, cleanup, permission loss, and late callback clear text
  and authority without output/copy;
- new Fn while editable starts no recorder/provider and cannot overwrite the draft;
- activation success, already-frontmost success, wrong-app notification, timeout, PID reuse/full
  identity mismatch, AX focus/selection/security failures, and task cancellation;
- exact original selection restoration occurs before pasteboard mutation; preflight failure leaves
  pasteboard/key events untouched; postflight failure is uncertain and never retried;
- every current non-cancellation delivery failure copies the frozen edited text once and emits
  transcript-free feedback; lifecycle cancellation copies nothing;
- disabling review-first preserves current continuous output with both `autoInsert` values;
- surface policy renders fixed streaming/sealing copy, registers only Command+Return and
  cancelAction in editable mode, preserves bare Return editing, uses fixed size bounds, and routes
  editable close to discard.

Tests should use secret-marker drafts and assert they do not appear in `status`, `overlayMessage`,
window title, fixed labels, delivery results, or captured logs/diagnostic fixtures.

This task is independent of production writes but must finish its behavioral contract before
implementers adapt to it.

### Task 1 — review values and settings migration

Owned production files:

- new `FeishuSpeech/Models/TranscriptionReviewState.swift`;
- `FeishuSpeech/Models/AppSettings.swift`;
- `FeishuSpeech/Models/CursorTextModels.swift` for value declarations only.

Implement declaration-complete state/settings/token values, then pass the settings and pure-state
tests. This task produces the types consumed by Tasks 2-4.

### Task 2 — destination capture, activation, and delivery

Owned production files:

- new `FeishuSpeech/Services/ReviewDestinationDelivery.swift`;
- `FeishuSpeech/Services/AccessibilityClient.swift`;
- `FeishuSpeech/Services/TextInputSimulator.swift`.

Order:

1. implement exact application identity capture/validation;
2. implement review AX read capture and allowed focus/selection restoration;
3. implement observer-before-request bounded activation;
4. add the two-phase process-targeted paste transaction;
5. compose typed delivery and recovery results;
6. pass `ReviewDestinationDeliveryTests` and `FinalTextOutputSecurityTests`.

Depends on Task 1. It is independent of window and Settings UI because the files are disjoint and
neither consumes their implementation.

### Task 3 — review surface

Owned production files:

- new `FeishuSpeech/Controllers/ReviewWindowController.swift`;
- new `FeishuSpeech/Views/TranscriptionReviewView.swift`.

Implement the single-panel nonactivating streaming/sealing presentation, idempotent full-snapshot
rendering, same-panel editable authority transition, state binding callbacks, size bounds,
close-as-discard, editor focus, incomplete warning, and shortcuts. Presenter methods remain
synchronous/nonthrowing and contain no animation completion or async readiness. Pass
`TranscriptionReviewViewTests`, then do a local non-secret visual/keyboard smoke check.

Depends only on Task 1's state vocabulary. It is genuinely independent of Task 2: it touches
different files and consumes no activation/AX/delivery implementation.

### Task 4 — MainViewModel convergence

Owned production file: `FeishuSpeech/ViewModels/MainViewModel.swift` only.

Depends on Tasks 1-3. Integrate the sampled route, strict destination capture, in-memory snapshot
ownership, revision-gated fire-and-forget preview scheduling, release-to-sealing presentation,
action-2 same-surface editor transition, new-Fn gate, exactly-once confirm, recovery, and lifecycle
clearing without changing either async transport/audio line. Pass `ReviewFirstMainViewModelTests`, the
existing `StreamingMainViewModelTests`, and `MainViewModelTests`.

No other production owner edits MainViewModel because it is the convergence point.

### Task 5 — Settings UI

Owned production file: `FeishuSpeech/Views/SettingsView.swift` only.

Depends on Task 1's setting and Task 4's finalized `updateSettings` signature. Add the toggle and
conditional compatibility copy, then pass the settings/view tests. It is sequenced after Task 4 to
avoid temporarily guessing or racing on the method signature.

### Task 6 — integrated review and fixes

The main session:

1. verifies write ownership and that overlay/#37 files are unchanged;
2. runs focused and complete gates;
3. routes behavioral/coverage failures to the TDD owner and compiler/concurrency/tooling failures to
   the build-error resolver;
4. runs independent source-first correctness review, then security/privacy/resource review;
5. routes production fixes to the appropriate production owner and reruns affected gates;
6. only after zero blocking findings, docks documentation from verified ground truth.

Tasks 2 and 3 are the only genuinely parallel production pair. Task 5 does not run in parallel with
Task 4 because it consumes a signature Task 4 finalizes. Documentation waits for all production,
tests, and independent reviews.

## 9. Validation commands

Run from `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-38`.

### Focused TDD gates

```bash
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/AppSettingsCredentialStorageTests test

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests test

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests test

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  -only-testing:FeishuSpeechTests/ReviewAxisConcurrencyTests \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests \
  -only-testing:FeishuSpeechTests/MainViewModelTests test
```

Because synchronized test roots compile all test sources, early focused runs may hit declaration
errors from another RED file. Do not remove tests or add project membership exceptions; complete
Task 1's declaration surface first.

### Static security/scope checks

```bash
rg -n 'setSelectedText\(|kAXSelectedTextAttribute' \
  FeishuSpeech/Services/ReviewDestinationDelivery.swift \
  FeishuSpeech/Controllers/ReviewWindowController.swift \
  FeishuSpeech/Views/TranscriptionReviewView.swift \
  FeishuSpeech/ViewModels/MainViewModel.swift

rg -n 'logger\.|print\(|NSLog\(' \
  FeishuSpeech/Models/TranscriptionReviewState.swift \
  FeishuSpeech/Services/ReviewDestinationDelivery.swift \
  FeishuSpeech/Controllers/ReviewWindowController.swift \
  FeishuSpeech/Views/TranscriptionReviewView.swift \
  FeishuSpeech/ViewModels/MainViewModel.swift

git diff --exit-code -- \
  FeishuSpeech/Controllers/OverlayWindowController.swift \
  FeishuSpeech/Views/RecordingOverlayView.swift \
  FeishuSpeech/Services/AudioRecorder.swift \
  FeishuSpeech/Services/ByteBoundedAudioIngress.swift \
  FeishuSpeech/Services/HoldPacketJournal.swift \
  FeishuSpeech/Services/FeishuStreamingSession.swift \
  FeishuSpeech/Services/TransportAttemptContext.swift \
  FeishuSpeech/Services/FeishuAPIService.swift \
  FeishuSpeech.xcodeproj/project.pbxproj

rg -n 'reviewSurface|reviewPresentation|ReviewSurface' \
  FeishuSpeech/Services/AudioRecorder.swift \
  FeishuSpeech/Services/ByteBoundedAudioIngress.swift \
  FeishuSpeech/Services/HoldPacketJournal.swift \
  FeishuSpeech/Services/FeishuStreamingSession.swift \
  FeishuSpeech/Services/TransportAttemptContext.swift \
  FeishuSpeech/Services/FeishuAPIService.swift

git diff --check
```

The selected-text command and the final topology command must return no hit. Existing compatibility
implementation outside the selected-text command's listed files is not part of that zero-hit
assertion. Manually inspect every logger hit; only fixed lifecycle and typed outcome fields are
allowed. Also source-review the MainViewModel diff to prove `captureDrainTask`,
`drainCapturedAudio`, `consumerTask`, `consumeAudio`, retry/replay loops, journal acknowledgements,
and recorder barriers contain no presenter invocation or review-dependent await; the concurrency
test is the executable regression gate for that topology.

### Repository gates

```bash
xcodebuild -scheme FeishuSpeech -configuration Debug -destination 'platform=macOS' build
xcodebuild -scheme FeishuSpeech -configuration Release -destination 'platform=macOS' build
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test
swiftlint lint --strict
git status --short --branch
```

Do not accept CI `continue-on-error` as the done verdict. The local commands above must exit zero.

### Manual macOS UAT

Use synthetic, non-private phrases and record semantic outcomes only, never the text itself.

- Confirm default-on migration and explicit off/on persistence.
- Hold Fn in TextEdit and Chromium/Electron: verify the separate review surface appears immediately
  as nonactivating read-only, the original caret remains active, every revised/shorter complete
  snapshot replaces the preview rather than appending, and release changes the same window in place
  to sealing.
- Under delayed session creation, retry backoff, journal replay, and slow action-2, verify the
  preview remains responsive while audio journaling/replay/drain continues; UI readiness or window
  movement must not delay packet/retry/finish evidence.
- In TextEdit and at least one Chromium/Electron editor, capture a caret and a nonempty selection;
  verify only action-2 changes the same panel to key-capable editable mode; edit with bare Return;
  confirm with Command+Return and the button; verify exact replacement occurs once in the original
  selection.
- Focus another application during review, close/relaunch the target, move its selection, enter a
  secure field, and enable Secure Event Input where possible. Each case must perform no automatic
  target write and leave the edited draft on the clipboard with fixed recovery feedback.
- Exercise activation timeout/unresponsive target without increasing the two-second bound or
  retrying.
- Double-click Input, repeat Command+Return, press Fn while the draft is open, deliver late
  recognition callbacks through a DEBUG fixture, then discard/reset/sleep/wake. Verify no duplicate
  or retargeted output and no retained draft.
- Verify Escape, Cancel, and window close write/copy nothing.
- Disable review-first and exercise current live AX, final-only/append, and `autoInsert=false`
  behavior to prove compatibility.
- Verify both the unchanged status-only recording overlay and the independent transcript review
  surface coexist correctly on multiple displays; keep #37's owner-UAT status separate.

Automated green is sufficient for integration evidence. Broad cross-application compatibility and
general availability remain unverified until this UAT matrix passes.

## 10. Failure routing and rollback

| Failure/risk | Required route |
|---|---|
| Old settings payload fails decode | Fix `StoredSettings.init(from:)`; do not reset all preferences or touch Keychain fallback behavior. |
| Review capture cannot prove editable/safe target | Fail before audio/network startup. Do not downgrade to ambient current focus. |
| PID exists but bundle/executable/launch identity differs | Treat as process reuse/relaunch and copy for recovery after confirm. Never accept PID alone. |
| Activation request rejects or times out | Copy frozen draft once, show fixed feedback, no retry or substitute app. |
| AX focus/selection restore or preflight fails | Zero pasteboard/key event, then recovery copy only. Do not write selected text. |
| Paste/key postflight is uncertain | Copy for recovery with fixed non-success feedback; never retry or claim definite failure. |
| Reset/sleep/termination wins during activation | Cancel/revoke review ID, clear text, and require the task's pre-mutation cancellation check. Late completion is a no-op. |
| Duplicate confirm | `.confirming` has already consumed authority; no second task/output/copy. |
| New Fn while editable | Reset only the new hot-key state. Preserve existing review and start no audio/network/output owner. |
| Preview render task is delayed or superseded | Keep recognition/capture running; latest review ID/revision wins and stale UI work is dropped. Never add an await or acknowledgement. |
| Surface cannot be made key/editable | Keep destination untouched, copy the frozen action-2 draft for recovery, clear authority, and do not weaken window/AX checks. |
| Compatibility regression | Keep the review toggle off path on the existing writer code; do not repair by weakening review checks. |
| Window shortcut ambiguity | Route to UI test owner and manual keyboard UAT; do not intercept bare Return globally. |
| Compiler/concurrency/tooling failure | Route to build-error resolver; preserve `@MainActor` for UI/AX and do not change deployment/build settings. |
| Behavioral or coverage failure | Route to TDD owner; production implementers do not edit tests. |
| Correctness/security finding | Route the fix to the owning production task, then rerun focused, full, lint, and both reviews. |

Repository rollback is the default-on preference plus a self-contained review route: before release,
setting `reviewBeforeInsert = false` selects the unchanged compatibility path. That flag is not a
substitute for fixing a broken default path; if issue acceptance cannot pass, keep issue #38 open
and do not ship the default-on migration. No data migration, dependency, schema, or destructive text
rollback is needed.

## 11. Deliberate limits

- This blueprint does not redesign successful pasteboard restoration. It reuses the existing
  process-targeted final-output primitive and adds only the pre/post validation split needed by the
  accepted destination contract. Any broader clipboard-ownership improvement is separate work.
- It does not preserve partial text after transport failure without action-2 authority; that would
  be a new product decision beyond issue #38's accepted empty-action-2 fallback.
- It does not promise every macOS editor exposes settable focus/range AX attributes. Failure is
  manual-recovery-only, and the UAT matrix determines supported applications.
- It does not remove the compatibility route's historical AX selected-text implementation. The
  zero-`kAXSelectedTextAttribute` rule is absolute for the new default review route; removing it from
  the explicitly preserved compatibility behavior would be a separate regression-prone decision.
- It does not alter issue #37 artifacts or status. The independent review surface is visible
  read-only during streaming/sealing and becomes editable after authoritative action-2; it never reuses or
  changes the recording overlay.
