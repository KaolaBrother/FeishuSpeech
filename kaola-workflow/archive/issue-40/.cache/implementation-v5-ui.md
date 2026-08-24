# Issue #40 v5 UI lane implementation receipt

Date: 2026-08-24 (Asia/Shanghai)

## Scope

Production-only UI lane changes in the issue worktree:

- `FeishuSpeech/Controllers/ReviewWindowController.swift`
- `FeishuSpeech/Views/TranscriptionReviewView.swift`
- `FeishuSpeech/Models/TranscriptionReviewState.swift`

No tests, MainViewModel, output/security services, capture/recognition paths, Xcode configuration,
or other workflow files were edited by this lane. Existing concurrent changes remain untouched.

## Implementation evidence

- `ReviewPanel` is constructed once with `.nonactivatingPanel`, `isFloatingPanel = true`,
  `becomesKeyOnlyIfNeeded = true`, `hidesOnDeactivate = false`, and `canBecomeMain = false`.
  Read-only states remain non-key and mouse-transparent; the same panel is reused for draft states.
- Presentation focus calls only `makeKeyAndOrderFront`; the activation seam is retained solely for
  injected compatibility environments and is never invoked. No `NSApp`/running-application activation,
  global event monitor, pasteboard, or target output path was added.
- Readiness continues to poll the injected application-active (target-preservation proxy), panel-key,
  editor materialization/attachment, and editor-first-responder predicates. A failed advisory activation
  request cannot promote an unproven surface or dismiss the visible Send fallback.
- `ReviewPanel.sendEvent(_:)` routes keyboard confirmation through one named
  `ReviewPreviewReturnArbiter`. It accepts only exact unmodified, nonrepeat main Return/keypad Enter
  delivered to the current key panel and a responder within the panel. Marked IME text, Shift,
  Option, Control, Command, Caps/function flags, repeats, and events outside the panel pass through.
  The native editor has no competing Return `keyDown` confirmation path, and Send has no Return key
  equivalent/default shortcut; mouse Send remains explicit.
- `preparingSubmission` and `submittedUnverifiedTerminal` render a frozen native read-only draft with
  no Send or qualified Return authority. The shared internal transcript size remains 18pt for streaming
  SwiftUI text and the native editor; existing panel dimensions/titlebar geometry are unchanged.

## Verification

Before evidence (authoritative RED receipt): `kaola-workflow/issue-40/test-red-v5.md` records the
baseline v5 selector set at 10 tests / 7 failures, including the four nonactivating/activation failures
and the Send default-key-equivalent failure; the existing coordinator supporting baseline was 152 tests /
0 failures.

After owned edits:

