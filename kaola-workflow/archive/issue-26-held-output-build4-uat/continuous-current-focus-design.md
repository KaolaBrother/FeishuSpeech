# Issue #26 continuous current-focus output investigation

## Outcome

The reported behavior is the current implementation, not a transport-side delay:

- A captured Accessibility target with selected-range read/write and range-text read-back receives
  every non-empty partial immediately and replaces one verified app-owned provisional range.
- A captured target without those range capabilities stores partials only and inserts one final
  after Fn release.
- A target that cannot be captured through Accessibility also stores partials only and posts one
  final to the then-current focus after Fn release.

The split is explicit in `MainViewModel`: `handlePartial` forwards only to `cursorSession`, while
`finalOnlyDestination` and `usesCurrentFocusFinalOutput` are consulted only by `deliverFinal`
(`FeishuSpeech/ViewModels/MainViewModel.swift:499-546`). Fn release changes the hot-key state from
`streaming` to `sealing`, which stops capture and calls `finish`; it is therefore the event that
finally reaches those two final-only output routes (`FeishuSpeech/Services/HotKeyService.swift:329-345`,
`FeishuSpeech/ViewModels/MainViewModel.swift:655-672`, `416-439`).

There is no safe, general-purpose way in the present app to replace an already posted current-focus
Unicode event. The reusable event adapter can insert a string, but it has no target element, caret,
range, delivery acknowledgement, selection operation, or ownership read-back. Extending it with
blind Backspace, Shift+Arrow, undo, or per-partial paste would be a destructive inference rather
than app-owned replacement. The repository's accepted decision records exactly this limitation
(`docs/decisions/D-25-01.md:18-25,124-131,183-194`).

Consequently, there are two distinct implementation decisions:

1. **Safe incremental behavior:** keep continuous replacement on targets where AX can prove range
   ownership; preserve final-only behavior elsewhere. This already exists and cannot satisfy a
   requirement that every current-focus target update continuously.
2. **Continuous behavior on unsupported/unbound targets:** introduce a real cross-application
   composition/marked-text boundary (for example, an input-source/IME integration) that owns marked
   text until release. This is the smallest architecture that could meet opaque replacement,
   Unicode, and release-only-finalization without synthetic deletion, but it is a new product and
   installation/permission surface. Its macOS feasibility and activation contract are not verified
   by this repository and require an external API investigation plus an explicit product decision.

Using the existing current-focus CGEvent adapter for repeated provisional replacement would be
smaller in code, but it is not safe and should not be represented as the requested architecture.

## Current production path: exact evidence

### Capability selection

- `MacAccessibilityClient.captureDestination` rejects when the process is untrusted or Secure
  Event Input is active, then captures the focused element and verifies its PID is frontmost
  (`FeishuSpeech/Services/AccessibilityClient.swift:54-76`).
- It returns `.live` only when selected text is settable, selected-range is settable, and
  string-for-range is supported. Failure to read the selected range or absence of live replacement
  capabilities returns `.finalOnly` (`AccessibilityClient.swift:73-110`).
- `CursorTextSession.begin` maps `.live` to `.armed`, `.finalOnly` to `.finalOnly`, and a rejection
  to `.invalid` (`FeishuSpeech/Services/CursorTextSession.swift:23-39`).
- `MainViewModel.prepareCursorTarget` turns capture exceptions and
  `.rejected(.accessibilityUnavailable)` into an unbound fallback rather than failing capture
  (`MainViewModel.swift:275-297,300-337`). An affirmatively secure target still fails startup
  (`MainViewModel.swift:304-306`).

### Why only live AX targets update while Fn remains held

- Every accepted packet produces a streaming event before release (`MainViewModel.swift:399-413`).
- `handlePartial` always remembers the opaque value in `latestFinalOnlyValue`, but sends it onward
  only when `cursorSession` exists (`MainViewModel.swift:499-508`).
- The `.live` capability keeps `cursorSession` when `autoInsert` is enabled. `.finalOnly` invalidates
  and clears it, storing only `finalOnlyDestination`; the unbound fallback also invalidates and
  clears it, setting `usesCurrentFocusFinalOutput` (`MainViewModel.swift:300-336`).
- Only `deliverFinal` branches to `routeFinalOnly` or `routeCurrentFocusFinal`
  (`MainViewModel.swift:511-569`). No partial path calls either output adapter.
