# Issue #26 held-output correction blueprint

Date: 2026-08-03

Implementation worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`

Branch: `workflow/issue-26`

## 1. Verdict and intended outcome

**PASS — the correction can remain inside the existing output and coordinator boundaries.** No
transport, audio, hot-key, permission, entitlement, dependency, deployment-target, schema, or public
API change is required.

The corrected contract is:

> While the matching Fn generation is still unsealed, every safe, non-contentless, eligible
> hypothesis is offered immediately to exactly one output owner. Live AX keeps verified whole-range
> replacement. Captured `finalOnly`, rebound `finalOnly`, and AX-unavailable current-focus modes use
> one PID-bound, modifier-neutral Unicode key-down/key-up sequence and then the existing strict UTF-16
> append frontier. Release only seals capture and finalizes the already-selected owner; it never
> causes a second full insertion after provisional delivery or uncertainty.

“Offered” is the strongest locally provable claim for the CGEvent routes. `CGEvent.postToPid` has no
target-control acknowledgement. Automated tests can prove the source, flags, pair, order, PID,
payload, security gates, and exact-once routing; installed owner UAT must prove that representative
controls visibly accept the sequence.

## 2. Evidence that fixes the scope

The retained build-4 evidence and current source establish two independent gaps:

1. All six retained runs received a usable hypothesis and used the AX-unavailable current-focus
   append route. Three selected it before release, including one 5.5 seconds early, but the owner saw
   no held output. `SystemFinalTextCurrentFocusEventPoster` currently creates one key-down event from
   `.hidSystemState`, does not clear inherited flags, posts globally at `.cghidEventTap`, emits no
   key-up, and returns `.posted` without target acknowledgement.
2. Initial AX `.finalOnly` and first-partial rebound `.finalOnly` intentionally retain hypotheses
   until final/release and use a one-shot Cmd+V route. Those are safe captured destinations but are
   excluded from continuous output by coordinator routing.

The locally installed macOS 26.5 SDK headers confirm the selected mechanics:

- `CGEventSource.h:19-48` says source tables carry modifier/key state, HID state is for hardware
  devices/daemons, and a private source owns an independent state table.
- `CGEvent.h:196-203` warns that frameworks may ignore the supplied Unicode string and translate
  from virtual keycode plus perceived event state.
- `CGEvent.h:356-374` defines process-specific posting through `CGEventPostToPid`.

The implementation must therefore correct both the physical event sequence and final-only routing.
Fixing only one leaves an ordinary safe auto-insert route release-gated or still vulnerable to the
held Fn modifier state.

## 3. Non-negotiable safety boundaries

- Keep `autoInsert=false` at zero output: no append factory, AX mutation, Unicode event, Cmd+V, or
  clipboard recovery.
- Keep affirmative Secure Input/secure-target rejection fail-closed before output and recovery copy.
- A captured token never degrades to PID-only validation. Its original PID, exact `AXUIElement`, and
  safe security state are checked before and after every provisional/final suffix post.
- An unbound route remains bound to one frontmost PID for the hold. App activation away, PID drift,
  Secure Input, generation invalidation, or post uncertainty permanently suspends it.
- No provisional route performs deletion, selection, navigation, Backspace, Return, pasteboard
  mutation, full-value resend, retry after uncertainty, or rollback.
- Once a provisional poster has been called, or delivery becomes uncertain, that route owns the
  ambiguity. No later Cmd+V, current-focus full post, or clipboard fallback is permitted.
- A one-shot final-only fallback remains allowed only if the append factory could not create a
  session before any provisional poster call. This preserves existing recovery without creating a
  duplicate path.
- Contentless and C0/C1/DEL-bearing values remain ineligible for automatic Unicode output. A manual
  copy of unsafe text is allowed only when no provisional post was attempted or became uncertain.
- Logs, enum descriptions, tests, and feedback remain transcript-free. Do not log payloads, focused
  element contents, app/window names, clipboard contents, stream IDs, audio, credentials, or tokens.

## 4. Smallest internal interface changes

These are module-internal/testable changes, not public API changes.

### 4.1 PID-bound Unicode poster

Change `FinalTextCurrentFocusEventPosting` in
`FeishuSpeech/Services/TextInputSimulator.swift` from:

```swift
func postUnicodeText(_ text: String) -> FinalTextCurrentFocusPostResult
```

to:

```swift
func postUnicodeText(
    _ text: String,
    to processIdentifier: pid_t
) -> FinalTextCurrentFocusPostResult
```

Both callers already know the authoritative PID:

- `CurrentFocusAppendSession` passes its immutable `boundProcessIdentifier`.
- `SystemFinalTextOutput.insertAtCurrentFocusOnce` passes the first sampled PID only after both
  frontmost-PID samples match.

Do not retain a global-post overload. Keeping one would make accidental retargeting possible again.

### 4.2 Injectable CoreGraphics seam

Give `SystemFinalTextCurrentFocusEventPoster` an internal initializer with three injected operations:

- create an event source from a requested `CGEventSourceStateID`;
- create a keyboard event from that source and a `keyDown: Bool` phase;
- post a constructed event to an explicit PID.

Production defaults call `CGEventSource(stateID:)`, `CGEvent(keyboardEventSource:virtualKey:keyDown:)`,
and `CGEvent.postToPid(_:)`. Tests inject recording closures. This is smaller than introducing a new
public service and is deep enough to deterministically prove construction and posting without
sending real input.

For each non-empty safe payload and positive PID, the system poster performs exactly this sequence:

1. Request one `CGEventSource(stateID: .privateState)`.
2. From that same source, create key-down and key-up events using the same inert placeholder virtual
   key currently used by the Unicode override.
3. Set the identical UTF-16 payload on both events. The event phase, not absence of Unicode data,
   distinguishes down from up.
4. Set `flags = []` explicitly on both events after creation. This prevents the physically held Fn
   or any ambient modifier state from contaminating the synthetic sequence.
5. Sample Secure Input immediately before the first post. A positive sample returns
   `.securityRejected` and posts neither event.
6. Post key-down, then key-up, both through `postToPid(boundPID)`. Once key-down is posted, key-up is
   always posted; no gate may split the pair.
7. Return `.posted` only after both post calls have been made. This means “submitted”, not “accepted
   by the target control”. Source/event construction failure before either post remains
   `.deliveryFailed` and is conservatively treated as uncertainty by the append owner.

Do not change `SystemFinalTextKeyEventPoster` in this correction. It is the explicit Cmd+V one-shot
fallback and necessarily uses Command flags; it is not a provisional held-output primitive.

### 4.3 Captured-destination append factory overload

Keep the existing unbound factory call:

```swift
func makeSession(generation: UInt64) ->
    (any CurrentFocusProvisionalOutputSession)?
