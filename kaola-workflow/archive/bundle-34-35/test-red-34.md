# Issue #34 bound physical DNS / no URLSession hop — RED receipt

Date: 2026-08-21

## Assignment

Pin failing tests for: physical-interface DNS on the keep-alive path (skip `198.18.0.0/15`, not
`getaddrinfo`-only, no Feishu CDN IP list, no `en0` string), and for `TransportAttemptContext`
never hopping factory/packet/finish to URLSession on a keep-alive connect-class miss.

## Test artifact

- `FeishuSpeechTests/TransportAttemptContextTests.swift`
- `FeishuSpeechTests/DirectFeishuKeepAliveSessionTests.swift`
- `FeishuSpeechTests/BoundTLSSocketTests.swift` (new)
- Production files changed: none (`FeishuSpeech/` not edited)

## Baseline

- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/bundle-34-35`
- Branch: `workflow/bundle-34-35`
- HEAD SHA from `.git/refs/heads/workflow/bundle-34-35`: `276c470d86e64634f70ebf2252e7a62ea94c884c`
- Production `BoundTLSSocket.swift` still resolves with `getaddrinfo` and filters via
  `0xC612_0000` / `0xFFFE_0000`.
- Production `TransportAttemptContext.send` still hops to URLSession after a keep-alive
  connect-class miss; `phase == .abort` still takes the URLSession slice.

## xcodebuild run

Orchestrator ran on worktree `276c470d86e64634f70ebf2252e7a62ea94c884c`:

```
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/feishuspeech-bundle-34-35-test-red \
  -only-testing:FeishuSpeechTests/DirectFeishuKeepAliveSessionTests \
  -only-testing:FeishuSpeechTests/TransportAttemptContextTests \
  -only-testing:FeishuSpeechTests/BoundTLSSocketTests \
  -only-testing:FeishuSpeechTests/AppSettingsCredentialStorageTests \
  test
```

**TEST FAILED** (compile):

```
BoundTLSSocketTests.swift:54:25: error: cannot find 'BoundPhysicalDNS' in scope
BoundTLSSocketTests.swift:66:25: error: cannot find 'BoundPhysicalDNS' in scope
Testing cancelled because the build failed.
```

Production `FeishuSpeech/` was not edited for this red.

Command to execute on this worktree:

```bash
cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/bundle-34-35
git rev-parse HEAD
git diff --stat -- FeishuSpeech/
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/feishuspeech-issue-34-test-red \
  -only-testing:FeishuSpeechTests/DirectFeishuKeepAliveSessionTests \
  -only-testing:FeishuSpeechTests/TransportAttemptContextTests \
  -only-testing:FeishuSpeechTests/BoundTLSSocketTests test
```

`-only-testing` still compiles the whole `FeishuSpeechTests` target.

## Expected RED on this baseline (source inspection, not a run)

```
RED: BoundTLSSocketTests.test_dnsResponseFixture_dropsTunnelRangeAndKeepsNonTunnelARecords
     cannot find 'BoundPhysicalDNS' in scope
RED: TransportAttemptContextTests.test_keepAliveConnectClassErrorDoesNotHopToURLSessionForFactoryPacketOrFinish
     expected rethrow + recordedStartCount == 0, got URLSession hop 200
baseline: 276c470d86e64634f70ebf2252e7a62ea94c884c
```

`BoundPhysicalDNS` is the #34 compile-fail seam. Until that type exists, hop and source-pin
assertions in this target do not execute. After a stub lands, those assertions are still false
on this baseline because:

| Test | Why it fails on `276c470` |
|---|---|
| `test_dnsResponseFixture_dropsTunnelRangeAndKeepsNonTunnelARecords` | `BoundPhysicalDNS` is not in the module |
| `test_dnsResponseFixture_allTunnelARecordsYieldEmptyList` | same missing type |
| `test_productionSourcePinsBoundUDPPhysicalDNSWithoutEn0CDNOrCustomVerify` | `BoundTLSSocket.swift` has `IP_BOUND_IF` and the tunnel mask, but uses `getaddrinfo` / `SOCK_STREAM`; no `SOCK_DGRAM` / UDP port 53 |
| `test_keepAliveConnectClassErrorDoesNotHopToURLSessionForFactoryPacketOrFinish` | `send` catches keep-alive connect-class errors and calls `sendURLSessionSlice`; probe `recordedStartCount` becomes 1 and HTTP 200 is returned |
| `test_keepAliveConnectClassMissRetriesKeepAliveOnNextSend` | first miss hops and sets sticky-URLSession; second send never retries keep-alive |
| `test_newTransportAttemptContextStartsOnKeepAliveAgain` | first context hop half still reaches URLSession |
| `test_keepAliveConnectClassMissDoesNotStartHungURLSession` | miss still starts the hung URLSession slice |
| `test_abortDoesNotHopToURLSessionWhenKeepAliveIsPresent` | `phase == .abort` takes URLSession first and returns the 500 decoy |

Existing no-hop pins (completed HTTP, 4xx, `CancellationError`, sticky-direct) remain and
already match this baseline. Live TCP `test_liveKeepAliveTCPIsNotOnVPNTunnelAddress` is
`XCTSkip` so it cannot hang the host.

## Tests encoded (behaviors, not names, are the contract)

`TransportAttemptContextTests` (in-process mock keep-alive + `URLProtocol`; no live network)

- keep-alive remains primary
- keep-alive connect-class miss (`timeout`, `connectionFailed`, `networkError`) on
  factory/packet/finish **rethrows** that error; `URLSessionTestProbe.recordedStartCount == 0`
- completed HTTP including 4xx still does not hop
- `CancellationError` still does not hop
- sticky-direct on keep-alive success still holds
- sticky-URLSession is gone: a connect-class miss retries keep-alive on the next `send`
- a new context still starts on keep-alive
- abort does not require URLSession; when keep-alive is present, abort uses it
- `file_recognize` is out of scope

`DirectFeishuKeepAliveSessionTests` / `BoundTLSSocketTests` (source pins + DNS fixture)

- production sources contain `open.feishu.cn`, `IP_BOUND_IF`, bound UDP DNS (`SOCK_DGRAM` /
  port 53), and skip `198.18.0.0/15` via `0xC612_0000` / `0xFFFE_0000`
- they do not contain `en0`, `sec_protocol_options_set_verify_block`, or Feishu CDN literals
  `98.96.213.145` / `98.96.242.53`
- `BoundPhysicalDNS.ipv4ARecords(from:)` parses a DNS A-record fixture, drops the tunnel
  range, and keeps non-tunnel addresses; no CDN allowlist API

## Assumed production seam (not implemented on this baseline)

```swift
nonisolated enum BoundPhysicalDNS {
    static func ipv4ARecords(from response: Data) -> [in_addr]
}
```

Internal / `@testable`. Parse DNS A RDATA; drop `198.18.0.0/15`; do not allowlist Feishu CDN
IPs. `BoundTLSSocket` should resolve over bound UDP/53 (not `getaddrinfo`-only) and feed that
parser. Public resolver literals such as `223.5.5.5` are allowed.

`TransportAttemptContext.send` must rethrow keep-alive connect-class errors for
factory/packet/finish and must not call URLSession. There is no sticky-URLSession.