- Existing coordinator tests codify this split: live mode expects both partial and final AX writes
  (`FeishuSpeechTests/StreamingMainViewModelTests.swift:230-250`); final-only expects one final
  insertion (`StreamingMainViewModelTests.swift:282-299`); unbound mode expects one current-focus
  final (`StreamingMainViewModelTests.swift:150-177`).

### Existing verified AX ownership behavior

`CursorTextSession` already implements the required opaque-replacement semantics for a live target:

- The first partial replaces the original selection. A later distinct partial replaces the full
  previously owned range; a duplicate is a no-op (`CursorTextSession.swift:79-117`).
- Before replacement it checks the original PID/focused element, Secure Input/target security, the
  expected caret/selection, and the exact text in the owned range (`CursorTextSession.swift:127-155,
  196-216`).
- After replacement it uses the target's returned caret to derive the range and reads the exact
  range text back. It does not derive AX range length from Swift string counts
  (`CursorTextSession.swift:173-194`).
- A shorter opaque partial therefore removes the superseded suffix; duplicate/revised/shorter and
  Unicode behavior are covered at `FeishuSpeechTests/CursorTextSessionTests.swift:24-73`.
- Focus, PID, caret, generation, or owned-text mismatch produces no further write and invalidates
  ownership (`CursorTextSessionTests.swift:75-143`).
- A post-write verification failure invalidates without rollback because the visible mutation is
  uncertain (`CursorTextSession.swift:121-124`; `CursorTextSessionTests.swift:221-231`).
- Empty final or stream failure preserves the last verified partial and releases ownership;
  non-empty final replaces it and commits (`CursorTextSession.swift:50-64,117-120`;
  `CursorTextSessionTests.swift:177-219`).

This is the behavior to retain as the reference contract for any new composition-capable output
session.

## Reusable current-focus event-posting infrastructure

### What can be reused

`SystemFinalTextOutput.insertAtCurrentFocusOnce` is an injectable, clipboard-free final insertion
boundary (`FeishuSpeech/Services/TextInputSimulator.swift:10-19,21-58,85-110`). It already:

- rejects action-capable C0/C1 and DEL control characters via
  `TextInputSimulator.isSafeForAutomaticPaste` (`TextInputSimulator.swift:218-222`);
- samples Secure Event Input twice;
- samples the frontmost PID twice and requires stability;
- calls a typed event poster and preserves `.posted`, `.securityRejected`, or `.deliveryFailed`
  without an ambiguous third ambient sample (`TextInputSimulator.swift:85-110,127-145`);
- posts the exact UTF-16 units with `keyboardSetUnicodeString`, with one final Secure Event Input
  check immediately before posting (`TextInputSimulator.swift:173-187`);
- is covered for stable PID, dynamic Secure Input, PID change, poster security rejection, and
  ordinary delivery failure (`FeishuSpeechTests/FinalTextOutputSecurityTests.swift:106-229`).

These security sampling, typed outcome, exact UTF-16 insertion, dependency seams, and privacy
properties are reusable for one-shot insertion and manual recovery.

### What cannot be reused as a replacement engine

The adapter has only `postUnicodeText(_:)`; it cannot select, delete, replace, mark, commit, or read
back (`TextInputSimulator.swift:127-136,173-187`). A successful `CGEvent.post` means the event was
posted, not that a particular control accepted the text. The adapter validates only a stable PID
within one call; it does not identify an element or caret and cannot distinguish two controls in the
same process (`TextInputSimulator.swift:90-103`).

The global event tap is also not an ownership monitor:

- it listens to keyDown/keyUp/flagsChanged plus tap-disabled events, not mouse/focus changes
  (`FeishuSpeech/Services/HotKeyService.swift:70-85`);
- keyDown cancels only during the initial `.pending` gate, not while streaming
  (`HotKeyService.swift:414-428`);
- posted Unicode events have no app-specific source tag or acknowledgement path in the current code.

Therefore the current infrastructure cannot prove that a previous provisional string is still
immediately before the caret. Synthetic deletion based on `String.count`, Unicode scalar count, or
UTF-16 count is not a replacement for that proof. Target applications differ in grapheme movement,
key handling, terminal escape handling, undo grouping, and event acceptance.

## Required behavior contract

The user request is most safely stated as follows:

- Once Fn passes the 0.3-second gate, each non-contentless streaming response is treated as the
  complete opaque current hypothesis.
- The first accepted partial establishes exactly one app-owned provisional composition at the
  active insertion point.
- Each later distinct partial replaces the complete app-owned provisional composition; it never
  appends a delta. A shorter value removes the superseded suffix. A duplicate is a no-op.
