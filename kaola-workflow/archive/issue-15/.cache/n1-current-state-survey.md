evidence-binding: n1-current-state-survey 98ac20b7df1b
current_behavior:
  - AudioRecorder publishes isRecording only; it has no failure/error channel for mid-recording runtime failures.
  - startRecording configures AVCaptureSession and starts it on sessionQueue but does not register AVCaptureSession runtime/interruption/device-loss notifications.
  - conversionErrorCount increments on sample/converter problems; once maxConversionErrors is reached captureOutput silently returns for the rest of the session.
  - MainViewModel only maps startRecording() false to "无法启动录音" and does not observe recorder failures while recording.
  - PermissionManager checks microphone authorization in checkAllPermissions() only; refreshAccessibilityStatus()/refreshSecureInputStatus() exist but no mic refresh method exists.
  - AppDelegate's 2s poll refreshes accessibility and secure input only.
files_for_n2:
  - FeishuSpeech/Services/AudioRecorder.swift
  - FeishuSpeech/ViewModels/MainViewModel.swift
  - FeishuSpeechTests/AudioRecorderRecoveryTests.swift
  - FeishuSpeechTests/MainViewModelTests.swift
files_for_n3:
  - FeishuSpeech/Services/PermissionManager.swift
  - FeishuSpeech/App/AppDelegate.swift
  - FeishuSpeechTests/PermissionManagerTests.swift
recommended_test_seams:
  - Add device-free test seams for runtime error/interruption/device-loss and conversion-exhaustion failure signals.
  - Deliver recorder failure to MainViewModel on the main actor before mutating status/cleanup.
  - Add a PermissionManager mic authorization provider/test hook analogous to existing secure-input simulation.
risks:
  - AudioRecorderRecoveryTests.swift is listed as a membership exception in the FeishuSpeechTests synchronized group; tests placed only there may not run without project.pbxproj changes, which are outside n2 write set.
  - AudioRecorder cleanup is async on sessionQueue while buffer cleanup is synchronous; failure handling must avoid sample-buffer/cleanup races.
  - Exact Chinese strings for runtime/interruption/conversion errors are not specified by the issue; implementation must choose specific accurate messages and test them.
validation_commands:
  - xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test -only-testing:FeishuSpeechTests/MainViewModelTests
  - xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test -only-testing:FeishuSpeechTests/PermissionManagerTests
  - xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test
  - xcodebuild -scheme FeishuSpeech -configuration Debug build
  - swiftlint
no_edits_made: true
