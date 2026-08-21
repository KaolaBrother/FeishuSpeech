# Issues #34 and #35 code review

Date: 2026-08-21
Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/bundle-34-35`
Branch: `workflow/bundle-34-35`
Baseline: `276c470`
Candidate: production delta vs main in the six assigned files

Oracle: `kaola-workflow/bundle-34-35/test-red-34.md`, `kaola-workflow/bundle-34-35/test-red-35.md`
GREEN receipt: `kaola-workflow/bundle-34-35/implement-green-34.md`, `kaola-workflow/bundle-34-35/implement-green-35.md`
Issues: https://github.com/KaolaBrother/FeishuSpeech/issues/34, https://github.com/KaolaBrother/FeishuSpeech/issues/35

Tests read only (not edited):
`FeishuSpeechTests/BoundTLSSocketTests.swift`,
`FeishuSpeechTests/DirectFeishuKeepAliveSessionTests.swift`,
`FeishuSpeechTests/TransportAttemptContextTests.swift`,
`FeishuSpeechTests/AppSettingsCredentialStorageTests.swift`

behavior_contract_version: 3
behavior_contract_hash: 308d49af0d19404ba0d50e28cee64b570df0a647c93f6b6f3636c3853835dfc7
resolved_profile_hash: a3fc3040f5cd0530569a869efba3606463e3fc7c6aeb701f528704dce1e3bb40

## Verdict

approve

No candidate-caused correctness defect was admitted. Bound UDP/53 physical DNS skips `198.18.0.0/15` by bitmask, recursor fallbacks are hostnames only, keep-alive connect-class misses no longer hop factory/packet/finish to URLSession, and launch-at-login no longer reads the credential store.

## Surface

Production changed:

- `FeishuSpeech/Services/BoundTLSSocket.swift` (new relative to HEAD's getaddrinfo-only socket) — `BoundPhysicalDNS` DHCP option-6 plus recursor hostnames, bound UDP/53, A-record parser, TCP `IP_BOUND_IF` over remaining A records, CFStream TLS with peer name `host`
- `FeishuSpeech/Services/TransportAttemptContext.swift` — factory/packet/finish stay on keep-alive; connect-class miss rethrows; abort uses keep-alive when one is present
- `FeishuSpeech/Services/KeychainCredentialStore.swift` — data-protection queries, `AfterFirstUnlockThisDeviceOnly` on add, login-keychain read migrates then deletes
- `FeishuSpeech/Models/AppSettings.swift` — `launchAtLoginPreference(from:)`
- `FeishuSpeech/App/AppDelegate.swift` — launch-at-login from UserDefaults only

`FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift` is in scope. `startConnection` still calls `BoundTLSSocket.connect(host: feishuDirectHost, interfaceName:)` with runtime `NWInterface.name`, SNI host `open.feishu.cn`, no `en0`, no custom verify block. The local-address reject `hasPrefix("198.18.")` matches issue #34 contract item 2 and is unchanged from main.

Unchanged callers checked: `FeishuAPIService.makeStreamingSession` / `getAccessToken` / `sendTokenRequest` / `sendStreamingRequest` / `recognizeSpeech`; `FeishuStreamingSession.cancel` invalidates first then best-effort abort; `MainViewModel.createStreamingSession` still outer-retries connect-class factory failures; `FeishuSpeechApp` still loads credentials once from `MainViewModel.init`.

This review did not re-run xcodebuild. GREEN receipts record Debug BUILD SUCCEEDED and swiftlint clean on the touched files. Official `xcodebuild test` still hangs on the adhoc test-host keychain; that is a later signing mission, not a production miss in these files. Orchestrator live measurement (unsigned validator on production `BoundTLSSocket`): resolve ~77ms mainland A records, TCP local `192.168.0.145`, HTTP 64ms Tengine, not `198.18`, not `98.96`.

## Owner constraints versus source

No dotted-quad literals in the three transport files. Recursor hostnames `dns.alidns.com` and `public1.114dns.com` are present; `223.5.5.5` / `114.114.114.114` / Feishu CDN `98.96.213.145` / `98.96.242.53` are absent. Tunnel skip uses `(ip & 0xFFFE_0000) == 0xC612_0000`. No `en0` string. TLS uses `kCFStreamSSLPeerName` plus `kCFStreamSSLValidatesCertificateChain`; no `sec_protocol_options_set_verify_block`.

`getaddrinfo` remains only inside `recursiveResolverAddresses()` for those recursor hostnames, not for `open.feishu.cn`. Keep-alive resolve of the Feishu host is bound UDP/53. That matches issue #34 ("do not use system getaddrinfo" for `open.feishu.cn`) and the later owner exception allowing recursor hostnames instead of IP literals.

## BoundPhysicalDNS and BoundTLSSocket

`ipv4ARecords(from:)` walks questions, collects type-A RDATA from answer and additional, skips authority, and drops `198.18.0.0/15`. The RED fixture (`198.18.1.23`, `203.0.113.50`, `198.19.255.255`, `198.17.255.255`) maps to the two non-tunnel addresses. Compression pointer `0xC00C` is handled in `skipName` with a hop cap.

`resolveIPv4` builds nameservers as DHCP option 6 for the passed interface (matched through SystemConfiguration service IDs, not a hardcoded BSD name) plus recursor A records, then bound `SOCK_DGRAM` / `IPPROTO_UDP` / `IP_BOUND_IF` / port 53. Empty or all-tunnel answers fall through to the next nameserver; none left throws `connectionFailed`. There is no Feishu CDN allowlist API.

`posixConnect` tries remaining A records in order until TCP succeeds. Main used only `.first` after `getaddrinfo`; trying the next A is the issue #34 reconnect rule inside one connect.

CFStream pair wraps the already-connected fd with peer name equal to the connect host (`open.feishu.cn` from `DirectFeishuKeepAliveSession`). Handshake is polled in `waitUntilOpen`. Logs are `transport=direct dns=udp` and `transport=direct bound-if` with no IPs, tokens, PCM, transcripts, stream IDs, or interface names.

DHCP-first versus recursor-first was considered. Issue #34's UAT table shows en0-scoped DNS as `1.1.1.2`, which would return overseas `98.96` A records if queried successfully. This code reads DHCP option 6, not `kSCPropNetDNSServerAddresses`, so a VPN overlay that rewrites SC DNS without rewriting the lease does not become the first resolver. Live measurement on the same machine returned mainland A records, not `98.96`. That is not admitted as a defect.

## TransportAttemptContext hop removal

`send` now:

1. Invalidated -> `CancellationError`
2. `stickyDirect` -> keep-alive only
3. `phase == .abort` and no keep-alive -> URLSession slice (abort without a session)
4. Else keep-alive; connect-class errors rethrow; no `sendURLSessionSlice`

That matches the RED oracle:

- factory/packet/finish connect-class miss rethrows; `URLSessionTestProbe.recordedStartCount` stays 0
- completed HTTP including 4xx does not hop
- `CancellationError` does not hop
- sticky-direct still holds across two sends
- injected keep-alive is reused on the next send after a first miss (`usesInjectedKeepAlive` skips nil/forceCancel)
- sticky-direct later miss still `invalidate()`s
- abort with keep-alive present uses `directSliceNanoseconds(.abort)`
- a new context still starts on keep-alive

Production `TransportAttemptContext(policy:)` has no injected keep-alive. First miss force-cancels and nils the session; coordinator `waitForRetryIfAdmitted` plus a new `makeStreamingSession` reconnects on a new context. `file_recognize` still uses `executeURLRequest` without a context.

`stickyURLSession` is still assigned inside `sendURLSessionSlice` but is no longer a send-order predicate. The only remaining URLSession entry is abort without a keep-alive, and production cancel invalidates before abort, so that assignment is not a reachable streaming hop.

## Keychain and launch-at-login

`baseQuery` sets `kSecUseDataProtectionKeychain` for modern items. `add` sets `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. `read` copies DP first; on `errSecItemNotFound` it copies the login item (no DP flag, `kSecUseAuthenticationUIFail`), adds it to DP, then deletes the login item. Two accounts stay two items. `unexpectedStatus` is still thrown for missing entitlement / interaction-not-allowed.

