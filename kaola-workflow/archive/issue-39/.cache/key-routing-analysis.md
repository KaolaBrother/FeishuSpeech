# Issue #39 review key-routing exploration

Scope: source-first mapping of the editable review surface. I did not edit any
production or test file; this report is my only write.

## Concise findings

The review callbacks and lifecycle already have the required boundary. The
smallest affected surface is the editable review event path in
`TranscriptionReviewView.swift` / `ReviewWindowController.swift`; no
`MainViewModel`, `ReviewDestinationDelivery`, clipboard, recorder, or streaming
consumer change is indicated by the current code.

The existing SwiftUI button shortcuts cannot express the new Return policy by
themselves. AppKit key-equivalent matching ignores Shift, so a bare
`.keyboardShortcut(.return, modifiers: [])` also matches Shift+Return. A
key-down/key-equivalent gate at the editable panel/editor boundary is the
relevant seam: classify the hardware key code and modifier flags, invoke the
existing confirm/discard closures for handled events, and let Shift+Return pass
through to the multiline editor.

Return and keypad Enter should be treated as the same logical action if “Enter”
is intended to include the numeric keypad. They are distinct hardware key codes
(`0x24` and `0x4c`) even though both synthetic events expose carriage-return
characters. Escape is `0x35`.

## Current source facts

### Editable view and current shortcuts

- `FeishuSpeech/Views/TranscriptionReviewView.swift:34-56` switches on
  `TranscriptionReviewState`. Only `.editable` creates `EditableDraftView`; the
  `.streaming`, `.sealing`, and `.confirming` branches do not create an editor.
- `FeishuSpeech/Views/TranscriptionReviewView.swift:90-122` uses a SwiftUI
  `TextEditor` backed by `@State private var draftText`. Its binding immediately
  calls `onDraftChange` for every text change, preserving the untrimmed draft.
- `FeishuSpeech/Views/TranscriptionReviewView.swift:130-145` currently has:
  - `取消` -> `onDiscard`, with `.keyboardShortcut(.cancelAction)`;
  - `输入` -> non-empty guard, then `onConfirm`, with
    `.keyboardShortcut(.return, modifiers: .command)`;
  - no bare Return shortcut; bare Return is currently ordinary TextEditor
    newline editing.
- `FeishuSpeechTests/TranscriptionReviewViewTests.swift:12-34` is source-text
  policy coverage. It currently requires Command+Return and cancel shortcuts
  and explicitly requires that bare `.keyboardShortcut(.return)` and
  `.keyboardShortcut(.enter)` are absent. This test must change with issue #39;
  the current baseline test passed unchanged.

### One panel and responder readiness

- `FeishuSpeech/Controllers/ReviewWindowController.swift:12-22` defines the
  dedicated `ReviewPanel` and gates `canBecomeKey`/`canBecomeMain` on
  `allowsKeyInteraction`.
- `renderReadOnly` at `ReviewWindowController.swift:49-72` clears all three
  callbacks, sets `allowsKeyInteraction = false`, sets
  `ignoresMouseEvents = true`, removes closability, and calls
  `orderFrontRegardless()`. Read-only streaming/sealing therefore has no
  editable responder authority.
- The one-panel invariant is established at `ReviewWindowController.swift:74-127`.
  `install` replaces the existing `NSHostingView` root instead of creating a
  second panel.
- `configureEditableSurface` at `ReviewWindowController.swift:247-275` stores
  the existing `onDraftChange`, `onConfirm`, and `onDiscard` closures, installs
  the editable SwiftUI root, then enables key/mouse interaction and closability.
- `editableSurfaceIsReady` at `ReviewWindowController.swift:293-301` recursively
  finds an editable `NSTextView`, verifies that it belongs to the panel, makes
  it first responder, and requires `panel.firstResponder === editor`.
  `editableTextView` at `ReviewWindowController.swift:427-439` confirms that the
  current implementation already depends on the AppKit text view under
  `TextEditor`.
- `dismiss` at `ReviewWindowController.swift:393-413` cancels readiness, clears
  all callbacks, resigns the panel, disables key/mouse interaction, orders it
  out, and releases hosted content. Any event monitor or panel-owned routing
  state must be cleared on this path too.
