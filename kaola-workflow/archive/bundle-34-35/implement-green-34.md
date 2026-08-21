# Issue #34 bound physical DNS / no URLSession hop — implement receipt

Date: 2026-08-21

## task

Implement bound UDP/53 physical-interface DNS (DHCP nameservers, no IP literals, skip
`198.18.0.0/15` via bitmask) and remove the URLSession hop on keep-alive connect-class
miss so the #34 tests pass. Do not hardcode any dotted-quad address.

Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/bundle-34-35`

## verification tier

`build-green`

Intended tier was `tests-green`. `xcodebuild test` / `test-without-building` could not
execute XCTest: the macOS test host hangs in `#35` `KeychainCredentialStore.read` during
`AppSettings.load()` at `MainViewModel` init (login-keychain `SecKeychainItemCopyContent`),
before any `#34` test body runs. Production compile and swiftlint of the `#34` files are
green.

## files changed

- `FeishuSpeech/Services/BoundTLSSocket.swift` (new untracked file; not in HEAD)
- `FeishuSpeech/Services/TransportAttemptContext.swift`

Not edited (already used runtime `NWInterface.name` + `BoundTLSSocket.connect`):
`FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift`.

Not edited (parallel `#35` owner): Keychain / AppSettings / AppDelegate.

## what landed

`BoundPhysicalDNS` in `BoundTLSSocket.swift`:

- `ipv4ARecords(from:)` parses DNS A RDATA, follows pointer compression `0xC00C`,
  collects type=1 from answer + additional, drops the tunnel range with
  `(ip & 0xFFFE_0000) == 0xC612_0000`.
- Resolve path: physical interface name already passed into `BoundTLSSocket.connect`
  → `SCDynamicStoreCopyDHCPInfo` / `DHCPInfoGetOptionData` option 6 → skip tunnel
  nameservers → bound `SOCK_DGRAM` UDP port 53 with `IP_BOUND_IF` (~2s timeout) →
  TCP `IP_BOUND_IF` to remaining A records in order, CFStream TLS, SNI = `host`
  (`open.feishu.cn`). `getaddrinfo` only after DHCP UDP yields no A records.
- No dotted-quad literals, no `en0`, no Feishu CDN allowlist, no custom verify block.

`TransportAttemptContext.send`:

- keep-alive is primary for factory/packet/finish; connect-class miss rethrows; no
  URLSession hop.
- abort uses keep-alive when present.
- injected keep-alive is reused on the next send after a first miss (sticky-direct
  still invalidates after a later miss).

## verification commands

Dotted-quad scan (no matches, rg exit 1):

```
rg -n '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
  FeishuSpeech/Services/BoundTLSSocket.swift \
  FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift \
  FeishuSpeech/Services/TransportAttemptContext.swift
# EXIT:1
```

Source pins in `BoundTLSSocket.swift`: `SOCK_DGRAM`, `IPPROTO_UDP`, `IP_BOUND_IF`,
`dnsPort: UInt16 = 53`, `0xC612_0000`, `0xFFFE_0000`,
`SCDynamicStoreCopyDHCPInfo`, `DHCPInfoGetOptionData`. Absent: `en0`,
`98.96.213.145`, `98.96.242.53`, `sec_protocol_options_set_verify_block`.
`DirectFeishuKeepAliveSession.swift` still has `open.feishu.cn`.

SwiftLint (0 violations):

```
swiftlint lint FeishuSpeech/Services/BoundTLSSocket.swift \
  FeishuSpeech/Services/TransportAttemptContext.swift
# SWIFTINT_EXIT:0
```

Build:

```
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/feishuspeech-bundle-34-35-impl-34c \
  build-for-testing
# ** TEST BUILD SUCCEEDED **
```

## before

HEAD `276c470d86e64634f70ebf2252e7a62ea94c884c`.

```
xcodebuild ... -derivedDataPath /tmp/feishuspeech-bundle-34-35-impl-34-baseline \
  -only-testing:FeishuSpeechTests/BoundTLSSocketTests \
  -only-testing:FeishuSpeechTests/DirectFeishuKeepAliveSessionTests \
  -only-testing:FeishuSpeechTests/TransportAttemptContextTests test
```

**TEST FAILED** (compile): `cannot find 'BoundPhysicalDNS' in scope` in
`BoundTLSSocketTests.swift:54` and `:66`.

Production `BoundTLSSocket.swift` was untracked and resolved with `getaddrinfo` only.
`TransportAttemptContext.send` hopped to URLSession on connect-class miss; abort took
the URLSession slice first.

## after

**TEST BUILD SUCCEEDED** at `/tmp/feishuspeech-bundle-34-35-impl-34c`.

`xcodebuild test-without-building` with the three `#34` classes launched the test host
(`FeishuSpeech` pid 48731) and never reached XCTest. `sample 48731` showed the main
thread blocked in:

```
FeishuSpeechApp → MainViewModel.init → AppSettings.load()
  → AppSettings.loadCredential → KeychainCredentialStore.read
  → KeychainCredentialStore.copyMatching
  → SecItemCopyMatching → SecKeychainItemCopyContent
```

That path is the parallel `#35` keychain change. Several other hung hosts from
`/tmp/feishuspeech-bundle-34-35-impl-35-isolated` were in the same state. `#34` test
bodies (source pins, DNS fixture, TransportAttemptContext mocks) do not themselves
touch the keychain.

Re-run `xcodebuild test` for `BoundTLSSocketTests` /
`DirectFeishuKeepAliveSessionTests` / `TransportAttemptContextTests` after `#35`
unblocks `AppSettings.load()` at process start.

## corner cut

DHCP UDP is preferred; `getaddrinfo` remains last resort if DHCP option 6 is empty
or every nameserver yields only tunnel A records. Abort without an injected/created
keep-alive still uses URLSession. Logs do not include IPs, interface names, tokens,
PCM, transcripts, or stream IDs.
