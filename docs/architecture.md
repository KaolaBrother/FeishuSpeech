# Architecture

Document system boundaries, major components, data flow, and deployment shape.

## Cursor-bound streaming speech architecture (issues #25/#26/#27)

Issue #25 accepted the initial design, issue #26 implemented the generation-bound streaming
pipeline, and issue #27 corrects held response assembly to complete snapshot replacement:

```text
HotKeyService
  -> MainViewModel (@MainActor generation owner)
      -> streaming AudioRecorder -> byte-bounded PCM ingress
          -> ordered packet journal + snapshot/replay ledger -> one fresh FeishuStreamingSession actor per attempt
      -> optional CursorTextSession (@MainActor) -> original AX editable element
      -> CurrentFocusAppendSession -> PID-bound grapheme-aware keyboard replacement
```

The production hot-key state is `idle -> pending -> streaming -> sealing -> idle | error`.
`pending` retains the 0.3-second gate. `streaming` owns one recorder/ingress, one ordered packet
journal, one generation-scoped snapshot/replay ledger, at most one active Feishu session, and at
most one cursor writer. A recoverable attempt
failure leaves the hold generation and capture alive, aborts an established failed stream once,
backs off, and replays the journal through a fresh serial session. Fn release or the 60-second cap
enters `sealing`, closes retry admission before awaiting work, actively cancels creation/backoff,
closes capture, and flushes at most one audio tail. A live attempt may finish; a replaying attempt is
cancelled through one shared bounded action-3 task. Completion waits for the old recorder barrier,
then closes the already-owned latest snapshot. A new hold
cannot start while sealing. Reset, sleep/wake, cancellation, or terminal lifecycle failure
invalidates the active generation before cleanup so late callbacks are inert.

### Streaming audio boundary

`AudioRecorder` sends converted 16 kHz mono signed Int16 PCM to
`ByteBoundedAudioIngress`, which coalesces capture-order bytes into 6,400-byte elements
(about 200 ms) before entering a non-blocking async stream. The retained 60-second cap is
1,920,000 bytes / 300 elements. This is a byte/duration bound, not a raw callback-count bound.
The ingress owns queued packets, pending coalescing bytes, delivered replay-retention accounting,
terminal state, and waiters under one lock. In production, drained packets remain charged because
the journal retains them for replay; the queued, pending, and delivered captured-byte total cannot
exceed 1,920,000 bytes. Explicit non-replay users still release exact capacity on dequeue. After the
real audio callback queue barrier, an established stream may pad its final non-empty tail to the
3,200-byte (100 ms) local minimum without charging generated silence as captured audio.
Overflow fails the hold explicitly; the pipeline never drops, reorders, re-chunks, or sends PCM
packets in parallel. The sole consumer appends every drained packet to the hold journal before its
first send. A fresh attempt replays those exact packet elements in order while the same capture and
ingress continue accepting audio.

### Streaming transport boundary

`FeishuStreamingSession` is an actor with an explicit FIFO request gate. It owns stream ID, cached
token snapshot, sequence number,
first-packet acknowledgement, terminal intent, active request, and completion state. It serializes
`action=1` open, `action=0` continuation, `action=2` finish, and bounded best-effort `action=3`
abort requests; action 3 has one total one-second best-effort deadline and cannot overlap an audio
or finish request. Recognition outcome and abort eligibility are independent: a failed action 1
before acceptance needs no abort; a failed established action 0 or action 2 may emit action 3 once;
a successfully completed action 2 forbids it. Only the exact known invalid-token business code in
a bounded HTTP 400/401 response may refresh inside the first session, retrying that same first
action and sequence once.

The coordinator, not the transport actor, owns retry. Recoverable failures create a fresh stream
after hold-wide exponential backoff (250 ms base, doubling to a 4-second cap; jitter produces a
200 ms minimum). It serially replays the journal from zero. Each response carries the stable packet
index used by the coordinator ledger: already-owned historical indices never own output again,
while a previously failed unowned index may claim once when replay first succeeds. The retry ordinal
never resets during the hold. Release closes admission to another session. There is no whole-file
fallback or parallel request chain.

Each successful response exposes one complete opaque recognition snapshot. Packet-index replay
ownership is independent: each eligible journal index may be admitted once, but an equal snapshot
does not mutate output, and a different snapshot replaces the held recognition state. A replayed
historical index remains suppressed even if a later attempt returns different text.

