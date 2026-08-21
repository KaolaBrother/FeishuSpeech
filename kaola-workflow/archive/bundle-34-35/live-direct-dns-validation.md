# Live direct DNS + bound TLS vs VPN (2026-08-21)

VPN on: Astrill OpenVPN `utun6` `198.18.1.23`, Wi-Fi `en0` `192.168.0.145`.
System DNS (`scutil`): `1.1.1.2`. OpenVPN `0/1` sends `98.96.x` onto `utun6`.

Oracle: process-local TCP address from `getsockname`, not utun byte counters.

## System / VPN path (`getaddrinfo` + default socket)

```
dig open.feishu.cn A → CNAME cdnbuild → 98.96.242.53, 98.96.213.145
DEFAULT_LOCAL 198.18.1.23 → 98.96.213.145:443
TCP 566ms + TLS 433ms + HTTP 863ms
Server: volc-dcdn
```

## Production BoundTLSSocket (worktree, no IP literals)

Validator: `/tmp/bound-dns-validate` compiled from
`FeishuSpeech/Services/BoundTLSSocket.swift` + stub (not the installed build 11 app).

```
iface=en0
resolve_ms=717 addrs=218.12.78.91,121.29.103.96,… (mainland; not 98.96; not 198.18)
connect_ms=109 local=192.168.0.145
http_ms=57 head=HTTP/1.1 200 OK Server: Tengine
VERDICT: PHYSICAL
```

Earlier run after shortening UDP timeout: resolve 77ms, connect 128ms, HTTP 64ms, same physical local.

## What is not proven

- `/Applications/FeishuSpeech.app` build 11 still strings as old `bound-if` only; it does not contain this DNS path.
- A live Fn-hold `lsof` of the menu-bar app was not captured for this DNS revision.
- `xcodebuild test` hangs on the adhoc test host Keychain ACL.
