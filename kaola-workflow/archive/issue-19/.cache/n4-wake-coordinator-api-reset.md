evidence-binding: n4-wake-coordinator-api-reset 7661e48a11f5

Assigned task: n4-wake-coordinator-api-reset reopened adaptive repair ownership.
Write set: FeishuSpeech/App/AppDelegate.swift; FeishuSpeech/ViewModels/MainViewModel.swift; FeishuSpeech/Services/FeishuAPIService.swift; FeishuSpeechTests/MainViewModelTests.swift; FeishuSpeechTests/FeishuAPIServiceTests.swift.
Tests changed: none in this pass; inspected existing MainViewModelTests and FeishuAPIServiceTests repair from main session.
Implementation files changed: none in this pass; current injected AppSettings/HotKeyWakeRecovering repair was sufficient.

RED: Pre-repair/failing signature was the focused direct XCTest issue #19 method set hanging when wake tests instantiated production MainViewModel defaults that touched real AppSettings/Keychain and HotKeyService/CGEventTap; cached failed path included the direct issue #19 new-methods run requiring repair.
GREEN: Current focused validation passes: git diff --check exit 0; xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' build-for-testing exit 0; selected 9 issue #19 direct xcrun xctest methods exit 0 after DerivedData-only FeishuSpeech.debug.dylib rpath symlink, executing 9 tests with 0 failures in 0.004s.
REFACTOR: No additional refactor or source edit was needed; accepted scoped injection repair, including AppSettings() in wake tests, TrackingHotKeyWakeRecoverer, and multi-yield pre-injection replay wait.

Validation results:
- git diff --check: pass.
- xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' build-for-testing: pass.
- bare cached direct xcrun xctest command: tooling/load-path failure before test execution, exit 83, Library not loaded @rpath/FeishuSpeech.debug.dylib.
- direct xcrun xctest same 9 selected issue #19 methods with DerivedData test-bundle Frameworks symlink to app Contents/MacOS/FeishuSpeech.debug.dylib: pass, 9 tests, 0 failures.
Failure classification: direct bare xctest failure was build/type/lint/tooling (runtime loader path), not behavior/test.
