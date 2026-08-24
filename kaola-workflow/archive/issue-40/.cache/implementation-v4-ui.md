# Issue #40 v4 UI/coordinator implementation receipt

Scope: production-only UI/coordinator lane in the four authorized files:

- `FeishuSpeech/Models/TranscriptionReviewState.swift`
- `FeishuSpeech/Controllers/ReviewWindowController.swift`
- `FeishuSpeech/Views/TranscriptionReviewView.swift`
- `FeishuSpeech/ViewModels/MainViewModel.swift`

The v4 UI lane removes `editablePending` and readiness-as-authority from the
product flow. After the action-2 plus recorder barrier, a usable draft is
published and rendered as `.editable` immediately in the existing review
panel. Send and qualified native Return/Enter are available without waiting
for presentation focus. Focus work is a generation/review/attempt-fenced,
content-free telemetry aid; activation failure is advisory, while actual
AppKit predicates are still polled. Focus completion cannot change review
state, draft revision, feedback, or delivery.

Confirmation now requires an opaque `ReviewConfirmationIntent` constructed
only by the real Send button or the qualified native Return/Enter path. The
coordinator requires the current review ID, exact nonoptional callback
revision, current authority-owned draft, and the opaque intent. Stale and
duplicate callbacks are no-ops. Failed, cancelled, and uncertain delivery
paths return the frozen draft to `.editable` with no automatic retry, copy, or
retarget. Accepted edits create a new authority revision and clear feedback
from the prior frozen attempt. The existing 18pt transcript typography,
fixed panel geometry, titlebar-safe content area, and independent capture and
recognition roots are preserved.

## Verification evidence

Before implementation, the serialized v4 focused RED command was:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests test
exit 65 — 54 tests, 49 failures; old editable-pending/readiness and
confirmation seams were still exercised.
result: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_20-25-32-+0800.xcresult
```

Production source parsing and the owned-file strict lint pass after the v4
changes:

```text
swiftc -parse FeishuSpeech/Models/TranscriptionReviewState.swift \
  FeishuSpeech/Controllers/ReviewWindowController.swift \
  FeishuSpeech/Views/TranscriptionReviewView.swift \
  FeishuSpeech/ViewModels/MainViewModel.swift
exit 0

swiftlint lint --strict --config .swiftlint.yml \
  FeishuSpeech/Models/TranscriptionReviewState.swift \
  FeishuSpeech/Controllers/ReviewWindowController.swift \
  FeishuSpeech/Views/TranscriptionReviewView.swift \
  FeishuSpeech/ViewModels/MainViewModel.swift
exit 0 — 0 violations, 0 serious in 4 files.

git diff --check
exit 0 — no output.
```

The Debug build was attempted after the UI lane. It reached the concurrent
output lane and remained blocked by unrelated, in-progress changes in
`FeishuSpeech/Services/TextInputSimulator.swift` (compiler/lint diagnostics);
that file is outside this lane's custody and was not changed here. The v4 test
doubles are also being migrated by test
custody, so the old focused test tree currently references removed APIs and
must not be edited in this lane.

Additional source/topology checks:

```text
swiftc -parse <the four authorized production files>
exit 0

obsolete-authority grep over the four authorized production files
exit 0 — no editablePending, ReviewEditable* readiness, onRetryReadiness,
requestEditableReadiness, or retryReviewReadiness symbols.

reviewDestinationDelivery.deliver call-site count in MainViewModel.swift
1

protected topology diff against 4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a
exit 0 — no protected-file changes.

swiftlint lint --strict --config .swiftlint.yml
exit 2 — 6 violations, all in the concurrent output lane's
FeishuSpeech/Services/TextInputSimulator.swift (complexity, parameter count,
and compatibility type-name diagnostics); the four owned files remain at
0 violations.
```

## Shared-output integration follow-up

The shared output lane now exposes `ReviewDeliveryResult.submittedUnverified`
instead of `.inserted`. The coordinator retains the exact frozen draft and
returns it to `.editable` with `.deliveryUncertain` feedback for both
`submittedUnverified` and `deliveryUncertain`; it never claims consumed
success or revokes the draft authority. The opaque confirmation capability is
now a `struct` with a fileprivate explicit initializer, because Swift enums
cannot contain stored properties; no compiler-generated public/memberwise
initializer is available.

Verification after this integration:

```text
swiftc -parse <the four authorized production files>
exit 0

swiftlint lint --strict --config .swiftlint.yml <the four authorized files>
exit 0 — 0 violations, 0 serious.

xcodebuild -scheme FeishuSpeech -configuration Debug build
exit 65 — shared output file
FeishuSpeech/Services/ReviewDestinationDelivery.swift:854 still has a
non-exhaustive insertion-result switch and requires the output lane owner to
handle `.inserted`; this file is outside UI/coordinator custody and was not
edited here.

serialized focused v4 test command
exit 65 — test execution cancelled by the same shared-output compile error.

The capture/recognition protected topology check excluding shared output model
files remains exit 0. The broader baseline diff including
`FeishuSpeech/Models/CursorTextModels.swift` is intentionally nonzero because
the output lane added `FinalTextInsertionResult.submittedUnverified` there;
that concurrent output change was preserved.
```
