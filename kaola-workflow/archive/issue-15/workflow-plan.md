# Workflow Plan - issue #15

<!-- plan_hash: 61b2d33b807db8ed24114f1b481430f6bbe91c6420d2aa575cd2b2c52ffee186 -->

## Meta
project: issue-15
issues: #15
labels: bug, P2-medium, workflow:in-progress
sink: merge
closure_policy: single_issue

## Nodes

| id | role | depends_on | declared_write_set | cardinality | shape | model |
| --- | --- | --- | --- | --- | --- | --- |
| n1-current-state-survey | code-explorer | — | — | 1 | sequence | sonnet |
| n2-audio-recorder-fail-fast | tdd-guide | n1-current-state-survey | FeishuSpeech/Services/AudioRecorder.swift, FeishuSpeech/ViewModels/MainViewModel.swift, FeishuSpeechTests/AudioRecorderRecoveryTests.swift, FeishuSpeechTests/MainViewModelTests.swift | 1 | sequence | sonnet |
| n3-permission-refresh | tdd-guide | n2-audio-recorder-fail-fast | FeishuSpeech/Services/PermissionManager.swift, FeishuSpeech/App/AppDelegate.swift, FeishuSpeechTests/PermissionManagerTests.swift | 1 | sequence | sonnet |
| n4-code-review | code-reviewer | n3-permission-refresh | — | 1 | sequence | opus |
| n5-docs | doc-updater | n4-code-review | docs/decisions/D-15-01.md, docs/architecture.md, CHANGELOG.md | 1 | sequence | sonnet |
| n6-finalize | finalize | n5-docs | CHANGELOG.md, kaola-workflow/ROADMAP.md | 1 | sequence | — |

## Plan Notes

Issue #15 is a bug fix across the audio-capture and permission-refresh lanes. Both lanes touch the
same coarse product/test areas (`FeishuSpeech/` and `FeishuSpeechTests/`), so they are serialized as
sequence nodes rather than authored as write-role fan-out siblings. A failing unit test is practical
for each lane, so both implementation nodes use `tdd-guide`.

- **n1-current-state-survey:** read-only confirmation of the current recorder lifecycle,
  `MainViewModel` error propagation, permission polling, and existing test hooks before changing
  code. This node should record exact success criteria for the two TDD nodes.
- **n2-audio-recorder-fail-fast:** write failing tests first for mid-recording capture failures and
  conversion-error exhaustion. Implement accurate fail-fast signaling from `AudioRecorder` for
  `AVCaptureSession.runtimeErrorNotification`, interruption/device-loss style notifications, and
  the `maxConversionErrors` path; then wire `MainViewModel` so an in-progress recording stops and
  surfaces a specific error instead of later reporting empty audio or microphone-permission noise.
  Keep the behavior covered in `AudioRecorderRecoveryTests` and `MainViewModelTests`.
- **n3-permission-refresh:** write failing tests first for runtime microphone authorization refresh.
  Add a testable microphone-status refresh path to `PermissionManager`, and call it from the
  existing 2-second `AppDelegate` permission poll alongside accessibility and secure-input refresh.
- **n4-code-review:** G1 gate; post-dominates both code-producing nodes. Model is `opus` because the
  change spans AVFoundation notifications, async recorder cleanup, Combine observation, and
  permission polling where subtle lifecycle regressions are plausible.
- **n5-docs:** document the recorder fail-fast contract and periodic microphone refresh. `D-15-01`
  is the next free decision record for issue #15; no existing `D-15-*` record or issue #15 docs
  mention was found before authoring.
- **G2/security:** no `security-reviewer` node is required. The frozen labels are bug/priority plus
  the workflow marker, and the planned write set does not touch secrets, auth, crypto, or network
  trust. Microphone permission behavior is privacy-relevant but is confined to local permission
  status refresh and accurate user-facing failure reporting.
- **n6-finalize:** unique sink for docs/state bookkeeping only. Product code is fully post-dominated
  by `n4-code-review` before finalization.

Validation expected before completion: focused unit tests for the new failure/permission paths,
`xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test`, `xcodebuild -scheme
FeishuSpeech -configuration Debug build`, and `swiftlint`.

## Node Ledger

| id | status |
| --- | --- |
| n1-current-state-survey | complete |
| n2-audio-recorder-fail-fast | complete |
| n3-permission-refresh | complete |
| n4-code-review | complete |
| n5-docs | complete |
| n6-finalize | complete |
## Required Agent Compliance

| Requirement | Status | Evidence | Skip Reason |
|-------------|--------|----------|-------------|
| code-explorer (n1-current-state-survey) | subagent-invoked | evidence-binding: n1-current-state-survey 98ac20b7df1b | |
| tdd-guide (n2-audio-recorder-fail-fast) | subagent-invoked | evidence-binding: n2-audio-recorder-fail-fast a25ecff6bf39 | |
| tdd-guide (n3-permission-refresh) | subagent-invoked | evidence-binding: n3-permission-refresh 76b18108f4d4 | |
| code-reviewer | subagent-invoked | evidence-binding: n4-code-review 8746313d3a56 | |
| doc-updater (n5-docs) | subagent-invoked | evidence-binding: n5-docs 859fd7e3f3d8 | |
| finalize (n6-finalize) | main-session-direct | evidence-binding: n6-finalize b63b0495f232 | |
