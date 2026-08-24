# Issue #40 architecture blueprint — review-first non-secure AX-miss fallback

Date: 2026-08-23

Repository: `/Users/ylpromax5/Workspace/feishuspeech`

Implementation worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`

Contract authority: Issue #40, with D-38-01 and D-39-01 retained except where this blueprint
explicitly supersedes D-38-01's strict-AX-only review capture and delivery rule.

## 1. Outcome and success criteria

Issue #40 removes only the false startup rejection caused by a non-secure target that cannot
produce D-38's strict `CursorDestinationToken`.

The accepted interaction has two review destination strengths:

```text
preferred:  complete original application identity + exact AX element + original selection
fallback:   complete original application identity + current focus in that exact application
```

Both strengths are captured before the read-only panel, recorder, or provider starts. Both keep
the review panel visible through streaming, sealing, and editing. Both require explicit human
confirmation. Neither writes any recognition text while Fn is held or while action 2 is settling.

The implementation is complete only when all of these are true:

1. A safe exact AX cursor still selects the existing D-38 exact-element/original-selection route.
2. When strict AX capture misses for an ordinary non-secure target, a complete original
   `ReviewApplicationIdentity` is bound before the review panel opens; preview, recording, and
   provider startup proceed.
3. Global Secure Event Input at accepted-Fn startup still rejects before panel, audio, journal, or
   provider work. An affirmatively secure AX role also rejects rather than falling back.
4. Confirmation synchronously freezes the exact untrimmed draft, consumes authority, and dismisses
   the editor before the first `await`, as in D-38/D-39.
5. Fallback delivery activates only the captured complete application identity, then obtains two
   consecutive pre-mutation samples proving Secure Input is off, the raw frontmost PID is the
   captured PID, and both running/frontmost complete identities equal the captured identity.
6. The fallback writes the frozen multiline-safe draft through exactly one process-targeted Cmd+V
   transaction to the captured PID and never discovers or substitutes an ambient PID.
7. Exact-path selection restoration, fallback sampling, text safety, pasteboard restoration,
   uncertainty, cancellation, and manual recovery are typed and independently testable.
8. Any activation, identity, PID, security, unsafe-text, post, or postflight failure is terminal;
   a current non-cancellation failure enters the existing exact-once manual-recovery path, and no
   automatic delivery retry occurs.
9. `captureDrainTask`/journal production and the recognition factory/retry/replay/consumer line are
   unchanged. Review presentation and delivery add no await, continuation, buffer, or backpressure
   edge to either line.

## 2. Current facts and retained decisions

### 2.1 Existing code facts

- `MainViewModel.beginStreaming` samples `reviewBeforeInsert`, checks the published Secure Input
  state, then calls `prepareReviewDestination` before configuration, recorder, ingress,
  `captureDrainTask`, or `consumerTask` startup.
- `SystemReviewDestinationDelivery.capture` currently asks
  `ReviewDestinationAccessing.captureReviewCursorDestination` for a strict cursor first. Therefore
  no `ReviewApplicationIdentity` survives if AX focus, role, subrole, selection, or settable
  attributes are unavailable.
- `MacAccessibilityClient.captureReviewCursorDestination` currently throws the same
  `AccessibilityClientError.accessibilityUnavailable` for global Secure Input and several ordinary
  cursor-capability misses. `MainViewModel` catches every error and shows `无法确认输入位置`.
- `ReviewDestinationToken` currently requires a non-optional `cursor`. The model cannot represent
  a stronger-than-PID, weaker-than-exact-element review authority.
- Exact review delivery already has the correct two-phase clipboard transaction: validate before
  mutation, snapshot every item/type, write once, post one Cmd+V pair to the captured PID,
  postflight once, and restore only after success while the transaction `changeCount` is unchanged.
- `SystemFinalTextOutput.insertAtCurrentFocusOnce` is the compatibility direct-Unicode route. It
  rejects LF and has different clipboard semantics. It is not suitable for an editable multiline
  review draft.
- `ReviewSurfaceAuthority`, review IDs/revisions, synchronous confirmation consumption,
  `reviewCopyRecoveryIssued`, and `completeReviewDelivery` already enforce one delivery task and
  one manual recovery copy.
- The project uses filesystem-synchronized Xcode groups. No project membership edit is required;
  Issue #40 should not add a new production file.

### 2.2 D-38 and D-39 retained unchanged

Issue #40 does not redesign review-first. It retains:

- default-on `reviewBeforeInsert` and per-interaction settings sampling;
- one nonactivating read-only panel through streaming and sealing, followed by the same panel's
  bounded editable transition;
- full opaque snapshot replacement, packet-index ownership, action-2 authority, contentless-final
  incomplete fallback, and late-callback fences;
- synchronous exact-once confirmation, whitespace rejection, exact untrimmed draft freezing, and
  D-39 Return/Enter/Shift/IME behavior;
- capture/journal and recognition/retry/replay as independent asynchronous roots;
- no transcript persistence, transcript-derived diagnostics, or transcript-bearing feedback;
- no automatic retry after a possible post; and
- the Issue #27 compatibility route when `reviewBeforeInsert == false`.

The recording overlay, hot-key state machine, audio recorder, journal, transport, retry, replay,
action sequencing, settings schema, dependencies, entitlements, deployment target, and Xcode build
settings remain out of scope.

## 3. Chosen model and typed capture boundaries

All new values are internal. No public API, persisted schema, dependency, or build-tool decision is
required.

### 3.1 Review destination binding

Modify `FeishuSpeech/Models/CursorTextModels.swift` so a review token carries the generation and one
of two explicit bindings:

```swift
enum ReviewDestinationBinding {
    case exactCursor(CursorDestinationToken)
    case applicationCurrentFocus
}

