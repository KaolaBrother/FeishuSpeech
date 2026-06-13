evidence-binding: n3-hotkey-wake-health 37aafd330068

RED: Added HotKeyServiceTests wake recovery expectations first; pre-implementation focused test failed because HotKeyService had no recoverAfterWakeForTesting hook.
GREEN: Implemented HotKeyService.recoverAfterWake(), private CGEvent.tapIsEnabled health helper, stale wake input reset, and DEBUG recoverAfterWakeForTesting hook.
REFACTOR: Kept behavior scoped to wake recovery and DEBUG test hook/result type; no unrelated HotKeyService changes.
changed_files: FeishuSpeech/Services/HotKeyService.swift, FeishuSpeechTests/HotKeyServiceTests.swift
validation: xcodebuild -scheme FeishuSpeech -configuration Debug build passed
validation: xcodebuild -scheme FeishuSpeech -destination platform=macOS build-for-testing passed
validation: git diff --check -- FeishuSpeech/Services/HotKeyService.swift FeishuSpeechTests/HotKeyServiceTests.swift passed
caveat: focused app-host xcodebuild test hung after build/test launch; hanging FeishuSpeech test host processes were cleaned up
