# Issue #40 v5 Correctness Review

- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
- Baseline: `b321ac5d6c04c91ced9afeb2240f9566d9b8d305`
- Scope: current uncommitted v5 production and tests, reviewed against `architecture-blueprint-v5.md` and the owner contract
- Result: FAIL. Seven blocking correctness findings remain (four high, three medium).

## Findings

### R1 - Exact-cursor capture never records or restores the original selection

finding: id=R1 scope=in_scope action=fix status=open severity=high fix_role=implementer rationale=exact-cursor submissions can land at a later same-application caret instead of the originally captured caret

- Failure class: wrong-target text placement.
- Trigger: capture an editable element whose selected range is settable, then move focus or the selection to another editable location in the same application before confirming.
- Expected: `.exactCursor` retains the original focused AX element and exact `CursorTextRange`; after the real confirmation, preflight restores and rereads that element and selection before any event preparation or post.
- Observed: `ReviewSubmissionRawTargetState` stores only the AX application element and an optional focused element; it has no original selection (`FeishuSpeech/Services/AccessibilityClient.swift:15-28`). Capture decides `.exactCursor` solely from `AXUIElementIsAttributeSettable` and never reads `kAXSelectedTextRangeAttribute` (`FeishuSpeech/Services/AccessibilityClient.swift:597-640`). Validation creates a fresh system-wide focused-element lookup and accepts any safe editable element in the captured PID; it neither compares that element with `target.focusedElement` nor performs a focused/selection AX setter or readback (`FeishuSpeech/Services/AccessibilityClient.swift:644-677`). The executor then prepares the Unicode pair immediately after that validation (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:645-727`).
- Reproduction: focus field A at offset N, begin Fn capture, move to field B in the same target application while the preview is open, and click Send. The current validation accepts field B because its PID and role are safe, then posts to that application's current responder. The originally captured caret is not restored.
- Guard analysis: stable application identity and fixed PID do not distinguish two fields or two selections in the same process. No current v5 test exercises `SystemReviewSubmissionAXRuntime`; the v5 fake always returns `.applicationBoundCurrentFocus` (`FeishuSpeechTests/FinalTextOutputSecurityTests.swift:2291-2343`). Existing original-selection tests exercise only the legacy `MacAccessibilityClient`/`FinalTextOutput` route, which the accepted app no longer uses.
- Minimal repair boundary: add original selection/focus facts to executor-confined raw state; read the selected range during exact capture under the capture deadline; after confirmation, set focus and the exact range on the captured element and reread equality/security/PID under the one submission deadline before event construction. Add production-runtime tests for exact restore, same-PID different-element rejection, selection mismatch, and zero setter calls before confirmation.

### R2 - The accepted v5 executor has no relevant-modifier stabilization or final modifier gate

finding: id=R2 scope=in_scope action=fix status=open severity=high fix_role=implementer rationale=holding a modifier through Send still reaches the Unicode down-up boundary

- Failure class: forbidden output under an unstable input state.
- Trigger: hold Command, Shift, Control, Option, Fn, or Caps Lock and click the real Send button while the preview is editable.
- Expected: the whole-deadline preflight obtains consecutive empty combined-session modifier samples and rechecks modifier emptiness at the final gate; a held relevant modifier returns `notStarted(.modifierInstability)` and posts zero events.
- Observed: `performRawAttempt` validates AX, builds the pair, and enters `commit` without any `CGEventSource.flagsState` sample (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:645-709`). The final gate compares only deadline, cancellation, phase, and epochs before posting down/up (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:729-803`). Repository search finds no modifier sampling in the v5 executor; `.modifierInstability` is only mapped by the coordinator after a receipt that production never creates (`FeishuSpeech/ViewModels/MainViewModel.swift:2497`).
- Reproduction: hold Command before the Send mouse click. The modifier `flagsChanged` can advance the global epoch before the attempt claim, but claim then captures that already-advanced value as its valid baseline. With no later modifier transition, both epoch comparisons succeed and the pair is posted.
- Guard analysis: modifier-free flags on the synthetic events do not prove the user's combined-session modifier state is empty. The new executor tests contain no modifier seam or held-modifier case; the modifier tests at `FeishuSpeechTests/FinalTextOutputSecurityTests.swift:1476-1564` exercise only the retired legacy delivery composition.
- Minimal repair boundary: add executor-confined combined-session modifier stabilization within the existing absolute deadline, check the attempt latch after every sample/sleep, and include a final empty-modifier sample before down without arbitrary callbacks under the commit lock. Add v5 production-composition tests for every relevant modifier with zero prepare/post or, if preparation must precede the final sample, zero post.

### R3 - The production facade never arms activation, termination, process-generation, or observer-loss signals

finding: id=R3 scope=in_scope action=fix status=open severity=high fix_role=implementer rationale=programmatic target drift after AX validation can still post to a no-longer-frontmost or terminated process

- Failure class: stale-target output race.
- Trigger: after `SystemReviewSubmissionAXRuntime.validate` samples the captured target as frontmost, programmatically activate another application or terminate/restart the captured process before the executor reaches key-down, without generating physical input.
- Expected: activation/frontmost, target termination, process-generation change, and observation loss synchronously advance the combined epoch; the executor also takes a final target identity/frontmost/security sample immediately before gate admission, so an observed pre-down change posts zero.
- Observed: raw validation samples `NSWorkspace.shared.frontmostApplication` once (`FeishuSpeech/Services/AccessibilityClient.swift:644-677`), then pair construction and gate admission have no target sampler (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:667-803`). `SystemReviewSubmissionFacade` constructs only the control plane, executor, AX runtime, and committer; it creates or starts no activation/termination/process observer (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:916-939`). The only workspace activation monitor that advances the combined epoch is the legacy `WorkspaceCurrentFocusActivationMonitor`, and its notifications advance the epoch only after an instance has been started (`FeishuSpeech/Services/CurrentFocusAppendSession.swift:973-1027`); the accepted facade never instantiates it. There is no termination observer in the v5 composition.
- Reproduction: inject a blocking event backend after AX validation, activate application B through `NSRunningApplication.activate`, then release preparation. No physical tap signal advances the epoch, the final gate sees the old baseline, and one down/up pair is posted to captured PID A even though A is no longer frontmost. The same window allows a terminated/restarted PID to pass the gate after the last identity sample.
- Guard analysis: fixed PID prevents ambient retargeting but does not satisfy the captured-target-must-remain-frontmost contract. The unavoidable public-API micro-window begins only after the required final sample/epoch gate; this implementation leaves the entire validation-to-post interval unobserved. Current tests manually advance a singleton epoch and use a fake AX runtime, so they do not exercise the missing production observer composition.
- Minimal repair boundary: make one executor-owned observation session part of `SystemReviewSubmissionFacade`/`ReviewSubmissionExecutor`, scoped to the exact captured identity and attempt. Fail closed if activation, termination, process-generation, or observer-loss coverage cannot be armed; sample exact stable identity/frontmost/security immediately before baseline/gate; add deterministic programmatic activation, termination, launch-date change, and observer-loss tests against the actual production composition.

### R4 - Ordinary nonsecure AX cursor misses terminate recording instead of selecting the application-bound fallback

finding: id=R4 scope=in_scope action=fix status=open severity=high fix_role=implementer rationale=common safe targets recreate the owner-rejected unable-to-confirm-input-position startup failure

- Failure class: accepted-path availability regression.
- Trigger: the captured application is stable/frontmost with Secure Input off and Accessibility trusted, but the system-wide focused-element lookup returns no value/times out, the ordinary editable element has no supported subrole, or its selected-range capability cannot be queried.
- Expected: distinguish a proven secure/unverifiable target from an ordinary nonsecure cursor-detail miss. For the latter, retain the captured application identity/PID and return `.applicationBoundCurrentFocus`; secure or genuinely unverifiable cases remain fail closed.
- Observed: a missing focused AX element returns `.accessibilityTimeout` before a fallback can be selected (`FeishuSpeech/Services/AccessibilityClient.swift:597-605`). `safeEditableElement` also requires a text role plus a nonnil `AXStandard`/search subrole, and any miss becomes `.securityRejected` (`FeishuSpeech/Services/AccessibilityClient.swift:613-627,726-745`). The fallback is selected only after all those exact-element probes succeed and only the selected-range attribute is definitively non-settable (`FeishuSpeech/Services/AccessibilityClient.swift:619-628`). MainViewModel maps every production capture failure to `"无法确认输入位置"` and terminates the interaction (`FeishuSpeech/ViewModels/MainViewModel.swift:768-800`).
- Reproduction: use an ordinary nonsecure editor for which `kAXFocusedUIElementAttribute` temporarily returns `.noValue`, or an AX text area whose subrole is absent. Fn startup enters capture, returns failure, and destroys the interaction rather than streaming to a review draft bound to the original application.
- Guard analysis: legacy fallback tests exercise `MacAccessibilityClient` and `SystemReviewDestinationDelivery`, not `SystemReviewSubmissionAXRuntime`. The v5 raw fake always returns fallback success, so it cannot catch production classification failures (`FeishuSpeechTests/FinalTextOutputSecurityTests.swift:2291-2343`).
- Minimal repair boundary: introduce typed raw-capture outcomes that separate secure/unverifiable evidence from ordinary cursor unavailability; under the owner-approved safe application-level proofs, mint `.applicationBoundCurrentFocus` for ordinary misses while preserving zero AX mutation. Add direct production AX-runtime tests for focused-element no-value, unsupported selected-range, missing benign subrole, secure field, unknown security, and identity drift.

### R5 - Boundary-crossed terminal output leaves the ordinary preview visible instead of dismissing and returning to idle

finding: id=R5 scope=in_scope action=fix status=open severity=medium fix_role=implementer rationale=submitted-unverified resets the hotkey but retains a transcript-bearing terminal panel and nonidle review state

- Failure class: terminal state-machine and UI lifecycle violation.
- Trigger: the one fixed down/up pair crosses key-down and the facade emits `.submittedUnverified`.
- Expected: immediately revoke Send/Return authority, release the target, dismiss the ordinary preview, clear transcript-bearing presentation state, and return the review/hot-key axes to idle; content-free uncertainty telemetry may remain and resend remains impossible.
- Observed: `handleReviewSubmissionTerminal` releases the target and clears authority, but sets `.submittedUnverifiedTerminal`, calls `renderDraft` with the exact transcript, and only resets the hot key (`FeishuSpeech/ViewModels/MainViewModel.swift:2290-2332`). It never calls `reviewSurfacePresenter.dismiss()` and never sets `transcriptionReviewState = .idle`. `TranscriptionReviewView` consequently renders the draft plus `"输入状态不确定；请检查目标应用。"` (`FeishuSpeech/Views/TranscriptionReviewView.swift:107-113`).
- Guard analysis: Send/qualified Return are correctly absent in this terminal surface, so no-resend holds, but dismissal/idle does not. The coordinator test codifies the wrong terminal presentation and checks only that the Send control is absent (`FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:378-399`); it has no dismissal/idle assertion.
- Minimal repair boundary: on the matching terminal receipt, revoke callbacks/handle/target, dismiss the presenter, erase transcript projection, and set review state to `.idle` while retaining only content-free diagnostics. Add assertions for exactly one dismissal, idle state, cleared draft projection, one pair, and inert late/duplicate terminal events.

### R6 - Presentation readiness proves only that some other application is frontmost

finding: id=R6 scope=in_scope action=fix status=open severity=medium fix_role=implementer rationale=the panel can report focused after the captured target has already changed to another application

- Failure class: false focus-topology proof.
- Trigger: capture target A, then make unrelated application B frontmost while the nonactivating preview attempts to become key/editor-first-responder.
- Expected: a focus request carries the exact captured stable application identity and readiness compares the live frontmost identity to that exact value while also proving FeishuSpeech inactive and the panel/editor key topology.
- Observed: `ReviewPresentationFocusRequest` carries only review ID, generation, and attempt ID (`FeishuSpeech/Models/TranscriptionReviewState.swift:66-70`), and MainViewModel therefore cannot pass a captured PID or stable identity (`FeishuSpeech/ViewModels/MainViewModel.swift:1985-2006`). The production readiness closure returns true for any frontmost PID other than FeishuSpeech (`FeishuSpeech/Controllers/ReviewWindowController.swift:73-84`), and `firstUnmetReadinessPredicate` treats that as sufficient (`FeishuSpeech/Controllers/ReviewWindowController.swift:437-456`).
- Reproduction: switch from captured A to B before focus polling completes. `applicationIsActive()` returns true because B is not FeishuSpeech; if the panel and editor predicates pass, the controller emits `.focused` for A even though A is not frontmost.
- Guard analysis: output preflight may later reject some drift, but presentation evidence is already false and cannot support the promised Return topology. `test_nonactivatingPanelKeepsCapturedTargetFrontmost` injects a boolean probe and has no captured target identity or different-app case (`FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift:30-49`).
- Minimal repair boundary: carry the stable captured application identity in `ReviewPresentationFocusRequest`; make the readiness environment return the live stable frontmost identity and compare exact equality, not merely not-self. Add positive A and negative B/restarted-A cases using the same retained panel.

### R7 - `ReviewConfirmationIntent` exposes a module-internal zero-argument factory

finding: id=R7 scope=in_scope action=fix status=open severity=medium fix_role=implementer rationale=any module caller can manufacture the capability intended to exist only at a real preview gesture site

- Failure class: confirmation authority forgeability and false test coverage.
- Trigger: any production code in the FeishuSpeech module that retains an editable preview confirmation callback calls `ReviewConfirmationIntent.qualifiedPreviewReturn()` directly.
- Expected: both construction paths are confined to real UI gesture custody: the Send button in the intent's file and the one native panel Return arbiter. Non-UI production code cannot construct an intent.
- Observed: although the stored initializer is `fileprivate`, `qualifiedPreviewReturn()` has default module-internal visibility and returns a fresh intent without an argument or capability (`FeishuSpeech/Views/TranscriptionReviewView.swift:14-32`). The controller uses it at the legitimate gesture site (`FeishuSpeech/Controllers/ReviewWindowController.swift:545-567`), but every other module file can invoke the same factory. The comment claiming internal visibility prevents manufacturing is incorrect.
- Guard analysis: MainViewModel still checks editable state, revision, draft safety, and one-active status, but those checks do not prove a real user gesture. Tests demonstrate forgeability by calling the factory directly (`FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:1753-1755`; `FeishuSpeechTests/TranscriptionReviewViewTests.swift:1029-1079`). The supposed opacity test checks only for the word `fileprivate` and the controller call, not the factory's access level (`FeishuSpeechTests/TranscriptionReviewViewTests.swift:399-424`). The Return tests also short-circuit through this factory instead of routing the qualifying event through a real `ReviewPanel.sendEvent`, so they do not exercise production intent minting.
- Minimal repair boundary: colocate the native Return arbiter/bridge with the intent so the Return constructor can remain `fileprivate`, or use an equivalently unforgeable fileprivate capability owned by the real panel gesture site. Remove direct factory calls from coordinator/keyboard tests and drive the actual panel event route; add a static/compiler boundary asserting no module-internal zero-argument intent factory exists.

## Passing surfaces verified

- The real app constructs `MainViewModel(settings:)` with no legacy delivery injection (`FeishuSpeech/App/FeishuSpeechApp.swift:9-16`); the initializer selects `SystemReviewSubmissionFacade` and sets `reviewDestinationDelivery = nil` (`FeishuSpeech/ViewModels/MainViewModel.swift:368-377`). The accepted production path therefore does not reach `SystemReviewDestinationDelivery` or legacy `FinalTextOutput`.
- The accepted facade/executor path contains no pasteboard access, Cmd+V, target activation, or global Return authorization. The panel is created as nonactivating and the Send button has no Return key equivalent.
- Once the current gate admits, production performs exactly one fixed-PID Unicode down attempt followed synchronously by exactly one mandatory up attempt, with no retry (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:765-791`). Admission, start, cancellation, raw work, and event delivery are dispatched off MainActor through separate serial contexts.
- Action 2 and the recorder barrier remain separate and converge before `.editable` (`FeishuSpeech/ViewModels/MainViewModel.swift:1868-1952`). No preconfirmation AX focus/selection setter, Unicode post, clipboard operation, or delivery call was found in the accepted v5 capture/preview/edit path.
- `git diff --check` passed. Per review policy, the expensive full test matrix was not rerun after blocking defects were admitted.

verdict: fail
findings_blocking: 7
review_conclusion: The candidate preserves several important no-output and exactly-once mechanics, but target binding, modifier fencing, drift observation, fallback capture, terminal dismissal, focus proof, and intent opacity remain incomplete.