struct ReviewDestinationToken {
    let generation: UInt64
    let application: ReviewApplicationIdentity
    let binding: ReviewDestinationBinding
    let capturedSecurityState: DestinationSecurityState
}
```

Required invariants at construction:

- `generation` is positive/current for the accepted interaction;
- `application` is complete: positive PID, nonempty bundle identifier, nonempty executable path,
  and finite launch date;
- `.exactCursor(cursor)` requires `cursor.generation == generation` and
  `cursor.processIdentifier == application.processIdentifier`;
- `.applicationCurrentFocus` does not contain an `AXUIElement`, selection, second PID, app name, or
  transcript; and
- `capturedSecurityState` must be `.safe` for either successful binding.

The enum is deliberately not an optional cursor. Exhaustive switching prevents a caller from
silently skipping exact preflight or accidentally treating a missing cursor as ambient authority.

### 3.2 AX-level outcome

Change the review-only method on `ReviewDestinationAccessing` from throwing a cursor to returning a
typed outcome:

```swift
enum ReviewCursorCaptureResult {
    case exact(CursorDestinationToken)
    case nonSecureCursorUnavailable
    case rejected(ReviewCursorCaptureRejection)
}

enum ReviewCursorCaptureRejection: Equatable, Sendable {
    case secureInput
    case accessibilityUnavailable
}

