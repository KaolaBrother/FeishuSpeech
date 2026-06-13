evidence-binding: test-seam-plan 671a0d5519db
# Test Seam Plan — issue #20

## Success Criteria

- `api-http-retry-tests` adds focused API coverage for parser malformed cases, deterministic retry behavior, token cache reuse, and speech 400/401 token invalidation without making live network calls or sleeping real retry delays.
- `state-interplay-tests` adds coordinator-level HotKeyService/MainViewModel interplay coverage that is still missing after #19, without re-testing already-covered raw state transitions and without touching `FeishuSpeech.xcodeproj/project.pbxproj`.
- No production/test source outside the frozen write sets is touched. `AudioRecorderRecoveryTests.swift` target membership is recorded as an out-of-scope follow-up unless the state lane duplicates a minimal compiled test inside `MainViewModelTests.swift`.

## Approaches Evaluated

### Option A: Keep tests at current public/DEBUG-hook surface only

Summary: Add parser tests through existing static parser hooks and add a few state tests that only use existing `HotKeyService.forceState`, `forceTranscribing`, and MainViewModel monitoring hooks.

Pros:
- Lowest production change volume.
- Very low behavior risk.
- No new dependency-injection surface.

Cons:
- Cannot drive `recognizeSpeech` through auth + speech business logic.
- Cannot verify speech 400/401 invalidates cached token and refreshes on retry.
- Retry tests still sleep real 1s/2s delays through `Task.sleep`.
- MainViewModel stale-transcription and exactly-once stop behavior remain hard to observe deterministically.

Risk/complexity: Low complexity, but high residual coverage gap. This does not satisfy the issue's core API and interplay goals.

What not to build here: Do not pretend `MockURLProtocol` gives coverage; current code uses direct `NWConnection` and `URLSession.shared`, so URLProtocol is not in the path.

### Option B: Add narrow DEBUG-only seams at existing private boundaries

Summary: Keep runtime behavior unchanged, but add test-only hooks exactly where current code blocks deterministic tests: a no-op/recording retry sleeper, a high-level fake sender used by `sendDirectRequest(path:headers:body:)`, and tiny MainViewModel DEBUG hooks/extractions for private coordinator paths. Repurpose `MockURLProtocol.swift` into a small request-sequence fake for the API lane.

Pros:
- Tests exercise real `recognizeSpeech`, `getAccessToken`, `sendSpeechRequest`, cache invalidation, and retry orchestration without network.
- Retry assertions can record intended delays `[1.0, 2.0]` without real sleeping.
- State tests can validate coordinator effects that HotKeyService-only tests cannot see.
- All source changes stay inside frozen write sets.
- Test seams are compiled only under `#if DEBUG` and do not alter release behavior.

Cons:
- Adds small test-only surface to production files.
- Singleton actor/service state must be carefully reset in test `tearDown`.
- The existing hosted xcodebuild runner may still hang, so validation needs compile gates and focused direct runner attempts.

Risk/complexity: Moderate but bounded. This is the best fit for the evidence because it closes the named gaps with the smallest viable seams.

What not to build here: Do not introduce a broad public networking abstraction, do not make FeishuAPIService non-singleton, do not inject URLSession globally, and do not add new test files that require Xcode project edits.

### Option C: Refactor production services around protocols and full dependency injection

Summary: Replace singleton/direct private calls with protocols for transport, sleeper, API service, hotkey service, overlay, text input, and timers.

Pros:
- Long-term testability improves substantially.
- More natural unit seams for MainViewModel.

Cons:
- Much larger blast radius than a test-coverage issue needs.
- Raises concurrency/thread-safety and API-design risk.
- Would likely require files outside frozen write sets and broaden review/security burden.

Risk/complexity: High. Overbuilt for this issue.

What not to build here: Do not restructure app architecture or replace the MVVM/service pattern during these TDD nodes.

## Recommended Approach

Use Option B.

The coverage audit shows the parser hooks already exist, but the important API behaviors are hidden behind private auth/speech methods and the retry loop sleeps real time. A minimal DEBUG sender seam above `getAccessToken`/`sendSpeechRequest` and a minimal DEBUG retry-sleeper seam are enough to test the real business flow deterministically. For state interplay, add only DEBUG hooks or private method extractions in `MainViewModel` so tests can call the coordinator paths directly instead of relying on CGEventTap, real timers, or live Feishu API calls.

## API Lane Strategy: `api-http-retry-tests`

Allowed files:
- `FeishuSpeech/Services/FeishuAPIService.swift`
- `FeishuSpeechTests/FeishuAPIServiceTests.swift`
- `FeishuSpeechTests/MockURLProtocol.swift`

### Acceptable FeishuAPIService seams

Add only DEBUG-gated hooks:

