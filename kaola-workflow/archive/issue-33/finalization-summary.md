# Finalization — Summary: issue-33

## Delivered

- Streaming Feishu transport skips VPN/TUN: keep-alive `NWConnection` is primary with `preferNoProxies` and `prohibitedInterfaceTypes = [.other]` (issue #33).
- URLSession is connect-class / no-HTTP fallback once per operation; completed HTTP and `CancellationError` do not hop.
- Sticky-direct after keep-alive success; sticky-URLSession after fallback success; a new attempt starts on keep-alive again.
- First-send keep-alive miss does not invalidate URLSession; mid-attempt sticky-direct drop still invalidates.
- Q2-B reversal recorded as D-32-01; no `en0` bind, no CDN IPs, no toggle; `file_recognize` unchanged.

## Files Changed

See Changed Paths.

## Test Coverage

- Focused: `DirectFeishuKeepAliveSessionTests` + `TransportAttemptContextTests` 13/13.
- Full macOS suite: 352 passed, 0 failed (`/tmp/feishuspeech-issue-33-impl-full`).
- `swiftlint`: 0 violations.
- Worktree Release `xcodebuild … -configuration Release build`: succeeded.

## Validation

- Consumer receipt: `verdict: pass` in `kaola-workflow/issue-33/.cache/final-validation.md`.
- Bound hash: `5a160b6a13977981d4404ebfd344a5aabf2b197d2a36338ceb01c79bf4eb6f8c`.
- Command: `xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue-33-impl-full test`
- Reuse boundary: the 352/0 suite and swiftlint ran on the production+test tree before docs docking; docs-only edits (`D-32-01`, api/architecture/README/CHANGELOG pointers) are outside that test rerun. Release build was of the production tree on the worktree.

## Changed Paths

- `CHANGELOG.md`
- `FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift`
- `FeishuSpeech/Services/TransportAttemptContext.swift`
- `FeishuSpeechTests/DirectFeishuKeepAliveSessionTests.swift`
- `FeishuSpeechTests/TransportAttemptContextTests.swift`
- `README.md`
- `docs/README.md`
- `docs/api.md`
- `docs/architecture.md`
- `docs/decisions/D-28-01.md`
- `docs/decisions/D-32-01.md`

## Mission List

All five items in `mission-list.md` are `done`: failing tests, keep-alive-primary implementation, suite/Release/lint, code+security review, docs docking.

## Documentation Docking

- `verdict: DOCKED` in `.cache/doc-docking.md`.
- `verdict: PASS` in `.cache/doc-updater.md`.

## Run gaps

## Follow-Up Items

None. Clash fake-ip DNS and corp `includeAllNetworks` were accepted residuals, not run-discovered defects.

## Status: ARCHIVED AFTER FINAL GIT GATE

## Sink Findings

post_rebase_tests: skipped

archived_paths:
- kaola-workflow/archive/issue-33/.cache/dispatch-log.jsonl
- kaola-workflow/archive/issue-33/.cache/doc-docking.md
- kaola-workflow/archive/issue-33/.cache/doc-updater.md
- kaola-workflow/archive/issue-33/.cache/final-validation.md
- kaola-workflow/archive/issue-33/.cache/origin/selection-record.json
- kaola-workflow/archive/issue-33/.cache/run-gaps.json
- kaola-workflow/archive/issue-33/code-review.md
- kaola-workflow/archive/issue-33/doc-update.md
- kaola-workflow/archive/issue-33/finalization-summary.md
- kaola-workflow/archive/issue-33/implement-green.md
- kaola-workflow/archive/issue-33/mission-list.md
- kaola-workflow/archive/issue-33/security-review.md
- kaola-workflow/archive/issue-33/test-red.md
- kaola-workflow/archive/issue-33/validation.md
- kaola-workflow/archive/issue-33/workflow-state.md