- `windowShouldClose` at `ReviewWindowController.swift:415-425` already routes
  an editable close to `onDiscard`; closing is therefore a separate existing
  discard path, not something the key-routing change needs to duplicate.

### Existing coordinator and delivery boundaries

- `FeishuSpeech/ViewModels/MainViewModel.swift:635-648` starts capture and
  recognition tasks, then schedules read-only rendering separately.
- `renderReviewReadOnly` at `MainViewModel.swift:695-735` is a cancellable,
  revision/review-ID-gated, fire-and-forget `@MainActor` task. It yields before
  presenting and never waits on the capture or recognition tasks.
- `handleReviewTerminal` at `MainViewModel.swift:2003-2065` closes recognition
  admission and starts a separate review-transition task. The recorder barrier
  is awaited only by `awaitReviewRecorderBarrier` at `2068-2076`.
- `finishReviewTransition` at `MainViewModel.swift:2078-2171` freezes the
  action-2 draft, resets the streaming/capture-side state, then calls the
  presenter with the three UI callbacks. The callback closures at
  `2135-2151` are revision- and review-ID guarded.
- `confirmReviewDraft` at `MainViewModel.swift:2228-2260` synchronously checks
  review authority and content, sets `reviewConfirmationInFlight`, changes
  state to `.confirming`, advances the revision, dismisses the panel, and only
  then creates the delivery task. Repeated confirm events are rejected by the
  guard at `2233-2238`.
- `discardReviewDraft` at `MainViewModel.swift:2263-2275` revokes authority and
  resets the hot key without delivery or copy. `revokeReviewAuthority` at
  `2305-2325` cancels all review tasks, clears callbacks/draft state, and
  dismisses the surface.
- `FeishuSpeech/Services/ReviewDestinationDelivery.swift:46-54` exposes the
  captured-target/deliver/manual-recovery protocol. The system implementation
  captures the exact target at `267-283` and delivers only through the frozen
  target at `285-320`; the key-routing change should not touch this service.
- Review safety remains in `TextInputSimulator.swift:701-710`: LF is allowed
  for review confirmation, while tab, CR, NUL, DEL, and C1 controls are
  rejected before mutation. The UI must preserve the exact draft; it must not
  normalize a Shift+Return newline or trim before handing the draft to the
  coordinator.

## Event and selector semantics verified locally

Evidence was checked against the installed Xcode 26.5 macOS SDK and with
synthetic AppKit events:

- `HIToolbox/Events.h:249` defines `kVK_ANSI_KeypadEnter = 0x4C`; line 266
  defines `kVK_Return = 0x24`; line 270 defines `kVK_Escape = 0x35`.
- `NSEvent.h:166-178` defines device-independent flags. Shift, Control,
  Option, Command, NumericPad, and Function are separate bits; NumericPad is
  not the same as Shift or Command.
- Synthetic key events for key codes 36 and 76 both expose `"\r"` as
  `characters` and `charactersIgnoringModifiers`; key code is the reliable
  distinction if both physical keys must be supported.
- `NSResponder.h:138-145` documents the key-binding handoff through
  `insertText` and `doCommandBySelector`; standard selectors include
  `insertNewline:` (`NSResponder.h:218-227`) and `cancelOperation:`
  (`NSResponder.h:264-267`).
- `NSTextView.h:619-623` exposes
  `textView(_:doCommandBySelector:)` to the delegate. The callback receives a
  selector, not the originating `NSEvent`, so it cannot by itself distinguish
  Shift+Return from bare Return. An event-level interception is required if
  Shift must pass through while bare Return confirms.
- `NSButton.h:164-171` says Return as a key equivalent is the default-button
  action and that button key-equivalent modifier masks only use Control,
  Option, and Command (`167-168`). Shift is ignored by this mechanism.
- Runtime check with an `NSButton` whose key equivalent was Return confirmed:
  - a no-modifier key equivalent matches main Return and keypad Enter;
  - it also matches Shift+main Return and Shift+keypad Enter;
  - a Command+Return key equivalent matches both main/keypad variants and
    also matches Shift+Command variants.
  Consequently, adding a bare SwiftUI `.keyboardShortcut(.return, modifiers: [])`
  cannot satisfy “bare Return confirms, Shift+Return inserts newline”.
