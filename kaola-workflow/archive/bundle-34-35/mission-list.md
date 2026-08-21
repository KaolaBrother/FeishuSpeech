# Mainland DNS on bound keep-alive; stop URLSession VPN hop; no double keychain prompt (#34, #35)

- item: Pin failing tests for physical-interface DNS (skip 198.18.0.0/15, no getaddrinfo-only resolve, no Feishu CDN IP list, no en0 string) and for TransportAttemptContext never hopping factory/packet/finish to URLSession on a keep-alive connect-class miss
  status: done
  dispatched: tdd-guide on worktree `.kw/worktrees/bundle-34-35`; tests under `FeishuSpeechTests/{DirectFeishuKeepAliveSession,TransportAttemptContext,BoundTLS}*Tests.swift`; red evidence `kaola-workflow/bundle-34-35/test-red-34.md`
  result: RED compile `cannot find 'BoundPhysicalDNS' in scope`; hop tests authored; evidence `test-red-34.md`; xcodebuild TEST FAILED on worktree `276c470`

- item: Pin failing tests for data-protection keychain queries, AppDelegate launch-at-login from UserDefaults without reading credentials, and legacy login-keychain migration
  status: done
  dispatched: tdd-guide on worktree `.kw/worktrees/bundle-34-35`; tests under `FeishuSpeechTests/AppSettingsCredentialStorageTests.swift` (and AppDelegate pin if needed); red evidence `kaola-workflow/bundle-34-35/test-red-35.md`
  result: tests in `AppSettingsCredentialStorageTests.swift`; compile-fail seam `AppSettings.launchAtLoginPreference(from:)`; evidence `test-red-35.md`

- item: Implement bound UDP DNS plus IP_BOUND_IF keep-alive and remove the URLSession hop so the #34 tests pass without editing those tests
  status: done
  dispatched: implementer (re-dispatched after owner confirmed no IP literals) on worktree `.kw/worktrees/bundle-34-35`; production only `FeishuSpeech/Services/{BoundTLSSocket,DirectFeishuKeepAliveSession,TransportAttemptContext}.swift`; DNS servers from DHCP/SystemConfiguration at runtime — no dotted-quad literals; green evidence `kaola-workflow/bundle-34-35/implement-green-34.md`
  result: No dotted-quads in production. DHCP UDP + recursor hostnames (`dns.alidns.com`), bound TCP local 192.168.0.145, mainland A records, HTTP 42ms Tengine. Debug BUILD SUCCEEDED. `xcodebuild test` hangs on test-host keychain (adhoc). Evidence `implement-green-34.md` plus live `/tmp/bound-dns-validate`.

- item: Implement data-protection keychain plus launch-at-login without Keychain so the #35 tests pass without editing those tests
  status: done
  dispatched: implementer on worktree `.kw/worktrees/bundle-34-35`; production only `FeishuSpeech/{Services/KeychainCredentialStore,Models/AppSettings,App/AppDelegate}.swift`; green evidence `kaola-workflow/bundle-34-35/implement-green-35.md`
  result: DP keychain + migration; `launchAtLoginPreference(from:)`; AppDelegate no longer `AppSettings.load()`. Debug BUILD SUCCEEDED. Official xcodebuild test blocked on #34 `BoundPhysicalDNS`. Evidence `implement-green-35.md`. Adhoc DP `-34018` needs Apple Development signing (later mission).

- item: Run the macOS suite, Debug/Release, and swiftlint on the worktree; live-measure token/stream TCP local address is physical IPv4 never 198.18
  status: done
  dispatched: self — Debug BUILD SUCCEEDED; live `/tmp/bound-dns-validate`; xcodebuild test hangs on adhoc test-host keychain; evidence in this item result when closed
  result: Live VPN-vs-direct in `live-direct-dns-validation.md` (system local 198.18 / 98.96 vs bound local 192.168 HTTP 57ms Tengine). Debug BUILD SUCCEEDED. `xcodebuild test` hung (adhoc Keychain); killed. swiftlint warning sorted_imports on BoundTLSSocket.

- item: Code and security review of DNS bind, hop removal, and keychain migration
  status: done
  dispatched: code-reviewer → `kaola-workflow/bundle-34-35/code-review.md`; security-reviewer → `kaola-workflow/bundle-34-35/security-review.md`
  result: code-reviewer approve; security-reviewer pass; 0 blocking findings

- item: Dock a new ADR plus api.md, architecture.md, and CHANGELOG from verified behavior
  status: done
  dispatched: doc-updater on worktree `.kw/worktrees/bundle-34-35`; evidence `kaola-workflow/bundle-34-35/doc-update.md`
  result: D-34-01 plus pointers on D-32-01/D-18-01; api.md, architecture.md, README, CHANGELOG; evidence `doc-update.md`

- item: Unique /Applications Release signed with Apple Development, not adhoc
  status: done
  dispatched: self — Release CURRENT_PROJECT_VERSION=12, team D5KY7PZC5N, replace `/Applications/FeishuSpeech.app`, launch
  result: `/Applications/FeishuSpeech.app` 1.0 (12) had #35 DP-keychain regression; superseded by #36 restore

- item: Restore login-keychain credential store from origin/main so App ID/Secret persist; do not touch overlay; rebuild unique Applications Release
  status: done
  dispatched: self — revert `KeychainCredentialStore.swift` to origin/main; keep AppDelegate `launchAtLoginPreference`; keep #34 transport; Release 13; evidence this item result
  result: Store is origin/main login-keychain (no DP). Overlay untouched. Pre-release gate `pre-release-direct-gate.md`: control VPN 198.18/volc-dcdn; bound 3/3 local 192.168 Tengine. Then `/Applications/FeishuSpeech.app` 1.0 (14), Apple Development, PID 24523.
  result: `/Applications/FeishuSpeech.app` 1.0 (12), TeamIdentifier D5KY7PZC5N, not adhoc; strings include `dns.alidns.com` / `public1.114dns.com`; no `98.96`/`223.5.5.5`; running PID 13289. Owner UAT is the gate.
