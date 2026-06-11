# Workflow Plan — bundle-6-7-8

<!-- plan_hash: 84c74eb70180e9319aefe699931a46c01703a365d22252ea54aba2a74de0c537 -->

## Meta

issues: 6, 7, 8
labels: bug, P1-high
sink: merge

## Summary

Three P1-high state-machine bugs share one root cause: `HotKeyService` and
`MainViewModel` run two parallel state machines that drift out of sync.

- #6 — Fn press+release during `.transcribing` resets the machine to `.idle`,
  allowing a concurrent recording session and stale-task `setError` stomps.
- #7 — Max-duration auto-stop stops the recorder without telling `HotKeyService`,
  so Fn release runs `stopRecordingAndTranscribe()` a second time on an empty buffer.
- #8 — `stopHotKeyMonitoring` leaks the `$state` sink; every permission flicker
  adds another subscriber, multiplying every hotkey event.

The architecture node settles a single shared state-machine contract first; the
three fixes are then applied as a sequenced chain because they overlap on
`HotKeyService.swift` and `MainViewModel.swift` (no safe disjoint fan-out).
Decision record `D-6-01` captures the contract.

## Nodes

| id | role | depends_on | declared_write_set | cardinality | shape | model |
| --- | --- | --- | --- | --- | --- | --- |
| node1 | code-architect | — | — | 1 | sequence | opus |
| node2 | tdd-guide | node1 | FeishuSpeech/Services/HotKeyService.swift, FeishuSpeech/ViewModels/MainViewModel.swift, FeishuSpeechTests/HotKeyServiceTests.swift | 1 | sequence | sonnet |
| node3 | tdd-guide | node2 | FeishuSpeech/Services/HotKeyService.swift, FeishuSpeech/ViewModels/MainViewModel.swift, FeishuSpeechTests/HotKeyServiceTests.swift | 1 | sequence | sonnet |
| node4 | tdd-guide | node3 | FeishuSpeech/ViewModels/MainViewModel.swift, FeishuSpeechTests/MainViewModelTests.swift | 1 | sequence | sonnet |
| node5 | code-reviewer | node4 | — | 1 | sequence | opus |
| node6 | doc-updater | node5 | CHANGELOG.md, docs/decisions/D-6-01.md, docs/architecture.md | 1 | sequence | sonnet |
| node7 | finalize | node6 | CHANGELOG.md | 1 | sequence | sonnet |

## Plan Notes

- **node1 (code-architect, opus):** Decide the shared state-machine contract that
  reconciles `HotKeyService` and `MainViewModel`. Specify: (a) `handleFnReleased`
  leaves `.transcribing` and `.error` untouched (only completion/error-recovery
  paths exit those states); (b) a new explicit `forceTranscribing()` event so
  max-duration drives the stop through the state machine; (c) `setError` gating so
  a stale task cannot override an active `.pending`/`.recording` session; (d) the
  `$state` subscription is held in a dedicated single `AnyCancellable?` cleared by
  `stopHotKeyMonitoring`. This contract becomes decision `D-6-01` (next free id;
  existing records are `D-1-01 (existing)`, `D-2-01 (existing)`), authored by
  node6 — code-architect is read-only and emits only the design node2+ consume.
  This decision constrains all three fixes → opus.
- **node2 (tdd-guide, sonnet):** Fix #6. Failing test first in
  `HotKeyServiceTests.swift` (release during `.transcribing` must not reset to
  `.idle`). Implement the `handleFnReleased` guard plus the `setError` gating in
  `MainViewModel.swift`, per the node1 contract.
- **node3 (tdd-guide, sonnet):** Fix #7. Depends on node2 — shares
  `HotKeyService.swift` + `MainViewModel.swift`, so serialized (overlapping write
  set, fan-out unsafe). Add `forceTranscribing()` to `HotKeyService`; drive
  `handleMaxDurationReached` through it and make `stopRecordingAndTranscribe`
  idempotent (guard on `audioRecorder.isRecording`). Failing test first.
- **node4 (tdd-guide, sonnet):** Fix #8. Depends on node3 — shares
  `MainViewModel.swift`. Hold `$state` in a dedicated `AnyCancellable?` that
  `stopHotKeyMonitoring` nils out. New test file `MainViewModelTests.swift` for the
  no-duplicate-handling assertion.
- **node5 (code-reviewer, opus):** G1 gate — post-dominates node2/node3/node4
  (all code producers). State-machine concurrency is subtle; strong reviewer → opus.
- **node6 (doc-updater, sonnet):** Update CHANGELOG.md (user-visible behavior),
  finalize `D-6-01`, and refresh `docs/architecture.md` (state-machine description).
  Carries out the documentation decision → sonnet.
- **node7 (finalize, sonnet):** Docs/state-only sink (CHANGELOG.md).

## Node Ledger

| id | role | status |
| --- | --- | --- |
| node1 | code-architect | complete |
| node2 | tdd-guide | complete |
| node3 | tdd-guide | complete |
| node4 | tdd-guide | complete |
| node5 | code-reviewer | complete |
| node6 | doc-updater | complete |
| node7 | finalize | complete |
## Required Agent Compliance

| Requirement | Status | Evidence | Skip Reason |
|-------------|--------|----------|-------------|
| code-architect (node1) | subagent-invoked | ## Architecture: State-Machine Contract for bundle-6-7-8 (#6, #7, #8) | |
| tdd-guide (node2) | subagent-invoked | RED: test_fnReleasedDuringTranscribing_stateRemainsTranscribing — compile error  | |
| tdd-guide (node3) | subagent-invoked | RED: test_forceTranscribing_fromRecording_transitionsToTranscribing / test_force | |
| tdd-guide (node4) | subagent-invoked | RED: test_stateCancellable_isNil_afterStopHotKeyMonitoring -- compile errors: st | |
| code-reviewer | subagent-invoked | verdict: pass | |
| doc-updater (node6) | subagent-invoked | Documentation updated for bundle-6-7-8 (#6, #7, #8). | |
| finalize (node7) | main-session-direct | finalize sink: docs/state confirmed complete | |
