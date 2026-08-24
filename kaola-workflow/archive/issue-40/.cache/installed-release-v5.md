# Issue #40 v5 installed Release receipt

timestamp: 2026-08-24T18:43:46+08:00
uat_status: pending_owner
issue_state: open
github_evidence_comment: https://github.com/KaolaBrother/FeishuSpeech/issues/40#issuecomment-5394122722

## Candidate identity

- branch: `workflow/issue-40`
- commit: `bf1d81d3ff2fa8ee0bc260ee8ed87fc6d7938c8c`
- pushed remote branch: `origin/workflow/issue-40`
- validated candidate hash: `6ff2b26b781ede9683f8fee49a1e7c0d5e1dc8b7752f455a9c3e9a67fca90d5d`
- build command: `xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Release -derivedDataPath /tmp/feishuspeech-issue40-bf1d81d-release build`
- build result: `BUILD SUCCEEDED`

## Installed artifact

- path: `/Applications/FeishuSpeech.app`
- bundle identifier: `Siji.FeishuSpeech`
- bundle short version: `1.0`
- bundle build: `8`
- architecture: `arm64`
- executable SHA-256: `1ddd9bd08a0a45866233ddd510c2e0013f19ad2b08d46ff0682ec0eabe1838b0`
- code directory hash: `b33203991a38cedfa991c7f0903a5cdade74c669`
- signature: ad hoc local Release; `codesign --verify --deep --strict` passed
- rejected previous installed executable SHA-256: `4a5bc6b1d76d3b56c52e133db8e6b26b9f9a9ac3c8d15ccf898c92a231618fdb`
- byte comparison: the installed bundle matched the built Release with `diff -qr` before the temporary build bundle was removed

## Sole-copy audit

- removed 291 exact `FeishuSpeech.app` build bundles under the project's Xcode DerivedData and bounded `/private/tmp/issue40-*` or `/private/tmp/feishuspeech-*` validation roots
- Spotlight existing bundle audit: only `/Applications/FeishuSpeech.app`
- `/Applications` and `~/Applications` audit: only `/Applications/FeishuSpeech.app`
- Xcode DerivedData audit: zero remaining bundles
- bounded `/private/tmp` audit: zero remaining bundles

## Runtime identity

- launched installed application after the audit
- PID at launch verification: `24793`
- `ps` command path: `/Applications/FeishuSpeech.app/Contents/MacOS/FeishuSpeech`
- `lsof` text executable path: `/Applications/FeishuSpeech.app/Contents/MacOS/FeishuSpeech`

## Quality gates bound to this candidate

- focused nine-suite matrix: 324 tests, 0 failures, 0 skips
- full project target: 537 tests, 0 failures, 1 expected issue-#34 live-TCP skip
- Debug and Release builds: pass
- strict SwiftLint: 0 violations
- correctness review R6: pass, zero blocking findings
- security review R6: pass, zero blocking findings
- accepted path contains no clipboard, Cmd+V, application activation, ambient retarget, or legacy direct output
- recording and recognition remain independent asynchronous roots

## Remaining owner gate

The installed candidate is intentionally not merged and Issue #40 remains open. Owner UAT must confirm the real third-party target behavior: hold Fn and observe streaming preview; release Fn and wait for the durable editable draft; edit it; confirm with preview-local Return or Send; observe exactly one output attempt at the original target; verify typing/editing before confirmation creates no external character, image paste, activation, or other signal. A failed UAT rejects this candidate and keeps the issue open.
