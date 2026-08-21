# Issue #33 skip VPN/TUN — RED receipt

Date: 2026-08-21

## Assignment

Pin a failing suite for streaming transport that skips VPN/TUN: Network.framework keep-alive is primary (`prohibitedInterfaceTypes` includes `.other`), URLSession is connect-class fallback only, completed HTTP does not hop, and both sticky-direct and sticky-URLSession hold for the rest of one `TransportAttemptContext`.

## Test artifact

- `FeishuSpeechTests/DirectFeishuKeepAliveSessionTests.swift`
- `FeishuSpeechTests/TransportAttemptContextTests.swift`
- Production files changed: none

## Assumed production seam (not implemented on this baseline)

Tests compile against this shape. The implementer can add it without rewriting tests:

```swift
protocol DirectKeepAliveTransport: AnyObject, Sendable {
    func send(_ request: URLRequest, deadlineNanoseconds: UInt64) async throws -> DirectHTTPResponse
    func forceCancel()
}

// TransportAttemptContext.init(policy:session:keepAlive:)
// keepAlive: (any DirectKeepAliveTransport)? = nil
// When nil, production constructs DirectFeishuKeepAliveSession.
// DirectFeishuKeepAliveSession conforms to DirectKeepAliveTransport.
```

The test target is built with `-default-isolation=MainActor`. If the protocol is inferred as main-actor-isolated, mark it `nonisolated` so `DirectFeishuKeepAliveSession` and the test mock can conform.

Primary `send` uses `policy.directSliceNanoseconds(for:)`. URLSession fallback uses `policy.urlSessionSliceNanoseconds(for:)`.

## Baseline and RED proof

```
RED: TransportAttemptContextTests — cannot find type 'DirectKeepAliveTransport' in scope
RED: TransportAttemptContextTests.makeProbedContext — extra argument 'keepAlive' in call
baseline: 89b9395d4a528d30dbc2c4bc07e9e6c6e8e566dd
```

- Baseline commit exercised: `89b9395d4a528d30dbc2c4bc07e9e6c6e8e566dd` (`89b9395 chore: archive bundle-28-29-30-31 [sink]`)
- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-33`
- Kind: **compile-fail** (test target did not link; no assertion run)
- Production `FeishuSpeech/` was not modified

Exact diagnostics from this run:

```text
FeishuSpeechTests/TransportAttemptContextTests.swift:321:57: error: cannot find type 'DirectKeepAliveTransport' in scope
private nonisolated final class MockKeepAliveTransport: DirectKeepAliveTransport, @unchecked Sendable {
                                                        ^~~~~~~~~~~~~~~~~~~~~~~~
FeishuSpeechTests/TransportAttemptContextTests.swift:292:24: error: extra argument 'keepAlive' in call
            keepAlive: keepAlive
~~~~~~~~~~~~~~~~~~~~~~~^~~~~~~~~
```

xcodebuild summary:

```text
Testing failed:
	Cannot find type 'DirectKeepAliveTransport' in scope
	Extra argument 'keepAlive' in call
	Testing cancelled because the build failed.

** TEST FAILED **
```

This compile-fail is the oracle for the missing keep-alive-primary seam: the suite injects `DirectKeepAliveTransport` and calls `TransportAttemptContext(policy:session:keepAlive:)`, neither of which exists on the baseline.

`DirectFeishuKeepAliveSessionTests` compiled. Its runtime assertions did not execute because `FeishuSpeechTests` failed to emit/link. On this baseline those assertions are still false:

- `DirectFeishuKeepAliveSession.makeParameters()` sets `preferNoProxies = true` only and does **not** assign `prohibitedInterfaceTypes` (no `.other`). `test_parametersPreferNoProxiesAndProhibitOtherInterfaceTypes` therefore expects `prohibitedInterfaceTypes?.contains(.other) == true` against an unset/empty value.
- `TransportAttemptContext.send` still uses URLSession first and hops to keep-alive only after a URLSession miss; there is no sticky-URLSession. After the seam compiles, the injected-mock tests fail until keep-alive is primary.

## Tests encoded (behaviors, not names, are the contract)

`DirectFeishuKeepAliveSessionTests`

- `test_parametersPreferNoProxiesAndProhibitOtherInterfaceTypes` — `preferNoProxies == true` and prohibited types include `.other`
- `test_productionSourcePinsOpenFeishuHostWithoutEn0OrCustomVerifyBlock` — source contains `open.feishu.cn`, does not contain `en0` or `sec_protocol_options_set_verify_block`
- `test_mapTransportErrorNeverExposesNWErrorToCoordinator` — existing NWError mapping pin (already true on baseline)

`TransportAttemptContextTests` (in-process mock keep-alive + `URLProtocol`; no live `open.feishu.cn`)

- `test_completedHTTPDoesNotInvalidateSession` — keep-alive HTTP 200 is returned; URLSession protocol is not started; context not invalidated; keep-alive deadline is `directSliceNanoseconds`
- `test_keepAliveConnectClassErrorHopsOnceToURLSession` — keep-alive `.connectionFailed` / `.timeout` / `.networkError` hops once; URLSession 200 is returned
- `test_keepAliveCompletedHTTP4xxDoesNotHopToURLSession` — keep-alive 400/401/403/407 is returned; URLSession is not started
- `test_keepAliveCancellationErrorDoesNotHopToURLSession` — `CancellationError` is rethrown; URLSession is not started
- `test_stickyDirectLeavesURLSessionUnusedAcrossTwoSends` — two keep-alive 200s; URLSession remains unused
- `test_stickyURLSessionDoesNotCallKeepAliveAgain` — after connect-class fail + URLSession 200, a second `send` must not call keep-alive
- `test_newTransportAttemptContextStartsOnKeepAliveAgain` — a new context starts on keep-alive even if the previous attempt stuck to URLSession
- `test_sliceTimerCancelsHungDataForAndInvalidates` — keep-alive throws connect-class, URLSession hangs, 40 ms URLSession slice wins (not the 2 s direct slice), context is invalidated
- existing configuration and `session.cancel()` invalidation pins unchanged

## Commands run

From the worktree:

```text
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue-33-test-red -only-testing:FeishuSpeechTests/DirectFeishuKeepAliveSessionTests -only-testing:FeishuSpeechTests/TransportAttemptContextTests test
```

- Exit status: 65
- Result bundle: `/tmp/feishuspeech-issue-33-test-red/Logs/Test/Test-FeishuSpeech-2026.08.21_15-00-49-+0800.xcresult`
- `git diff --stat -- FeishuSpeech/`: empty

## Outcome

RED confirmed on baseline `89b9395d4a528d30dbc2c4bc07e9e6c6e8e566dd`. Keep-alive is not primary and `.other` is not prohibited. The implementation role now has a test-owned oracle for skip-VPN keep-alive-primary transport; do not edit these test files to make them pass.
