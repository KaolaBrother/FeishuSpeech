# Finalization — Summary: issue-26

## Delivered

- Diagnosed the installed build-5 one-word stall from privacy-safe runtime evidence: audio capture continued and 66 HTTP-200 streaming transactions completed over 13.55 seconds, placing the failure after transport.
- Replaced raw-scalar prefix suppression with generation-scoped, journal-indexed exact-once ownership. Every eligible held response on a distinct packet index now concatenates into one locally growing UTF-16 frontier, including equal, disjoint, shorter, and revised response values.
- Replay never re-owns historical packet indices; a previously failed index may be owned once when a replacement stream first returns a usable response for it.
- Live AX and PID-bound append owners receive the growing frontier while Fn remains held. Exact AX element, captured PID, Secure Input, target drift, delivery-uncertainty, permanent suspension, and no-resend boundaries remain fail-closed.
- Fn release synchronously closes response and retry admission before recorder/session draining. Action 2, in-flight packets, and late partial/final callbacks cannot create, append, replace, rewrite, paste, or copy output.
- Removed release-time one-shot/final-only output and manual clipboard recovery from the streaming coordinator.
- Separated held-recognition availability from output eligibility so disabled, unsafe, or ownerless output is not misreported as empty recognition or a stream failure while remaining zero-output and zero-copy.
- Added transcript-free receipt diagnostics containing only generation/retry ordinals, packet index, source/event/eligibility labels, UTF-16 lengths, coarse response shape, ownership, and typed/offered output outcome.

## Files Changed

- Production: `FeishuSpeech/ViewModels/MainViewModel.swift`.
- Tests: `FeishuSpeechTests/StreamingMainViewModelTests.swift`, `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift`.
- Documentation: `README.md`, `CHANGELOG.md`, `docs/README.md`, `docs/api.md`, `docs/architecture.md`, `docs/streaming-speech-design.md`, `docs/decisions/D-25-01.md`, `docs/decisions/D-26-01.md`.
- Workflow history: the prior build-5 archive is retained under `kaola-workflow/archive/issue-26-one-word-build5-uat` so this run can archive losslessly.

## Test Coverage

- RED-first tests reproduced disjoint/equal multi-response suppression, growing AX-range behavior, replay identity, action-2 mutation, and output-disabled completion classification before the production repairs.
- The final clean lifecycle-free direct XCTest bundle passed 272/272 with zero failures and zero unexpected failures.
- Coordinator coverage passed 71/71 and retains exact PID/AX, Secure Input, unsafe text, target drift, uncertain delivery, retry, cancellation, reset, sleep/wake, overlay privacy, recorder barrier, successor exclusion, and late-generation protections.
- Independent correctness review passed after its sole P2 recognition/output classification finding was fixed test-first and re-reviewed. Independent security/privacy review passed with zero findings.

## Validation

- Consumer validation receipt: `verdict: pass`.
- Validated candidate hash: `0734b758c2a9dff89a6425de139f8468bf6d7b4caf125477f81a359653534f05`.
- Exact direct XCTest command recorded in `.cache/final-validation.md`; result: 272 tests, 0 failures.
- `swiftlint lint --strict`: 27 production files, 0 violations.
- Clean build-for-testing, Debug build, and Release build succeeded with `CURRENT_PROJECT_VERSION=6` without launching the application. Existing unrelated Xcode concurrency/deprecation warnings remain outside this issue's changed production surface.
- Release 1.0 build 6 has bundle ID `Siji.FeishuSpeech`, a valid strict ad-hoc signature, and executable SHA-256 `b05753367fb31c235879fff7825bfdca7aaa8fce99ea9d8f040f86fe63448870`.

## Changed Paths

- `FeishuSpeech/ViewModels/MainViewModel.swift`
- `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift`
- `FeishuSpeechTests/StreamingMainViewModelTests.swift`
- `README.md`
- `CHANGELOG.md`
- `docs/README.md`
- `docs/api.md`
- `docs/architecture.md`
- `docs/streaming-speech-design.md`
- `docs/decisions/D-25-01.md`
- `docs/decisions/D-26-01.md`
- `kaola-workflow/archive/issue-26-one-word-build5-uat/`

## Documentation Docking

`verdict: DOCKED`. README, changelog, architecture, API, streaming design, documentation index, and issue #26 decision records now describe journal-index ownership, local frontier assembly, replay suppression, seal-only release, removal of release fallbacks, recognition/output separation, privacy diagnostics, retained safety boundaries, unknown provider semantics, and pending installed Release UAT.

## Run gaps

- The run-gap scanner observed no gap classes; no follow-up issue was fabricated.

## Follow-Up Items

- Keep GitHub issue #26 open until owner UAT verifies sustained multi-word visible output while Fn remains held in real target applications.
- Provider intermediate response semantics and target acceptance remain unverified externally; local concatenation is an explicit product policy, and `CGEventPostToPid` still provides no target-control acknowledgement.

## Installation

- `/Applications/FeishuSpeech.app` is the sole matching app under `/Applications`, Release 1.0 build 6, and matches the validated executable hash above.
- The previously running build 5 was terminated only for replacement and moved to the system Trash as the recoverable rollback copy; build 6 was not launched by this run.

## Status: ARCHIVED AFTER FINAL GIT GATE

## Sink Findings

post_rebase_tests: skipped

archived_paths:
- kaola-workflow/archive/issue-26/.cache/dispatch-log.jsonl
- kaola-workflow/archive/issue-26/.cache/doc-docking.md
- kaola-workflow/archive/issue-26/.cache/doc-updater.md
- kaola-workflow/archive/issue-26/.cache/final-validation.md
- kaola-workflow/archive/issue-26/.cache/origin/selection-record.json
- kaola-workflow/archive/issue-26/.cache/run-gaps.json
- kaola-workflow/archive/issue-26/code-review-multipartial.md
- kaola-workflow/archive/issue-26/documentation-docking.md
- kaola-workflow/archive/issue-26/finalization-summary.md
- kaola-workflow/archive/issue-26/mission-list.md
- kaola-workflow/archive/issue-26/multipartial-red-evidence.md
- kaola-workflow/archive/issue-26/multipartial-semantics-analysis.md
- kaola-workflow/archive/issue-26/multipartial-test-reconciliation.md
- kaola-workflow/archive/issue-26/one-word-runtime-diagnosis.md
- kaola-workflow/archive/issue-26/output-disabled-red-evidence.md
- kaola-workflow/archive/issue-26/security-review-multipartial.md
- kaola-workflow/archive/issue-26/workflow-state.md

## Post-UAT Closure — 2026-08-04

- Release 1.0 build 8 now delivers issue #26's cursor-bound, status-only streaming transcription at the original target.
- Issue #27 and D-27-01 supersede this archive's historical concatenation, no-replay, and immediate-release-seal policies with opaque snapshot replacement and bounded post-release drain.
- The owner completed real-credential testing, accepted the current behavior, and explicitly agreed that issue #26 can end.
- GitHub issue #26 was closed and its active roadmap source was removed. This closure does not claim universal compatibility across every application in the original UAT matrix.