@MainActor
protocol ReviewDestinationAccessing: AnyObject {
    func captureReviewCursorDestination(generation: UInt64) -> ReviewCursorCaptureResult
    func restoreAndValidateBeforeDelivery(_ token: CursorDestinationToken) throws -> Bool
    func validateAfterDelivery(_ token: CursorDestinationToken) throws -> Bool
}
```

`nonSecureCursorUnavailable` means only: Accessibility trust was present, live global Secure Event
Input samples were clear, no AX observation affirmatively identified a secure text field, but the
strict exact-element contract could not be completed. Examples are no focused element, unusable
role/subrole, PID/focus mismatch, invalid/unreadable selection, or unsettable focus/range.

The failure classification is ordered and fail-closed:

1. Lost Accessibility trust returns `.rejected(.accessibilityUnavailable)`; it is not a fallback
   admission. Normally the app's permission gate prevents this state, but a live loss must remain
   terminal.
2. Live global Secure Event Input returns `.rejected(.secureInput)` before other AX work.
3. If AX returns `kAXSecureTextFieldSubrole`, return `.rejected(.secureInput)` even if the global
   sample was briefly clear.
4. A fully supported safe element with valid selection/settable focus and range returns `.exact`.
5. An ordinary AX error or capability miss returns `.nonSecureCursorUnavailable` only after a
   final live Secure Event Input recheck remains clear. A secure transition during probing returns
   `.rejected(.secureInput)`.

Capture still performs no AX setter and never queries whether `kAXSelectedTextAttribute` is
settable. Compatibility `AccessibilityClient.captureDestination` and `CursorCapabilityResult` do
not change.

### 3.3 Composite review-capture outcome

Change `ReviewDestinationDelivering.capture` to a nonthrowing typed result:

```swift
enum ReviewDestinationCaptureResult {
    case captured(ReviewDestinationToken)
    case rejected(ReviewDestinationCaptureRejection)
}

enum ReviewDestinationCaptureRejection: Equatable, Sendable {
    case secureInput
    case destinationUnavailable
}