- Releasing Fn does not perform the first visible insertion. It seals audio and finalizes the
  existing composition. A non-empty authoritative final replaces and commits it; an empty final or
  stream failure preserves the last visible verified provisional value.
- No Return, Tab, Escape, navigation, command shortcut, or other action-capable control character
  is synthesized.
- `autoInsert=false` performs no target mutation, current-focus event posting, or recovery copy.
- Secure Input or an affirmatively secure/unverifiable target fails closed before the next output
  mutation. Late callbacks from an invalid generation remain no-ops.
- Transcript text, focus contents, app/window titles, stream IDs, and audio remain absent from logs
  and status surfaces.

### Focus-change rule needed for safe ownership

There is an unavoidable product distinction between **the cursor active when the hold begins** and
**whatever control is current for each partial**.

For an app-owned provisional value, the safe default is destination affinity: after the first
visible partial, any process/element/caret/focus change invalidates live ownership, preserves the
already visible text, and stops automatic writes for that hold. It must not redirect the complete
opaque hypothesis to a new field because that duplicates the provisional text across destinations.
Release may copy the final for manual recovery only when the failure is ordinary and non-security
related.

If product intent instead requires the provisional composition to follow focus changes, the output
provider itself must own cross-focus composition movement and guaranteed cancellation of the old
marked text. The current AX and CGEvent boundaries cannot provide that guarantee. This choice blocks
a reliable implementation plan and must be resolved before production work.

## Smallest safe architecture

### Within the current app target

Use one coordinator-owned protocol for provisional output, with `CursorTextSession` as the existing
implementation:

```text
ProvisionalTextSession (@MainActor)
  begin() -> capability/outcome
  replaceOpaque(text, generation) -> verified / noOp / invalid / securityRejected
  finalize(text?, generation) -> committed / preserved / invalid / securityRejected
  invalidate()                    // never destructive rollback
```

`MainViewModel` would own one such session per generation and route every partial and final through
it. It should not separately retain `finalOnlyDestination`, `usesCurrentFocusFinalOutput`,
`deliveredCurrentFocusFinal`, and `latestFinalOnlyValue` once a composition-capable provider exists;
those four fields currently encode the delayed-final split (`MainViewModel.swift:51-64`).

The current AX implementation already satisfies the protocol. The existing one-shot
`FinalTextOutput` remains a recovery/final-only sink, not the provisional session.

This refactor alone does not add continuous unsupported-target behavior. It creates the narrow seam
needed for a provider that can actually own marked text.

### Provider required for unsupported/unbound targets

A composition-capable provider must offer a cross-process equivalent of set/update/commit marked
text at the focused insertion point. It must return typed outcomes and own focus/secure-input checks
at the actual mutation boundary. A macOS input-source/IME companion is the plausible system
architecture, but this repository contains no such target, lifecycle, registration, or tests, and
the existing design explicitly lists a universal input method as a non-goal
(`docs/streaming-speech-design.md:89-96`). Do not implement it on local assumptions.

Before selecting this provider, verify against authoritative macOS documentation and a throwaway
prototype:

- whether a menu-bar app and enabled input source can coordinate one marked-text session;
- how the user enables/selects it and whether it may temporarily become the active input source;
- Secure Input behavior and whether marked-text updates are suppressed in password/terminal modes;
- focus changes, app termination, target rejection, cancellation, and stale callback behavior;
- Unicode normalization/indexing and whether the host, not FeishuSpeech, owns composition ranges;
- signing, notarization, packaging, sandbox, and deployment-target requirements.

If that investigation fails, there is no safe universal continuous fallback. The product must keep
the present capability split or explicitly accept destructive best-effort synthetic editing.

### Why not extend `SystemFinalTextCurrentFocusEventPoster`

An event-based `replace(previous:new:)` would need to infer ownership and synthesize deletion or
selection. Even with double PID/Secure Input samples, it cannot detect a caret move within one app,
text edited by the user, programmatic focus changes, dropped/rewritten events, or host-specific
Unicode movement. A mid-transaction failure also leaves an unknown amount of selection/deletion and
new text. No rollback is safe. This violates the existing ownership rule and the requested
"app-owned provisional text" requirement.

## Exact affected files

### Production, if only introducing the safe session seam

- `FeishuSpeech/Models/CursorTextModels.swift`
  - add provider-neutral provisional output outcomes/state only if they cannot remain private to the
    service; preserve AX-returned `CursorTextRange` semantics (`lines 10-65`).
