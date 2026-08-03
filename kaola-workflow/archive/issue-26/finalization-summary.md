# Finalization — Summary: issue-26

## Delivered

- Every usable pre-seal recognition partial is routed to the selected output owner while Fn remains held.
- Initial and first-partial rebound `.finalOnly` destinations now arm a continuous append owner bound to the captured PID and exact AX element; the triggering partial is applied immediately.
- PID-bound Unicode output uses one `.privateState` source, identical UTF-16 key-down/key-up payloads, and empty flags. The full pair is constructed before a final live Secure Input sample, then posted adjacently.
- Release only seals recording/retry admission and finalizes the existing owner. It is not the first-output trigger and does not resend a full result after a provisional attempt or uncertainty.
- Exact PID, focused AX element, captured-token security, live Secure Input, generation, retry, replay, and post-seal protections remain fail-closed.
- Completion feedback no longer claims unacknowledged text was preserved or inserted.

## Files Changed

- Production: `RecordingState.swift`, `CurrentFocusAppendSession.swift`, `TextInputSimulator.swift`, `MainViewModel.swift`.
- Tests: `CurrentFocusAppendSessionTests.swift`, `FinalTextOutputSecurityTests.swift`, `StreamingMainViewModelTests.swift`.
- Documentation: `README.md`, `CHANGELOG.md`, `docs/api.md`, `docs/architecture.md`, `docs/streaming-speech-design.md`, `docs/decisions/D-26-01.md`.
- Workflow history: the prior build-4 issue archive is retained as `kaola-workflow/archive/issue-26-held-output-build4-uat` so this run can archive without overwriting it.

## Test Coverage

- RED-first coverage proved the former initial/rebound final-only release delay, HID-state one-sided event defect, pair-construction split, late Secure Input window, and unsafe recovery revalidation gap.
- Focused post-repair suites passed 94/94.
- Final lifecycle-free direct XCTest run passed 263/263 with 0 failures.
- Independent code and security reviews both passed with 0 blocking findings.

## Validation

- Consumer validation receipt: `verdict: pass`.
- Candidate hash: `40a6dc6726f90cbc2ad83d7dfae823c640c59ef6f2fd8067e4a6e69780f7dc9f`.
- SwiftLint strict: 27 files, 0 violations.
- Debug build-for-testing and Release build succeeded without launching the application.
- Release 1.0 build 5 has a valid strict code signature; bundle ID is `Siji.FeishuSpeech`; executable SHA-256 is `1f0e496200c8a066062c2112793fcbf13a83d77697c56cfd0ba2bd75aef47e6e`.
- The validation run covered the final code, tests, documentation, and archive rename. Documentation edits did not change the already validated code or Release bytes.

## Changed Paths

The finalize transaction will append its measured changed-path report here verbatim.

## Documentation Docking

`verdict: DOCKED`. User workflow, API/output contract, architecture/trust boundary, streaming design, changelog, and decision record all reflect held-partial output and release-only sealing. `docs/README.md` required no navigation change.

## Run gaps

The run-gap scanner observed no gap classes; no follow-up issue was fabricated.

## Follow-Up Items

- Owner UAT must verify that target applications visibly accept PID-bound Unicode pairs while Fn remains held. `CGEventPostToPid` has no target-control acknowledgement, so local `.posted` proves submission only.
- GitHub issue #26 remains open and claimed work is released after sink; the installed Release is for this UAT.

## Status: ARCHIVED AFTER FINAL GIT GATE

## Sink Findings

post_rebase_tests: skipped

archived_paths:
- kaola-workflow/archive/issue-26/finalization-summary.md
