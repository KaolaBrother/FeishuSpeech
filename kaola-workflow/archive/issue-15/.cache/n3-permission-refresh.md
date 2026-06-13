evidence-binding: n3-permission-refresh ca91319445fe
RED: review-blocking repair reproduced order-dependent singleton pollution with `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test -only-testing:FeishuSpeechTests/AudioRecorderFailureTests -only-testing:FeishuSpeechTests/PermissionManagerTests`; AudioRecorderFailureTests.test_viewModelRecorderFailure_cleansUpAndShowsSpecificError failed because PermissionManagerTests left allPermissionsGranted true and MainViewModel later surfaced hot-key permission error.
GREEN: added DEBUG resetStateForTesting() to PermissionManager to reset microphone provider, accessibilityGranted, microphoneGranted, isChecking, allPermissionsGranted, and secureInputEnabled; PermissionManagerTests now calls it in setUp and tearDown.
Focused validation rerun by main session:
- xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test -only-testing:FeishuSpeechTests/AudioRecorderFailureTests -only-testing:FeishuSpeechTests/PermissionManagerTests => TEST SUCCEEDED; 11 tests passed.
- git diff --check -- FeishuSpeech/Services/PermissionManager.swift FeishuSpeech/App/AppDelegate.swift FeishuSpeechTests/PermissionManagerTests.swift => passed.
Delegated validation also reported PermissionManagerTests, full xcodebuild test, and Debug build passed; swiftlint unavailable, command not found.
Changed files in repair: FeishuSpeech/Services/PermissionManager.swift and FeishuSpeechTests/PermissionManagerTests.swift. AppDelegate.swift remains changed from original n3 implementation.