1. Retry sleeper seam:
   - Add a private DEBUG optional closure such as `retrySleeperForTesting: (@Sendable (TimeInterval) async throws -> Void)?`.
   - Replace both direct `Task.sleep` calls in `withRetry` with a private helper like `sleepBeforeRetry(delay:)` that uses the test sleeper when present and otherwise calls `Task.sleep`.
   - Add DEBUG setters/resetters so tests can record delays and avoid real sleeps.

2. High-level request sender seam:
   - Add a private DEBUG optional closure used by the public/private `sendDirectRequest(path:headers:body:)` overload before it enters direct IP or URLSession fallback logic.
   - Closure shape should expose `path`, `headers`, and `body`, returning `DirectHTTPResponse`.
   - This lets tests drive the real `recognizeSpeech -> getAccessToken -> sendSpeechRequest -> withRetry` path without exposing private auth/speech methods or touching network.
   - If exact endpoint assertions are needed, add DEBUG-only `authPathForTesting` and `speechPathForTesting` accessors rather than making constants public.

3. Test reset seam:
   - Add a DEBUG reset method that clears cached token/expiry, sets network available true, clears injected request sender, and clears injected sleeper.
   - Use it in `setUp`/`tearDown` because `FeishuAPIService.shared` is an actor singleton.

Do not add real transport sleeps, real DNS, URLSession protocol-class plumbing, or public production injection APIs.

### API tests to add

Parser malformed/edge coverage using existing parser hooks:
- Malformed status line throws `APIError.invalidResponse`.
- Invalid or negative `Content-Length` throws `APIError.invalidResponse`.
- Truncated headers/no `\r\n\r\n` delimiter returns nil for complete parsing.
- Malformed chunk size throws `APIError.invalidResponse`.
- Missing chunk CRLF after chunk data throws `APIError.invalidResponse`.
- Chunk extensions plus trailers decode successfully.
- Extra bytes after a valid content-length body are ignored and only the declared body is returned.

Keep parser coverage to this set; skip lower-value cases such as exhaustive non-UTF8 header permutations unless a regression appears.

Deterministic retry coverage through `withRetryForTesting` plus sleeper seam:
- Retriable `APIError.timeout` retries until success, attempts exactly 3 times, and records delays `[1.0, 2.0]` without sleeping.
- Non-retriable `APIError.authFailed` attempts once and does not call the sleeper.
- Generic errors retry until exhaustion and rethrow the last error.
- `networkUnavailable` preflight throws before invoking the operation when `isNetworkAvailable` is false.

Token cache and speech 400/401 invalidation coverage through the high-level request sender seam:
- Auth success populates cache; a second `recognizeSpeech` reuses cached token and does not call auth again.
- Seed or create a cached token, return speech HTTP 400, then on retry assert auth is called again and the next speech request uses the fresh `Authorization: Bearer ...` token.
- Repeat the invalidation assertion for HTTP 401, either as a looped helper test or a second focused test.
- Keep response payloads minimal: auth JSON with `code: 0`, `tenant_access_token`, `expire`; speech JSON with `code: 0`, `data.recognition_text` matching existing models.

### `MockURLProtocol.swift` decision

Repurpose it, do not keep it as URLProtocol.

Rationale: the file is compiled but dead, and current code does not use a configurable URLSession. The API lane needs a reusable fake request sequence, and the frozen write set does not include a new helper filename. Replace the URLProtocol helper with a small test-only transport helper, for example a `MockFeishuTransport`/`MockFeishuRequestSequence` that records `(path, headers, body)` and returns queued `DirectHTTPResponse` or errors. If the executor keeps all helpers inside `FeishuAPIServiceTests.swift` instead, then delete `MockURLProtocol.swift`; do not leave the current unused URLProtocol class in place.

## State Lane Strategy: `state-interplay-tests`

Allowed files:
- `FeishuSpeech/Services/HotKeyService.swift`
- `FeishuSpeech/ViewModels/MainViewModel.swift`
- `FeishuSpeechTests/HotKeyServiceTests.swift`
- `FeishuSpeechTests/MainViewModelTests.swift`

### Valuable tests after #19 and existing coverage

Do not duplicate existing HotKeyService-only tests for #6/#7 or wake recovery. Add coordinator-level tests that prove the MainViewModel interaction is safe:

1. Exactly-once stop/transcribe on duplicate transcribing events:
   - Use a fake `AudioRecorder` subclass in `MainViewModelTests.swift` that can be forced into recording and counts `stopRecording()` calls.
   - Drive MainViewModel with a DEBUG `handleHotKeyStateForTesting(.transcribing)` or equivalent private extraction.
   - Send a second transcribing/Fn-release-equivalent signal and assert `stopRecording()` remains called once because the recorder is no longer recording.

