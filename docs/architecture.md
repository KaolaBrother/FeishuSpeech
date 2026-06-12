# Architecture

Document system boundaries, major components, data flow, and deployment shape.

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

## HotKeyService — state-machine contract

`HotKeyService` drives the CGEventTap state machine: `idle → pending (0.3 s) → recording →
transcribing → idle`. The following contract rules (issue #6, #7, #8; see
`docs/decisions/D-6-01.md`) keep `HotKeyService` and `MainViewModel` in sync:

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
and surfaces `.failed` as an error status. The retry policy is unbounded capped exponential
backoff (1 s → 2 s → … → 30 s cap) instead of the previous hard 3-attempt limit.

**`previousFlags` lifecycle**

`stopMonitoring()` resets `previousFlags` to `.init()` so a restart begins with a clean
key-flag baseline. After each backoff delay, `CGEventSource.flagsState(.combinedSessionState)`
is sampled to detect a held Fn key and cancel any stale pending/recording state before the
tap is re-created.

**Secure keyboard entry**

`PermissionManager` polls `IsSecureEventInputEnabled()` every 2 seconds. When active, the
menu bar shows an orange "安全输入已启用，热键暂不可用" warning (issue #10). The hotkey
suppression itself is enforced by the OS kernel; detection and display is the only recourse.

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