- `FeishuSpeech/Services/CursorTextSession.swift`
  - conform the existing verified AX writer to the provisional-session seam; preserve its
    pre/post verification and no-rollback rules (`lines 42-216`).
- `FeishuSpeech/ViewModels/MainViewModel.swift`
  - own one provisional session per generation; route `.partial` and `.final` uniformly; invalidate
    before asynchronous cleanup (`lines 51-64,233-337,466-584,675-742`).
- `FeishuSpeech/Services/TextInputSimulator.swift`
  - retain the one-shot final/recovery adapter. Only shared secure-input/PID samplers or typed
    outcomes should be extracted for reuse; do not add blind replacement to
    `FinalTextCurrentFocusEventPosting` (`lines 10-145,173-201`).

No `HotKeyService` production change is required for routing partials before release; it already
keeps the interaction in `.streaming` until Fn release (`HotKeyService.swift:329-345`). Changing its
event mask or suppressing input would be a separate behavioral/security change.

### Additional production surface if composition support is approved

- a new composition/input-source service behind the provisional-session seam;
- a new app-extension/input-source target and its plist/signing/packaging configuration in
  `FeishuSpeech.xcodeproj/project.pbxproj`;
- only the entitlements and Info.plist keys proven necessary by the authoritative API investigation.

The app target is a filesystem-synchronized Xcode group, so a new Swift file would normally join the
target without hand-maintained build-file entries (`FeishuSpeech.xcodeproj/project.pbxproj:14-48`).
A new target would still require explicit project configuration.

### Tests

- `FeishuSpeechTests/CursorTextSessionTests.swift`
  - retain and, if the protocol is generalized, re-run the existing duplicate/revised/shorter,
    Unicode, focus/caret/owned-text mismatch, failure preservation, post-write uncertainty, and late
    callback cases (`lines 24-243`).
- `FeishuSpeechTests/StreamingMainViewModelTests.swift`
  - replace final-only/unbound "partial causes no output" expectations with provider-dependent
    continuous composition expectations only after a real composition provider exists;
  - retain secure startup, `autoInsert=false`, generation invalidation, exact-once teardown, fixed
    feedback, and transcript privacy cases (`lines 21-250,282-448,610-675`).
- `FeishuSpeechTests/FinalTextOutputSecurityTests.swift`
  - keep one-shot current-focus tests; add no provisional replacement expectations to this suite
    unless the event adapter itself remains a one-shot dependency of the composition provider
    (`lines 106-229`).
- New `FeishuSpeechTests/ProvisionalTextSessionContractTests.swift`
  - run the provider-neutral state/ownership contract against the AX and composition fakes.
- New provider-specific tests and installed Release UAT for the input-source boundary; deterministic
  unit fakes cannot prove third-party host composition behavior.

## Proposed acceptance tests

### Provider-neutral deterministic contract

1. First non-empty partial creates one visible provisional value before Fn release.
2. Duplicate opaque partial performs zero mutation.
3. Longer, revised, and shorter opaque partials each replace the whole provisional value and never
   append duplicates.
4. Unicode cases include composed/decomposed accents, emoji ZWJ sequences, skin-tone modifiers,
   CJK, RTL text, and newline-as-text where the provider can represent it; ownership uses
   provider-returned composition/range state, never Swift/UTF-8 byte counts.
5. Non-empty terminal final replaces and commits the provisional value exactly once; release itself
   does not create a second insertion.
6. Empty/whitespace-only final and stream failure preserve the last verified provisional value and
   release ownership.
7. Failure before first output mutates nothing. Failure after uncertain mutation invalidates with no
   rollback.
8. Stale generation partial/final/failure is a no-op.
9. `autoInsert=false` produces zero AX writes, marked-text operations, CGEvents, clipboard writes,
   or manual-recovery copies.
10. C0/C1/DEL values never become synthetic key actions. For an unsafe partial, preserve the prior
    safe provisional and disable further automatic provisional output; on final, apply the existing
    copy-only recovery only for an ordinary non-security outcome.

### Focus and security

11. Frontmost PID, focused element, caret/selection, or composition-owner mismatch after the first
    provisional invalidates the session before another mutation; no late value is redirected.
12. Focus change before the first partial either establishes the then-current provider-owned
    insertion point or fails without mutation, according to the approved focus contract.
