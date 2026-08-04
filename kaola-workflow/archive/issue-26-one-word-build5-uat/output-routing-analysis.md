# Issue #26 output-routing analysis

verdict: PASS

scope: Read-only trace of the current `workflow/issue-26` candidate at `43fbfe2`, covering production construction, cursor capability selection, first-partial rebind, continuous append, final-only delivery, retry/replay, sealing, and focused tests. No source/test file was edited and the app was not launched or controlled.

## Concise finding

The installed Release can intentionally suppress every usable partial until Fn release in **two ordinary `autoInsert=true` routes**:

1. The initial AX probe returns `.finalOnly`. `configureCursorCapability` discards `CursorTextSession`, retains only `finalOnlyDestination`, and sets `.finalOnly` (`FeishuSpeech/ViewModels/MainViewModel.swift:386-391`). Every partial is retained in `latestFinalOnlyValue`, but `prepareContinuousOutputIfNeeded` is gated exclusively by `usesCurrentFocusFinalOutput`; the final-only route has that flag false, so neither cursor replacement nor current-focus append receives the partial (`MainViewModel.swift:906-925,1006-1012`). The first actual insertion occurs through `routeFinalOnly` from terminal final/sealed recovery (`MainViewModel.swift:994-1002,781-788,1134-1160`).
2. Startup AX capture is unavailable, but the one first-partial rebind returns `.finalOnly`. That branch retains the token, turns off `usesCurrentFocusFinalOutput`, and deliberately does **not** arm `CurrentFocusAppendSession` (`MainViewModel.swift:1028-1051`). Control returns to `handlePartial`; because there is now neither `cursorSession` nor `currentFocusAppendSession`, the same first partial falls through without output (`MainViewModel.swift:914-925`). The current regression explicitly requires this delayed behavior: `test_firstPartialFinalOnlyRebindKeepsCapturedDestinationAndNeverArmsAppend` asserts zero append/current-focus output before sealing and one captured final insertion after sealing (`FeishuSpeechTests/StreamingMainViewModelTests.swift:1873-1897`).

These branches match the owner report without requiring a transport failure: streaming packet responses are handled while Fn is held (`MainViewModel.swift:545-563`), but routing intentionally withholds them. Release changes the hot-key state to sealing and starts recorder/transport finalization (`MainViewModel.swift:1203-1247`); it is not what makes partial responses available.

## How the installed target likely reaches the branch

Production constructs `MainViewModel()` with all defaults (`FeishuSpeech/App/FeishuSpeechApp.swift:3-7`). That selects the real `MacAccessibilityClient`, `SystemFinalTextOutput`, and `SystemCurrentFocusProvisionalOutputSessionFactory` (`MainViewModel.swift:118-135`), so the append facility is present in the installed Release; this is not the test-only factory omission path.

`MacAccessibilityClient.captureDestination` classifies an affirmatively non-secure, frontmost, editable element as `.finalOnly` in either of these cases:

- reading `AXSelectedTextRange` fails with `operationFailed`, `noFocusedElement`, or `invalidValue` (`FeishuSpeech/Services/AccessibilityClient.swift:73-97`); or
- the range is readable, but `AXSelectedTextRange` is not settable or string-for-range verification is unsupported (`AccessibilityClient.swift:98-110`).

Therefore a normal editor can be safe for one-shot insertion but lack the AX range/read-back capability required by `CursorTextSession`'s owned-range replacement. The installed target application's identity and exact AX result were not captured in the supplied evidence, so the exact leg is unknown. The strongest source-backed inference is initial `.finalOnly` (zero second capture) or unbound-then-rebind `.finalOnly` (two captures). Both produce the reported symptom and are covered by current tests. Browser/Electron/rich-editor involvement is only a possibility, not a confirmed fact.

## Other intentional deferrals and why they are not the primary defect