The response trust boundary deliberately differs from the request identity boundary. Requests
still carry the session-owned `stream_id`, `sequence_id`, and action, but code-zero responses do
not have to echo matching IDs. The parser prefers `data.recognition_text`, falls back to
`data.text`, and maps missing `data`/text to an empty event, matching KaolaTerminal's proven
streaming implementation. Nonzero business codes and malformed JSON fail that transport attempt;
the coordinator retries only its explicit recoverable subset. Business code `10024` is in that
subset because of the observed failure sequence, but its provider meaning is unknown: current
official Feishu/Lark documentation and SDK do not define it.

These packet sizes, tail padding, lowercase stream IDs, same-sequence token retry, strict
serialization, and exact-once terminal behavior are FeishuSpeech application invariants. Public
Feishu documentation does not guarantee their runtime acceptance or idempotency; credential-bearing
Release UAT remains pending.

### Cursor-writing boundary

The post-UAT correction supersedes the original strict destination startup gate. Failure to
capture or confirm an Accessibility cursor/focused element no longer blocks audio capture or the
Feishu stream. AX-backed live replacement is an opportunistic enhancement, not a prerequisite for
recognition.

`CursorTextSession` captures the original frontmost PID, focused `AXUIElement`, selected-text
range, and session generation once. A live session requires settable selected-text/range
attributes plus range read-back support. Each different eligible snapshot replaces the
coordinator's latest snapshot; the writer replaces one app-owned provisional range with it:

1. verify generation, process, focused element, caret, and previous range text;
2. select the owned range;
3. set the complete latest snapshot as selected text;
4. read back the resulting caret and text before updating ownership.

The owned range comes from Accessibility's returned ranges, not Swift character counts. Equal
snapshots are no-ops. Shorter, longer, or revised snapshots replace the one verified range.
LF/newline content is written through AX as multiline text data; this route does not synthesize a
Return key event.
Any focus,
selection, caret, text, element, or generation mismatch permanently invalidates that writer.
Late events are dropped and are never redirected to a newly focused control.

The AX writer does not use per-partial clipboard writes, synthetic Backspace, or Shift+Arrow
selection. D-27-01 permits Backspace only in the generic keyboard route described below.
If a safe editable element was captured but lacks verified range replacement, startup immediately
arms a `CurrentFocusAppendSession` bound to the captured PID and exact element. If the first-partial
rebind returns final-only, it arms the same kind of owner and applies that triggering partial before
returning. Every eligible packet response received before sealing may own its journal index once;
only a different complete snapshot is offered to output. Release cannot open a writer, claim a
response, or mutate output; it only closes the already selected owner.

If no AX destination can be captured or confirmed at startup, the first non-empty partial triggers
one final AX binding attempt. A live result takes the normal captured-range path. If that probe does
not yield live capability,
`CurrentFocusAppendSession` binds the then-current frontmost PID for this hold. It reconciles each
different complete snapshot against the snapshot it successfully submitted: exact longest common
prefix by Swift `Character`, then one serialized transaction containing the required Backspace
down/up pairs followed by the replacement suffix. Equal snapshots post nothing. Replay cannot
re-own historical indices, but may own a previously failed index once.

The keyboard path checks Secure Input, generation/admission, and bound PID immediately before and
after each transaction. Before a snapshot can be claimed or posted on this route, LF and every
other C0/C1/DEL action control are rejected so recognition text cannot become Return, submit, or
execute input. Captured sessions also validate the captured
token's current security, original PID, and exact focused `AXUIElement` identity through `CFEqual`
before and after each mutation. Any PID/element/security/delivery uncertainty permanently suspends
the owner for the hold.

The existing HID `CGEventTap` is the synchronous physical-interference authority. Monitor
installation and baseline capture occur atomically under one shared `NSLock` gate. The generic
writer acquires that gate for each Backspace or insertion pair, verifies the armed epoch, and keeps
the lock continuously from synthetic key-down through key-up. Physical key-down, non-Fn
modifier-change, mouse-down, and mouse-drag events acquire the same gate before advancing the
epoch, and the tap cannot return them for dispatch until a synthetic pair releases it. An epoch
change permanently suspends output without rollback. Fn transitions and FeishuSpeech-tagged
synthetic events do not advance the epoch. Tap timeout/user-input disable advances the epoch as
loss of input observability before recovery.

Local and global AppKit event monitors supplement this ordering guard with early main-actor
suspension. They are not the authority; production requires both to arm, and arm failure fails
closed before keyboard output.