13. Secure Input active at startup prevents audio/network start when affirmatively detected, as now.
14. Secure Input activating between two provisional updates invalidates generation/ownership before
    the next output call, cancels once, performs no clipboard recovery, and leaks no transcript.
15. Secure Input becoming active inside the provider's final pre-mutation boundary returns a typed
    security rejection and performs no mutation or copy.
16. Target closure/app termination and provider operation failure never retarget to another focus.

### Coordinator and Fn lifecycle

17. At least two partials are visible/replaced while hot-key state remains `.streaming` and before a
    `.sealing` transition is injected.
18. Fn release stops capture and finishes transport exactly once, finalizes the already visible
    composition, and does not post a duplicate final.
19. Release/60-second-cap race remains exact-once.
20. Terminal provider failure after a successful partial preserves the verified provisional,
    invalidates the generation first, hides overlay once, and ignores late callbacks.

### Installed Release UAT (no transcript capture in diagnostics)

21. Native AppKit text field/text view, browser contenteditable, Electron editor, terminal, and rich
    document editor: partial visible before release, revised/shorter replacement, final commit, undo
    behavior, and caret placement.
22. Mouse/keyboard caret interference, switching fields in the same app, switching apps, target
    close, and Secure Input transition all obey the approved focus contract.
23. Emoji/combining/RTL/CJK and control-character cases do not corrupt adjacent user content.

## Permission and privacy constraints

- Accessibility trust is already required for the global Fn event tap; monitoring does not start
  without it (`HotKeyService.swift:55-95`). `PermissionManager` also includes Accessibility and
  microphone in `allPermissionsGranted` (`FeishuSpeech/Services/PermissionManager.swift:23-39,
  137-139`).
- Microphone access is requested through AVFoundation (`PermissionManager.swift:47-67`), with the
  usage string in `FeishuSpeech/Info.plist:33-34`.
- Secure Input is sampled both by the AX client and one-shot current-focus output, and active-session
  changes invalidate before teardown (`AccessibilityClient.swift:54-60,121-131`;
  `MainViewModel.swift:125-138`). A composition provider must preserve an equivalent check at its
  actual mutation boundary rather than rely only on the polled publisher.
- Do not add Input Monitoring, Automation, sandbox, extension, or input-source privileges by guess.
  The current entitlements contain Apple Events and audio input only
  (`FeishuSpeech/FeishuSpeech.entitlements:1-9`); any new requirement needs authoritative proof and
  user approval because it changes installation/trust behavior.
- Tests and logs must use fixed sentinel strings and assert that transcript values do not enter
  overlay/status/log surfaces. No investigation or UAT should inspect or record existing user
  content.

## Facts, assumptions, and blocking unknowns

### Confirmed facts

- The streaming transport returns partials before release; coordinator routing, not Feishu finish,
  suppresses partial output in final-only/unbound modes.
- Verified AX replacement already implements opaque whole-value replacement and Unicode-safe range
  ownership.
- Current-focus event posting is insert-only and stable-PID-only; it has no safe replacement or
  ownership primitive.
- Release is already a sealing/finalization transition and need not be redesigned to make partials
  visible earlier.

### Assumptions requiring product confirmation

- "current cursor/focus" means the insertion point at which the first provisional value is created,
  and a later focus/caret change should preserve that value and stop writes rather than redirect it.
- Existing `autoInsert=false` and Secure Input fail-closed semantics remain authoritative.
- A user-visible setup step for a composition/input-source provider may be acceptable if it is the
  only safe way to support continuous output in AX-unsupported apps.

### Unknowns blocking a reliable implementation plan

- Which application/control failed AX capture during the reported UAT, and whether it returned
  `.finalOnly` or fully unbound. This can be diagnosed with transcript-free capability-category
  logging; user content must not be inspected.
- Whether continuous behavior is required in every target, or only in targets for which safe
  ownership is available.
- Whether focus should remain bound after first provisional output or follow focus changes.
- Whether a macOS input-source/IME companion can satisfy the signing, activation, Secure Input,
  host-compatibility, and lifecycle requirements for this app. Repository code provides no answer.

Until those unknowns are resolved, an implementation that adds synthetic deletion would be a
behavioral regression disguised as continuous output.

## Validation commands after implementation

```bash
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test
swiftlint
xcodebuild -scheme FeishuSpeech -configuration Release build
```

Installed Release cross-application UAT remains mandatory for any composition provider. Unit tests
can prove coordinator state and fake-provider ownership, but not a third-party application's real
marked-text, focus, Unicode, undo, or Secure Input behavior.