```text
swiftlint lint --strict FeishuSpeech/Controllers/ReviewWindowController.swift \
  FeishuSpeech/Views/TranscriptionReviewView.swift \
  FeishuSpeech/Models/TranscriptionReviewState.swift
exit 0 — 0 violations

git diff --check
exit 0

v5 UI static guard search (style/arbiter/state symbols, then rejection search for
`activate(`, `addGlobalMonitorForEvents`, `keyboardShortcut(.return`, and `override func keyDown`)
exit 0 — pass
```

Focused UI test command:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests test
```

Exit 65 before test execution because the concurrent output lane currently has compile errors in
`FeishuSpeech/Services/ReviewSubmissionExecutor.swift` (`fileprivate` access to the new handle fields and
`Thread.yield` unavailable). The UI files compiled during the build attempt; no UI-file compiler error was
reported.

Debug build command:

```text
xcodebuild -scheme FeishuSpeech -configuration Debug build -parallel-testing-enabled NO
```

Exit 65 for the same concurrent output-lane errors. The working tree still contains no changes to the
protected audio/recognition topology; a name-only protected-path check showed no diff for
`AudioRecorder.swift`, `FeishuStreamingSession.swift`, `FeishuStreamingSpeechProvider.swift`, or
`HoldPacketJournal.swift`. The newly added state cases also require the separately owned MainViewModel
coordinator integration to extend its exhaustive switches; that integration was intentionally not made
in this UI lane.

Verification tier: **build-green** for the owned UI files (strict lint and source compilation reached
cleanly); repository-wide build/tests remain blocked by the concurrent output lane and must be rerun after
that lane settles.

## Coordinator integration addendum

Date: 2026-08-24 (Asia/Shanghai)

Production-only coordinator integration in the issue worktree additionally changed:

- `FeishuSpeech/ViewModels/MainViewModel.swift`

The accepted default path now constructs `SystemReviewSubmissionFacade`; the legacy
`ReviewDestinationDelivering` path is selected only when that compatibility dependency is explicitly
injected. MainActor receives only `StableApplicationIdentity` and
`CapturedReviewTargetDescriptor` values. Target capture is asynchronous through the facade, validates
the request generation, stable application identity, and safe capture state, releases stale or rejected
target IDs, and does not gate the independent audio/recognition lanes. A terminal recognition result
waits for a pending target capture before the action-2-plus-recorder-barrier transition can publish the
editable authority.

Confirmation now validates the current review ID, generation, revision, frozen draft, and production
target ID; it issues and stores the opaque handle, request, and immutable admission envelope before
enqueue. Only matching uncancelled admission events enqueue start. Close/discard/lifecycle cancellation
enqueues nonblocking cancellation while retaining the frozen authority and handle until a matching
terminal receipt. Pre-boundary failures restore the exact draft with typed feedback. A
`submittedUnverified` receipt renders the frozen terminal state without Send/Return capability, releases
the captured target, clears the editable authority, and returns the hot-key axis to idle; it never retries,
copies, retargets, or re-exposes confirmation. Matching checks reject foreign/stale events without
mutating the current surface.

Verification after this integration:

```text
xcodebuild -scheme FeishuSpeech -configuration Debug build -parallel-testing-enabled NO
exit 0 — BUILD SUCCEEDED

swiftlint lint --strict FeishuSpeech/ViewModels/MainViewModel.swift \
  FeishuSpeech/Controllers/ReviewWindowController.swift \
  FeishuSpeech/Views/TranscriptionReviewView.swift \
  FeishuSpeech/Models/TranscriptionReviewState.swift
exit 0 — 0 violations

git diff --check
exit 0

protected topology name-only check for AudioRecorder.swift, FeishuStreamingSession.swift,
FeishuStreamingSpeechProvider.swift, and HoldPacketJournal.swift
exit 0 — no protected-path diffs
```

The serialized coordinator/UI test command was attempted after the output lane compiled, but test
compilation is currently blocked by an untouched concurrent test switch in
`FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:1942`, which lacks the newly owned
`preparingSubmission` and `submittedUnverifiedTerminal` cases. The command exited 65 before test
execution; no test file was changed by this lane. This is a test-custody handoff blocker, not a
production compile failure.

Verification tier: **build-green** for the production integration; focused test execution remains
blocked by the concurrent test protocol update.

### Coordinator follow-up safety checks

- Ambient monitoring/Secure Input failure while a production handle is live now takes the same
  nonblocking cancellation path as close/discard, retaining the frozen authority until its terminal
  receipt instead of silently dropping the attempt.
- Drain-expiry recovery demotes the surface to read-only and releases the captured production target;
  it cannot manufacture action-2 authority or leave a target registration live.
- The facade event sink remains a weak MainViewModel capture, so teardown cannot retain the coordinator
  through late typed events.

Final production checks after these follow-ups:

```text
xcodebuild -scheme FeishuSpeech -configuration Debug build -parallel-testing-enabled NO
exit 0 — BUILD SUCCEEDED

swiftlint lint --strict FeishuSpeech/ViewModels/MainViewModel.swift \
  FeishuSpeech/Controllers/ReviewWindowController.swift \
  FeishuSpeech/Views/TranscriptionReviewView.swift \
  FeishuSpeech/Models/TranscriptionReviewState.swift
exit 0 — 0 violations

git diff --check
exit 0
```

Final post-edit rerun after cancellation de-duplication and pending-draft projection fencing:

```text
xcodebuild -scheme FeishuSpeech -configuration Debug build -parallel-testing-enabled NO
exit 0 — BUILD SUCCEEDED

swiftlint lint --strict FeishuSpeech/ViewModels/MainViewModel.swift \
  FeishuSpeech/Controllers/ReviewWindowController.swift \
  FeishuSpeech/Views/TranscriptionReviewView.swift \
  FeishuSpeech/Models/TranscriptionReviewState.swift
exit 0 — 0 violations

git diff --check
exit 0

protected topology check
exit 0 — no protected-path diffs
```

## Coordinator terminal-state oracle repair

Date: 2026-08-24 (Asia/Shanghai)

`FeishuSpeech/ViewModels/MainViewModel.swift` now publishes
`.submittedUnverifiedTerminal` before rendering either the production-facade or explicit legacy
`.submittedUnverified` receipt. The frozen text, incomplete flag, and `.deliveryUncertain` feedback are
the same values passed to the terminal presenter. The editable authority is invalidated before the
terminal render, the production target is released, the terminal callbacks are inert, and the hot-key
axis returns to idle. This prevents a receipt from leaving the published ViewModel state at
`.preparingSubmission` or allowing a stale callback to remount an editable surface.

Verification:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test
exit 0 — 32 tests, 0 failures

xcodebuild -scheme FeishuSpeech -configuration Debug build -parallel-testing-enabled NO
exit 0 — BUILD SUCCEEDED

swiftlint lint --strict FeishuSpeech/ViewModels/MainViewModel.swift
exit 0 — 0 violations

git diff --check
exit 0

protected topology check
exit 0 — no protected-path diffs
```

Verification tier: **tests-green**

## v5 correctness-review R5-R7 production repair

Date: 2026-08-24 (Asia/Shanghai)

Owned production repairs:

- `MainViewModel` now treats a matching `submittedUnverified` receipt as a terminal lifecycle event:
  it cancels stale presentation work, releases the production target, revokes the handle/authority,
  clears the transcript projection, sets review state to `.idle`, dismisses the presenter once, and
  resets the hot-key axis. Duplicate or late facade/legacy events find no current handle/authority and
  are inert. Pre-boundary `notStarted` still restores the exact editable draft.
- `ReviewPresentationFocusRequest` carries the captured `StableApplicationIdentity`. Production
  readiness now samples the live stable frontmost identity (PID, bundle ID, executable URL, launch date)
  and requires exact equality plus FeishuSpeech inactive; compatibility requests without identity retain
  the existing injected boolean seam.
- Intent minting is now colocated in `ReviewWindowController`: both the real SwiftUI Send callback and
  the qualified native panel Return route are the only gesture bridges that call fileprivate intent
  constructors. The SwiftUI view receives only a no-argument gesture callback and cannot manufacture an
  intent; MainViewModel still accepts only the opaque intent callback and never constructs one.

The supplied R7 lexical oracle is internally contradictory: it requires
`fileprivate static func qualifiedPreviewReturn` to appear in
`TranscriptionReviewView.swift` while also requiring `ReviewWindowController.swift` to invoke that
fileprivate symbol. Swift fileprivate access is file-scoped, so both requirements cannot be true in a
valid implementation. The production repair follows the valid architecture—controller-local
fileprivate constructors plus controller-owned Send/Return gesture bridges—and does not add a
forgeable compatibility factory or source-string workaround. The test/TDD owner must reconcile that
oracle with the approved architecture.

R1-R4 remain outside this lane's custody because they require
`AccessibilityClient.swift`, `ReviewSubmissionExecutor.swift`, and related output/security surfaces;
they were not modified here.

Static verification (no `xcodebuild` run per coordinator serialization instruction):

```text
swiftlint lint --strict FeishuSpeech/Models/TranscriptionReviewState.swift \
  FeishuSpeech/Controllers/ReviewWindowController.swift \
  FeishuSpeech/Views/TranscriptionReviewView.swift \
  FeishuSpeech/ViewModels/MainViewModel.swift
exit 0 — 0 violations

git diff --check
exit 0
```

Verification tier: **build-green** pending root's serialized build and migrated UI/coordinator tests.

## v5 UI follow-up: readiness key seam and retry diagnosis

Date: 2026-08-24 (Asia/Shanghai)

The native Return arbiter now consumes the controller's injected
`readinessEnvironment.panelIsKey` predicate. The AppKit default remains
`panel.isKeyWindow`, so production still requires the real nonactivating panel
to be key; deterministic accessory-host tests can now use the same readiness
seam without weakening the production predicate. The arbiter continues to
require the exact panel window number, qualified Return/keypad key, no repeat,
no relevant modifiers, and a responder inside the panel content.

The second real Send failure reported after `.notStarted(.cancellation)` was
audited as a test-host geometry issue rather than a stale production callback:
`renderDraft` reassigns `onConfirm` on every render, resets `isConfirming` for
`.editable`, updates `renderedState`, and routes the SwiftUI callback through
`handleSendGesture`, which reads the current callback. The recovery feedback
text changes the fixed-stack button y-position, while the test helper probes
only y values 30 through 10; the first Send has no feedback and succeeds at
that coordinate. `EditableDraftView` also propagates the current native editor
text through `updateNSView` and the draft-change callback. No production
callback/state repair was warranted, and no test was changed.

The missing captured-identity focus test remains a fixture issue when the
request omits `capturedApplication`; production MainViewModel always supplies
the exact identity and no compatibility fallback was added for that fixture.

Static verification:

```text
swiftlint lint --strict FeishuSpeech/Models/TranscriptionReviewState.swift \
  FeishuSpeech/Controllers/ReviewWindowController.swift \
  FeishuSpeech/Views/TranscriptionReviewView.swift \
  FeishuSpeech/ViewModels/MainViewModel.swift
exit 0 — 0 violations

swiftc -parse FeishuSpeech/Models/TranscriptionReviewState.swift \
  FeishuSpeech/Controllers/ReviewWindowController.swift \
  FeishuSpeech/Views/TranscriptionReviewView.swift \
  FeishuSpeech/ViewModels/MainViewModel.swift
exit 0

git diff --check
exit 0
```

Verification tier: **build-green** (static production gate green; root retains
serialized build/test custody).

## v5-r3 R11 whitespace-only Return repair

Date: 2026-08-24 (Asia/Shanghai)

`ReviewPreviewReturnArbiter` now samples the retained native editor's current
string and rejects a main Return/keypad Enter confirmation when trimming
`whitespacesAndNewlines` leaves an empty string. The local panel route consumes
that exact unmodified/nonrepeating event without minting an intent, so the
whitespace-only draft remains unchanged rather than receiving an LF through
the ordinary NSTextView route. Marked-text events still forward to the IME;
Shift, Option, Control, Command, repeat, wrong-window, non-key-panel, and
non-whitespace multiline behavior remain unchanged. The existing panel key,
window-number, descendant-responder, and fileprivate intent gates remain in
force.

Baseline RED from `test-green-v5.md`: the 19-test keyboard selector had 2
failures, both whitespace cases, because the arbiter admitted the whitespace
draft. The first repair correctly removed confirmation but forwarded Return,
which exposed the required no-mutation detail by adding LF. The final repair
consumes only the exact whitespace-only eligible event.

Focused verification:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-r11-r3-green.3Anhjf \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests test
exit 0 — 36 tests, 0 failures
  - TranscriptionReviewViewKeyboardTests: 19 passed
  - ReviewWindowControllerReadinessTests: 17 passed

swiftlint lint --strict FeishuSpeech/Controllers/ReviewWindowController.swift
exit 0 — 0 violations

swiftc -parse FeishuSpeech/Controllers/ReviewWindowController.swift
exit 0

git diff --check
exit 0
```

Verification tier: **tests-green**.
