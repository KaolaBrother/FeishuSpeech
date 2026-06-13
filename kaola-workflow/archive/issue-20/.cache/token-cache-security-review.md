evidence-binding: token-cache-security-review d095f8d29f88
verdict: pass
findings_blocking: 0

# Security Review - issue #20 token-cache-security-review

## Verdict
APPROVE. No blocking security or privacy findings found.

## Findings
### CRITICAL
none

### HIGH
none

### MEDIUM
none

### LOW
none

## Scope Reviewed
- FeishuAPIService DEBUG seams: `TestDirectRequestSender` and `TestRetrySleeper` are declared only inside `#if DEBUG` at `FeishuSpeech/Services/FeishuAPIService.swift:38`; actor-injected sender/sleeper storage is DEBUG-only at `FeishuSpeech/Services/FeishuAPIService.swift:349`; path/reset/parser/accessor testing APIs are inside the DEBUG-only testing block at `FeishuSpeech/Services/FeishuAPIService.swift:402`. The runtime retry and direct-request paths consult injected seams only inside DEBUG branches at `FeishuSpeech/Services/FeishuAPIService.swift:564` and `FeishuSpeech/Services/FeishuAPIService.swift:658`. Release build settings show no `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG`.
- Token cache invalidation: speech 400/401 responses clear `cachedToken` and `tokenExpiry` before throwing retriable `httpError`, so retry obtains a fresh token instead of reusing the stale one at `FeishuSpeech/Services/FeishuAPIService.swift:635`. No cached token value is exposed by testing snapshots; token-state access remains boolean-only at `FeishuSpeech/Services/FeishuAPIService.swift:469`.
- Mock/test data: `MockFeishuRequestSequence` records path, headers, and body in memory only and has no logging or persistence path at `FeishuSpeechTests/MockURLProtocol.swift:20`. The bearer tokens in `FeishuSpeechTests/FeishuAPIServiceTests.swift:337` and `FeishuSpeechTests/FeishuAPIServiceTests.swift:386` are test literals (`cached-token`, `stale-token`, `fresh-token`), and audio inputs are byte literals (`Data([1, 2])`, `Data([3, 4])`) rather than user data.
- MainViewModel DEBUG hooks: test-only entrypoints are DEBUG-gated at `FeishuSpeech/ViewModels/MainViewModel.swift:137`, `FeishuSpeech/ViewModels/MainViewModel.swift:352`, and `FeishuSpeech/ViewModels/MainViewModel.swift:424`. The production hot-key subscription still calls `handleHotKeyState(state)` with the default `startsTranscriptionTask: true` at `FeishuSpeech/ViewModels/MainViewModel.swift:97`, and the new error helper does not broaden recognized-text/audio access beyond the pre-existing logging behavior.
- Concurrency/Sendable: actor-injected closures are `@Sendable` and actor-isolated; the test request sequence uses an `NSLock` around mutation and the accessor helpers used by tests. No production data race or token exposure path was found.

## Validation Reviewed
- `git diff --stat` and focused hunks for `FeishuAPIService.swift`, `MainViewModel.swift`, `FeishuAPIServiceTests.swift`, `MainViewModelTests.swift`, and `MockURLProtocol.swift`.
- Secret-pattern scan found only source field names and fake test literals, not real credentials.
- `xcodebuild -scheme FeishuSpeech -configuration Debug -showBuildSettings` confirms DEBUG is active for Debug; `xcodebuild -scheme FeishuSpeech -configuration Release -showBuildSettings` produced no DEBUG active compilation condition.
