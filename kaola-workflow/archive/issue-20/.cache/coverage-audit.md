evidence-binding: coverage-audit 500c5ed3f824

# coverage-audit evidence

## Facts

### 1. FeishuAPIService HTTP parser and API-test seams

- `FeishuSpeech/Services/FeishuAPIService.swift:24-36` defines `DirectHTTPResponse`, `DirectRequestSender`, and `URLSessionRequestSender`; the sender typealiases are private and only injectable through test-only wrappers today.
- `FeishuSpeech/Services/FeishuAPIService.swift:214-230` exposes direct HTTP parsing stages internally: complete response, close-delimited response, and timeout-buffer parsing.
- `FeishuSpeech/Services/FeishuAPIService.swift:232-270` parses status line, headers, chunked bodies, content-length bodies, and close-delimited bodies. Header names are lowercased in `parseHeaders` at `FeishuSpeech/Services/FeishuAPIService.swift:272-284`.
- `FeishuSpeech/Services/FeishuAPIService.swift:286-332` decodes chunked bodies, including `;` chunk extensions (`sizeLine.split(separator: ";", maxSplits: 1)`) and trailers/terminal CRLF handling.
- `FeishuSpeech/Services/FeishuAPIService.swift:392-465` has DEBUG test hooks for token lifetime, direct parser stages, network availability seeding, state snapshot, `withRetry`, and direct/fallback sender injection.
- `FeishuSpeech/Services/FeishuAPIService.swift:478-483` wraps full `recognizeSpeech` in `withRetry`, but `getAccessToken` and `sendSpeechRequest` remain private and use private `sendDirectRequest`.
- `FeishuSpeech/Services/FeishuAPIService.swift:529-567` implements token cache/reuse/expiry after auth success.
- `FeishuSpeech/Services/FeishuAPIService.swift:590-599` clears cached token and expiry on speech HTTP 400/401 before throwing `APIError.httpError`.
- `FeishuSpeech/Services/FeishuAPIService.swift:628-693` supports injected direct/fallback senders only inside private `sendDirectRequest`; DEBUG `sendDirectRequestForTesting` at `FeishuSpeech/Services/FeishuAPIService.swift:447-464` exercises this helper with auth path and empty body, not the auth/speech business flows.
- `FeishuSpeech/Services/FeishuAPIService.swift:695-713` has a URLSession fallback using `URLSession.shared`, so `URLProtocol`-based mocking cannot hook it unless the code gains an injectable `URLSession` or protocol-class configuration.

Existing tests:

- `FeishuSpeechTests/FeishuAPIServiceTests.swift:15-29` covers `AuthResponse.expire` decoding.
- `FeishuSpeechTests/FeishuAPIServiceTests.swift:31-53` covers token lifetime math and default fallback behavior.
- `FeishuSpeechTests/FeishuAPIServiceTests.swift:55-72` covers complete and incomplete content-length parsing.
- `FeishuSpeechTests/FeishuAPIServiceTests.swift:74-93` covers complete and unterminated chunked response parsing.
- `FeishuSpeechTests/FeishuAPIServiceTests.swift:95-103` covers close-delimited parsing behavior.
- `FeishuSpeechTests/FeishuAPIServiceTests.swift:105-121` covers timeout-buffer parsing for complete content-length and timeout error for incomplete content-length.
- `FeishuSpeechTests/FeishuAPIServiceTests.swift:123-141` covers `withRetryForTesting` cancellation short-circuit only.
- `FeishuSpeechTests/FeishuAPIServiceTests.swift:143-170` covers direct sender cancellation short-circuit, no later IPs, no fallback.
- `FeishuSpeechTests/FeishuAPIServiceTests.swift:172-188` covers wake reset clearing token/network-error state.

Remaining API gaps:

- Direct HTTP parser gaps: malformed status line, invalid/negative content-length, malformed chunk size, missing chunk CRLF, chunk extensions/trailers, extra bytes after content-length/keep-alive style responses, truncated headers/no delimiter, and non-UTF8 headers are not covered.
- Chunked decoding has partial coverage only; terminal chunk and missing terminal chunk are covered, but malformed chunk framing and extension/trailer behavior are not.
- Timeout coverage is only `parseBufferedResponseBeforeTimeout`; no test drives the real async timeout scheduled in `DirectFeishuHTTPClient.send` at `FeishuSpeech/Services/FeishuAPIService.swift:196-202` or cancellation of `NWConnection` through `CancelBox` at `FeishuSpeech/Services/FeishuAPIService.swift:100-211`.
- Retry gaps: no test covers retriable `APIError` retry count, non-retriable short-circuit, generic error retry, exhausted retry returning last error, network-unavailable preflight inside retry, or delay behavior. Current seam sleeps real 1s/2s delays at `FeishuSpeech/Services/FeishuAPIService.swift:506-521` unless a later seam bypasses/injects sleep.
- Token caching gaps: no test covers auth request success populating cache, cached-token reuse, expired token refresh, auth HTTP errors, auth payload `code != 0`, or speech flow using the cached token. Current hooks can seed/snapshot token state but cannot inject a full auth/speech transport through `recognizeSpeech`.
- Speech 400/401 invalidation gap: behavior exists at `FeishuSpeech/Services/FeishuAPIService.swift:590-599`, but no test can currently fake the private speech request path without a new or expanded test seam.

