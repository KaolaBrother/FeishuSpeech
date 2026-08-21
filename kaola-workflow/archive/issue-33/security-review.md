# Issue #33 security review

Date: 2026-08-21
Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-33`
Baseline: `89b9395d4a528d30dbc2c4bc07e9e6c6e8e566dd`
Candidate: uncommitted production delta in `FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift` and `FeishuSpeech/Services/TransportAttemptContext.swift` (tests are oracle-only)

Owner-confirmed contract (2026-08-21): skip VPN/TUN via `prohibitedInterfaceTypes = [.other]` (not `en0` bind); hostname and SNI `open.feishu.cn`; peer auth required; no `sec_protocol_options_set_verify_block`; no CDN IP allowlist; `preferNoProxies = true` remains; URLSession fallback on connect-class miss; completed HTTP does not hop; no user-facing toggle; `file_recognize` unchanged; logs are `transport=direct` / `transport=urlsession` without tokens, PCM, transcripts, stream IDs, IPs, or interface names.

The Q2-B reversal (tenant App Secret and bearer token leaving a consumer VPN/TUN on the primary keep-alive path) is an accepted owner policy. It is residual risk, not a candidate defect.

## Verdict

PASS. No candidate-caused P0, P1, P2, or P3 security defect was admitted.

## Surface inspected

Production:

- `FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift` (protocol seam, `makeParameters`, host/SNI, HTTP encode)
- `FeishuSpeech/Services/TransportAttemptContext.swift` (keep-alive primary, sticky modes, URLSession hop, logging, invalidate)
- Callers: `FeishuAPIService.makeStreamingSession` / `getAccessToken` / `sendTokenRequest` / `sendStreamingRequest` / `recognizeSpeech` / `makeURLRequest`
- Request builders: `FeishuStreamingSession.makeRequest` (fixed `https://open.feishu.cn/.../stream_recognize`)
- Unchanged parser: `DirectFeishuHTTPClient.parseCompleteResponseKeepingRemainder`
- `Info.plist` (no ATS exceptions), `FeishuSpeech.entitlements` (no sandbox/network-client change)

Tests (oracle, not a production injection path):

- `FeishuSpeechTests/DirectFeishuKeepAliveSessionTests.swift`
- `FeishuSpeechTests/TransportAttemptContextTests.swift`

Production `keepAlive:` is passed only from tests. App construction is `TransportAttemptContext(policy: streamingDrainPolicy)` with the default nil transport.

## Threat walkthrough

### TLS identity (SNI vs socket, custom verify, ATS)

Keep-alive still builds `NWConnection(host: NWEndpoint.Host("open.feishu.cn"), port: 443)` with `NWParameters(tls:)`. `sec_protocol_options_set_tls_server_name` is set to the same name. Apple documents that API as the name used when verifying the peer certificate (it overrides any name taken from the endpoint). There is no `sec_protocol_options_set_verify_block`. There is no IP connect and no CDN allowlist on this type.

ATS does not apply to Network.framework. Identity therefore depends on default `NWProtocolTLS.Options` trust evaluation plus the pinned server name, not on Info.plist ATS. On macOS 13+ that default still requires a system-trusted peer certificate for a client TLS connection; the candidate does not disable peer authentication. URLSession fallback remains under ATS.

No candidate TLS identity defect.

### Tenant App Secret / bearer leaving a mandatory corp VPN

