# Bundle #34 / #35 security review

Date: 2026-08-21
Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/bundle-34-35`
Issues: #34 (bound UDP DNS + IP_BOUND_IF TLS, no URLSession hop), #35 (data-protection keychain + launch-at-login without credential load)
Red baseline named in test receipts: `276c470d86e64634f70ebf2252e7a62ea94c884c`

Owner-confirmed contract:

- Bound UDP/53 DNS plus `IP_BOUND_IF` TLS to `open.feishu.cn`. Peer certificate validation stays on. No custom verify block. No hardcoded IPs. Recursor hostnames `dns.alidns.com` / `public1.114dns.com` are DNS servers only (when DHCP/LAN DNS does not yield a usable A set, including Local Network TCC block).
- Keychain: `kSecUseDataProtectionKeychain`, `AfterFirstUnlockThisDeviceOnly`, migrate login-keychain items then delete. AppDelegate no longer `AppSettings.load()` at launch.
- Logs must not include tokens, PCM, transcripts, stream IDs, IPs, or interface names.

## Verdict

PASS. No candidate-caused P0, P1, P2, or P3 security defect was admitted.

## Surface inspected

Production:

- `FeishuSpeech/Services/BoundTLSSocket.swift` (`BoundPhysicalDNS` UDP/53, tunnel bitmask, recursor hostnames, POSIX `IP_BOUND_IF`, CFStream TLS)
- `FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift` (physical wifi/wired snapshot, `BoundTLSSocket.connect(host: feishuDirectHost)`, local `198.18.` reject, HTTP encode)
- `FeishuSpeech/Services/TransportAttemptContext.swift` (keep-alive primary; connect-class miss rethrows; abort URLSession only when keep-alive is absent)
- `FeishuSpeech/Services/KeychainCredentialStore.swift` (DP queries, accessibility on add, login-keychain migrate-then-delete)
- `FeishuSpeech/Models/AppSettings.swift` (`launchAtLoginPreference(from:)` UserDefaults-only)
- `FeishuSpeech/App/AppDelegate.swift` (launch-at-login without `AppSettings.load()`)
- Callers: `FeishuAPIService.makeStreamingSession` / `getAccessToken` / `sendTokenRequest` / `sendStreamingRequest` / `recognizeSpeech` / `makeURLRequest`
- Request builders: `FeishuStreamingSession` fixed `https://open.feishu.cn/.../stream_recognize`
- `Info.plist` (no ATS exceptions), `FeishuSpeech.entitlements` (no network-client or keychain-access-group change)

Tests (oracle, not a production injection path):

- `FeishuSpeechTests/BoundTLSSocketTests.swift`
- `FeishuSpeechTests/DirectFeishuKeepAliveSessionTests.swift`
- `FeishuSpeechTests/TransportAttemptContextTests.swift`
- `FeishuSpeechTests/AppSettingsCredentialStorageTests.swift`

Production keep-alive host is the compile-time `feishuDirectHost = "open.feishu.cn"`. `TransportAttemptContext(keepAlive:)` is passed only from tests.

## Threat walkthrough

### TLS identity (IP connect, SNI/peer name, custom verify, ATS)

Keep-alive no longer uses `NWConnection(host: "open.feishu.cn")` for the send path. `startConnection` calls `BoundTLSSocket.connect(host: feishuDirectHost, interfaceName:)`. DNS returns IPv4 A records; TCP connects to those addresses with `IP_BOUND_IF`; TLS is CFStream on the connected fd.

Apple documents `kCFStreamSSLPeerName` as the name used for certificate verification, and that if no host name was used when the stream was created, no peer name is used unless this key is set. `CFStreamCreatePairWithSocket` supplies no hostname, so PeerName is the identity control. The candidate sets:

- `kCFStreamSSLPeerName` = `host` (`open.feishu.cn` on the production call)
- `kCFStreamSSLValidatesCertificateChain` = true
- no `sec_protocol_options_set_verify_block`
- no `kCFNull` peer name, no `kCFStreamSSLAllowsExpiredCertificates` / `AllowsAnyRoot`