- `autoInsert=false` intentionally retains recognition without target mutation (`MainViewModel.swift:913`; capability handling at `MainViewModel.swift:378-394`). This is outside the user's “safe auto-insert cursor path” requirement.
- Contentless partials are ignored before routing (`MainViewModel.swift:911`). Unsafe control-bearing values are suppressed by `CurrentFocusAppendSession` (`FeishuSpeech/Services/CurrentFocusAppendSession.swift:152-173`) and by final-only insertion (`MainViewModel.swift:1134-1140`). These are safety exclusions, not ordinary text.
- If the first-partial AX probe remains unavailable/throws, `armCurrentFocusAppendSession` asks the factory for a writer. A factory miss retains the old one-shot fallback (`MainViewModel.swift:1020-1025,1048-1064`). In production the system factory returns nil only when it cannot obtain a frontmost PID (`CurrentFocusAppendSession.swift:304-344`), so there is no safely bound current-focus destination to write to.
- Once append output is armed, revisions/shortenings are intentionally suppressed but the first accepted value has already been made visible. Exact UTF-16 extensions append only the unseen suffix; duplicates are no-ops (`CurrentFocusAppendSession.swift:108-173`). This is the existing duplicate/revision protection and should remain unchanged.
- Secure Input, PID/focus drift, generation invalidation, or uncertain event delivery permanently stop further output (`CursorTextSession.swift:127-170,210-216`; `CurrentFocusAppendSession.swift:126-149,234-265`; `MainViewModel.swift:182-194,1344-1352`). These are required fail-closed gates.

## Smallest dependency-safe correction boundary

The narrow correction belongs in the coordinator's final-only-to-continuous routing, not in Feishu transport, audio ingress, hot-key release, or the AX owned-range writer:

1. On the first usable partial for either an initially captured `.finalOnly` token or a rebind result of `.finalOnly`, arm the existing `CurrentFocusAppendSession` and feed that same partial through it immediately. Preserve the captured final-only token only as a fallback when no continuous writer can be safely created **before any provisional output**.
2. A captured final-only token has a stronger focus contract than the unbound PID-only append path. Do not simply route it through current-focus append with only its existing PID checks. Wrap every append apply/finalize mutation with the existing captured-token validation (`currentSecurityIsSafe`, frontmost PID, and `CFEqual` focused element in `MainViewModel.swift:1162-1185`) before and after the synchronous Unicode post. On any failed preflight, postflight, security sample, or uncertain delivery, invalidate/suspend that append writer permanently and prohibit fallthrough to one-shot final insertion or clipboard recovery after any provisional post may have occurred.
3. Keep `CurrentFocusAppendSession`'s exact UTF-16 prefix frontier unchanged (`CurrentFocusAppendSession.swift:122-149,152-173`) and keep retry replay's single catch-up frontier unchanged (`MainViewModel.swift:566-599`). Those two layers already prevent duplicate replay and suppress destructive revisions.
4. Keep release as sealing only. The already-armed writer should finalize an exact final/suffix once; divergent/shorter finals preserve visible text and never trigger a second full paste (`MainViewModel.swift:962-1003`; `CurrentFocusAppendSession.swift:176-210`).

This boundary can be implemented in `MainViewModel` plus a small destination-validation hook/wrapper around append application. It does not require changing `CursorTextSession`, Feishu request semantics, retry policy, packet journal, audio sealing, `TextInputSimulator`, or permissions. Merely changing the `.finalOnly` switch to call the current PID-only append factory would be smaller textually but would weaken the captured element/focus gate and is therefore not dependency-safe.

## Existing tests that define the safety envelope

