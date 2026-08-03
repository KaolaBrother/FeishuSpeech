# Finalization — Summary: issue-26

## Delivered

- Recoverable streaming failures no longer publish an early error while Fn remains held. The coordinator aborts an established failed attempt once, backs off from 250 ms to a 4 s cap, creates a fresh serial stream, and replays the same hold's ordered audio.
- Fn release, the 60-second cap, reset, sleep/wake, security loss, and capture failure close retry admission and cancel pending delay/session creation. Release shares one bounded action-3 cancellation; abnormal termination revokes generation, cursor writers, ingress consumer, and transport immediately.
- Continuous output now begins while Fn remains held. Verified AX targets replace one app-owned range; AX-unavailable targets append only exact monotonic UTF-16 suffixes under stable-PID and Secure Input checks.
- Replay retention is charged against one 1,920,000-byte hold-wide budget. Terminal failures preserve already emitted text and produce at most one fixed, transcript-free feedback state.
- The previous response-contract issue-26 archive was preserved as `kaola-workflow/archive/issue-26-response-contract-uat` so this cycle can own the canonical `issue-26` archive.
- The sole `/Applications/FeishuSpeech.app` was replaced with Release 1.0 build 4, verified after installation, and left stopped for owner testing.

## Files Changed

- Production: streaming models/session, byte-bounded ingress, current-focus append session, text-input seams, recording feedback, and `MainViewModel` coordination.
- Tests: transport cancellation, ingress replay budget, retry policy, coordinator lifecycle/barrier behavior, and continuous-output security/UTF-16 behavior.
- Documentation: README, changelog, API, architecture, streaming design, docs index, D-25-01, and new D-26-01.
- Workflow history: the prior response-contract archive was renamed without altering its contents.

## Test Coverage

- Lifecycle-free direct XCTest: 249 passed, 0 failed, 0 skipped.
- Strict SwiftLint: 0 violations and 0 serious findings across 27 production Swift files.
- Debug build-for-testing: passed.
- Release 1.0 build 4: passed; strict deep code-signature verification passed.
- Installed bundle: version 1.0 build 4, bundle ID `Siji.FeishuSpeech`, executable SHA-256 `f1f65f6b829386d26db57c048ad76cdd0ed5f22893ad4cee68f62d185a1dbf7d`; one Applications copy; not launched.
- Correctness review: PASS, R1–R11 resolved, 0 blocking findings.
- Security/privacy review: PASS, 0 blocking findings.

## Validation

The finalize transaction classified validation as `chains_green`. Its consumer receipt binds candidate hash `bbe694ad45157e6a798fe7c0869059f6926dea428923d0a8255a047d661cdcc4` to the issue worktree. The test/build/lint evidence covers the final code and tests; the subsequent changelog count correction and workflow archive rename are non-code bookkeeping outside the rerun trigger.

## Changed Paths

The finalize transaction measured these code-relevant paths:

- `FeishuSpeech/Models/RecordingState.swift`
- `FeishuSpeech/Models/StreamingSpeechModels.swift`
- `FeishuSpeech/Services/ByteBoundedAudioIngress.swift`
- `FeishuSpeech/Services/CurrentFocusAppendSession.swift`
- `FeishuSpeech/Services/FeishuStreamingSession.swift`
- `FeishuSpeech/Services/TextInputSimulator.swift`
- `FeishuSpeech/ViewModels/MainViewModel.swift`
- `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift`
- `FeishuSpeechTests/FeishuStreamingSessionTests.swift`
- `FeishuSpeechTests/StreamingAudioIngressTests.swift`
- `FeishuSpeechTests/StreamingCoordinatorStateTests.swift`
- `FeishuSpeechTests/StreamingMainViewModelTests.swift`

## Documentation Docking

DOCKED. See `.cache/doc-updater.md` and `.cache/doc-docking.md`.

## Run gaps

- none: the scanner found no newly discovered defect requiring a separate follow-up issue.

## Follow-Up Items

- Keep GitHub issue #26 open until Yanlei self-tests Release 1.0 build 4 with the real tenant, Fn hold/release, and target applications.
- Same-PID caret movement cannot be observed on the AX-unavailable suffix path; divergent partial revisions are therefore preserved rather than destructively corrected.
- Do not claim live end-to-end success before owner UAT.

## Status: ARCHIVED AFTER FINAL GIT GATE

## Sink Findings

post_rebase_tests: skipped

archived_paths:
- kaola-workflow/archive/issue-26/finalization-summary.md