- `NSEvent.h:539-547` documents local monitors: they receive events before
  `NSApplication.sendEvent`, may return `nil` to suppress dispatch, and are not
  called for nested tracking loops. This is a viable event boundary only when
  installed for the editable panel, removed on every dismissal, and guarded by
  the panel/editor first-responder identity.
- SwiftUI `View.onKeyPress` is present in the installed SDK only under
  `@available(macOS 14.0, ...)` (SwiftUI interface around lines 18947-18959).
  `CLAUDE.md`/historical `AGENTS.md` describe macOS 13+, while the current
  `project.pbxproj:281,342,423,449` actually sets a 26.2 deployment target.
  This target drift is an unknown to resolve before relying on an
  `onKeyPress`-only solution.

## Smallest affected seam and policy boundary

The minimal behavioral boundary is the editable panel/editor key event path,
not the view-model or delivery path. Two existing facts make this local:

1. `EditableDraftView` is only mounted for `.editable` (view lines 34-56), and
   the three callbacks are already supplied by `MainViewModel` (controller
   lines 247-275 and view lines 80-86).
2. The panel becomes key and focuses exactly one `NSTextView` only after the
   action-2/recorder-barrier transition (controller lines 293-301; view-model
   lines 2078-2171).

The event gate must run before a SwiftUI/AppKit default-button key equivalent
can consume Return. It can be panel-scoped or editor-scoped; whichever seam is
selected must satisfy all of these observable rules:

| Physical/event input | Required outcome | Boundary condition |
| --- | --- | --- |
| main Return (`0x24`) with no action modifiers | confirm | suppress default newline |
| keypad Enter (`0x4c`) with no action modifiers | confirm if keypad is included in “Enter” | suppress default newline |
| Return/keypad Enter + Shift, without Command | pass through to `NSTextView` | inserts one LF; never invokes confirm |
| Return/keypad Enter + Command | confirm | existing Command+Return contract remains |
| Escape (`0x35`) | discard | no delivery, copy, or target activation |
| unrelated key or unsupported modifier (Option/Control/etc.) | pass through | do not invent new command semantics |
| streaming/sealing panel | no acceptance | `allowsKeyInteraction == false`, no editor callbacks, mouse ignored |

The requirement does not state the precedence of Shift+Command+Return or
Option/Control+Return. Existing NSButton behavior makes Shift+Command+Return
confirm because Shift is ignored. That is a product-policy unknown; it should
be explicitly covered by tests rather than inferred from key-equivalent behavior.

The gate should also be aware of repeated keyDown events. The coordinator is
already idempotent (`reviewConfirmationInFlight` and authority guards), but a
key policy may choose to accept only the first keyDown for a confirm/discard
action and pass all other repeat events through. It must never turn key-up into
a second action.

## Risks to preserve explicitly

- Do not attach a global key handler to `TranscriptionReviewView` or the
  hosting view without an editable/first-responder guard. Read-only
  streaming/sealing must accept none and must not steal original-target focus.
- Do not use a bare SwiftUI key equivalent as the Shift-sensitive policy; the
  verified AppKit matching behavior defeats that distinction.
- Do not route through only `textView(_:doCommandBySelector:)` if Shift vs bare
  Return matters; selector-only callbacks have no event modifiers.
- If a local monitor is used, it must be installed only for the editable
  lifetime, return the event unchanged for Shift+Return/unrelated events, and
  be removed from `dismiss`, failed readiness, discard, confirmation, reset,
  sleep/wake, and cleanup paths. Its documented nested event-loop limitation
  needs live UAT coverage.
- A panel-level handler must ensure the panel’s first responder is the review
  editor before treating Return as review confirmation. Otherwise a focused
  button, text field introduced later, or another app event could be consumed.
- Replacing SwiftUI `TextEditor` with a custom AppKit text view would enlarge
  the change surface: binding updates, selection/undo, IME composition,
  accessibility, scroll behavior, and the existing readiness traversal would
  all need revalidation. The current code already exposes the underlying
  `NSTextView` only for readiness; its runtime hierarchy is not a stable public
  SwiftUI API.
- Preserve the three independent async roots. Key routing must call the
  existing synchronous callbacks only; it must not await, block, or add a
  dependency from capture drain or recognition consumption to editor focus,
  window activation, dismissal, or delivery.