Smallest viable API test seams for later nodes:

- Parser edge cases can use existing static hooks at `FeishuSpeech/Services/FeishuAPIService.swift:404-415`; no production transport seam is needed for those.
- Retry behavior can use `withRetryForTesting` at `FeishuSpeech/Services/FeishuAPIService.swift:443-445`, but deterministic fast tests need a way around real `Task.sleep` delays.
- Full auth/token/speech tests need a fakeable send path above `getAccessToken` and `sendSpeechRequest`; the existing `sendDirectRequestForTesting` only tests the lower transport loop and cannot drive `recognizeSpeech` end-to-end.

### 2. MockURLProtocol status

- `FeishuSpeechTests/MockURLProtocol.swift:5-83` defines `MockURLProtocol`, `MockResponse`, and `MockError`.
- `rg` found references only in `MockURLProtocol.swift` itself; no test registers `MockURLProtocol`, no `URLSessionConfiguration.protocolClasses` is configured, and no app code imports it.
- The Xcode build file list generated during the audit includes `FeishuSpeechTests/MockURLProtocol.swift`, so it is compiled into the test target. Derived evidence: `FeishuSpeechTests.SwiftFileList:5` contains the file and `FeishuSpeechTests-OutputFileMap.json:49-57` has object outputs for it.
- Current app fallback uses `URLSession.shared` at `FeishuSpeech/Services/FeishuAPIService.swift:708`, so the existing mock is still dead for current tests. It could only be repurposed if a later seam makes URLSession/configuration injectable; otherwise deletion is a cleanup decision for the planner/executor.

### 3. HotKeyService/MainViewModel interplay coverage after issue #19

Issue body facts:

- Issue #1: stale recorder session/reset recovery.
- Issue #6: Fn release during `.transcribing` reset the state machine and allowed concurrent sessions.
- Issue #7: max-duration auto-stop desynced HotKeyService and MainViewModel, causing duplicate stop/transcribe on later Fn release.
- Issue #8: `startHotKeyMonitoring` leaked `$state` subscriptions across permission cycles.

Current code/test facts:

- `FeishuSpeech/Services/HotKeyService.swift:317-331` makes Fn release during `.transcribing`, `.error`, `.cancelled`, and `.idle` a no-op.
- `FeishuSpeechTests/HotKeyServiceTests.swift:108-123` directly covers issue #6 at the HotKeyService state level.
- `FeishuSpeech/Services/HotKeyService.swift:360-372` implements `forceTranscribing()` for max-duration and makes `.recording`/`.pending` transition to `.transcribing`, while `.transcribing` is ignored.
- `FeishuSpeechTests/HotKeyServiceTests.swift:76-106` covers issue #7 at the HotKeyService state level.
- `FeishuSpeech/ViewModels/MainViewModel.swift:397-401` routes max-duration through `hotKeyService.forceTranscribing()` and guards on `audioRecorder.isRecording`.
- `FeishuSpeech/ViewModels/MainViewModel.swift:245-249` makes `stopRecordingAndTranscribe()` idempotent when the recorder is not recording.
- `FeishuSpeech/ViewModels/MainViewModel.swift:34-39`, `FeishuSpeech/ViewModels/MainViewModel.swift:90-118` store the hotkey `$state` subscription in a dedicated `stateCancellable` and nil it on stop.
- `FeishuSpeechTests/MainViewModelTests.swift:10-21` documents issue #8, and `FeishuSpeechTests/MainViewModelTests.swift:33-120` covers state cancellable nil-after-stop, replacement on restart, and cleanup release.
- `FeishuSpeechTests/AudioRecorderRecoveryTests.swift:9-13`, `FeishuSpeechTests/AudioRecorderRecoveryTests.swift:28-60`, `FeishuSpeechTests/AudioRecorderRecoveryTests.swift:64-85`, and `FeishuSpeechTests/AudioRecorderRecoveryTests.swift:89-112` are intended to cover issue #1 stale session and reset recovery, but this file is not currently compiled into the test bundle due to project wiring (see section 4).
- `FeishuSpeechTests/MainViewModelTests.swift:435-459` separately covers recorder failure cleanup and no stop/transcribe after a mid-recording failure; this file is compiled.
- Issue #19 wake recovery tests added coverage in `FeishuSpeechTests/HotKeyServiceTests.swift:332-373` and `FeishuSpeechTests/MainViewModelTests.swift:122-162`, including wake reset of token state and hotkey recovery.

