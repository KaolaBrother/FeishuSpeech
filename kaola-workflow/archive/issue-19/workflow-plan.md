# Workflow Plan - issue #19

<!-- plan_hash: d3634172e5e867182b4c1dc1e966ec302f4c89944ce0a5c114e76ef3e74af7a4 -->

## Meta
project: issue-19
issues: #19
labels: enhancement, P3-low, workflow:in-progress
sink: merge
closure_policy: single_issue

## Nodes

| id | role | depends_on | declared_write_set | cardinality | shape | model |
| --- | --- | --- | --- | --- | --- | --- |
| n1-current-wake-gap-survey | code-explorer | — | — | 1 | sequence | sonnet |
| n2-macos-wake-api-contract | knowledge-lookup | — | — | 1 | sequence | sonnet |
| n3-hotkey-wake-health | tdd-guide | n1-current-wake-gap-survey, n2-macos-wake-api-contract | FeishuSpeech/Services/HotKeyService.swift, FeishuSpeechTests/HotKeyServiceTests.swift | 1 | sequence | sonnet |
| n4-wake-coordinator-api-reset | tdd-guide | n3-hotkey-wake-health | FeishuSpeech/App/AppDelegate.swift, FeishuSpeech/ViewModels/MainViewModel.swift, FeishuSpeech/Services/FeishuAPIService.swift, FeishuSpeechTests/MainViewModelTests.swift, FeishuSpeechTests/FeishuAPIServiceTests.swift | 1 | sequence | sonnet |
| n5-code-review | code-reviewer | n4-wake-coordinator-api-reset | — | 1 | sequence | opus |
| n6-security-review | security-reviewer | n5-code-review | — | 1 | sequence | opus |
| n7-docs | doc-updater | n6-security-review | docs/decisions/D-19-01.md, docs/architecture.md, docs/api.md, CHANGELOG.md | 1 | sequence | sonnet |
| n8-finalize | finalize | n7-docs | CHANGELOG.md, kaola-workflow/ROADMAP.md | 1 | sequence | — |

## Plan Notes

Issue #19 is scoped to sleep/wake recovery only. Do not bundle issue #20; it remains separate broad
test debt. The codebase currently has launch and termination cleanup in `AppDelegate`, hot-key tap
timeout/user-input recovery in `HotKeyService`, manual reset in `MainViewModel`, and
`FeishuAPIService.resetState()` for token/network error cleanup, but no `NSWorkspace` sleep/wake
observer path.

The two discovery nodes are independent read-only work and can be opened together by the executor.
The code nodes serialize because both lanes operate in the same coarse product/test areas and the
coordinator lane depends on the hot-key wake health API introduced by `n3`.

- **n1-current-wake-gap-survey:** confirm the current lifecycle contracts around
  `AppDelegate.applicationDidFinishLaunching`, `applicationWillTerminate`, `HotKeyService`
  event-tap storage/threading, `MainViewModel.resetService()`/`cleanup()`, and existing tests. Record
  the exact wake recovery success criteria and the smallest code surface needed.
- **n2-macos-wake-api-contract:** confirm the local macOS/AppKit contract for
  `NSWorkspace.willSleepNotification`, `NSWorkspace.didWakeNotification`,
  `NSWorkspace.shared.notificationCenter`, and `CGEvent.tapIsEnabled`/tap re-enable semantics. Treat
  external documentation as factual input only.
- **n3-hotkey-wake-health:** use `tdd-guide`. Write failing tests first for wake-time hot-key health
  behavior: a live enabled tap remains active, a missing/dead/disabled tap is recreated through the
  existing stop/start lifecycle, pending transitions are cancelled as appropriate, and
  `previousFlags` is reset so a pre-sleep Fn-down snapshot cannot poison post-wake input. Implement
  the smallest public/internal API on `HotKeyService` that the coordinator can call after wake.
- **n4-wake-coordinator-api-reset:** use `tdd-guide`. Write failing tests first for the coordinator
  behavior: sleep/wake cleanup aborts active recording or transcription without sending stale audio,
  hides overlays/timers by returning `MainViewModel` to idle, clears the Feishu token/network-error
  cache, and routes wake handling from `AppDelegate` via `NSWorkspace` observers registered on
  launch and removed on termination. Keep `FeishuAPIService` changes limited to testable reset or
  wake-refresh helpers if the existing `resetState()` contract is insufficient.
- **n5-code-review:** G1 gate; post-dominates both code-producing nodes (`n3`, `n4`). Model is
  `opus` because the change crosses CGEventTap lifecycle, Combine/UI state, async transcription
  cancellation, and AppKit system notifications.
- **n6-security-review:** included deliberately even though the frozen labels are not `security`.
  The wake path touches Feishu token/cache reset behavior and external API readiness after network
  sleep/wake flaps. Verify no credential/token values are logged, persisted differently, or exposed
  through new test hooks, and that reset behavior cannot corrupt in-flight API calls.
- **n7-docs:** document the sleep/wake recovery contract. `D-19-01` is the next free decision record
  for issue #19; `rg` found no existing `D-19-*` record or prior issue #19 docs mention before
  authoring. Update architecture/API docs only where the behavior changes are relevant.
- **cross-edition symbol scoping:** this repo has no `scripts/` or `plugins/` edition trees. The
  wake-recovery symbols are local app/test symbols, and no cross-edition registration surface applies.
- **n8-finalize:** unique sink for workflow bookkeeping only. Product code is fully post-dominated
  by code and security review before finalization.

Validation expected before completion: focused failing-then-passing tests for wake tap recovery,
recording/transcription abort, and API reset behavior; `xcodebuild -scheme FeishuSpeech
-destination 'platform=macOS' test`; `xcodebuild -scheme FeishuSpeech -configuration Debug build`;
and `swiftlint`.

## Node Ledger

| id | status |
| --- | --- |
| n1-current-wake-gap-survey | complete |
| n2-macos-wake-api-contract | complete |
| n3-hotkey-wake-health | complete |
| n4-wake-coordinator-api-reset | complete |
| n5-code-review | complete |
| n6-security-review | complete |
| n7-docs | complete |
| n8-finalize | complete |
## Required Agent Compliance

| Requirement | Status | Evidence | Skip Reason |
|-------------|--------|----------|-------------|
| code-explorer (n1-current-wake-gap-survey) | subagent-invoked | evidence-binding: n1-current-wake-gap-survey 38b2e00ef0d9 | |
| knowledge-lookup (n2-macos-wake-api-contract) | subagent-invoked | evidence-binding: n2-macos-wake-api-contract 38b2e00ef0d9 | |
| tdd-guide (n3-hotkey-wake-health) | subagent-invoked | evidence-binding: n3-hotkey-wake-health 37aafd330068 | |
| tdd-guide (n4-wake-coordinator-api-reset) | subagent-invoked | evidence-binding: n4-wake-coordinator-api-reset fe104c8bbfd8 | |
| code-reviewer | subagent-invoked | evidence-binding: n5-code-review 39ea561d98de | |
| security-reviewer | subagent-invoked | evidence-binding: n6-security-review e57afb30bf04 | |
| doc-updater (n7-docs) | subagent-invoked | evidence-binding: n7-docs 0aa2289bb730 | |
| finalize (n8-finalize) | main-session-direct | evidence-binding: n8-finalize 1f29e058365f | |
