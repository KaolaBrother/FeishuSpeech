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