The low-level poster creates one tagged `.privateState` source and constructs every required event
before posting: modifier-neutral Backspace down/up pairs, then a Unicode suffix down/up pair when
needed, all to the same positive bound PID. Any construction failure or final security rejection
produces zero posts. The shared gate serializes each complete pair against physical epoch advance;
an intervening physical event runs after the current pair, then stops the remaining transaction and
permanently suspends the owner. The prior snapshot advances only after the complete ordered
transaction is submitted. There is no target acceptance acknowledgement, so a local `.posted`
result cannot prove visible replacement.

After destination/security loss, external caret-affecting input, or delivery uncertainty, the owner
never rolls back, selects, navigates, resends a full value, switches target, uses Cmd+V, or falls
through to clipboard recovery. Backspace is allowed only inside a validated transaction and never
exceeds this hold's recorded owned tail. Release-time one-shot/final-only insertion and manual-copy
recovery remain removed.
Without an AX range, the unbound owner cannot observe a caret move
inside the same PID; that residual targeting risk is explicit. A divergent final leaves output
unchanged rather than attempting destructive repair.

All routes reject action-capable C0/C1/DEL controls except that verified AX range replacement may
carry LF as multiline text data. The generic keyboard route rejects LF as well. An affirmatively
detected secure target or Secure Event Input is fail-closed and receives
neither synthetic input nor recovery copy. `autoInsert=false` produces no target or pasteboard
mutation. Usable held recognition is tracked separately from output eligibility, so disabled,
unsafe, or ownerless output is not misreported as empty recognition or a stream failure.

### Finalization and privacy

Release closes response and retry admission before recorder or session drain. Action-2 text and
late packet/partial/final callbacks are transcript-free diagnostic inputs only; they cannot create,
append, replace, rewrite, or copy output. Finalization closes the existing owner without changing
text or synthesizing Return. Because PID posting has no target
acceptance acknowledgement, this is retained local submission state rather than proof that text is
visible. A failure before the first write causes no target mutation.

The overlay remains status-only; target applications are the editing surface. Empty-recognition and
uncertain-output outcomes use fixed, neutral, generation-guarded feedback presented
for two seconds even though the coordinator has already returned to idle. The neutral strings do
not claim that a target accepted an event or that visible text was preserved. Logs may include
typed state/eligibility/ownership/output outcomes, generations, attempt and journal indices,
snapshot decision, previous/new/common-prefix UTF-16 and `Character` counts, Backspace/insertion
counts, and route/outcome, but never transcript text or hashes, audio,
credentials/tokens, stream IDs, focused-control identities or contents, application/window titles,
or clipboard payloads.

A recoverable provider/transport event owns one attempt transition, not an abnormal hold exit. The
coordinator cancels the failed attempt, waits with cancellable backoff, and admits a successor only
while the same generation is active and unsealed. It publishes no user-facing error, overlay
transition, clipboard recovery, or notification. A non-recoverable terminal event immediately
invalidates the generation and every cursor writer, fails the ingress, cancels the
consumer/transport, and hides the overlay. An already-running recorder-stop barrier is not awaited
before those authority revocations; it is retained only to block a successor and delay the final
idle/error publication until the old recorder has actually stopped. Identical reflected hot-key
errors cannot re-enter teardown.

An authentication-provider failure is surfaced only as `认证失败，请检查应用凭据`. The associated
backend detail is not a public diagnostic surface.

## AudioRecorder — session lifecycle and recovery

`AudioRecorder` wraps `AVCaptureSession` with a `forceCleanup()` recovery contract (issue #1,
see `docs/decisions/D-1-01.md`):

- `startRecording()` calls `forceCleanup()` before the `isRecording` guard so stale state from
  a prior cancel or error path is always cleared before a new session begins.
- `handleCancelledState()` and `handleErrorState()` both call `forceCleanup()` to keep
  `isRecording` consistent with the actual `AVCaptureSession` state on every abnormal exit.
- `resetService()` calls `forceCleanup()` so a deliberate reset from the UI recovers a stuck
  mic without an app restart.

`forceCleanup()` is idempotent — calling it on an already-stopped session is a no-op.

Issue #15 adds a fail-fast failure contract for capture failures and conversion-error
exhaustion (see `docs/decisions/D-15-01.md`):

- `AudioRecorder` publishes `@Published private(set) var failure: RecordingFailure?`.
  `RecordingFailure` distinguishes `.runtime`, `.interrupted`, `.deviceLost`, and
  `.formatConversion`.
