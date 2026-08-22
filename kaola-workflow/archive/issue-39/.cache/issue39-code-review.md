evidence-binding: issue39-code-review 5a47b4fa7ac8

# Issue #39 independent correctness review

## Scope and candidate

- Candidate inspected source-first from `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-39` at HEAD `286c6d956d3966a31d38b53133caf4568923b632`, with uncommitted changes in `TranscriptionReviewView.swift`, `TranscriptionReviewViewTests.swift`, and `ReviewFirstMainViewModelTests.swift` plus issue-local workflow evidence.
- Production delta is confined to `FeishuSpeech/Views/TranscriptionReviewView.swift`; no controller, coordinator, destination-delivery, clipboard, capture, recorder, journal, recognition, retry, or transport production file changed.
- I read the changed view and tests in context, then traced `ReviewWindowController` readiness/dismissal and `MainViewModel` review authority, exact-once confirmation, target delivery, capture, and recognition boundaries.
- `git diff --check` passed. Per the review contract, I did not run the expensive XCTest/build commands after admitting the blocking coverage defect below.

## Prior finding closure frontier

finding: id=R1 scope=in_scope action=none status=resolved severity=medium fix_role=tdd-guide rationale=repair_delta_closes_custom_editor_coverage_frontier

failure_class: test_coverage_gap

trigger:

- Exercise the candidate-owned `ReviewDraftTextView.keyDown` branches with keypad Enter, Shift+Command+Return, Option+Return, Control+Return, or Return while the text view has marked IME text; or exercise the new custom `NSTextView` through selection, undo, accessibility, responder-readiness, and scrolling/binding transitions.

expected:

- Deterministic candidate tests prove keypad Enter confirms, Shift+Command+Return confirms, Option/Control Return pass through, marked-text Return remains owned by the input method, whitespace cannot confirm, and the custom editor preserves multiline sizing, current-draft binding, selection/undo, standard text accessibility, and first-responder behavior. These are explicit acceptance surfaces introduced by replacing SwiftUI `TextEditor` with a custom `NSTextView`.

observed:

- `FeishuSpeechTests/TranscriptionReviewViewTests.swift:155-253` exercises only main Return, main Shift+Return, main Command+Return, and Escape. It never sends key code 76, Shift+Command, Option, Control, or a marked-text event, and never checks empty/whitespace confirmation through the editor.
- No candidate test exercises selection preservation, undo, IME composition, accessibility role/value, document-view growth/scrolling, or the production `ReviewWindowController` readiness traversal with this new concrete editor. The tests manually call `window.makeFirstResponder(editor)` at lines 283-285, bypassing the production readiness path.
- The structural assertion at lines 15-31 does not repair this gap: `source.contains("TextEditor")` passes accidentally because the replacement type is named `ReviewDraftTextEditor`, even if the actual multiline/AppKit configuration regresses.
- The added `ReviewFirstMainViewModelTests` call coordinator methods directly. They correctly retain exact untrimmed delivery, idempotence, and read-only authority coverage, but cannot detect an event-routing or native-editor regression.

primary_anchor: `FeishuSpeechTests/TranscriptionReviewViewTests.swift:155`

secondary_anchors:

- `FeishuSpeechTests/TranscriptionReviewViewTests.swift:19`
- `FeishuSpeechTests/TranscriptionReviewViewTests.swift:283`
- `FeishuSpeech/Views/TranscriptionReviewView.swift:167`
- `FeishuSpeech/Views/TranscriptionReviewView.swift:204`
- `FeishuSpeech/Views/TranscriptionReviewView.swift:250`

proof:

- The production classifier has distinct candidate-caused conditions at `TranscriptionReviewView.swift:250-270`: two hardware key codes, marked-text pass-through, Option/Control pass-through, Command precedence, and Shift-only pass-through. Four event tests cover only one key code and omit three of those material conditions.
- The omitted outcomes are harmful rather than stylistic: a regression can submit an incomplete IME composition or confirm on Option/Control Return, causing delivery to the captured target; another can make keypad Enter or Shift+Command fail the stated confirmation contract. The current suite would remain green for those regressions.
- The issue-local key-routing analysis explicitly warned that replacing `TextEditor` expands the surface to binding, selection/undo, IME, accessibility, scroll behavior, and readiness, and prescribed tests for keypad, modifier, marked-text/pass-through, and repeat boundaries. The final candidate made that replacement but did not add those tests.

severity_rationale:

- Medium: the currently inspected implementation appears to choose the required branches correctly, so this is not proof of a present data-loss execution. However, the candidate lacks regression evidence for input paths that can unexpectedly confirm and deliver user text, and it replaces a framework editor with a custom native editor without parity coverage.

## Verified production behavior

