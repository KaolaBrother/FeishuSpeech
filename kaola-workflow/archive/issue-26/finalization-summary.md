# Finalization — Summary: issue-26

## Delivered

- Closed the recursive `.error` feedback path that repeatedly re-entered abnormal teardown and prevented the recording overlay hide animation from completing.
- Made terminal provider/stream events own exactly one teardown and prevented terminal packet handling from falling through into normal finish.
- Sanitized provider authentication failure to the fixed public message `认证失败，请检查应用凭据` without exposing provider detail, credentials, or transcript content.
- Preserved generation-gated late-callback rejection, current-focus delivery, and Secure Input behavior.
- Installed one verified Release 1.0 (build 1) at `/Applications/FeishuSpeech.app` without launching it.

## Files Changed

- Production: `FeishuSpeech/Services/HotKeyService.swift`, `FeishuSpeech/ViewModels/MainViewModel.swift`.
- Tests: `FeishuSpeechTests/HotKeyServiceTests.swift`, `FeishuSpeechTests/StreamingMainViewModelTests.swift`.
- Documentation: `README.md`, `CHANGELOG.md`, `docs/api.md`, `docs/architecture.md`, `docs/streaming-speech-design.md`, `docs/decisions/D-25-01.md`.
- Workflow history: preserved the prior cursor-gate UAT archive under `kaola-workflow/archive/issue-26-cursor-gate-uat` before creating this cycle's archive.

## Test Coverage

- Added RED-first coverage for immediate provider terminal failure, overlay dismissal, exact-once generation teardown/cancel, late partial/final rejection, sanitized authentication feedback, and identical-error publication suppression.
- Final lifecycle-free XCTest result: 184 passed, 0 failed, 0 skipped.
- Strict SwiftLint: 0 violations across 26 production files.
- Debug build-for-testing and Release build both succeeded.
- Correctness review: PASS, 0 blocking findings.
- Security/privacy review: PASS, 0 blocking findings.

## Validation

The consumer receipt records `verdict: pass` against candidate hash `e46a379b50c7dc252750286d37e1e147d2706c75a9f4947daa833807a3cc84ef`. The 184/184 XCTest and Debug build cover the final code/test bytes; later changes were documentation docking and workflow/archive bookkeeping, which those commands do not consume. The final Release was rebuilt after documentation docking, passes strict code-sign verification, and its installed executable SHA-256 is `300e486b6d7174dd55c483478ec34b1d9699b09c4b6a794f1072cfbad2bbeb25`.

## Changed Paths

The finalize transaction appends its measured changed-path finding here.

## Documentation Docking

DOCKED. README, changelog, API, architecture, streaming design, and D-25-01 record the user-visible behavior, authentication-before-stream boundary, privacy mapping, lifecycle invariant, regression coverage, and owner-UAT boundary. Documentation navigation, environment schema, conventions, and repository instructions have explicit no-impact reasons.

## Run gaps

No run-discovered defect requires a new follow-up issue. The observed Feishu rejection is a documented owner-UAT/configuration boundary: it happened during tenant-token acquisition before the streaming endpoint and is not claimed as live-stream success.

## Follow-Up Items

- Keep GitHub issue #26 open for Yanlei's installed-Release UAT with valid App ID/App Secret, `speech_to_text:speech` permission, a published application, and a supported tenant edition.
- Real tenant streaming semantics and the target-application matrix remain UAT evidence, not local implementation claims.

## Status: ARCHIVED AFTER FINAL GIT GATE