- Live AX whole-range replacement, including duplicate/revised/shorter hypotheses and generation/focus/caret/read-back invalidation: `FeishuSpeechTests/CursorTextSessionTests.swift:24-174,177-242`.
- Final-only one-shot security, destination revalidation, control-character downgrade, and no synthetic output on unsafe state: `FeishuSpeechTests/StreamingMainViewModelTests.swift:282-423`; sink-level pre/post validation: `FeishuSpeechTests/FinalTextOutputSecurityTests.swift:14-104`.
- Current-focus append first value, UTF-16 suffixes, duplicate/revision suppression, PID/Secure Input pre/post checks, no resend after uncertainty, and final sealing: `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift:16-227,230-388`.
- Unbound continuous output before release and retry/replay frontier behavior: `FeishuSpeechTests/StreamingMainViewModelTests.swift:1034-1161`.
- The contradictory acceptance surface to replace is `test_firstPartialFinalOnlyRebindKeepsCapturedDestinationAndNeverArmsAppend` (`StreamingMainViewModelTests.swift:1873-1897`). Initial `.finalOnly` tests currently assert only the release-time result and do not assert visible partial output (`StreamingMainViewModelTests.swift:282-299,1782-1824`).

## Recommended RED acceptance cases (test custody)

1. **Initial final-only emits before release.** Start with `.finalOnly`, deliver a safe non-empty partial, and assert one continuous-session apply before `stopStreamingRecording`/sealing, zero one-shot insert, and no clipboard copy.
2. **Final-only rebind emits the triggering partial.** Start unavailable, rebind `.finalOnly`, and replace the current contradictory test with assertions that the append factory is armed once and receives the same first partial before release.
3. **Captured element gate remains exact.** For initial and rebound final-only, change the focused AX element within the same PID before the first partial. Assert zero Unicode post, zero Cmd+V, zero clipboard recovery, permanent suspension, and no release-time fallthrough.
4. **Captured destination postflight uncertainty is terminal for output.** Simulate focus/element drift immediately after one Unicode post. Assert at most one post, no retry/resend, no later suffix, and no full final paste/copy.
5. **Secure Input remains fail-closed at every boundary.** Exercise preflight, poster, and postflight activation. Assert no automatic fallback/copy and fixed transcript-free termination feedback, reusing the existing secure-input outcome contract.
6. **PID/app activation drift remains permanent.** Switch away and back during final-only continuous output. Assert later partial/final events cannot resume or redirect output.
7. **Duplicate/revision protections survive routing.** For final-only continuous mode, send first, duplicate, shorter, divergent, then exact extension. Assert posts are exactly `[first, unseenSuffix]`; no deletion, selection, pasteboard write, or full-value resend.
8. **Retry/replay publishes only the frontier.** Fail after a visible final-only partial, replay the journal, and assert the same append session/focus token remains owned, historical hypotheses do not post, and only a new exact frontier suffix may post.
9. **Release seals without first output.** Hold until at least one safe partial is accepted and assert output already exists before `.sealing`; release may append one exact final suffix or commit exact text, never make the first full insertion.
10. **Factory miss is safe and non-duplicating.** If no frontmost PID/writer can be created, assert no continuous mutation. If the captured final-only token remains valid and no provisional post occurred, one release-time insertion is permitted; if any provisional delivery was attempted/uncertain, one-shot and clipboard fallthrough are forbidden.
11. **`autoInsert=false` remains zero-output.** Neither initial nor rebound final-only may create an append session, mutate AX/current focus, paste, or copy.
12. **Late generation/release races remain inert.** Reset, Secure Input invalidation, or lifecycle termination before/while sealing must invalidate both the continuous writer and captured token before late partial/final/replay callbacks.

## Validation commands after implementation

Focused behavioral suites:

```bash
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests \
  -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests \
  -only-testing:FeishuSpeechTests/CursorTextSessionTests \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests test
```

Required project validation:

```bash
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test
xcodebuild -scheme FeishuSpeech -configuration Release build
swiftlint
```

## Facts, inference, and remaining unknowns

Facts are the two source/test-locked final-only deferrals, the production default factory construction, and the capability rules cited above. The installed target reaching one of the two final-only legs is a strong inference from the symptom, not runtime proof. Unknowns that do not block the correction are the target application/control and whether `.finalOnly` occurred on the initial or second probe. A transcript-free capability-category diagnostic or owner retest can distinguish them; it is not necessary to broaden the fix because both legs share the same missing continuous routing.
