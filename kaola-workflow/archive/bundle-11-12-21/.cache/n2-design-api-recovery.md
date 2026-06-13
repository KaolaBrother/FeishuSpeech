evidence-binding: n2-design-api-recovery 857d8a3e6ddf
architecture_decisions

- Scope n3 as one serial TDD task because FeishuAPIService.swift, SpeechResult.swift, FeishuAPIServiceTests.swift, and project.pbxproj are shared by #11/#12/#21.
- Keep behavior in existing FeishuAPIService actor and private direct HTTP client; expose only minimal DEBUG/internal test hooks or pure helpers for @testable import.
- Direct HTTP completion should use a completeness-aware parser: finish early on complete Content-Length body or terminal chunked body, preserve close-delimited parse on isComplete, and on timeout attempt a complete parse before throwing timeout.
- Auth expiry should decode AuthResponse.expire tolerantly, use expire - 300s when valid, and fall back to the current 6000s behavior when absent/invalid.
- Cancellation should be explicit: Task.checkCancellation at retry loop/IP loop boundaries and immediate CancellationError rethrow before API/generic retry handling or fallback.

test_plan

- Add FeishuSpeechTests/FeishuAPIServiceTests.swift.
- Cover AuthResponse expire decode, expiry helper expire-minus-margin, fallback expiry, direct Content-Length completion, short Content-Length incomplete, terminal chunked completion, timeout parse fallback, withRetry CancellationError propagation after one attempt, and direct IP loop no-next-IP/no-fallback on cancellation.
- Use deterministic injected closures/test hooks; no live Feishu network calls and no MockURLProtocol dependency.

implementation_steps

1. Wire a macOS unit test bundle target FeishuSpeechTests in FeishuSpeech.xcodeproj/project.pbxproj, including synchronized test root and host app/test settings as needed for xcodebuild test.
2. Add expire: Int? to AuthResponse, with tolerant decoding if required.
3. In FeishuAPIService.swift add fallback/safety constants, expiry helper, completeness-aware response parser, timeout fallback parse, and cancellation short-circuiting in retry/direct request paths.
4. Add focused FeishuAPIServiceTests with RED/GREEN evidence and run focused then full validation.

validation_commands

- xcodebuild -list -project FeishuSpeech.xcodeproj
- xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test -only-testing:FeishuSpeechTests/FeishuAPIServiceTests
- xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test
- xcodebuild -scheme FeishuSpeech -configuration Debug build
- swiftlint

risks

- If scheme/test target requires files outside n3 write set, route back to orchestrator.
- Newly activated existing tests may fail due unrelated pre-existing code; distinguish target wiring from product regression.
- Parser must not treat incomplete bodies as invalid/complete prematurely.
- Cancellation tests should assert attempt counts, not only final thrown error.