```

Add a distinct captured overload rather than nullable PID/validator parameters:

```swift
func makeSession(
    generation: UInt64,
    boundProcessIdentifier: pid_t,
    validateBoundDestination: @escaping @MainActor () ->
        CurrentFocusBoundDestinationValidation
) -> (any CurrentFocusProvisionalOutputSession)?
```

Use a transcript-free validation enum with only:

```text
valid | destinationChanged | securityRejected
```

The overload prevents invalid combinations such as “explicit PID without exact validation” or
“validator with a newly captured PID”. The system factory must use the supplied PID directly; it
must not replace it by querying current focus.

`CurrentFocusAppendSession` stores the optional additional validator. Its existing
`sampleDestinationAndSecurity()` remains the single gate, but for captured sessions each sample
also invokes the exact validator after the ordinary Secure Input and PID checks. Preserve the
current two preflight samples and one postflight sample. Map exact validation failure to the
existing permanent suspension categories.

`MainViewModel` supplies a weak-self closure around `validateFinalOnlyDestination(token)`. A lost
view model maps to `destinationChanged`; do not form a session-to-view-model retain cycle. Reuse the
same typed validation for existing one-shot final-only delivery rather than maintaining two subtly
different exact-focus rules.

## 5. Coordinator routing

### 5.1 Initial `finalOnly`

In `configureCursorCapability`:

1. Keep the captured `CursorDestinationToken` in `finalOnlyDestination` as a fallback authority.
2. When `autoInsert` is true, immediately ask the new captured factory overload for an append
   session using the token PID and exact validator.
3. If creation succeeds, store it in `currentFocusAppendSession`, clear
   `usesCurrentFocusFinalOutput`, and present `.streaming`; the first usable partial will flow into
   that already-bound session before release.
4. If creation returns nil, retain `.finalOnly` and the existing release-time captured Cmd+V path.
   No provisional post was possible, so this one-shot fallback is non-duplicating.

Do not clear `finalOnlyDestination` when the append session is created. It remains identity evidence
for the exact validator, not an alternate output route. Dispatch priority remains
`cursorSession -> currentFocusAppendSession -> finalOnlyDestination -> unbound final output`, so an
owned append session prevents fallthrough.

### 5.2 First-partial rebound `finalOnly`

In `prepareContinuousOutputIfNeeded`, when the one allowed rebound returns `.finalOnly(token)`:

1. retain the token;
2. create the captured append session through the new overload;
3. on success, return to `handlePartial`, which must pass the same triggering partial to the new
   session in that call;
4. on factory miss, keep the captured final-only fallback and do not attempt another bind/factory on
   later partials.

The rebound remains exactly once. Do not requery a new AX element after a captured session has
failed, suspended, or become uncertain.

### 5.3 AX-unavailable current focus

Keep the existing first-hypothesis rebound and unbound append factory selection. The only routing
change is that the session passes its immutable PID into the corrected event poster. Prefix,
duplicate, revision, content, activation, Secure Input, and generation logic stays in
`CurrentFocusAppendSession`.

### 5.4 Live AX

Do not modify `CursorTextSession` or `AccessibilityClient`. Live AX already writes each usable
partial before release and proves the destination/range/caret/text after each write. It is the
strongest output route and remains first priority.

## 6. Output ownership, fallback, and feedback matrix

| State at finalization | Allowed action | Forbidden action | Feedback rule |
|---|---|---|---|
| Live AX has verified provisional text | Commit/replace once through the same owned range | New target, Cmd+V, clipboard recovery | Fixed status may say content remains because AX read-back proved it |
| Append session returned `.posted` at least once | Exact final suffix or exact no-op through same session | Full resend, Cmd+V, current-focus one-shot, clipboard fallback | Use neutral “check target” wording; CGEvent acceptance is not acknowledged |
| Append postflight/PID/focus became uncertain | Close/suspend only | Any retry, suffix, full resend, Cmd+V, clipboard fallback | Fixed transcript-free uncertainty wording, never “content preserved” |
| Secure Input/secure token observed | Terminate fail-closed | Target output and recovery copy | Existing fixed security error |
| Captured append factory returned nil before any poster call | Existing captured final-only route may run once at release | Provisional retry or new destination | Existing inserted/manual-copy result rules |
| Append session saw only contentless/unsafe values and made no poster call | Safe text may still be finalized; unsafe non-empty text may be copied for manual recovery | Automatic unsafe event | No preservation claim; copy claim only follows the existing copy operation |
| No usable text at all | No output | Synthetic or clipboard mutation | Fixed no-usable-text wording |

Preserve this `CurrentFocusAppendFinalOutcome` invariant: `.noUsableText` is reachable only when the
session has never called its poster. Any poster call returning failure remains
`.deliveryUncertain`, even if construction likely failed before CoreGraphics posting; the
coordinator must not guess that retry or fallback is duplicate-free.

The visible strings in `RecordingState` currently overclaim successful preservation even when no
post occurred or the target may have ignored it. Keep the enum cases to avoid unrelated churn, but
change their presentation:

- `.emptyFinalPreservedPartial`: neutral text such as `未返回可用最终文本`; no checkmark icon.
- `.provisionalOutputPreserved`: neutral text such as `自动输入状态不确定，请检查光标处内容`; no
  checkmark icon.
- use an orange warning/attention presentation rather than a success-colored checkmark.

The fixed strings remain transcript-free. Do not insert recognized text into the overlay to make
the feedback more specific.

## 7. Release, late hypotheses, retry, and replay

### Release is a seal, not an output trigger

`beginSealing` remains responsible only for atomically setting `sealStarted`, closing retry
admission, updating lifecycle status, and stopping/sealing the recorder. It does not create an
output session or route text.

Add a seal gate after `handlePartial` records the latest non-contentless value but before it binds or
applies provisional output. The same rule applies to nonterminal hypotheses returned from an
in-flight request after sealing:

- if `sealStarted == false`, prepare/apply immediately;
- if `sealStarted == true`, retain the value as a finalization candidate but do not create a writer
  or call `applyOpaqueHypothesis`.

The terminal action-2 result or sealed recoverable-completion path may then finalize once:

- an existing AX/append owner commits or appends one exact final suffix;
- if no provisional owner ever existed, a captured/current-focus final fallback may make the first
  one-shot output;
- if a provisional owner posted or became uncertain, there is no alternate fallback.

MainActor ordering defines the release race. A partial handled before `sealStarted` is eligible held
output; one handled after the seal is a finalization candidate. Do not add timers or sleeps to alter
that order.

### Retry/replay frontier

Do not change the packet journal or retry policy. Preserve these ownership rules:

- `currentFocusAppendSession` and its captured token/PID survive fresh transport attempts for the
  same generation; the append factory is called at most once for that output route.
- Replay does not publish every historical hypothesis. Only the existing latest catch-up-frontier
  event is offered after journal catch-up while the generation is still unsealed.
- The append session compares that frontier against its emitted UTF-16 units. A duplicate or
  divergent/shorter replay is suppressed; only an exact unseen suffix may post.
- If sealing wins before replay reaches its catch-up frontier, replay history is not eligible held
  output. Finalization uses the already retained/verified value under the existing sealed-recovery
  rules and never opens a new provisional session.
- Reset, sleep/wake, security/permission loss, capture failure, cleanup, and generation replacement
  invalidate the output owner before late retry/replay callbacks. Late callbacks remain no-ops.

This definition avoids claiming that an intermediate historical replay response is a usable visible
partial. It becomes eligible only at the existing catch-up frontier.

## 8. File-by-file implementation plan

### Test custody first

The `tdd-guide` remains sole owner of test artifacts. The implementer may read and run them but must
not author or weaken them.

1. `FeishuSpeechTests/FinalTextOutputSecurityTests.swift`
   - Update fake posters for the PID parameter.
   - Add deterministic system-poster tests proving `.privateState`, one shared source, down/up
     creation order, identical UTF-16 payloads, explicit empty flags, exact PID for both posts,
     secure rejection before either post, and no partial pair when construction fails.
   - Keep the current current-focus two-PID/two-security-sample tests and assert the stable sampled
     PID is passed to the poster.
2. `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift`
   - Record `(text, PID)` poster requests.
   - Add captured-validator cases for exact-element drift in the same PID, preflight Secure Input,
     postflight focus/security drift, activation away-and-back, and permanent suspension.
   - Assert at most one poster call after uncertainty and no replay/final resend.
   - Lock `.noUsableText` to zero poster calls.
3. `FeishuSpeechTests/StreamingMainViewModelTests.swift`
   - Initial `.finalOnly` arms one captured append session before the first packet; the first safe
     partial is applied before recorder stop/release.
   - Rebound `.finalOnly` arms once and applies the triggering partial in the same callback.
   - Captured same-PID element drift and security rejection yield zero posts, zero Cmd+V, and zero
     clipboard recovery.
   - A successful/uncertain provisional call blocks all release-time full insertion and copy.
   - Factory miss before provisional ownership preserves exactly one release-time fallback.
   - Duplicate/revision/exact-suffix and retry/replay frontier behavior remain unchanged.
   - `autoInsert=false`, stale generation, reset/lifecycle invalidation, and secure startup remain
     zero-output.
   - Release before first usable partial does not open a provisional writer; a late value is handled
     only by finalization. No-partial completion uses neutral fixed feedback.
   - Fixed completion text/icons contain no transcript and do not claim preservation on a zero-post
     or uncertain route.

Do not add a new test file unless the test custodian finds it materially clearer. The Xcode project
uses file-system-synchronized root groups, so a new test file would not require a project-file edit.

### Production order

4. `FeishuSpeech/Services/TextInputSimulator.swift`
   - Land the PID-bearing poster protocol and injectable private-source paired-event implementation.
   - Update `SystemFinalTextOutput` to pass its stable sampled PID.
5. `FeishuSpeech/Services/CurrentFocusAppendSession.swift`
   - Pass `boundProcessIdentifier` to every Unicode post.
   - Add the typed captured-destination validator and factory overload.
   - Integrate exact validator samples into the existing two-pre/one-post gate without changing the
     UTF-16 frontier or suspension semantics.
6. `FeishuSpeech/ViewModels/MainViewModel.swift`
   - Arm initial and rebound final-only through the captured factory overload.
   - Preserve the token as validation/fallback authority while making append-session ownership
     exclusive after creation.
   - Apply the triggering rebound partial immediately.
   - Add the sealing gate and enforce the fallback matrix.
   - Reuse one exact captured-destination validator; capture `self` weakly in the session closure.
7. `FeishuSpeech/Models/RecordingState.swift`
   - Replace preservation-success wording/checkmarks on no-result or uncertain CGEvent outcomes with
     neutral fixed feedback.

No production edits are expected in:

- `AccessibilityClient.swift` or `CursorTextSession.swift`;
- `FeishuStreamingSession.swift`, `FeishuAPIService.swift`, `ByteBoundedAudioIngress.swift`, or
  `AudioRecorder.swift`;
- `HotKeyService.swift` or `HotKeyState.swift`;
- permissions, settings, entitlements, dependencies, build settings, or the Xcode project.

If a compiler error appears to require one of those files, stop and prove the dependency before
expanding scope.

### Documentation after behavior is green

8. Update only source-grounded statements in:
   - `README.md`;
   - `CHANGELOG.md`;
   - `docs/architecture.md`;
   - `docs/api.md`;
   - `docs/streaming-speech-design.md`;
   - `docs/decisions/D-26-01.md`.

The documentation must say that captured final-only now uses continuous PID-bound Unicode output
with exact token validation, the current-focus poster uses a private modifier-neutral paired event,
release only seals/finalizes, and CGEvent target acceptance remains an installed-UAT claim. Amend
the `D-26-01` supersession boundary so the older D-25 captured-final-only release-only statement is
no longer presented as authoritative. Do not claim broad TextEdit/browser/Electron/terminal/rich
editor compatibility before UAT.

## 9. Task dependencies and genuine independence

```text
RED contracts
   -> PID-bound paired poster
      -> captured-validator append factory
         -> initial/rebound final-only coordinator routing
            -> sealing/fallback/feedback completion
               -> focused + full validation
                  -> documentation and installed owner UAT