- Preserve exact untrimmed draft delivery and existing clipboard behavior. The
  key handler should only select confirm/discard/pass-through; it should not
  sanitize, trim, recapture, retarget, retry, or write text.

## Deterministic test strategy

### Key-policy tests

The current source-string test is useful for structural invariants but cannot
prove event semantics. Add a deterministic policy/event test at the test seam
chosen by implementation, using `NSEvent.keyEvent(with:...)` like the existing
helper in `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift:1270-1287`:

- main Return/no modifiers -> confirm;
- keypad Enter/no modifiers -> confirm (if keypad inclusion is accepted);
- main Return/Shift and keypad Enter/Shift -> pass-through/newline;
- main Return/Command and keypad Enter/Command -> confirm;
- Escape -> discard;
- ordinary character, Option+Return, Control+Return, and key-up -> pass-through;
- explicit Shift+Command+Return expectation once product policy is decided;
- repeated confirm/discard key-down is one coordinator action at most.

If the production event seam is panel-local, a deterministic integration test can
install a test panel/editor and feed synthetic events directly through the
panel’s event entry point. Avoid relying only on an actual WindowServer key
window in unit tests; the event classifier and callback suppression should be
testable without app activation.

### Existing lifecycle/regression tests to retain and rerun

- `FeishuSpeechTests/TranscriptionReviewViewTests.swift:36-107` keeps the
  one-panel/read-only-vs-editable authority assertions. Update the shortcut
  assertions to describe the new event gate rather than requiring absence of a
  bare-return concept.
- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:22-77` proves
  streaming/sealing are read-only and that attempted draft callbacks do not
  mutate recognition state.
- `ReviewFirstMainViewModelTests.swift:79-109` proves only one explicit
  confirmation delivers, including repeated confirmation.
- `ReviewFirstMainViewModelTests.swift:251-273` proves discard and late window
  callbacks revoke authority without output or copy.
- `ReviewFirstMainViewModelTests.swift:500-556` proves review presentation
  gating and recorder/consumer separation; these are the three-axis regression
  boundary.
- `FeishuSpeechTests/ReviewDestinationDeliveryTests.swift` retains exact
  captured application/AX target validation.
- `FeishuSpeechTests/ReviewPasteboardLifecycleTests.swift:13-165` retains full
  clipboard snapshot/restore and third-party-change/uncertainty behavior.

### Validation commands

    xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
      -destination 'platform=macOS' \
      -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests test

    xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
      -destination 'platform=macOS' \
      -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test

    xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
      -destination 'platform=macOS' \
      -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests \
      -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests test

    xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test

Baseline evidence from this clean worktree:

- `TranscriptionReviewViewTests`: 4/4 passed.
- `ReviewFirstMainViewModelTests`: 21/21 passed.
- `git diff --check`: clean; `git status --short --branch` showed only
  `workflow/issue-39` before this report was created.

### Live validation still required

Unit tests cannot prove WindowServer activation/key-window behavior or every
native responder path. The design document’s UAT matrix at
`docs/streaming-speech-design.md:841-855` calls for native TextEdit/AppKit,
rich text, browser, Electron, and terminal controls. For this issue, the
minimum live checks are the same editable surface with main Return, keypad
Enter, Shift+Return, Command+Return, Escape, click buttons, close, and rapid
repeat; verify that streaming/sealing remain nonactivating and that confirmation
still writes once to the original captured target with clipboard preservation.

## Unknowns blocking a fully reliable implementation plan

1. Does “Return” explicitly include keypad Enter? AppKit exposes them as
   different key codes but the current button shortcut matches both. This
   should be fixed in the acceptance tests.
2. What should Shift+Command+Return do? The stated requirements cover Shift+Return
   and Command+Return independently; current key-equivalent semantics choose
   Command confirmation.
3. Is macOS 13 still a supported deployment target? Project settings currently
   say 26.2 while canonical project guidance says macOS 13+. This determines
   whether SwiftUI `onKeyPress` can be considered.
4. Is the desired implementation allowed to use a panel-scoped local monitor,
   or must the event policy remain editor-local? The former is smaller without
   replacing `TextEditor`, but its nested event-loop limitation and cleanup
   lifecycle need explicit acceptance.
