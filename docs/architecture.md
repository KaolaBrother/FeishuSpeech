# Architecture

Document system boundaries, major components, data flow, and deployment shape.

## Planned cursor-bound streaming speech architecture (issue #25)

Issue #25 accepts the design in `docs/decisions/D-25-01.md` and
`docs/streaming-speech-design.md`; it does not implement it. The production architecture will move
from whole-file capture followed by one paste to a generation-bound streaming pipeline:

```text
HotKeyService
  -> MainViewModel (@MainActor generation owner)
      -> streaming AudioRecorder -> byte-bounded PCM ingress
          -> FeishuStreamingSession actor -> partial/final events
      -> CursorTextSession (@MainActor) -> original AX editable element
```

The hot-key state becomes `idle -> pending -> streaming -> sealing -> idle | error`.
`pending` retains the 0.3-second gate. `streaming` owns one recorder, Feishu stream, and optional
cursor writer. Fn release or the 60-second cap enters `sealing`, closes capture, flushes at most one
audio tail, emits one normal finish, and waits for the final response. A new hold cannot start while
sealing. Reset, sleep/wake, cancellation, or failure advances the session generation before cleanup
so late callbacks are inert.

### Streaming audio boundary

Converted 16 kHz mono signed Int16 PCM is coalesced in capture order into 6,400-byte elements
(about 200 ms) before entering a non-blocking async stream. The retained 60-second cap is
1,920,000 bytes / 300 elements. This is a byte/duration bound, not a raw callback-count bound.
An established stream may pad its final non-empty tail to the 3,200-byte (100 ms) minimum.
Overflow fails the current stream explicitly; the pipeline never drops, reorders, replays, or sends
PCM packets in parallel.

### Streaming transport boundary

`FeishuStreamingSession` is an actor that owns stream ID, cached token snapshot, sequence number,
first-packet acknowledgement, terminal intent, active request, and completion state. It serializes
`action=1` open, `action=0` continuation, `action=2` finish, and bounded best-effort `action=3`
abort requests. A known invalid token may refresh only before the first packet is accepted.
An established stream has no whole-file fallback or whole-audio retry.

Intermediate `recognition_text` is treated as opaque replacement state because Feishu does not
document whether it is delta, cumulative, stabilized, or revisable.

### Cursor-writing boundary

`CursorTextSession` captures the original frontmost PID, focused `AXUIElement`, selected-text
range, and session generation once. A live session requires settable selected-text/range
attributes plus range read-back support. Each non-empty partial replaces one app-owned provisional
range on the captured element:

1. verify generation, process, focused element, caret, and previous range text;
2. select the owned range;
3. set the complete new partial as selected text;
4. read back the resulting caret and text before updating ownership.

The owned range comes from Accessibility's returned ranges, not Swift character counts. Duplicate
partials do nothing; shorter or revised partials replace the complete prior range. Any focus,
selection, caret, text, element, or generation mismatch permanently invalidates that writer.
Late events are dropped and are never redirected to a newly focused control.

The app does not use per-partial clipboard writes, synthetic Backspace, or Shift+Arrow selection.
Unsupported editable elements use a clearly reported final-only path: the stream retains only the
latest opaque response in memory and inserts once through the existing pasteboard path only if the
same target remains focused. A stale fallback target receives no synthetic input. Secure Event
Input and secure text fields are rejected rather than downgraded.

### Finalization and privacy

A non-empty final response replaces the verified provisional range and releases ownership without
synthesizing Return. Empty final or stream failure preserves a last verified visible partial rather
than risk deleting user content after ownership becomes uncertain. A failure before the first
write causes no target mutation.

The overlay remains status-only; target applications are the editing surface. Logs may include
typed state/failure values, generations, sequence numbers, and byte counts, but never transcript
text, audio, credentials/tokens, stream IDs, focused-control contents, application/window titles,
or clipboard payloads.

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

`MainViewModel.handleSystemWillSleep()` and `handleSystemDidWake()` both call the
same idle reset path used for stale transcription cleanup:

- advance the transcription generation and cancel the current transcription
  task;
- hide the overlay;
- call `audioRecorder.forceCleanup()` rather than `stopRecording()`, so stale
  audio is discarded instead of transcribed;
- stop the max-duration timer;
- clear the consecutive-failure counter;
- set coordinator status to `.idle`;
- call `hotKeyService.resetToIdle()`;
- call `FeishuAPIService.resetStateForWake()`.

The wake handler also calls `HotKeyService.recoverAfterWake()` after the API
wake reset.

## HotKeyService — state-machine contract

`HotKeyService` drives the CGEventTap state machine: `idle -> pending (0.3 s) -> recording ->
transcribing -> idle`. The following contract rules (issues #6, #7, #8, #22, #23, #24; see
`docs/decisions/D-6-01.md` and `docs/decisions/D-24-01.md`) keep `HotKeyService` and
`MainViewModel` in sync:

- **`handleFnReleased` is a no-op except in `.recording`.** Calling it from `.transcribing`,
  `.error`, `.cancelled`, or `.idle` performs no transition. Only `.recording → .transcribing`
  is the normal Fn-release path.
- **`forceTranscribing()` drives the max-duration stop path.** When the max-duration timer
  fires, `handleMaxDurationReached` calls `forceTranscribing()`, which transitions
  `.recording → .transcribing` through the state machine. `stopRecordingAndTranscribe()` is
  idempotent so a subsequent Fn-release produces no error.
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

## TextInputSimulator — clipboard-restore contract

`TextInputSimulator` writes transcribed text to `NSPasteboard.general`, sends a synthetic
Cmd+V, then restores the previous clipboard state (issue #13, see
`docs/decisions/D-13-01.md`):

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
  timeout, the simulator restores the pasteboard unconditionally and posts an
  `NSNotification` so the caller can surface a warning to the user.

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
