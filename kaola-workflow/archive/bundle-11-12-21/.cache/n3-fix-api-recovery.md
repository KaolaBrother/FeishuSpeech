evidence-binding: n3-fix-api-recovery 86b4979113a5
assigned_task: n3-fix-api-recovery repair after adversarial R1/R2
write_set:
  - FeishuSpeech/Services/FeishuAPIService.swift
  - FeishuSpeech/Models/SpeechResult.swift
  - FeishuSpeechTests/FeishuAPIServiceTests.swift
  - FeishuSpeech.xcodeproj/project.pbxproj
changed_files:
  - FeishuSpeech/Services/FeishuAPIService.swift
  - FeishuSpeech/Models/SpeechResult.swift
  - FeishuSpeechTests/FeishuAPIServiceTests.swift
  - FeishuSpeech.xcodeproj/project.pbxproj
changes:
  - Direct HTTP parsing completes on full Content-Length bodies and terminal chunked bodies, preserving close-delimited parsing for connection close.
  - Timeout path attempts to parse a complete buffered response before throwing timeout; incomplete bodies still throw timeout.
  - AuthResponse decodes Feishu expire; token lifetime uses expire - 300 seconds for positive expire values and 6000 seconds only when expire is absent or non-positive invalid.
  - withRetry and direct-IP request loop rethrow CancellationError/Task cancellation without retrying, trying later IPs, or falling back.
  - FeishuSpeechTests target now runs FeishuAPIServiceTests plus older passing HotKey/MainViewModel/Permission/EmptyResult tests; only AudioRecorderRecoveryTests.swift is excluded as a reproduced pre-existing/out-of-scope blocker.
RED:
  - Initial focused API test failed before implementation with missing AuthResponse.expire, parser/retry/direct-request test hooks, and DirectHTTPResponse test access.
  - Repair RED: FeishuAPIServiceTests.test_tokenLifetimeForShortPositiveExpire_expiresImmediatelyInsteadOfDefaultFallback failed while expire 299 still returned 6000s.
  - Project wiring RED: full xcodebuild test failed with all tests visible only in AudioRecorderRecoveryTests.test_scenarioA_staleRecordingFlag_isResetBeforeStartAttempt, outside this node write set.
GREEN:
  - xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test -only-testing:FeishuSpeechTests/FeishuAPIServiceTests passed independently; 13 FeishuAPIServiceTests passed including short positive expire.
  - xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test passed independently; output visibly ran FeishuAPIServiceTests, HotKeyServiceTests, HotKeyStateTests, MainViewModelTests, EmptyResultFeedbackTests, and PermissionManagerTests.
  - xcodebuild -scheme FeishuSpeech -configuration Debug build passed independently.
REFACTOR:
  - Scoped cleanup/config only; no broad refactor. Project wiring excludes only the reproduced pre-existing AudioRecorderRecoveryTests file.
validation:
  - xcodebuild -list -project FeishuSpeech.xcodeproj: passed; FeishuSpeech and FeishuSpeechTests listed
  - xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test -only-testing:FeishuSpeechTests/FeishuAPIServiceTests: passed; 13 tests
  - xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test: passed; older passing suites visible
  - xcodebuild -scheme FeishuSpeech -configuration Debug build: passed
  - git diff --check: passed
  - swiftlint: not run; binary not found on PATH
residual_risk:
  - swiftlint unavailable on this machine/PATH.
  - AudioRecorderRecoveryTests.test_scenarioA_staleRecordingFlag_isResetBeforeStartAttempt remains a reproduced pre-existing/out-of-scope blocker excluded from this bundle's test target; it should be repaired under an AudioRecorder-owned issue before re-enabling that suite.
