# Workflow Plan — bundle-5-9-10

<!-- plan_hash: bdc93ee7de443de1c513a9918e59e2ab7e62e32e93dfae74c5b963dcf6072ad0 -->

## Meta

issues: 5, 9, 10
labels: bug, P0-critical, P1-high, P2-medium
sink: merge

## Summary

Three hotkey-reliability bugs where the Fn hotkey goes silently dead while the UI
still shows 就绪. They share the `HotKeyService` event-tap surface but split into
one coupled lane plus one independent lane:

- #5 (P0) — `CGEvent.tapCreate` failure surfaces nowhere: `MainViewModel` sets its
  own `isMonitoring = true` unconditionally and nobody observes
  `HotKeyService.$isMonitoring`, so a stale-TCC tap-creation failure shows all
  green. Surface the failure as a dedicated state, bind `$isMonitoring`, and retry
  with backoff instead of giving up after 3 attempts.
- #9 (P1) — the tap run-loop source is added to `CFRunLoopGetMain()`, so a blocking
  `AVCaptureSession.startRunning()` on the main actor delays/loses Fn events and can
  leave the machine stuck in `.recording`. Move the tap off the main run loop, run
  `startRunning()` on a background queue, reset `previousFlags` in `stopMonitoring()`,
  and resync from `CGEventSource.flagsState` after a timed-out tap re-enable.
- #10 (P2) — secure keyboard entry (`IsSecureEventInputEnabled()`) is never checked,
  so the hotkey is inert with no user messaging while a password field is focused.
  Poll it on the existing 2s permission timer and reflect it in the menu bar status.

#5 and #9 both rewrite the `HotKeyService` state machine / run-loop placement on the
same file, so they are sequenced behind one shared architecture contract (semantic
coupling on identical logic — no safe disjoint fan-out across the same file). #10 is
file-disjoint (`PermissionManager`, `MenuBarView`, `AppDelegate`) and runs as a
parallel sibling, giving the executor a 2-wide ready frontier after the architect.
Decision record `D-5-01` captures the shared tap-lifecycle + threading contract.

## Nodes

| id | role | depends_on | declared_write_set | cardinality | shape | model |
| --- | --- | --- | --- | --- | --- | --- |
| node1 | code-architect | — | — | 1 | sequence | opus |
| node2 | tdd-guide | node1 | FeishuSpeech/Services/HotKeyService.swift, FeishuSpeech/Services/HotKeyState.swift, FeishuSpeech/ViewModels/MainViewModel.swift, FeishuSpeechTests/HotKeyServiceTests.swift | 1 | sequence | sonnet |
| node3 | tdd-guide | node2 | FeishuSpeech/Services/HotKeyService.swift, FeishuSpeech/Services/AudioRecorder.swift, FeishuSpeechTests/HotKeyServiceTests.swift | 1 | sequence | opus |
| node4 | tdd-guide | node1 | FeishuSpeech/Services/PermissionManager.swift, FeishuSpeech/Views/MenuBarView.swift, FeishuSpeech/App/AppDelegate.swift, FeishuSpeechTests/PermissionManagerTests.swift | 1 | sequence | sonnet |
| node5 | code-reviewer | node3, node4 | — | 1 | sequence | opus |
| node6 | doc-updater | node5 | CHANGELOG.md, docs/decisions/D-5-01.md, docs/architecture.md | 1 | sequence | sonnet |
| node7 | finalize | node6 | CHANGELOG.md | 1 | sequence | sonnet |

## Plan Notes

- **node1 (code-architect, opus):** Settle the shared tap-lifecycle + threading
  contract that #5 and #9 both depend on, because both rewrite the same
  `HotKeyService` event-tap surface. Specify: (a) a new `HotKeyState` (or
  `isMonitoring`-derived) **tap-failure / monitoring-down** signal that
  `MainViewModel` and the menu bar can observe, and the rule that
  `startHotKeyMonitoring` must bind `HotKeyService.$isMonitoring` instead of
  assuming success (#5); (b) the retry policy — backoff with unbounded retry / retry
  on accessibility re-grant rather than giving up after `maxRestartRetries = 3`
  (#5); (c) which run loop the tap source lives on (dedicated thread/run loop vs.
  main) and the rule that `AVCaptureSession.startRunning()` runs on a background
  queue with asynchronous started-state confirmation (#9); (d) `previousFlags = []`
  reset in `stopMonitoring()` and the post-timeout resync from
  `CGEventSource.flagsState` to detect a missed Fn release (#9). This contract
  becomes decision `D-5-01` (next free id; existing records are `D-1-01 (existing)`,
  `D-2-01 (existing)`, `D-6-01 (existing)`), authored by node6 — code-architect is
  read-only and emits only the design that node2/node3 consume. The decision
  constrains both coupled fixes and is threading-correctness-bound → opus.
- **node2 (tdd-guide, sonnet):** Fix #5. Failing test first in
  `HotKeyServiceTests.swift` (tap-creation failure must drive `isMonitoring=false`
  and surface a distinct observable state, not stay 就绪). Add the tap-failure
  signal to `HotKeyState.swift`, surface it in `HotKeyService.swift`, bind
  `HotKeyService.$isMonitoring` in `MainViewModel.swift`, and apply the backoff
  retry policy per the node1 contract. Carries out an already-decided contract → sonnet.
- **node3 (tdd-guide, opus):** Fix #9. Depends on node2 — shares
  `HotKeyService.swift` (state-machine / run-loop rewrite), so serialized; an
  overlapping write set makes a fan-out with node2 unsafe. Failing test first
  covering `previousFlags` reset on `stopMonitoring()` and the post-timeout resync.
  Move the tap off `CFRunLoopGetMain()`, run `AudioRecorder.startRecording()`'s
  `session.startRunning()` on a background queue with async confirmation, reset
  `previousFlags`, and resync from `CGEventSource.flagsState`. Run-loop placement and
  the background-queue/main-actor boundary are concurrency-correctness-bound and
  easy to get subtly wrong → opus.
- **node4 (tdd-guide, sonnet):** Fix #10. Depends only on node1 (the contract) and is
  **file-disjoint** from node2/node3 (`PermissionManager.swift`, `MenuBarView.swift`,
  `AppDelegate.swift`) → runs as a parallel sibling on the ready frontier. Failing
  test first in new `PermissionManagerTests.swift` (secure-input-enabled must flip an
  observable flag). Poll `IsSecureEventInputEnabled()` on the existing 2s permission
  timer in `AppDelegate.swift`, publish it from `PermissionManager.swift`, and reflect
  "安全输入已启用，热键暂不可用" in `MenuBarView.swift`. Mechanical polling/status wiring → sonnet.
- **node5 (code-reviewer, opus):** G1 gate — post-dominates node2, node3, node4 (all
  code producers). Event-tap lifecycle, run-loop threading, and the main-actor/
  background-queue boundary are subtle; a strong reviewer over the cheaper
  implementers → opus.
- **node6 (doc-updater, sonnet):** Update CHANGELOG.md (user-visible: tap-failure
  surfacing, secure-input messaging), finalize `D-5-01`, and refresh
  `docs/architecture.md` (tap run-loop placement and recording-start threading).
  Carries out the documentation decision → sonnet.
- **node7 (finalize, sonnet):** Docs/state-only sink (CHANGELOG.md).

## Node Ledger

| id | role | status |
| --- | --- | --- |
| node1 | code-architect | pending |
| node2 | tdd-guide | pending |
| node3 | tdd-guide | pending |
| node4 | tdd-guide | pending |
| node5 | code-reviewer | pending |
| node6 | doc-updater | pending |
| node7 | finalize | pending |