@MainActor
protocol ReviewDestinationDelivering: AnyObject {
    func capture(generation: UInt64) -> ReviewDestinationCaptureResult
    func deliver(
        _ frozenText: String,
        to destination: ReviewDestinationToken
    ) async -> ReviewDeliveryResult
    func copyForManualRecovery(_ frozenText: String)
}
```

`SystemReviewDestinationDelivery.capture` must bind application identity before asking AX to find
the cursor:

1. Read `applicationRuntime.frontmostIdentity()` and require a complete identity.
2. Require `applicationRuntime.identity(for: capturedPID)` to equal that same complete identity.
3. Ask `ReviewDestinationAccessing` for its typed AX outcome.
4. Re-read running and frontmost complete identities; both must still equal the original identity.
5. For `.exact`, additionally require cursor generation/PID equality and return an exact binding.
6. For `.nonSecureCursorUnavailable`, return `.applicationCurrentFocus` bound to the already
   captured application identity.
7. Map AX secure rejection to `.rejected(.secureInput)`; map lost trust, incomplete/missing
   identity, identity drift, or any inconsistent token to `.rejected(.destinationUnavailable)`.

This order proves that the fallback authority is the original application seen before panel
presentation. It never binds whatever is frontmost after FeishuSpeech activates its editor.

## 4. State transitions and coordinator integration

The three-axis D-38 topology is unchanged:

```text
capture:      idle -> streaming ---------------------------> sealing -> idle
recognition:  idle -> factory/retry/replay/live/action-2 -------------> idle
review:       idle -> streaming -> sealing -> editable -> confirming -> idle
```

Only review destination preparation gains a second successful binding.

### 4.1 Accepted-Fn startup

In `MainViewModel.prepareReviewDestination` switch exhaustively over
`ReviewDestinationCaptureResult`:

- `.captured(token)`: verify token generation, complete identity, safe captured state, and binding
  invariants; create the existing `ReviewSurfaceAuthority`; publish `.streaming(preview: "")`.
- `.rejected(.secureInput)`: call the existing startup cleanup with
  `安全输入框不支持语音输入`.
- `.rejected(.destinationUnavailable)`: call the existing startup cleanup with
  `无法确认输入位置`.

Both exact and application-current-focus capture succeed before `showOverlay`, ingress creation,
recorder start, `captureDrainTask`, `consumerTask`, and the first read-only render command. The
existing top-level `permissionManager.secureInputEnabled` guard remains in place; the live typed
capture check closes a stale-publisher race.

No review fallback may call `prepareCursorTarget`, arm `CursorTextSession`, arm
`CurrentFocusAppendSession`, use `usesCurrentFocusFinalOutput`, or write partial/final text before
confirmation. This is a review delivery binding, not compatibility continuous output.

### 4.2 Streaming, sealing, editing, confirm, and cleanup

No semantic change is needed after successful capture until confirmation:

- streaming/sealing snapshots update only in-memory `TranscriptionReviewState` and the existing
  cancellable presentation lane;
- action 2 and the recorder barrier freeze the same editable draft as D-38;
- D-39 keyboard routing remains unchanged;
- confirmation consumes `reviewConfirmationInFlight`, freezes the exact draft, sets
  `.confirming`, increments the revision, and dismisses before starting one delivery task;
- discard and lifecycle cleanup do no destination or pasteboard work; and
- `completeReviewDelivery` keeps one-copy recovery for every current non-cancellation failure and
  zero copy for cancellation.

The pending authority continues to store one `ReviewDestinationToken`; later phases switch on its
binding only inside `SystemReviewDestinationDelivery`. UI and recognition code do not inspect the
binding strength.

## 5. Delivery paths

### 5.1 Common preflight and activation

`SystemReviewDestinationDelivery.deliver` first performs the existing synchronous text and token
checks:

- non-whitespace exact draft;
- `TextInputSimulator.isSafeForReviewConfirmation`, admitting LF but rejecting NUL, tab, CR, DEL,
  and C1 controls without normalization;
- captured security state `.safe`;
- current generation/binding invariants; and
- current running application identity exactly equals the captured identity.

It then calls `activateAndWait` once for that exact identity with the existing two-second bound.
After the await, cancellation is checked and both running and frontmost complete identities must
again equal the captured identity. No substitute app is activated and no target is recaptured.

### 5.2 Preferred exact-cursor route

For `.exactCursor`, retain the D-38 implementation and order:

1. verify complete running/frontmost application identity;
2. `restoreAndValidateBeforeDelivery` focuses only the captured element, verifies `CFEqual`,
   restores the original selected range, and rereads it exactly;
3. recheck complete identity/frontmost/security before pasteboard mutation;
4. perform one process-targeted review Cmd+V transaction;
5. postflight exact identity, frontmost app, focused AX element, AX trust, and Secure Input; and
6. restore the clipboard only after successful postflight and unchanged transaction change count.

Do not weaken this route merely because the fallback exists. A valid exact cursor always wins.

### 5.3 Application-bound current-focus route

For `.applicationCurrentFocus`, no AX element exists and no AX setter or later AX recapture is
allowed. After exact-app activation, perform two consecutive, synchronous main-actor samples before
pasteboard mutation. Each sample must prove all of:

- `SecureInputStateProviding.isSecureInputEnabled() == false`;
- `FrontmostProcessProviding.frontmostProcessIdentifier() == capturedPID`;
- `applicationRuntime.identity(for: capturedPID) == capturedApplicationIdentity`; and
- `applicationRuntime.frontmostIdentity() == capturedApplicationIdentity`.

Both samples must succeed. Missing PID, a different PID, PID instability, missing identity fields,
PID reuse, launch-date/path/bundle drift, another frontmost app, or either secure sample is a
certain pre-mutation rejection. The samples are adjacent to the paste transaction and introduce no
`await`.

Then perform one review paste transaction to `capturedPID`. `CGEvent.postToPid` must receive the
captured PID directly; never pass a newly sampled ambient PID as the target. A postflight sample
rechecks Secure Input, raw frontmost PID, running identity, and frontmost identity. Failure after a
possible Cmd+V is `.deliveryUncertain`, with no automatic retry or clipboard restoration.

The selected fallback contract is intentionally "current focus inside the exact original
application after reactivation." It cannot restore D-38's original intra-application element or
selection because those values were unavailable. That is a documented capability limit, not
permission to cross applications.

## 6. Multiline-safe exact-once paste primitive

Extend `FinalTextOutput` with a review-only current-focus overload; do not reuse the compatibility
`insertAtCurrentFocusOnce` Unicode method:

```swift
enum ReviewCurrentFocusValidation: Equatable, Sendable {
    case valid
    case securityRejected
    case identityChanged
    case destinationInvalid
}

