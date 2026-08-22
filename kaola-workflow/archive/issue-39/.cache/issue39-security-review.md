evidence-binding: issue39-security-review 19f2fd86ef88

# Issue 39 independent security and privacy review

## Scope and candidate

- Reviewed the working-tree candidate in `.kw/worktrees/issue-39` source-first against `origin/main`/HEAD `286c6d9`.
- Candidate production change is limited to `FeishuSpeech/Views/TranscriptionReviewView.swift`; the other two tracked changes are tests. No dependency, entitlement, credential, transport, recorder, recognizer, accessibility client, destination delivery, or clipboard implementation changed.
- Reviewed the entire candidate diff and every changed file in context, then traced the surrounding authority and delivery path through `ReviewWindowController`, `MainViewModel`, `ReviewDestinationDelivery`, `AccessibilityClient`, and `TextInputSimulator`.
- Threat classes walked: keyboard interception scope, stale callback authority, secure-input and destination validation, transcript exposure, unsafe control characters, repeated events, exact-once delivery, pasteboard privacy, and async-axis coupling. No candidate-caused injection, secret exposure, authentication/authorization bypass, unsafe external call, or dependency risk was found.

## Security and privacy analysis

### Keyboard interception and modifier handling

- The new interception point is a private `NSTextView` subclass mounted only by the editable review branch. It does not add a global/local event monitor, event tap, notification observer, or application-wide shortcut (`TranscriptionReviewView.swift:114-121,155-202,247-271`).
- Only hardware Return and keypad Enter key codes are classified. Unrelated keys are passed to AppKit. Option/Control plus Return are passed through; Shift plus Return is passed through; bare Return and Command plus Return confirm (`TranscriptionReviewView.swift:250-270`).
- The handled event is not forwarded after confirmation, so one key-down cannot also insert a newline or invoke a second responder action. The pre-existing Command-Return button shortcut remains unchanged.
- Auto-repeat does not expand the delivery authority: confirmation synchronously changes the coordinator state to `.confirming`, sets `reviewConfirmationInFlight`, advances the revision, and dismisses the surface before starting one delivery task. Later/repeated confirm callbacks fail the editable/in-flight guards (`MainViewModel.swift:2233-2260`).

### IME marked text and exact draft handling

- Return/Enter is explicitly passed to AppKit while `hasMarkedText()` is true, so IME composition is committed/handled by the native text system instead of being interpreted as confirmation (`TranscriptionReviewView.swift:250-254`).
- SwiftUI-to-AppKit synchronization also refuses to overwrite the editor while marked text exists, preventing an external state refresh from clobbering an active composition (`TranscriptionReviewView.swift:204-221`).
- Text changes flow as the exact `NSTextView.string`; confirmation checks only for contentlessness and does not trim or normalize the delivered value (`TranscriptionReviewView.swift:114-120,147-151,236-243`; `MainViewModel.swift:2240-2255`). LF remains accepted by the unchanged delivery validator while action-capable control characters remain rejected before mutation.

### Read-only and stale authority

- Streaming and sealing construct no editable text view and receive nil draft/confirm/discard callbacks. The controller also keeps the panel non-key, mouse-ignoring, non-closable, and non-activating in read-only mode (`ReviewWindowController.swift:49-70`).
- Editable input is enabled only after the same panel is configured, FeishuSpeech activates, the editor belongs to that panel, and it becomes the first responder (`ReviewWindowController.swift:247-301`).
- Draft and action callbacks remain bound to the captured review identifier and revision. Late updates, confirmation, and discard fail closed outside `.editable`; dismissal clears callbacks and transcript-bearing hosted content (`MainViewModel.swift:2131-2151,2219-2275,2305-2325`; `ReviewWindowController.swift:393-412`).

### Transcript privacy and accessibility exposure

- The candidate adds no transcript logging, window-title interpolation, help/accessibility-label duplication, persistence, network transfer, pasteboard write, or cross-process event monitor.
- The editable transcript remains in one standard native `NSTextView`, equivalent in accessibility visibility to the prior native-backed SwiftUI editor. The transcript-bearing hosting view is released on dismissal. Read-only transcript visibility is pre-existing and unchanged.
- The new callback from the text view to its coordinator is weak, so it does not create a new retention cycle (`TranscriptionReviewView.swift:167-172`; `ReviewWindowController.swift:393-412`).

### Original target, fail-closed delivery, and clipboard restoration

- The target is still captured before audio starts, with generation, PID, full application identity, frontmost identity, safe security state, and original selection checks. The candidate does not recapture or retarget on confirmation (`MainViewModel.swift:604-628,665-693`; `ReviewDestinationDelivery.swift:267-283`).
- Delivery still uses the frozen draft and captured token only. It revalidates application identity/frontmost status, restores and validates the exact target/selection, validates security before mutation, and validates again after posting. Any uncertainty is terminal and routes to one manual-recovery copy rather than retrying or targeting current focus (`ReviewDestinationDelivery.swift:285-390`; `MainViewModel.swift:2282-2300`).
- Clipboard snapshot, guarded restoration, third-party-change preservation, and unsafe-text rejection implementations are outside the diff and remain unchanged.

### Independent capture, recognition, and review axes

- The change calls only the existing synchronous review callbacks and adds no task, await, lock, service call, recorder barrier, recognition consumer dependency, or delivery scheduling change.
- Capture drain and recognition consumption remain independent tasks. Read-only rendering remains a separate cancellable presentation task, and editable presentation remains gated behind the recorder barrier only after terminal recognition (`MainViewModel.swift:625-648,695-735,2078-2171`).

## Validation evidence

- `git diff --check`: passed.
- Focused command: `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1` with only the view, keyboard, review-first coordinator, destination-delivery, and pasteboard-lifecycle suites.
- Result: `TEST SUCCEEDED`; 48 tests executed, 0 failures, 0 unexpected failures.
- Coverage receipts: `ReviewDestinationDeliveryTests` 13/13; `ReviewFirstMainViewModelTests` 22/22; `ReviewPasteboardLifecycleTests` 5/5; `TranscriptionReviewViewKeyboardTests` 4/4; `TranscriptionReviewViewTests` 4/4.
- The selected tests exercise bare Return, Shift-Return, Command-Return, Escape/discard, read-only callback rejection, repeated confirm exact-once delivery, exact untrimmed multiline draft delivery, capture-before-audio ordering, recorder/consumer separation, target identity reuse rejection, secure/unverifiable capture rejection, pre/postflight fail-closed behavior, and clipboard restoration/third-party-change preservation.

## Findings

No candidate-caused security or privacy defects met the high-confidence admission threshold. No pre-existing weakness was relied on as a candidate finding.

verdict: pass
findings_blocking: 0
review_conclusion: The candidate keeps keyboard handling local to the editable review editor and preserves the existing fail-closed privacy and delivery boundaries.