Handshake completion is `waitUntilOpen` until both streams are `.open`, or throw on `.error` / timeout. HTTP (including `Authorization` and `app_id`/`app_secret` JSON) is written only after `connect` returns.

ATS does not apply to CFStream. Identity therefore depends on those SSL settings plus the pinned peer name, not on Info.plist. Info.plist still has no ATS exceptions. URLSession abort (keep-alive absent) and `file_recognize` remain under ATS.

No candidate TLS identity defect.

### Hardcoded IPs / CDN allowlist / recursor use

Production keep-alive sources contain no Feishu CDN dotted quads (`98.96.213.145` / `98.96.242.53`) and no `en0` string. Recursor *hostnames* `dns.alidns.com` and `public1.114dns.com` are resolved with `getaddrinfo` and used only as UDP/53 nameserver addresses after tunnel-range filtering. They are never TLS peers and never HTTP `Host` / SNI.

`open.feishu.cn` itself is not resolved with system `getaddrinfo`. `resolveIPv4` queries bound UDP/53 and throws `connectionFailed` if DHCP and recursor UDP yield no non-tunnel A records.

### DNS spoofing / poisoned DHCP / public recursor

UDP `recvfrom` does not authenticate the nameserver beyond a 16-bit transaction ID. The parser collects type=1 RDATA from answer and additional sections and does not require the owner name to equal the QNAME. A LAN attacker or a rogue DHCP option-6 server can therefore influence which A records are tried.

Expected safe behavior: those IPs are only TCP/443 candidates; TLS must still present a system-trusted chain for `open.feishu.cn`. Observed: PeerName and chain validation stay on, so a spoofed A record without a valid `open.feishu.cn` certificate fails closed. That is DNS-untrusted / TLS-trusted, matching the contract. Not a trust-model breach.

### SSRF / unexpected host

Socket, PeerName, and HTTP `Host` are the compile-time constant `open.feishu.cn`. `Host` and `Connection` from the `URLRequest` are stripped. Path/query come from production builders (`authPath` or fixed `streamingSpeechURL`). No user-controlled URL, IP list, or redirect follow exists on this send path.

### URLSession hop removal (credential path)

`TransportAttemptContext.send` uses keep-alive for factory/packet/finish and rethrows connect-class errors. It does not hop those phases to URLSession. After a miss, non-injected keep-alive is dropped so the next send retries a new bound connect rather than sticky-URLSession.

This keeps tenant App Secret and bearer tokens on the bound path for streaming auth and `stream_recognize`. Abort still uses URLSession when keep-alive is absent (specified best-effort). `file_recognize` still uses `executeURLRequest` / `URLSession.shared` (out of scope).

### Keychain data-protection and launch path