func insertReviewAtCurrentFocusOnce(
    _ text: String,
    processIdentifier: pid_t,
    validateBeforeMutation: () -> ReviewCurrentFocusValidation,
    validateAfterPosting: () -> ReviewCurrentFocusValidation
) -> FinalTextInsertionResult
```

Add `.identityChanged` to `FinalTextInsertionResult` so a certain pre-mutation identity failure can
remain typed through the paste layer. Provide a default protocol implementation that returns
`.destinationInvalid` so unrelated test doubles remain fail-closed until explicitly updated.

`SystemReviewDestinationDelivery` supplies a `validateBeforeMutation` closure that executes the two
samples from section 5.3 and a postflight closure that executes one sample. The
`SystemFinalTextOutput` overload owns the same pasteboard/key-event transaction as exact delivery:

1. reject contentless or unsafe review text before validation or mutation;
2. call the typed pre-mutation validator once (it performs the required two samples);
3. snapshot every data-bearing type from every current pasteboard item;
4. replace the pasteboard with the exact unmodified draft;
5. record the transaction change count;
6. post one complete Cmd+V pair to the supplied captured PID;
7. call postflight once;
8. on success schedule the existing bounded double-change-count restoration; and
9. on post or postflight uncertainty schedule no restore and never retry.

Refactor the duplicate steps shared with the exact-cursor overload into one private review-paste
helper inside `SystemFinalTextOutput`. This is reuse of the existing D-38 mechanism, not a second
clipboard subsystem.

Exact-once authority exists at three layers:

- `MainViewModel` consumes confirmation synchronously and creates one task;
- `SystemReviewDestinationDelivery` activates/routes once and never retries; and
- `SystemFinalTextOutput` writes once and posts one Cmd+V pair.

The app still cannot prove an arbitrary destination control consumed Cmd+V. Any uncertainty after
the post boundary is terminal and routes to manual recovery, because a retry could duplicate text.

## 7. Security and failure matrix

| Phase | Observation | Result | Mutation/recovery |
|---|---|---|---|
| startup | published or live global Secure Input enabled | secure rejection | no panel/audio/provider/pasteboard; existing startup error |
| startup | AX secure subrole | secure rejection | no fallback and no startup work |
| startup | lost AX trust | destination unavailable | no fallback; permission flow remains authoritative |
| startup | complete stable app identity + exact safe cursor | exact binding | review proceeds; exact path preferred |
| startup | complete stable app identity + ordinary non-secure strict cursor miss | application-current-focus binding | review proceeds; no text output before confirm |
| startup | missing/incomplete identity, PID reuse, or frontmost identity drift | destination unavailable | no panel/audio/provider |
| confirm | unsafe/control draft | unsafe text | zero target mutation; one existing manual recovery copy |
| activation | not running, rejected, timeout, or cancelled | typed activation result | cancellation copies nothing; other current failures copy once |
| preflight | either Secure Input sample enabled | security rejected | zero pasteboard/event mutation; copy once |
| preflight | PID missing/different/unstable | destination invalid | zero pasteboard/event mutation; copy once |
| preflight | complete running/frontmost identity mismatch | identity changed | zero pasteboard/event mutation; copy once |
| exact preflight | AX focus/selection/security cannot be restored exactly | destination invalid/security rejected | zero pasteboard/event mutation; copy once |
| pasteboard write | replacement fails | delivery failed | no key post; current failure copies once |
| key post | event construction/post uncertain | delivery uncertain | no retry/automatic restore; manual recovery once |
| postflight | app/PID/security/AX uncertainty after possible post | delivery uncertain | no retry/automatic restore; manual recovery once |
| success | postflight passes and transaction change count remains owned | inserted | one bounded restore; third-party clipboard change wins |
| discard/reset/sleep/permission cleanup | authority revoked | cancelled/stale | no activation, copy, AX setter, pasteboard, or event |

Cross-app delivery is prohibited in every row. The fallback's only destination PID is the PID in
the original complete identity captured before the panel opened.

## 8. File changes

### Production files to modify

| File | Change |
|---|---|
| `FeishuSpeech/Models/CursorTextModels.swift` | Add typed destination binding/capture results and current-focus validation; make review token generation-centric; add typed pre-mutation identity result. |
| `FeishuSpeech/Services/AccessibilityClient.swift` | Return exact/non-secure-unavailable/secure-or-trust rejection for review capture; preserve compatibility API and exact restore/postflight behavior. |
| `FeishuSpeech/Services/TextInputSimulator.swift` | Add multiline-safe review current-focus Cmd+V overload; reuse the existing review clipboard snapshot/change-count transaction; leave compatibility Unicode behavior unchanged. |
| `FeishuSpeech/Services/ReviewDestinationDelivery.swift` | Capture complete frontmost identity before AX; compose exact or application-current-focus token; inject/reuse secure and frontmost-PID providers; route delivery and map typed results. |
| `FeishuSpeech/ViewModels/MainViewModel.swift` | Consume typed capture result, map secure vs destination startup feedback, accept both successful bindings, and remove assumptions that every review token has a cursor. |

No new production file is required.

### Test files to update

Test custody is separate from production custody.

| File | Coverage |
|---|---|
| `FeishuSpeechTests/ReviewDestinationDeliveryTests.swift` | Typed AX capture classification, app-identity-before-AX order, exact preference, fallback delivery samples, PID/identity/secure failures, no AX use on fallback. |
| `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift` | Non-secure miss starts panel/audio/provider; secure/destination rejection stays startup-terminal; preview/sealing/edit/confirm and one-copy recovery work with fallback. |
| `FeishuSpeechTests/FinalTextOutputSecurityTests.swift` | Exactly two secure/stable-PID preflight samples, fixed captured PID, multiline acceptance, unsafe rejection, one Cmd+V, and postflight uncertainty. |
| `FeishuSpeechTests/ReviewPasteboardLifecycleTests.swift` | Exact and fallback routes share successful restore, third-party-change preservation, and no restore after uncertainty. |

Existing D-39 editor tests remain regression gates and should not be rewritten.

### Explicitly unchanged product areas

- `FeishuSpeech/Services/AudioRecorder.swift`
- `FeishuSpeech/Services/ByteBoundedAudioIngress.swift`
- `FeishuSpeech/Services/HoldPacketJournal.swift`
- `FeishuSpeech/Services/FeishuStreamingSession.swift`
- `FeishuSpeech/Services/TransportAttemptContext.swift`
- `FeishuSpeech/Controllers/ReviewWindowController.swift`
- `FeishuSpeech/Views/TranscriptionReviewView.swift`
- `FeishuSpeech/Controllers/OverlayWindowController.swift`
- `FeishuSpeech/Views/RecordingOverlayView.swift`
- `FeishuSpeech/Services/CurrentFocusAppendSession.swift`
- `FeishuSpeech/Models/AppSettings.swift`
- `FeishuSpeech/Views/SettingsView.swift`
- hot-key service/state, settings schema, API/transport, entitlements, Info.plist, dependencies, and
  `FeishuSpeech.xcodeproj/project.pbxproj`

## 9. Dependency-safe TDD task order

Production implementers may read and run tests but must not author or edit them. The test custodian
owns all test artifacts listed below.

### Task 1 — RED capture/coordinator contract (test custodian)

Owned files:

- `FeishuSpeechTests/ReviewDestinationDeliveryTests.swift`
- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift`

