# Pre-release direct-connect gate (2026-08-21)

Worktree: `.kw/worktrees/bundle-34-35`
Validator: compiled from **current** `FeishuSpeech/Services/BoundTLSSocket.swift` (not an old `/tmp` binary).
VPN: Astrill `utun6` `198.18.1.23` up. System DNS `1.1.1.2`.

## Control (system `getaddrinfo` + default socket)

- `open.feishu.cn` → `98.96.242.53`
- local **`198.18.1.23`** (VPN)
- HTTP `Server: volc-dcdn`
- `route get 98.96.213.145` → `utun6` / `198.18.0.1`

## Bound production socket (3/3)

| Round | resolve | A records | TCP local | HTTP | Server |
|---|---|---|---|---|---|
| 1 | 626ms | 16 mainland, no `98.96`/`198.18` | `192.168.0.145` | 90ms | Tengine |
| 2 | 14ms | same class | `192.168.0.145` | 54ms | Tengine |
| 3 | 14ms | same class | `192.168.0.145` | 59ms | Tengine |

`route get 218.11.15.29` and `101.72.238.84` → `en0` / `192.168.0.1`.

Verdict: `PHYSICAL x3`. Exit 0.

## Other gates

- `KeychainCredentialStore.swift` diff vs `origin/main`: empty (login-keychain, no DP).
- Login items `Siji.FeishuSpeech.credentials` `appId`/`appSecret` still present.
- No dotted-quad literals under `FeishuSpeech/Services`.
- factory/packet/finish do not hop to URLSession; abort hops only if keep-alive is absent.
- Overlay untouched.

Not proven: live Fn-hold `lsof` of the menu-bar app (owner UAT).
