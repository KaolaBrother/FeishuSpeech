evidence-binding: n2-audio-recorder-fail-fast 0b9a0505fcc0
RED: review-blocking repair added test_backgroundRuntimeError_cleansUpRecorderOnMainThread; delegated TDD run confirmed AudioRecorderFailureTests failed before repair because off-main failure delivery could call forceCleanup before hopping to main.
GREEN: abortRecording(with:) now dispatches to main before calling forceCleanup() or publishing failure; forceCleanup still stops AVCaptureSession on sessionQueue. Added non-main failure regression coverage in AudioRecorderFailureTests.
Focused validation rerun by main session:
- xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test -only-testing:FeishuSpeechTests/AudioRecorderFailureTests => TEST SUCCEEDED; 4 AudioRecorderFailureTests passed.
- git diff --check -- FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/ViewModels/MainViewModel.swift FeishuSpeechTests/AudioRecorderRecoveryTests.swift FeishuSpeechTests/MainViewModelTests.swift => passed.
Delegated validation also reported full xcodebuild test and Debug build passed; swiftlint unavailable, command not found.
Changed files in repair: FeishuSpeech/Services/AudioRecorder.swift and FeishuSpeechTests/MainViewModelTests.swift. MainViewModel.swift remains changed from the original n2 implementation.