Add failing coverage for:

- global secure, AX secure role, lost trust, exact capture, and non-secure strict miss as different
  typed outcomes;
- complete application identity captured before the AX attempt and revalidated afterward;
- exact cursor chosen whenever available;
- fallback token containing no AX element/selection;
- fallback startup opening streaming preview and starting recorder/provider only after capture;
- secure/identity rejection keeping panel, recorder, journal, provider, pasteboard, and output at
  zero; and
- existing review snapshot, sealing, action-2, editing, confirmation, stale callback, and async
  independence tests passing with an application-current-focus fixture.

Record the focused baseline command and the expected failures before production changes.

### Task 2 — RED current-focus review transaction (test custodian)

Owned files:

- `FeishuSpeechTests/FinalTextOutputSecurityTests.swift`
- `FeishuSpeechTests/ReviewPasteboardLifecycleTests.swift`

Add failing coverage for:

- two consecutive secure/PID/full-identity samples before any pasteboard snapshot/write;
- first or second secure sample rejecting with zero mutation;
- missing, changed, or unstable PID and PID-reuse identity rejecting with zero mutation;
- exact multiline draft bytes written once and one Cmd+V pair posted only to the captured PID;
- NUL/tab/CR/DEL/C1 rejected before mutation and LF retained exactly;
- post/postflight uncertainty producing no retry or automatic restore; and
- successful fallback using the same full pasteboard restoration and third-party `changeCount`
  preservation as exact delivery.