- Bare Return and keypad Enter reach the same confirm callback at `TranscriptionReviewView.swift:250-270`; the handler consumes the event rather than inserting a newline.
- Shift without Command passes to `NSTextView`; Command wins over Shift; Option or Control passes through; marked-text Return passes through to AppKit.
- `EditableDraftView.confirmDraft` rejects whitespace using a trimmed eligibility check but forwards the unmodified draft through the existing coordinator. `MainViewModel.confirmReviewDraft` freezes `reviewDraftText` before its first await and rejects repeated confirmation after synchronously entering `.confirming`.
- The custom text view enables edit/select/undo, uses a vertically resizable width-tracking text container inside a vertical `NSScrollView`, avoids external string replacement during marked text, and preserves a bounded caret location on external updates. A local AppKit probe confirmed this configuration expands a 500x240 document view to 1414 points for 100 lines while retaining the scroll-view width.
- `ReviewWindowController.editableSurfaceIsReady` finds the new editable `NSTextView`, verifies its panel, and makes the exact view first responder. Read-only states mount no editor, clear callbacks, reject key interaction, ignore mouse events, and do not activate the app.
- Escape and close remain discard-only paths. The coordinator revision/review-ID guards and synchronous confirmation authority consumption retain exact-once delivery.
- The production diff does not alter Issue #38 destination identity, AX selection restoration, one-shot directed paste, clipboard snapshot/restore, capture-to-journal, recognition consumer/retry/replay, or review-axis scheduling. Existing tests for those unchanged paths remain present.

## Prior missing harmful cases, now covered by the closure repair

1. Main Return and keypad Enter across bare, Command, and Shift+Command confirmation.
2. Main Return and keypad Enter with Shift-only insertion of exactly one LF and zero confirmation.
3. Option/Control combinations passing through with zero confirmation.
4. Marked-text Return committing/preserving IME composition with zero confirmation.
5. Editor-driven change followed by immediate Return proving the exact current untrimmed draft reaches the coordinator once; editor-driven whitespace proving zero confirmation.
6. Selection and undo across SwiftUI representable updates, standard accessibility role/value, long-text scroll growth, and production `ReviewWindowController` first-responder readiness.
7. Repeated key-down confirmation remaining one coordinator/delivery action, plus read-only streaming/sealing accepting no key route.

## Closure repair evidence

- Production is unchanged from the previously reviewed candidate. The repair delta is confined to `FeishuSpeechTests/TranscriptionReviewViewTests.swift` and `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift`.
- Main and keypad Return now cover bare, Command, Shift+Command, Shift-only LF, Option/Control pass-through, marked-text pass-through, and whitespace rejection.
- The native editor tests now cover immediate exact-draft binding, selection replacement, undo/redo, standard text-area accessibility role/value, and long-document growth beyond the vertical viewport.
- `test_reviewFirst_repeatedBareReturnFromNativeEditorDeliversExactDraftOnce` mounts the real `TranscriptionReviewView` in `NSHostingView`, discovers and focuses its native `NSTextView`, edits through that view, sends two Return events, and proves the coordinator delivers the exact untrimmed draft once.
- The accidental `source.contains("TextEditor")` false-positive assertion was removed.
- `/tmp/feishuspeech-issue39-r1-focused-final.log` records the focused closure run: 40 tests executed, 0 failures, `TEST SUCCEEDED`. `/tmp/feishuspeech-issue39-r1-native-integration.log` separately records the native editor-to-coordinator integration passing.
- `git diff --check` passed. Issue #38 controller, destination, clipboard, capture, journal, recognition, retry, replay, and transport production remain unchanged.

## Production readiness oracle disposition

- `/tmp/feishuspeech-issue39-readiness.log` records an experimental `ReviewWindowControllerReadinessTests` returning `.failed` instead of `.ready` in the XCTest host.
- That production method additionally requires `NSApp.isActive` and `panel.isKeyWindow` after application activation. Those WindowServer/application-activation conditions are not stable authorities in this test host, and the log does not isolate failure to editor discovery or first-responder acceptance.
- The failed experimental oracle was correctly not retained. The deterministic native integration proves the candidate editor is discoverable in the hosted hierarchy, belongs to a window, accepts first-responder status, propagates edits, and reaches coordinator exact-once delivery.
- `ReviewWindowController` is unchanged from Issue #38 and its readiness traversal accepts any editable `NSTextView`. The environment-dependent oracle therefore does not keep R1 open and is not a repair-delta defect.

## Closure assessment

- R1's complete prior frontier is now executable: keypad, modifier precedence/pass-through, IME marked text, whitespace, exact current binding, repeat-to-coordinator idempotence, selection/undo, accessibility, scroll growth, and native first responder.
- Existing read-only callback guards still prove streaming/sealing cannot edit or confirm. Escape and close remain discard-only.
- No new defect has a primary or secondary anchor in the R1 repair delta.

verdict: pass
findings_blocking: 0
review_conclusion: Prior finding R1 is resolved by deterministic native-editor and coordinator coverage, with no repair-delta defects remaining after source-first closure review.