Modern queries set `kSecUseDataProtectionKeychain = true`. `add` sets `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (not synced, this device only). Read tries DP first; on `errSecItemNotFound` it copies the login-keychain item (no DP flag), `SecItemAdd`s it into DP, then `SecItemDelete`s the login item. `kSecUseAuthenticationUIFail` remains on copy/update/delete.

`AppDelegate.applicationDidFinishLaunching` applies `LoginItemService.setEnabled(AppSettings.launchAtLoginPreference(from: .standard))` and does not call `AppSettings.load()`. `launchAtLoginPreference` decodes `FeishuSpeechSettings.launchAtLogin` from the given defaults and does not touch `AppSettings.credentialStore`.

`MainViewModel.init` still calls `AppSettings.load()` (one credential read after UI construction). That is the remaining migration/read site, not a second launch-time load from AppDelegate. Credentials stay out of UserDefaults on the D-18-01 save path.

No candidate credential-store defect: items move into the per-app data-protection keychain; login-keychain leftovers after a failed delete are residual copies, not a new exposure class.

### Logging of secrets, IPs, interface names

Candidate logs are string literals plus interface *type* (`wifi` / `wired` / `other` / `none` / `unknown`), not BSD names:

- `transport=direct dns=udp`
- `transport=direct bound-if`
- `transport=direct connecting path=<kind>`
- `transport=direct rejected tunnel local`
- `transport=direct path=<kind> tunnel=false`
- `transport=direct` / `transport=urlsession` / `transport=urlsession invalidated`
- keychain: `Migrated credential for account appId|appSecret` (account enum, not values)

`localIPv4` is used only for a `198.18.` prefix reject. `mapTransportError` still collapses `NWError` / `URLError` to typed `APIError`. No token, PCM, transcript, stream ID, IP, or interface name is interpolated on this candidate surface.

Pre-existing (not admitted): `FeishuAPIService` DEBUG/historical `Direct Feishu request via \(ipAddress)` on `sendDirectRequest`, which production streaming does not call; `FeishuStreamingSession` diagnostic logs `sequenceID` (unchanged).

### Injection of keep-alive transport

`DirectKeepAliveTransport` is an internal protocol. App construction is `TransportAttemptContext(policy:)` with default nil transport, then `DirectFeishuKeepAliveSession` on first `sendDirect`. The only `keepAlive:` argument sites are tests. Not attacker-reachable.

## Findings (P0-P3)

None. No candidate-caused security defect was admitted at P0, P1, P2, or P3.

## Contract pins (non-findings)

- Peer cert validation on: `kCFStreamSSLValidatesCertificateChain = true`, `kCFStreamSSLPeerName = open.feishu.cn`.
- No `sec_protocol_options_set_verify_block` in keep-alive or BoundTLS sources.
- No hardcoded destination IPs; recursor hostnames are nameserver-only.
- No `en0` source string; bind uses runtime `NWInterface.name` from wifi/wired.
- Tunnel A records dropped with `0xC612_0000` / `0xFFFE_0000` (`198.18.0.0/15`).
- Connected socket with local IPv4 prefix `198.18.` is closed without HTTP.
- Factory/packet/finish do not hop to URLSession on connect-class miss.
- `kSecUseDataProtectionKeychain` and `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` on new items; migrate then delete login items.
- AppDelegate does not `AppSettings.load()`.
- Candidate logs omit tokens, PCM, transcripts, stream IDs, IPs, and BSD interface names.
- `file_recognize` and no user-facing VPN toggle remain unchanged.

## Residual risk (owner policy or pre-existing, not defects)

1. CFStream keep-alive is outside ATS; certificate identity is system trust plus pinned `open.feishu.cn` PeerName.
2. `kCFStreamSocketSecurityLevelNegotiatedSSL` is the compatibility TLS level. On macOS 13+ Secure Transport still requires a trusted peer cert; Feishu must offer a usable TLS version. Not a custom-trust bypass.
3. Recursor hostnames are resolved with unbound `getaddrinfo` (system/VPN DNS). Returned tunnel-range IPs are dropped. Those names are never used as TLS peers. Eager concatenation means the lookup runs even when DHCP UDP later succeeds; that is metadata, not credential leakage.
4. UDP DNS does not authenticate the nameserver. TLS to `open.feishu.cn` remains the security boundary.
5. Local-address reject uses `198.18.` (`/16` string) while DNS skip is `/15`. Primary control is `IP_BOUND_IF` to a wifi/wired interface; the local check is belt-and-suspenders for the issue #34 `198.18.*` clause.
6. Abort without an in-memory keep-alive, and whole-file `file_recognize`, still use URLSession (VPN/DNS as the system provides). Specified exceptions.
7. Adhoc Debug signing can return keychain `-34018` for DP operations until the later Apple Development signing mission. Production DP queries are still the specified store.
8. If login-item delete fails after a successful DP add, a stale login-keychain copy can remain until a later delete. Reads prefer DP.

## Proof notes

High-confidence admission requires a reachable trigger that breaches the trust model beyond the accepted policy. None of the inspected paths send streaming credentials to a host other than `open.feishu.cn`, disable peer certificate checks, log secrets on the candidate surface, honor an injected production transport, hop factory/packet/finish to URLSession, hardcode CDN IPs, or load Keychain from AppDelegate for launch-at-login.

verdict: pass
findings_blocking: 0
review_conclusion: The candidate introduces no admitted security defect; bound UDP DNS plus IP_BOUND_IF CFStream TLS keeps peer validation on for open.feishu.cn without a custom verify block or hardcoded IPs, and the data-protection keychain migration does not add secret logging or a launch-time credential prompt path from AppDelegate.