Tasks 1 and 2 are genuinely independent: they touch different test files and neither test artifact
is generated from the other. They may run in parallel under separate test-custodian ownership if
the workflow chooses; production remains blocked on both RED receipts.

### Task 3 — typed model and AX capture (production implementer)

Owned files:

- `FeishuSpeech/Models/CursorTextModels.swift`
- `FeishuSpeech/Services/AccessibilityClient.swift`

Implement sections 3.1 and 3.2 only. Preserve `captureDestination` and the compatibility cursor
session unchanged. Run the focused capture tests but do not edit them.

### Task 4 — multiline review paste primitive (production implementer)

Owned file:

- `FeishuSpeech/Services/TextInputSimulator.swift`

Implement section 6 by extending the existing D-38 review clipboard transaction. Do not change
compatibility `insertAtCurrentFocusOnce`, direct-Unicode safety, or current-focus append behavior.
Run the focused output/pasteboard tests but do not edit them.

Task 4 depends on Task 3's small shared declarations (`ReviewCurrentFocusValidation` and the
`FinalTextInsertionResult` case), even though the behavioral implementations touch different
files. Do not dispatch Tasks 3 and 4 as independent writes unless Task 3's declarations have
already landed. After that declaration gate, their remaining implementation work is file-disjoint.

### Task 5 — composite capture and delivery routing (production implementer)

Owned file:

- `FeishuSpeech/Services/ReviewDestinationDelivery.swift`

Depends on Tasks 3 and 4. Implement identity-first capture, exact/fallback routing, activation,
the two consecutive samples, postflight, and typed result mapping. Do not add retry, AX recapture,
or an ambient-PID path.

### Task 6 — coordinator integration (production implementer)

Owned file:

- `FeishuSpeech/ViewModels/MainViewModel.swift`

Depends on Tasks 3 and 5. Exhaustively consume the typed capture result and accept either binding.
Keep existing review authority, presentation, recorder barrier, recognition, manual recovery, and
cleanup topology. Do not change production UI/window files.

### Task 7 — independent review and validation

After all focused tests pass:

- correctness review checks exhaustive enum handling, exact-path preference, capture-before-panel,
  two-sample order, exact-once authority, cancellation, and absence of async review backpressure;
- security/privacy review checks no cross-app route, PID-reuse resistance, secure transitions,
  unsafe multiline controls, clipboard uncertainty, transcript-free diagnostics, and zero mutation
  on rejection; and
- any production fix returns to the production implementer, while test-oracle gaps return to the
  test custodian.

### Task 8 — documentation docking (documentation owner)

Depends on verified implementation and final test evidence.

- create `docs/decisions/D-40-01.md` as the implemented authority;
- update D-38-01's header and capture/delivery sections to say D-40 supersedes only strict-AX-only
  startup and adds the application-bound current-focus confirmation route;
- update D-39-01's retention wording so its keyboard policy remains unchanged while target capture
  is D-38 as amended by D-40;
- update `README.md`, `CHANGELOG.md`, `docs/README.md`, `docs/architecture.md`, and
  `docs/streaming-speech-design.md` with the verified symbols and measured validation;
