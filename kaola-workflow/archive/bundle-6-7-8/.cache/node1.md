## Architecture: State-Machine Contract for bundle-6-7-8 (#6, #7, #8)

### Summary

Read-only architecture analysis. Designed 4-point contract reconciling HotKeyService and MainViewModel state machines for issues #6, #7, #8.

### Key Findings

- `handleFnReleased` default branch resets to `.idle` from `.transcribing` — root cause #6
- `handleMaxDurationReached` calls `stopRecordingAndTranscribe()` without transitioning state → double-stop on Fn release — root cause #7
- `$state` subscription stored in shared `Set<AnyCancellable>` never removed in `stopHotKeyMonitoring` — root cause #8

### Four Contract Decisions

**(a) handleFnReleased guard (node2):** Replace catch-all `default: state = .idle` with explicit `.transcribing`/`.error`/`.cancelled`/`.idle` → no-op cases. Only `.recording` transitions to `.transcribing`.

**(b) forceTranscribing() event (node3):** Add `func forceTranscribing()` to HotKeyService (guards on `.recording`/`.pending`). `handleMaxDurationReached` calls ONLY `hotKeyService.forceTranscribing()` — the `.transcribing` publish routes through the `$state` sink to `stopRecordingAndTranscribe()`. Also make `stopRecordingAndTranscribe()` idempotent (guard on `audioRecorder.isRecording`).

**(c) setError gating (node2):** Gate in `transcribeAudio` catch block in MainViewModel: `if hotKeyService.state.isActive { return }` before setting `status = .error` / calling `setError`. Do NOT gate inside `HotKeyService.setError` (would suppress legitimate config/permission/mic errors that fire while `.recording`).

**(d) $state subscription ownership (node4):** Add `private var stateCancellable: AnyCancellable?`. `startHotKeyMonitoring` assigns to it. `stopHotKeyMonitoring` sets it to `nil` before `hotKeyService.stopMonitoring()`.

### Critical Edge Cases

- Only `handleFnReleased`(from `.recording`) and `forceTranscribing` may enter `.transcribing`.
- `stopRecordingAndTranscribe` MUST be idempotent (guard on `audioRecorder.isRecording`).
- `setError` gating must be at the `transcribeAudio` catch site only, NOT inside `HotKeyService.setError` (avoids suppressing legitimate fresh-session errors from `canStartRecording`/`handleRecordingState`).
- `handleFnReleased` no-op on `.transcribing` combined with `forceTranscribing` publishing `.transcribing` eliminates double-stop without `stopRecordingAndTranscribe` being called twice.