```

- The three RED surfaces are conceptually independent because they exercise different boundaries,
  but two coordinator groups share `StreamingMainViewModelTests.swift`; one test custodian should
  serialize edits to that file.
- Poster implementation and documentation drafting touch different files, but final documentation
  depends on verified behavior and must not be finalized early.
- Production tasks 4–7 are not genuinely independent: the poster protocol change feeds the append
  session, the append factory feeds coordinator routing, and feedback depends on final outcomes.
  Implement them in that order to keep compile failures attributable.
- After implementation, `code-reviewer` and `security-reviewer` can run independently because both
  are read-only and neither produces inputs consumed by the other. Resolve both before UAT.

## 10. Exact validation

### Focused automated suites

```bash
xcodebuild -project FeishuSpeech.xcodeproj \
  -scheme FeishuSpeech \
  -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests \
  -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests \
  -only-testing:FeishuSpeechTests/CursorTextSessionTests \
  test
```

`CursorTextSessionTests` is a regression gate even though no edit is expected there.

### Required repository validation

Run from `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`:

```bash
xcodebuild -project FeishuSpeech.xcodeproj \
  -scheme FeishuSpeech \
  -destination 'platform=macOS' \
  test

swiftlint

xcodebuild -project FeishuSpeech.xcodeproj \
  -scheme FeishuSpeech \
  -configuration Debug \
  build

