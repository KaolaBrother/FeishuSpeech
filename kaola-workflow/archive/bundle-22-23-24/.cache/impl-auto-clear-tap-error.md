evidence-binding: impl-auto-clear-tap-error 1e337cb6e03b
Assigned task: impl-auto-clear-tap-error
write_set:
  - FeishuSpeech/Services/HotKeyService.swift
  - FeishuSpeech/ViewModels/MainViewModel.swift
  - FeishuSpeechTests/MainViewModelTests.swift
changed_files:
  - FeishuSpeech/Services/HotKeyService.swift
  - FeishuSpeech/ViewModels/MainViewModel.swift
  - FeishuSpeechTests/MainViewModelTests.swift
summary:
  - HotKeyService.forceState(_:) is now DEBUG-only.
  - MainViewModel.cleanup() routes through stopHotKeyMonitoring(); stopHotKeyMonitoring() always nils stateCancellable.
  - MainViewModel records the specific hot-key monitoring error and auto-clears only that stale error when monitoringState becomes .active.
  - MainViewModelTests now cover accessibilityNotTrusted/tapCreationFailed error mapping, auto-clear recovery, unrelated error preservation, and cleanup releasing stateCancellable.
RED:
  - xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test -only-testing:FeishuSpeechTests/MonitoringStateBindingTests -only-testing:FeishuSpeechTests/MainViewModelTests/test_cleanup_releasesStateCancellable failed before implementation with missing handleMonitoringStateForTesting hook.
GREEN:
  - xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test -only-testing:FeishuSpeechTests/MonitoringStateBindingTests -only-testing:FeishuSpeechTests/MainViewModelTests/test_cleanup_releasesStateCancellable passed after implementation.
  - xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test passed in the delegated node run.
  - xcodebuild -scheme FeishuSpeech -configuration Debug build passed in the delegated node run.
  - xcodebuild -scheme FeishuSpeech -configuration Release build passed in the delegated node run.
  - git diff --check -- FeishuSpeech/Services/HotKeyService.swift FeishuSpeech/ViewModels/MainViewModel.swift FeishuSpeechTests/MainViewModelTests.swift passed independently in main session.
validation:
  - swiftlint not run; binary unavailable on PATH in delegated node run.