- `AVCaptureSession.runtimeErrorNotification` maps to `.runtime`,
  `AVCaptureSession.wasInterruptedNotification` maps to `.interrupted`, and
  `AVCaptureDevice.wasDisconnectedNotification` maps to `.deviceLost`.
- Repeated sample-buffer or converter failures increment the conversion-error counter; reaching
  `maxConversionErrors` aborts the recording with `.formatConversion`.
- If the abort is delivered off-main, `AudioRecorder` dispatches to the main queue before
  calling `forceCleanup()` and publishing `failure`. `forceCleanup()` still runs
  `AVCaptureSession.stopRunning()` and session teardown on `sessionQueue`, so blocking session
  work remains off the main actor.
- `MainViewModel` observes `audioRecorder.$failure`; on failure it hides the overlay,
  force-cleans the recorder, stops the max-duration timer, sets a specific error status, and
  puts `HotKeyService` into `.error` with the same localized message. This path does not call
  `stopRecording()` and does not start transcription.

## AppSettings — credential storage and migration

Issue #18 moves Feishu App ID and App Secret storage behind `CredentialStoring`
(see `docs/decisions/D-18-01.md`). `AppSettings.credentialStore` defaults to
`KeychainCredentialStore`, which stores generic password items through
Security.framework using service `Siji.FeishuSpeech.credentials` and account
values `appId` / `appSecret`.

`AppSettings` still exposes `appId` and `appSecret` to the app at runtime, but
its custom `Codable` implementation does not encode those fields into
`FeishuSpeechSettings`. That user-defaults payload is limited to `autoInsert`,
`playSound`, and `launchAtLogin`.

Loading settings performs a guarded migration from legacy credentials:

- encoded `FeishuSpeechSettings` credentials are read if present;
- standalone user-default keys `appId` and `appSecret` are also read;
- standalone values take precedence over encoded values;
- legacy defaults are removed only after credential-store migration succeeds and
  the migrated credentials can be read back;
- when migration or credential read/write fails, legacy values remain available
  as the fallback and later saves avoid deleting the only remaining copy.

`SettingsView` keeps credential edits in transient `@State` fields and saves via
`MainViewModel.updateSettings(...)`, which calls `AppSettings.save()`. It does
not use `@AppStorage` for App ID or App Secret.

## AppDelegate and MainViewModel — sleep/wake lifecycle

Issue #19 defines the system sleep/wake recovery contract (see
`docs/decisions/D-19-01.md`). `AppDelegate` registers
`NSWorkspace.willSleepNotification` and `NSWorkspace.didWakeNotification` through
`NSWorkspace.shared.notificationCenter` when the app finishes launching. The
observer tokens are retained in `workspaceObserverTokens` and removed during
application termination.

Workspace lifecycle delivery is routed through `MainViewModel`. If a sleep or
wake notification arrives before `setViewModel(_:)`, `AppDelegate` queues the
event and replays the queued lifecycle events once the view model is injected.

`MainViewModel.handleSystemWillSleep()` and `handleSystemDidWake()` both use the streaming terminal
path: invalidate the active identity and cursor ownership first; fail the ingress; cancel consumer
and transport work; release captured destination/session references; force-clean the recorder; and
stop the timer and overlay. If recorder sealing is already in flight, the terminal path retains and
awaits that barrier before returning coordinator and hot-key state to idle. It then calls
`FeishuAPIService.resetStateForWake()`.

The wake handler also calls `HotKeyService.recoverAfterWake()` after the API
wake reset.

## HotKeyService — state-machine contract

`HotKeyService` drives `idle -> pending (0.3 s) -> streaming(sessionID) ->
sealing(sessionID) -> idle`. The following rules keep `HotKeyService` and `MainViewModel` in sync:

- **The 0.3-second gate allocates the identity.** Each accepted gate increments a monotonically
  increasing generation and publishes it with `.streaming`.
- **Release and duration cap converge on sealing.** Fn release and the 60-second timer both move
  that same identity from `.streaming` to `.sealing`; repeated transitions are ignored and a new
  Fn press during sealing cannot open another session.
- **Reset/error/stop/wake clears identity before cleanup.** Late audio, network, AX, timer, and
  overlay callbacks compare the captured generation and cannot revive or redirect a retired hold.
- **`MainViewModel` holds `stateCancellable: AnyCancellable?` for the single `$state`
  subscriber.** `startHotKeyMonitoring` assigns it (replacing any prior subscriber);
  `stopHotKeyMonitoring` nils it before calling `stopMonitoring()`. At most one live
  `$state` subscriber exists at any time.
