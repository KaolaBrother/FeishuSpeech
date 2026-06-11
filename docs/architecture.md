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
