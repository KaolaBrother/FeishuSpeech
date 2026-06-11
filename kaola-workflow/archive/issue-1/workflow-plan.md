# Workflow Plan — issue-1

<!-- plan_hash: 5e41110d25d3c1de008aa573f278a2e773a60cba0e37e8885d786aa52a3c3862 -->

## Meta
issue: 1
title: Stale AudioRecorder session permanently disables recording; 重置服务 cannot recover
labels: bug, P0-critical
sink: merge

## Nodes

| id | role | depends_on | declared_write_set | cardinality | shape | model |
| --- | --- | --- | --- | --- | --- | --- |
| n1-fix-recorder-lifecycle | tdd-guide | — | FeishuSpeech/Services/AudioRecorder.swift, FeishuSpeech/ViewModels/MainViewModel.swift, FeishuSpeechTests/AudioRecorderRecoveryTests.swift | 1 | sequence | sonnet |
| n2-review | code-reviewer | n1-fix-recorder-lifecycle | — | 1 | sequence | opus |
| n3-docs | doc-updater | n2-review | docs/decisions/D-1-01.md, docs/architecture.md | 1 | sequence | sonnet |
| n4-finalize | doc-updater | n3-docs | CHANGELOG.md | 1 | sequence | sonnet |

## Plan Notes

- Single semantic fix = recorder-lifecycle self-healing, so n1 keeps the two coupled source
  files (`AudioRecorder.swift`, `MainViewModel.swift`) in one node — they implement the same
  recovery contract and together with the new test file sit at 3 paths, under FILE_CEILING (6).
- non_tdd_reason: N/A — n1 is `tdd-guide`. A meaningful failing unit test exists: set
  `AudioRecorder.isRecording = true` with no live session, assert `startRecording()` self-heals
  (returns true / runs `forceCleanup()` first) instead of returning false forever; and assert
  that leaving `.recording` via cancel/error stops the recorder (`isRecording == false`). The
  fix is the three changes in the issue: (1) reorder `forceCleanup()` before the `isRecording`
  guard in `startRecording()`; (2) stop the recorder in `handleCancelledState` /
  `handleErrorState`; (3) add `audioRecorder.forceCleanup()` to `resetService()`.
- n1 model `sonnet`: it carries out an already-specified fix (the issue enumerates the exact
  edits and files). n2 `code-reviewer` model `opus`: P0-critical lifecycle/concurrency change
  (audioQueue + @MainActor coordination, recovery-path correctness) is reasoning-bound and the
  strongest place to spend depth — G1 wall over the implement node.
- G1 satisfied: `code-reviewer` (n2) post-dominates the only code-producing node (n1).
- G2 not required: no secrets/auth/network/permission surface changes (pure AVFoundation
  capture-session lifecycle and view-model state handling). labels carry no security marker.
- No `knowledge-lookup`: the fix is local AVFoundation/Combine lifecycle logic confirmable from
  the codebase; no external API/library behavior is in question.
- Decision record numbering: the only existing record is D-2-01 (existing); no prior record for
  this issue exists (grepped docs/ + CHANGELOG.md). The next free id for this issue is D-1-01.
- n3 records the recovery-contract decision (`D-1-01.md`) and notes the recorder-lifecycle
  data-flow in `docs/architecture.md`. n4 is the docs/state-only `finalize` sink — it writes
  only `CHANGELOG.md` (user-visible: 重置服务 now recovers a stuck mic; Fn recording self-heals).

## Node Ledger

| id | status |
| --- | --- |
| n1-fix-recorder-lifecycle | pending |
| n2-review | pending |
| n3-docs | pending |
| n4-finalize | pending |