`AppDelegate.applicationDidFinishLaunching` no longer calls `AppSettings.load()`. It applies `LoginItemService.setEnabled(AppSettings.launchAtLoginPreference(from: .standard))`. The reader decodes `StoredSettings.launchAtLogin` from the injected defaults and does not touch `AppSettings.credentialStore`. Missing payload -> false. `MainViewModel.init` still loads credentials once, which is the remaining launch read and the migration trigger. Settings toggle still calls `LoginItemService.setEnabled` from `saveSettings()`.

Adhoc Debug `-34018` on live DP operations is documented in the #35 GREEN receipt and is owned by the later Apple Development signing mission, not these three files.

## Concurrency and locks

`BoundPhysicalDNS` is stateless. `BoundTLSSocket.close` is locked; read/write run on `DirectFeishuKeepAliveSession`'s serial queue. `TransportAttemptContext` still copies session/keep-alive then unlocks before `invalidateAndCancel` / `forceCancel`, and does not hold the context lock across `keepAlive.send`. The two production locks are not nested.

## Coverage note (not a finding)

Parser, source-pin, and in-process hop tests cover the RED contract. They do not execute DHCP, bound UDP, or recursor `getaddrinfo` in-process; the RED oracle skipped live sockets so the XCTest host would not hang. Live validator evidence is the runtime proof for that path. Isolated DP round-trip tests skip on `-34018` in the adhoc host.

verdict: pass
findings_blocking: 0
review_conclusion: Bound physical DNS, hop removal, and data-protection keychain match issues 34 and 35 with no admitted candidate-caused defect.
