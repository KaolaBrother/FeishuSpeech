# Issue #40 v6 installed Release receipt

timestamp: 2026-08-24T19:23:54+08:00
uat_status: pending_accessibility_reauthorization_and_owner
issue_state: open
github_evidence_comment: https://github.com/KaolaBrother/FeishuSpeech/issues/40#issuecomment-5394529872

## Source identity

- production repair commit: `39848ee4`
- documentation/install-state head: `ae53360`
- branch pushed to: `origin/workflow/issue-40`

## Installed artifact

- path: `/Applications/FeishuSpeech.app`
- bundle identifier: `Siji.FeishuSpeech`
- version/build: `1.0 (8)`
- architecture: arm64
- executable SHA-256: `2adb263bb8bc1b4b6ecc0bac1a1718da007c5432a1b65473af9954ff58c17208`
- CDHash: `77d8046dc8a48d3e209070f164bd57e76ca8ec64`
- signature: `Apple Development: Yanlei Chen (C2D65N458L)`
- TeamIdentifier: `D5KY7PZC5N`
- designated requirement: stable identifier + Apple anchor + development certificate identity
- `codesign --verify --deep --strict`: pass
- built-versus-installed `diff -qr`: pass before the temporary build bundle was removed

## Sole-copy audit

- `/Applications` and `~/Applications`: only `/Applications/FeishuSpeech.app`
- project Xcode DerivedData: zero `FeishuSpeech.app` bundles
- project workspace: zero embedded `FeishuSpeech.app` bundles
- all five v6 validation DerivedData roots and the signed-install DerivedData root under
  `/private/tmp` were removed after verification
- Spotlight bundle-ID audit: only `/Applications/FeishuSpeech.app`

## Runtime

- running PID: `45760`
- process executable: `/Applications/FeishuSpeech.app/Contents/MacOS/FeishuSpeech`
- System Settings opened to Privacy & Security > Accessibility
- current v6 runtime reports Accessibility false because the remaining TCC row is the rejected v5
  ad-hoc CDHash requirement; the owner must authorize the newly signed current binary

Issue #40 remains open. No claim is made that the target consumed text until owner UAT completes.