Interplay tests still missing:

- #6 is covered only at HotKeyService state level; no MainViewModel-level test proves a stale transcription error cannot call `hotKeyService.setError` over a new active recording. Existing MainViewModel code has a guard at `FeishuSpeech/ViewModels/MainViewModel.swift:327-330`, but there is no direct test for that race.
- #7 is covered only at HotKeyService state level and by code guards; no MainViewModel-level test proves max-duration `forceTranscribing` results in exactly one `stopRecording()` and that a later Fn release does not trigger a second transcription/empty-buffer error.
- #8 tests prove the `AnyCancellable?` lifecycle, but they do not count `handleHotKeyState` side effects across repeated start/stop cycles. A focused test seam could count recording starts/stops or expose subscription event count without real CGEventTap.
- #1 intended tests are present on disk but not active in the compiled test target; until wiring is fixed, stale-recorder recovery coverage is only partial through `MainViewModelTests.swift:435-459`.

Smallest viable state/interplay seams for later nodes:

- Existing test helpers already support forcing hotkey state (`FeishuSpeech/Services/HotKeyService.swift:352-357`), forcing transcribing (`FeishuSpeech/Services/HotKeyService.swift:360-372`), simulating monitoring state (`FeishuSpeech/Services/HotKeyService.swift:450-471`), and wake recovery (`FeishuSpeech/Services/HotKeyService.swift:511-528`).
- MainViewModel exposes `handleMonitoringStateForTesting` at `FeishuSpeech/ViewModels/MainViewModel.swift:199-203`, but `handleHotKeyState`, `handleMaxDurationReached`, and the transcription task path are private. Later tests may need narrow DEBUG hooks or injected collaborators to observe exactly-once stop/transcribe and stale-result discard without real API calls.
- `AudioRecorder` subclassing is already used as the local fake pattern in `FeishuSpeechTests/MainViewModelTests.swift:462-510` and `FeishuSpeechTests/AudioRecorderRecoveryTests.swift:126-139`.

### 4. Xcode project/test target wiring

- `FeishuSpeech.xcodeproj/project.pbxproj:31-47` uses `PBXFileSystemSynchronizedRootGroup` for `FeishuSpeech` and `FeishuSpeechTests`, so files in those folders are generally auto-included.
- `FeishuSpeech.xcodeproj/project.pbxproj:22-28` defines an exception set for the `FeishuSpeechTests` target with `membershipExceptions = ( AudioRecorderRecoveryTests.swift, );`.
- The generated `FeishuSpeechTests.SwiftFileList` from the audit build contains AppSettingsCredentialStorageTests, FeishuAPIServiceTests, HotKeyServiceTests, MainViewModelTests, MockURLProtocol, and PermissionManagerTests, but not AudioRecorderRecoveryTests. This confirms `AudioRecorderRecoveryTests.swift` is currently excluded from compilation/test execution.
- `FeishuSpeech.xcodeproj/project.pbxproj:200-214` has empty explicit PBXSources build phases because synchronized folders drive membership.
- `FeishuSpeech.xcodeproj/project.pbxproj:408-430` configures the test target as a hosted app test bundle (`TEST_HOST = .../FeishuSpeech.app/...`). Targeted test run evidence: `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test -only-testing:FeishuSpeechTests/FeishuAPIServiceTests` built but failed after 325s with `The test runner hung before establishing connection.` A concurrent `AudioRecorderRecoveryTests` probe was interrupted after the hang was detected, so runtime discovery could not prove test execution.

## Assumptions

- The generated Swift file list from DerivedData reflects current Xcode membership for this worktree after the audit build.
- Since this is a read-only node, deletion vs repurposing of `MockURLProtocol` is left for planner/executor decision; the factual state is that it is compiled but unreferenced and does not hook current `URLSession.shared` usage.

## Unknowns / blockers for reliable implementation planning

- Full test execution is blocked by hosted app test-runner hang in this environment; a later node should either fix/route the test-host hang or use a narrower build/discovery command before relying on runtime pass/fail.
- The exact best seam for full `recognizeSpeech` auth/token/speech testing depends on how much production API surface the executor is allowed to expose under DEBUG versus dependency injection.
