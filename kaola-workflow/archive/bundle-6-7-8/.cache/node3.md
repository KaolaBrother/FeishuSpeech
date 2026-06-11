RED: test_forceTranscribing_fromRecording_transitionsToTranscribing / test_forceTranscribing_whenAlreadyTranscribing_isNoOp -- compile error: forceTranscribing() did not exist yet
GREEN: both tests pass; forceTranscribing() transitions .recording -> .transcribing and is no-op when already .transcribing; all prior tests still green

Changes:
- HotKeyService.swift: added func forceTranscribing() after forceState(); .recording/.pending -> .transcribing; others no-op
- MainViewModel.swift: handleMaxDurationReached() now calls hotKeyService.forceTranscribing() only (no direct stopRecordingAndTranscribe); stopRecordingAndTranscribe() has isRecording idempotency guard
- HotKeyServiceTests.swift: added test_forceTranscribing_fromRecording_transitionsToTranscribing and test_forceTranscribing_whenAlreadyTranscribing_isNoOp

Build clean. All tests green.
