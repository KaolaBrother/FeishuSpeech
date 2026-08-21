# Finalization — Summary: bundle-34-35

## Delivered

- Streaming keep-alive resolves `open.feishu.cn` over bound UDP/53 (DHCP option 6, then recursor hostnames) and connects with `IP_BOUND_IF` + CFStream TLS. No IP literals, no `en0` string, no custom TLS verify. factory/packet/finish do not hop to URLSession on connect-class miss (issue #34).
- Issue #35 data-protection keychain is withdrawn. `KeychainCredentialStore` is again the issue #18 login-keychain store so existing App ID/Secret items load (issue #36). AppDelegate still applies launch-at-login from UserDefaults only.
- Pre-release live gate with Astrill up: system path local `198.18.1.23` / `volc-dcdn`; bound path 3/3 local `192.168.0.145` / `Tengine` (`pre-release-direct-gate.md`). Then `/Applications` Release 14.

## Files Changed

See Changed Paths.

## Test Coverage

- New/updated: `BoundTLSSocketTests`, `DirectFeishuKeepAliveSessionTests`, `TransportAttemptContextTests` (no URLSession hop), `AppSettingsCredentialStorageTests` (login-keychain pin, launch-at-login without credential store).
- `swiftlint`: 0 violations on the worktree.
- `xcodebuild … test` hung on the adhoc test host Keychain ACL; not claimed green.
- Release `xcodebuild … -configuration Release build` (version 14): succeeded.

## Validation

- Consumer receipt: `verdict: pass` in `kaola-workflow/bundle-34-35/.cache/final-validation.md`.
- Bound hash: `3c47d294d3eb48646e559913253975524d81c9e1d548fe961f7e468d3d4a9226`.
- Command: `swiftlint lint --quiet; /tmp/bound-dns-validate; xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Release -destination generic/platform=macOS -derivedDataPath /tmp/feishuspeech-bundle-34-36-release14 CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=D5KY7PZC5N CODE_SIGN_IDENTITY='Apple Development: Yanlei Chen (C2D65N458L)' CURRENT_PROJECT_VERSION=14 build`
- Reuse boundary: live 3/3 bound-vs-VPN gate and Release 14 build used this candidate tree (`6e16af6`). `xcodebuild test` was not green.

## Changed Paths

- `CHANGELOG.md`
- `FeishuSpeech/App/AppDelegate.swift`
- `FeishuSpeech/Models/AppSettings.swift`
- `FeishuSpeech/Services/BoundTLSSocket.swift`
- `FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift`
- `FeishuSpeech/Services/TransportAttemptContext.swift`
- `FeishuSpeechTests/AppSettingsCredentialStorageTests.swift`
- `FeishuSpeechTests/BoundTLSSocketTests.swift`
- `FeishuSpeechTests/DirectFeishuKeepAliveSessionTests.swift`
- `FeishuSpeechTests/TransportAttemptContextTests.swift`
- `README.md`
- `docs/README.md`
- `docs/api.md`
- `docs/architecture.md`
- `docs/decisions/D-18-01.md`
- `docs/decisions/D-32-01.md`
- `docs/decisions/D-34-01.md`

## Mission List

All items in `mission-list.md` are `done`, including #36 restore of login-keychain store and unique Applications Release 14 after the direct-connect gate.

## Documentation Docking

- `verdict: DOCKED` in `.cache/doc-docking.md`.
- `verdict: PASS` in `.cache/doc-updater.md`.

## Run gaps

- `manual:uat-crash` (Fn SIGTRAP in NSHostingView overlay constraints after recording start; overlay sources unchanged vs origin/main; filed as independent follow-up): filed: #37

## Follow-Up Items

- #37 remains open: Fn-hold process death in overlay constraints. Overlay was not changed in this run.

## Status: ARCHIVED AFTER FINAL GIT GATE

## Sink Findings

post_rebase_tests: skipped

archived_paths:
- kaola-workflow/archive/bundle-34-35/.cache/dispatch-log.jsonl
- kaola-workflow/archive/bundle-34-35/.cache/doc-docking.md
- kaola-workflow/archive/bundle-34-35/.cache/doc-updater.md
- kaola-workflow/archive/bundle-34-35/.cache/final-validation.md
- kaola-workflow/archive/bundle-34-35/.cache/origin/selection-record.json
- kaola-workflow/archive/bundle-34-35/.cache/run-gaps-manual.md
- kaola-workflow/archive/bundle-34-35/.cache/run-gaps.json
- kaola-workflow/archive/bundle-34-35/code-review.md
- kaola-workflow/archive/bundle-34-35/doc-update.md
- kaola-workflow/archive/bundle-34-35/finalization-summary.md
- kaola-workflow/archive/bundle-34-35/implement-green-34.md
- kaola-workflow/archive/bundle-34-35/implement-green-35.md
- kaola-workflow/archive/bundle-34-35/live-direct-dns-validation.md
- kaola-workflow/archive/bundle-34-35/mission-list.md
- kaola-workflow/archive/bundle-34-35/pre-release-direct-gate.md
- kaola-workflow/archive/bundle-34-35/security-review.md
- kaola-workflow/archive/bundle-34-35/test-red-34.md
- kaola-workflow/archive/bundle-34-35/test-red-35.md
- kaola-workflow/archive/bundle-34-35/workflow-state.md