- **App teardown uses the same hot-key stop path as normal monitoring shutdown.**
  `MainViewModel.cleanup()` calls `stopHotKeyMonitoring()`, so cleanup releases
  `stateCancellable` before delegating to `HotKeyService.stopMonitoring()`. Teardown must not
  bypass `stopHotKeyMonitoring()` or leave a live `$state` subscriber behind.

## HotKeyService — tap-lifecycle and threading contract

The CGEventTap machinery was redesigned in issues #5, #9, and #10 (see
`docs/decisions/D-5-01.md`). The key invariants are:

**Threading model**

| Thread / Queue | Owns |
|---|---|
| Tap thread (private `CFRunLoop`) | CGEventTap callback, `CFRunLoopSource` |
| `sessionQueue` (serial background) | `AVCaptureSession.startRunning()` / `stopRunning()`, `isRecording` flip |
| `@MainActor` | `monitoringState` publish, all UI updates, `MainViewModel` state |

The tap source is added to a private dedicated `Thread`+`CFRunLoop`, not
`CFRunLoopGetMain()`. This eliminates contention with `AVCaptureSession.startRunning()`,
which blocks the run loop and previously caused sporadic hotkey event drops.

**`MonitoringState` observable**

`HotKeyService` publishes `@Published var monitoringState: MonitoringState` with three
cases: `.stopped`, `.active`, and `.failed(TapFailureReason)`. `MainViewModel` subscribes
and surfaces `.failed` as the fixed error status `热键不可用，请检查辅助功能权限`.

When monitoring later publishes `.active`, `MainViewModel` auto-clears only that specific
stale hot-key monitoring error and returns to `.idle`. The clear is guarded by both the
tracked hot-key monitoring failure flag and the current status value, so unrelated errors
such as speech-recognition failures are preserved. The retry policy is unbounded capped
exponential backoff (1 s -> 2 s -> ... -> 30 s cap) instead of the previous hard 3-attempt
limit.

**`previousFlags` lifecycle**

`stopMonitoring()` resets `previousFlags` to `.init()` so a restart begins with a clean
key-flag baseline. After each backoff delay, `CGEventSource.flagsState(.combinedSessionState)`
is sampled to detect a held Fn key and cancel any stale pending/recording state before the
tap is re-created.

**Wake recovery**

`recoverAfterWake()` cancels pending transitions, returns the state machine to
`.idle`, and clears `previousFlags` before checking tap health. For real taps,
tap health is read through `CGEvent.tapIsEnabled(tap:)`. If the tap exists and
is enabled, monitoring remains active. If the tap is missing or disabled, wake
recovery restarts monitoring through the normal `stopMonitoring()` /
`startMonitoring()` lifecycle.

The DEBUG test hook drives the same recovery branch without a real
`CFMachPort`, and its result exposes only `restartCount`.

**Secure keyboard entry**

