# Issues #34 and #35 documentation docking receipt

## Verdict

DOCKED. Worktree documentation matches the verified bound physical DNS / no URLSession hop
contract (#34) and the data-protection keychain / AppDelegate-without-credential-load contract
(#35). No claim is made that `xcodebuild test` is green, that the installed `/Applications`
build contains this DNS path, or that a live Fn-hold `lsof` was captured.

## Evidence reconciled

- Issues: https://github.com/KaolaBrother/FeishuSpeech/issues/34 ,
  https://github.com/KaolaBrother/FeishuSpeech/issues/35
- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/bundle-34-35`
- Live: `kaola-workflow/bundle-34-35/live-direct-dns-validation.md`
- Reviews: `kaola-workflow/bundle-34-35/code-review.md` (approve);
  `kaola-workflow/bundle-34-35/security-review.md` (pass); 0 blocking findings
- GREEN receipts: `implement-green-34.md`, `implement-green-35.md` (Debug BUILD SUCCEEDED;
  official `xcodebuild test` hung on adhoc test-host Keychain)

Production, verified by reading source (not re-run as a suite):

- No dotted-quad literals in `BoundTLSSocket.swift`,
  `DirectFeishuKeepAliveSession.swift`, or `TransportAttemptContext.swift` (grep
  `[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+` empty). Hostname/SNI `open.feishu.cn`. No `en0` string under
  `FeishuSpeech/Services`. No `sec_protocol_options_set_verify_block` under `FeishuSpeech/`.
- `BoundPhysicalDNS.resolveIPv4`: DHCP option 6 on the runtime physical interface, then recursor
  *hostnames* `dns.alidns.com` / `public1.114dns.com` (not IPs). Skip `198.18.0.0/15` via
  `(ip & 0xFFFE_0000) == 0xC612_0000`. Bound UDP/53 `IP_BOUND_IF`. TCP `IP_BOUND_IF` over remaining
  A records, CFStream TLS with `kCFStreamSSLPeerName` = `open.feishu.cn` and
  `kCFStreamSSLValidatesCertificateChain` on. Connected local IPv4 prefix `198.18.` is closed
  without HTTP.
- `DirectFeishuKeepAliveSession.startConnection` calls
  `BoundTLSSocket.connect(host: feishuDirectHost, interfaceName:)` with runtime `NWInterface.name`.
- `TransportAttemptContext.send`: keep-alive primary; factory/packet/finish connect-class miss
  rethrows and does **not** hop to URLSession; completed HTTP including 4xx does not hop;
  `CancellationError` does not hop; sticky-direct after keep-alive success; new context starts on
  keep-alive; abort uses keep-alive when present, URLSession only when keep-alive is absent;
  production first-send miss drops the session; mid-attempt sticky-direct drop still invalidates.
- D-32-01 URLSession-fallback / fake-ip-out-of-scope is superseded for streaming token +
  `stream_recognize`. `file_recognize` / `recognizeSpeech` still `executeURLRequest`.
- Keychain: `kSecUseDataProtectionKeychain`, `AfterFirstUnlockThisDeviceOnly` on add, migrate
  login items then delete. `AppDelegate` uses `launchAtLoginPreference(from:)` and does not
  `AppSettings.load()`. `MainViewModel.init` still loads credentials once.

Live with Astrill `utun6` up (unsigned validator compiled from production `BoundTLSSocket.swift`,
not the installed build 11 app):

- system path local `198.18.1.23` → `98.96` HTTP ~863 ms `volc-dcdn`
- bound path local `192.168.0.145`, mainland A records, HTTP 57 ms Tengine

Missing evidence (not invented):

- `xcodebuild test` hung on adhoc test-host Keychain (`SecKeychainItemCopyContent` / `-34018`).
  Do not claim a green suite.
- `/Applications/FeishuSpeech.app` build 11 still strings as old `bound-if` only; it does not
  contain this DNS path.
- A live Fn-hold `lsof` of the menu-bar app was not captured for this DNS revision.
- Unique `/Applications` Release signed with Apple Development is a later mission (`mission-list`
  item still `todo`).

## Updated documentation surfaces (worktree)

Paths are under `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/bundle-34-35`.

- `docs/decisions/D-34-01.md` **(new)** — bound physical DNS + no URLSession hop; no IP
  literals; CFStream TLS peer name `open.feishu.cn` with chain validation on; live validator
  numbers and hung-suite caveat in Consequences.
- `docs/decisions/D-32-01.md` — header pointer that URLSession connect-class hop and fake-ip /
  physical-interface DNS out-of-scope are superseded by D-34-01 / issue #34. Decision body not
  rewritten.
- `docs/decisions/D-18-01.md` — header pointer for data-protection keychain, login-item migrate
  then delete, `launchAtLoginPreference(from:)`, and AppDelegate no longer `AppSettings.load()`.
  Decision body not rewritten.
- `docs/api.md` — replaced keep-alive Network.framework + URLSession-hop paragraph with
  `BoundTLSSocket` bound UDP/53 + `IP_BOUND_IF` TLS and no factory/packet/finish hop; credential
  storage now documents DP keychain and AppDelegate UserDefaults-only launch-at-login; HTTP
  transport section no longer claims system DNS for streaming token / `stream_recognize`; see-also
  includes D-34-01 and D-18-01; test caveat records hung `xcodebuild test` and unsigned validator.
- `docs/architecture.md` — same transport-paragraph replacement; AppSettings section documents
  DP keychain, login-item migrate-then-delete, and AppDelegate `launchAtLoginPreference`.
- `docs/README.md` — listed D-34-01 and D-18-01; noted D-32-01 hop/fake-ip superseded; design-index
  pointer that #28–#31 transport order was later superseded by D-32-01 then D-34-01 for hop/DNS.
- `CHANGELOG.md` — `[Unreleased]` Fixed entries for issues #34 and #35 (quoted below).
- `README.md` — feature bullet plus VPN FAQ: streaming token / `stream_recognize` stay on bound
  physical keep-alive and do not hop to URLSession; new FAQ for launch keychain prompts.

User-visible CHANGELOG lines:

> 修复 VPN 开启时流式识别仍走海外 CDN / TUN：keep-alive 在运行时物理网卡上做 bound UDP/53 DNS（DHCP option 6，再回退 recursor 主机名 `dns.alidns.com` / `public1.114dns.com`，跳过 `198.18.0.0/15`），TCP `IP_BOUND_IF` + CFStream TLS（SNI `open.feishu.cn`，证书链校验开启）。无 IP 字面量、不绑定 `en0`、无自定义 TLS verify。factory/packet/finish 在 keep-alive 连接类失败时不再 hop 到 URLSession。整文件识别仍走 URLSession（issue #34）

> 修复启动时连续弹出两次钥匙串授权：凭据写入 data-protection keychain（`kSecUseDataProtectionKeychain`，`AfterFirstUnlockThisDeviceOnly`），从 login keychain 迁移后删除；AppDelegate 用 `launchAtLoginPreference(from:)` 同步开机启动，不再 `AppSettings.load()`（issue #35）

## Skipped (no real change, or instructed historical)

- `scripts/codemaps/` and `docs/CODEMAPS/` — neither exists; no codemap tooling to regenerate.
- `docs/designs/capture-recognition-split-direct-connect.md` — historical confirmed design for
  #28–#31; not rewritten. Index pointer in `docs/README.md` is the supersession notice.
- `docs/streaming-speech-design.md` — issue #27 snapshot/output design; no transport-order
  paragraph to reconcile.
- `docs/conventions.md` — coding/review conventions unchanged.
- `docs/decisions/D-28-01.md` Decision body — user asked a pointer from D-32-01, not a silent
  rewrite of D-28-01. Header already points at D-32-01 for transport order.
- `CLAUDE.md` / `AGENTS.md` — project rules and redirect unchanged. Known Gotcha for issue #18
  (Keychain-backed credentials; UserDefaults are migration inputs) remains true; #35 details live
  on D-18-01.
- `.env.example` — not present.
- `kaola-workflow/ROADMAP.md` — generated mirror; not hand-edited.
- Production Swift and tests — out of doc-updater custody; not edited.

## Commands

- Read worktree docs, `BoundTLSSocket.swift` / `BoundPhysicalDNS`,
  `DirectFeishuKeepAliveSession.startConnection`, `TransportAttemptContext.send`,
  `KeychainCredentialStore`, `AppSettings.launchAtLoginPreference(from:)`,
  `AppDelegate.applicationDidFinishLaunching`, `FeishuAPIService.recognizeSpeech`, and
  `kaola-workflow/bundle-34-35/{live-direct-dns-validation,code-review,security-review,implement-green-34,implement-green-35,mission-list}.md`.
- Fetched GitHub issues #34 and #35 for contract/acceptance language.
- Detection: `scripts/` does not exist; `docs/CODEMAPS/` does not exist.
- Grep: no dotted-quads in the three transport files; no `en0` under `FeishuSpeech/Services`;
  no `sec_protocol_options_set_verify_block` under `FeishuSpeech/`; recursor hostnames and
  `kSecUseDataProtectionKeychain` / `launchAtLoginPreference` present in production.
- Relative Markdown links on the updated doc files: `docs/README.md` targets
  `architecture.md`, `api.md`, `streaming-speech-design.md`,
  `designs/capture-recognition-split-direct-connect.md`, `conventions.md`, `decisions/`,
  `decisions/D-18-01.md`, `D-25-01.md`, `D-26-01.md`, `D-27-01.md`, `D-28-01.md`,
  `D-32-01.md`, `D-34-01.md`, `../CHANGELOG.md` — all exist.
  `docs/api.md` see-also `decisions/D-25-01.md` … `D-34-01.md`, `D-18-01.md`,
  `streaming-speech-design.md` — all exist.
  `docs/decisions/D-32-01.md` → `D-34-01.md` exists.
- Did **not** re-run `xcodebuild test` (prior hung adhoc Keychain receipt). Did **not** invent
  a green suite count.
- No shell tool in this agent: `git diff --check` / `git status` were not executed.

This receipt: `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/bundle-34-35/doc-update.md`