Primary send is now keep-alive, so factory tenant-token POSTs (`app_id` / `app_secret` JSON) and `stream_recognize` Bearer POSTs traverse a path that prohibits `NWInterface.InterfaceType.other` (Apple's virtual/unknown bucket, including typical utun VPN). That is the owner-accepted invert of Q2-B.

It does not leak more than that policy: HTTP is not sent until `.ready` (TLS up); `.waiting` before first ready fails without a body; completed HTTP including 4xx does not hop; `file_recognize` still uses `executeURLRequest` / `URLSession.shared` with no keep-alive wrap.

Residual (not admitted): on a corp VPN that marks include-all and leaves no physical path, keep-alive misses and the same credentials fall back to URLSession, which uses the system proxy/VPN. That fallback is the specified corp escape hatch, not extra leakage beyond the contract.

### Logging of secrets, IPs, interface names

New logs are string literals only: `transport=direct connecting`, `transport=direct`, `transport=urlsession`, `transport=urlsession invalidated`. `mapTransportError` still collapses `NWError` / `URLError` to typed `APIError` (timeout / connectionFailed / `networkError("")`). No token, PCM, transcript, stream ID, IP, or interface name is interpolated.

Pre-existing `Direct Feishu request via \(ipAddress)` stays on the DEBUG/historical IP helper, which this candidate does not put on the streaming production path.

### SSRF / unexpected host

Socket, SNI, and HTTP `Host` are the compile-time constant `open.feishu.cn`. `Host` and `Connection` from the `URLRequest` are stripped. Path/query come from the request URL, which production builds as `https://open.feishu.cn` plus fixed `authPath` or the fixed `streamingSpeechURL`. No user-controlled URL, IP list, or redirect follow exists on this send path.

### Injection of keep-alive transport (test seam) in production

`DirectKeepAliveTransport` is an internal Swift protocol. `TransportAttemptContext.init(keepAlive:)` defaults to nil and, in production, constructs `DirectFeishuKeepAliveSession` on first `sendDirect`. The only `keepAlive:` argument sites are `FeishuSpeechTests`. The app target is not a plugin host and does not expose the initializer across a trust boundary. Not attacker-reachable.

### Fallback sending credentials to a proxy after intending to skip VPN

Connect-class miss (timeout / connectionFailed / networkError) hops once to a `URLSessionConfiguration.default` session (`preferNoProxies` is not set on that session). That is the documented fallback for corp `includeAllNetworks` / no physical path. Completed HTTP does not hop (covered by tests for 200 and 4xx). Cancellation does not hop. Sticky-direct stays on keep-alive; sticky-URLSession stays on URLSession for the rest of one context. A new context starts on keep-alive again.

Residual (not admitted): a slice timeout after the direct POST has already been written can resend the same credentials on URLSession. That is the same connect-class timeout rule the suite requires, not a new host or a completed-HTTP hop.

### Fake-ip DNS

Out of scope as specified. Residual only: skip-TUN plus a 198.18.0.0/16 fake-ip typically cannot complete on a physical path (TLS to a name-mismatched or unroutable address fails), then URLSession fallback may use the VPN path where fake-ip works. No custom verify block would accept a fake-ip certificate for `open.feishu.cn`.

## Contract pins (non-findings)

- `preferNoProxies = true` retained; `prohibitedInterfaceTypes = [.other]` added; no `requiredInterface` / `en0`.
- No `sec_protocol_options_set_verify_block` in the keep-alive source.
- No user-facing toggle (Views/Settings untouched).
- `recognizeSpeech` / `file_recognize` still call `getAccessToken` without a `TransportAttemptContext` and `executeURLRequest`.
- Abort remains URLSession unless already sticky-direct, matching the stated best-effort abort exception.

## Residual risk (owner policy, not defects)

1. Consumer VPN/TUN skip on the primary streaming auth and `stream_recognize` path (Q2-B reversal).
2. Network.framework is outside ATS; certificate identity is default system trust plus pinned `open.feishu.cn`.
3. Fake-ip / VPN DNS mismatch can force the URLSession fallback (availability and path selection, not a custom-trust bypass).
4. User-space HTTP proxies without a utun `.other` interface are skipped only by `preferNoProxies`, not by the new prohibit list.

## Proof notes

High-confidence admission requires a reachable trigger that breaches the trust model beyond the accepted policy. None of the inspected paths send streaming credentials to a host other than `open.feishu.cn`, disable peer certificate checks, log secrets, honor an injected production transport, hop after completed HTTP, or wrap `file_recognize`.

verdict: pass
findings_blocking: 0
review_conclusion: The candidate introduces no admitted security defect; keep-alive TLS identity stays pinned to open.feishu.cn with system peer auth, and the owner-accepted VPN skip does not add secret logging, SSRF, or a production transport-injection path.