2. Max-duration path routes through HotKeyService without duplicate stop:
   - Use existing `HotKeyService.forceTranscribing()` coverage for the raw transition, but add MainViewModel coverage for the coordinator effect.
   - Either add `handleMaxDurationReachedForTesting()` or use a direct transcribing-state hook after forcing recorder active.
   - Assert the max-duration path produces one stop/transcribe and a later Fn release while `.transcribing` does not cause a second stop.

3. Stale transcription error does not clobber a new active recording:
   - Extract the error-handling tail of `transcribeAudio` into a private method and expose a DEBUG test hook, or add a DEBUG hook that invokes that branch with the current generation.
   - Force `HotKeyService.shared` into an active state (`.recording` or `.pending`) before injecting the stale error.
   - Assert MainViewModel does not set a new error status and HotKeyService remains active rather than being overwritten with `.error`.

4. Optional #8 side-effect count, only if cheap:
   - Existing tests prove `stateCancellable` lifecycle but not side-effect multiplicity.
   - If the executor adds a tiny DEBUG counter around `handleHotKeyState`, test repeated start/stop cycles produce one handler invocation per emitted state.
   - Skip this if it pushes the seam beyond a simple counter; the exactly-once recorder tests are more valuable.

### Acceptable state seams

- Add `#if DEBUG` `handleHotKeyStateForTesting(_:)` in MainViewModel that calls the existing private `handleHotKeyState`.
- Add `#if DEBUG` `handleMaxDurationReachedForTesting()` only if needed to avoid a 60s timer.
- Extract transcription success/error handling into small private methods only if necessary for a deterministic stale-error test; expose only DEBUG wrappers, not public runtime API.
- Keep `HotKeyService` changes minimal. Existing `forceState`, `forceTranscribing`, and wake helpers should be enough; only add counters or reset helpers if a specific test cannot be written otherwise.
- Do not instantiate real event taps in new tests; avoid `startMonitoring()` unless an existing helper already uses it and the test can tolerate missing Accessibility permission.
- Use existing fake-recorder subclass style in `MainViewModelTests.swift`; do not create new files.

## AudioRecorderRecoveryTests Exclusion

Leave `AudioRecorderRecoveryTests.swift` target membership repair out of scope for these TDD nodes. The required xcodeproj edit is not in any frozen write set, so routing it through the current nodes would violate the plan.

If stale-recorder coverage is needed for issue #20, duplicate one minimal compiled assertion into `MainViewModelTests.swift` using the existing fake-recorder pattern. Separately record the excluded test file as follow-up evidence for a future plan that includes `FeishuSpeech.xcodeproj/project.pbxproj`.

## Validation Plan

Because the audit observed the hosted app test runner hanging before connection, use compile-first validation and bounded focused runtime attempts:

1. Compile app and tests:
   `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath .kw/DerivedData/issue-20 build-for-testing`

2. Focused hosted runner attempt, expected to be best-effort in this environment:
   `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath .kw/DerivedData/issue-20 test-without-building -only-testing:FeishuSpeechTests/FeishuAPIServiceTests -only-testing:FeishuSpeechTests/HotKeyServiceTests -only-testing:FeishuSpeechTests/MainViewModelTests`

3. Direct focused xcrun attempt if the bundle path exists and hosted runner still hangs:
   `TEST_BUNDLE=$(find .kw/DerivedData/issue-20/Build/Products -path '*FeishuSpeechTests.xctest' -type d -print -quit)`
   `xcrun xctest -XCTest FeishuSpeechTests.FeishuAPIServiceTests/test_withRetry_whenRetriableError_recordsRetryDelaysWithoutSleeping "$TEST_BUNDLE"`

   Treat direct `xcrun xctest` as suitable only if it loads the hosted bundle on this machine. If it refuses because the test bundle requires `TEST_HOST`, record that and use `build-for-testing` plus source-level focused review as the reliable gate until the runner hang is fixed.

4. Run lint after source edits:
   `swiftlint`

5. Do not depend on `AudioRecorderRecoveryTests.swift` appearing in runtime discovery unless a separate plan adds the xcodeproj membership repair.

## Hidden Risks and Assumptions

- `FeishuAPIService.shared` and `HotKeyService.shared` are singleton state; every new test must reset injected hooks, network availability, cached token, hotkey state, and fake recorder counters.
- DEBUG hooks must not change release behavior or widen app-facing API.
- Parser tests that already pass are still useful coverage, but the RED step for the API node should come from tests that reference missing sender/sleeper seams.
- MainViewModel tests should avoid permission and microphone gates unless a DEBUG hook bypasses them; otherwise failures will depend on host machine state.
- The validation runner hang is environmental evidence, not a reason to skip compile validation.