`PermissionManager` polls `IsSecureEventInputEnabled()` every 2 seconds. When active, the
menu bar shows an orange "安全输入已启用，热键暂不可用" warning (issue #10). The hotkey
suppression itself is enforced by the OS kernel; detection and display is the only recourse.

The same 2-second `AppDelegate` poll also refreshes accessibility, microphone authorization,
and secure-input status (issue #15). `PermissionManager.refreshMicrophoneStatus()` reads the
current microphone authorization status without prompting and recomputes
`allPermissionsGranted`, so permission changes made in System Settings are reflected at runtime.

**Current-focus interference epoch**

Issue #27 extends the existing HID event tap mask to physical key-down, non-Fn modifier changes,
mouse-down, and mouse-drag events. At the start of the tap callback, before the event is returned
for dispatch, `CurrentFocusInputInterferenceEpoch` acquires the same `NSLock` used to guard complete
synthetic pairs and increments the epoch. Monitor installation plus baseline capture is atomic under
that lock. The generic writer uses this synchronous gate rather than AppKit monitor callback timing
to guard destructive replacement. Tap-disable events advance the epoch before recovery because
input observability was lost. FeishuSpeech's tagged synthetic events and the Fn transition itself
are excluded. Local/global AppKit monitors remain supplemental; failure to install either prevents
the writer from arming.

## TextInputSimulator — clipboard-restore contract

The legacy compatibility helper in `TextInputSimulator` writes a final string to
`NSPasteboard.general`, sends a synthetic Cmd+V, then restores the previous clipboard state
(issue #13, see `docs/decisions/D-13-01.md`). Production streaming output never uses this
path. It instead:

- permits LF only on the verified AX range path, where it is multiline text data; the generic
  keyboard-event path rejects LF and all other C0/C1/DEL controls before claim/post;
- when a destination token exists, targets that captured process with `CGEvent.postToPid` and
  validates the captured element and security state before and after delivery;
- when AX capture/confirmation is unavailable, re-probes AX once on the first non-empty partial;
  if still unavailable, binds the frontmost PID and posts grapheme-aware Backspace-plus-Unicode
  replacement transactions while Secure Input stays clear, atomic arming captures the HID epoch,
  the shared lock covers every complete synthetic pair, and the PID stays stable;
- treats local/global AppKit event monitors as supplemental suspension signals and fails closed if
  either monitor cannot arm;
- gives captured final-only-capability targets the same continuous owner, additionally checking the original
  PID and exact AX element before/after each mutation; after any post attempt or uncertainty it
  never falls through to a full resend, Cmd+V, another target, or clipboard recovery;
- never performs release-time one-shot/final-only insertion or manual clipboard recovery.

The older compatibility helper retains these clipboard-restore mechanics:

- **Full snapshot before write.** Before placing the transcribed text on the pasteboard, the
  simulator reads every `type` from `NSPasteboard.general` and stores a
  `[(type: NSPasteboard.PasteboardType, data: Data)]` array. All types — not just the first
  string item — are captured so non-string content (RTF, images, etc.) survives the round-trip.
- **changeCount-based confirmation.** After sending Cmd+V, the simulator polls
  `NSPasteboard.general.changeCount` at a short interval up to a bounded timeout. The
  changeCount advances each time an application reads from the pasteboard. Restoration is
  deferred until that increment is observed, ensuring the target application has read the
  transcribed text before the old data is written back.
- **Fallback notification on timeout.** If the changeCount does not advance within the
  timeout, the simulator restores the pasteboard unconditionally and posts a user notification.

The `maxDurationTimer` in `HotKeyService` is scheduled with `RunLoop.main.add(timer,
forMode: .common)` so it fires in both `.default` and `NSEventTrackingRunLoopMode` (e.g.
while the menu-bar menu is open) — issue #16.

## OverlayWindowController — generation guard

`OverlayWindowController` maintains a monotonically incrementing `Int` generation counter
to prevent hide/show races (issue #17, see `docs/decisions/D-13-01.md`):

- Each `show()` call increments the counter and captures the new value in its animation
  completion closure.
- Each `hide()` call captures the current generation at call time.
- Any completion block that fires with a stale (mismatched) generation is a no-op and does
  not close or modify the window.

This prevents a `hide()` completion from a superseded call from closing a window that a
newer `show()` has already claimed.

Issue #26 extends the same guard to completion feedback. A requested interval is clamped to one
through five seconds (the coordinator always requests two); show, hide, or replacement feedback
cancels the previous delayed hide and advances the generation, so stale feedback cannot hide a new
recording overlay.

## Verification boundary

Issue #26's 272/272 lifecycle-free evidence predates the issue #27 correction and must not be used
as proof of snapshot reconciliation. Issue #27 requires focused and full-suite evidence for
duplicate, extension, shorter, revision, replay, Unicode grapheme, ordered transaction, suspension,
and release-sealing cases. The final issue #27 candidate at Release 1.0 build 7 passes 300/300 full
tests, strict SwiftLint, and Debug and Release builds. Production is `ec4ddd6`, final
production-gate tests run through `cd1132c`, and the behavior/security documentation provenance is
`6e5d262`. Automated evidence still cannot prove target-control acceptance.

Credential-bearing Feishu behavior and cross-application Accessibility compatibility remain live
UAT. Installed build 5 recorded 66 HTTP-200 transactions over 13.55 seconds while visible output
stopped after one word. This proves continuing transport, not response shape, output ownership, or
target acceptance. The snapshot-replacement policy, subsequent actions, terminal encoding, real
text/token-refresh behavior, PCM/tail handling, slow networks,
native/browser/Electron/terminal/rich-text targets, focus/caret interference, Unicode, and undo
remain owner-UAT gates. No broad application compatibility is claimed yet.

In particular, `CGEventPostToPid` has no target acceptance acknowledgement. A locally submitted
replacement transaction with no visible target text remains PARTIAL and must not trigger global
HID posting, retries, rollback, or an alternate clipboard path after uncertainty.