- record `docs/api.md: no impact` unless implementation changes the Feishu transport/response
  contract (this blueprint does not); and
- do not claim that installed third-party targets consumed Cmd+V without owner UAT.

## 10. Validation commands

Run from `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`.

### Focused RED/GREEN gate

```bash
xcodebuild \
  -scheme FeishuSpeech \
  -destination 'platform=macOS,arch=arm64' \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests \
  -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests \
  test
```

### Full serial test gate

```bash
xcodebuild \
  -scheme FeishuSpeech \
  -destination 'platform=macOS,arch=arm64' \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  test
```

### Build, lint, and diff gates

```bash
xcodebuild -scheme FeishuSpeech -configuration Debug build
xcodebuild -scheme FeishuSpeech -configuration Release build
swiftlint --strict
git diff --check
```

### Static scope and topology checks

```bash
git diff --name-only -- \
  FeishuSpeech/Services/AudioRecorder.swift \
  FeishuSpeech/Services/ByteBoundedAudioIngress.swift \
  FeishuSpeech/Services/HoldPacketJournal.swift \
  FeishuSpeech/Services/FeishuStreamingSession.swift \
  FeishuSpeech/Services/TransportAttemptContext.swift \
  FeishuSpeech/Services/CurrentFocusAppendSession.swift \
  FeishuSpeech/Controllers/ReviewWindowController.swift \
  FeishuSpeech/Views/TranscriptionReviewView.swift \
  FeishuSpeech/Controllers/OverlayWindowController.swift \
  FeishuSpeech/Views/RecordingOverlayView.swift

rg -n "captureDrainTask|consumerTask|reviewSurfacePresenter|renderReview|renderEditable" \
  FeishuSpeech/ViewModels/MainViewModel.swift

rg -n "insertReviewAtCurrentFocusOnce|postCommandV|postUnicodeText|restoreAndValidateBeforeDelivery" \
  FeishuSpeech FeishuSpeechTests
```

The first command must print no changed protected production paths. The `rg` output is a review
aid: verify that capture/journal and recognition loops gained no presenter wait/call, that fallback
review delivery uses Cmd+V rather than compatibility Unicode output, and that exact AX restoration
still exists.

## 11. Rollback and failure routing

- Because changes are internal and no stored schema changes, rollback is a source/test/docs revert;
  no data migration or dependency rollback is required.
- If typed capture cannot prove the original complete identity before the panel opens, keep
  `.destinationUnavailable`; do not weaken identity completeness or bind after panel activation.
- If global Secure Input cannot be distinguished reliably from ordinary cursor absence, keep the
  interaction blocked and route the evidence to the security reviewer; do not admit the fallback.
- If the two samples or fixed-PID Cmd+V cannot be made atomic enough on `@MainActor`, retain the
  exact route and fail fallback confirmation into one-copy manual recovery. Do not use global HID
  posting or ambient focus.
- If a key post or postflight fails after pasteboard mutation, classify delivery uncertain, leave
  the frozen draft available through the existing one-copy recovery, and never retry or restore
  automatically.
- If a test failure is behavioral/oracle-related, return it to the test custodian; build/type/lint
  failures route to the build-error resolver; production fixes remain with the implementer.

## 12. Deliberate limit and UAT boundary

The application-bound fallback proves the exact original application, not the original control or
caret inside that application. After review-panel dismissal and exact-app activation, delivery is
to that application's current focus. Supporting an unavailable original AX element would require
a different platform authority (for example an input method) and is outside Issue #40.

Automated tests can prove identity/PID/security sampling, fixed process targeting, exact-once local
submission, multiline bytes, and clipboard rules. They cannot prove WindowServer activation or
that every third-party control consumed Cmd+V. Installed Release UAT must cover at least one target
that previously showed `无法确认输入位置`, one exact-AX target, Secure Input startup rejection,
cross-app switching during confirmation, multiline confirmation, and manual recovery after a
forced delivery uncertainty.
