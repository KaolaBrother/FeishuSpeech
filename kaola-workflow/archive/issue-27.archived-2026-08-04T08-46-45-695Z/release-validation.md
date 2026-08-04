# Issue #27 Release validation and installation

## Candidate

- Binary source commit: `b10a40c8231cec98ed08a869bf1450e9b056b577`.
- Final documentation-only head: `b78e68ab8c9f7e596a3dc3b9998d32e8eed1cc6a`.
- Release metadata: version 1.0, build 8.
- Installed executable SHA-256: `f53ff4c89ff222bcf1fcc6f50d85833fa8250be16cd8b0863d93ec94fe607e3f`.

## Automated validation

- Isolated build-for-testing: passed.
- Direct lifecycle-free XCTest bundle: 316/316 passed.
- Strict SwiftLint: 27 files, 0 violations.
- Debug build: passed.
- Release build: passed.
- Strict deep code-sign verification: passed with the local ad-hoc signature; no Developer ID or notarization claim.
- `git diff --check`: passed.

## Applications installation

- Replaced `/Applications/FeishuSpeech.app` with Release 1.0 build 8.
- Terminated the previously running build-7 process before replacement.
- `/Applications` contains exactly one matching `FeishuSpeech.app` bundle.
- The build-8 app was not launched after installation and no matching process was running at verification.
- The prior build-7 bundle was moved recoverably to `/Users/ylpromax5/.Trash/FeishuSpeech-build7-pre-release-drain-20260804T163600.app`.

## UAT boundary

- Automated validation did not trigger UI automation, simulate Fn, request macOS permissions, or use the owner's credentials.
- Real-credential cross-application UAT remains the only issue-closure gate.