xcodebuild -project FeishuSpeech.xcodeproj \
  -scheme FeishuSpeech \
  -configuration Release \
  build
```

Do not launch the app, simulate Fn, install a build, or exercise credentials as part of automated
validation. The final workflow stage owns one incremented Release build and one installation after
tests/lint/builds and reviews pass.

### Owner UAT acceptance

Use the sole incremented installed Release and record transcript-free semantic evidence only:

1. Hold Fn long enough to receive at least one usable partial; visible text must begin before
   release on the previously failing target.
2. Repeat on a live AX control, a captured final-only control, and an AX-unavailable control when
   available. Record capability category, whether first output preceded release, whether release
   duplicated text, and whether any fixed warning appeared; do not record recognized content.
3. Exercise one longer exact-extension phrase and confirm release adds at most one suffix/no-op,
   never a second full value.
4. Switch applications or enable a secure target during a separate privacy-safe attempt and confirm
   fail-closed behavior with no redirected output/copy.
5. Verify `autoInsert=false` produces no target or clipboard mutation.

Installed UAT is **PARTIAL**, not success, if the app logs a `.posted` pair but the target still
shows no text. `CGEventPostToPid` cannot close that evidence gap locally.

## 11. Rollback and failure routing

- Keep the correction in separable commits if practical: test RED, poster primitive, append binding,
  coordinator/feedback, then docs. A regression can revert the smallest layer without touching
  transport/audio work.
- Build/type/lint/tooling failures route to `build-error-resolver`; behavioral/coverage failures
  route back to `tdd-guide`; focus/Secure Input/duplicate risks route to `security-reviewer` before
  implementation changes are accepted.
- If the private-source, empty-flag, PID-bound down/up pair still produces no visible UAT output, do
  not add global HID posting, repeated key events, Cmd+V/clipboard fallback after provisional
  uncertainty, destructive editing, or an acknowledgement claim. Preserve the validated code and
  report installed output **PARTIAL**.
- A composition-capable input method/IME, event-tap strategy change, broader Accessibility write,
  or app-specific integration is a separate product/signing/packaging/security decision. Escalate it
  to the owner rather than designing past the failed UAT inside issue #26.

## 12. Completion checklist

- [ ] Every eligible safe partial received before sealing reaches one output owner immediately.
- [ ] Unicode output is private-source, explicit-empty-flags, key-down/key-up, and PID-bound.
- [ ] Initial and rebound final-only retain exact token/security pre/post validation.
- [ ] Any provisional post or uncertainty permanently blocks full-post/Cmd+V/clipboard fallthrough.
- [ ] Retry replay offers only its existing catch-up frontier and never reopens ownership.
- [ ] Release only seals/finalizes; post-release late hypotheses do not start provisional output.
- [ ] No-partial and uncertain feedback is fixed, transcript-free, and makes no false preservation
  claim.
- [ ] `autoInsert=false` and security rejection remain zero-output/fail-closed.
- [ ] Focused tests, full tests, SwiftLint, Debug build, and Release build pass.
- [ ] Independent code/security reviews pass.
- [ ] One incremented installed Release passes owner UAT, or the outcome is honestly reported
  **PARTIAL** without unsafe fallback expansion.
