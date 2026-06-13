# Workflow Plan - bundle #22/#23/#24

<!-- plan_hash: f58f1c7cb58521fa21759fd5211aef5ed630d7a49eff5a38820b9a1a12ac99e5 -->

## Meta
labels: bug, P3-low, enhancement

## Nodes

| id | role | depends_on | declared_write_set | cardinality | shape | model |
|---|---|---|---|---|---|---|
| impl-auto-clear-tap-error | tdd-guide | - | FeishuSpeech/Services/HotKeyService.swift, FeishuSpeech/ViewModels/MainViewModel.swift, FeishuSpeechTests/MainViewModelTests.swift | 1 | sequence | sonnet |
| review-code | code-reviewer | impl-auto-clear-tap-error | - | 1 | sequence | opus |
| docs-auto-clear-policy | doc-updater | review-code | docs/architecture.md, docs/decisions/D-24-01.md | 1 | sequence | sonnet |
| finalize | finalize | docs-auto-clear-policy | CHANGELOG.md | 1 | sequence | - |

## Notes

- `impl-auto-clear-tap-error`: use TDD for the MainViewModel monitoring binding. Cover `.failed(.accessibilityNotTrusted)` and `.failed(.tapCreationFailed)` mapping to `status = .error("热键不可用，请检查辅助功能权限")`; cover the selected #24 policy that `.active` after that tap-failure error auto-clears the stale error to `.idle` without masking unrelated errors. Also cover or preserve the #22 teardown invariant, then gate `HotKeyService.forceState(_:)` behind `#if DEBUG` and route `MainViewModel.cleanup()` through `stopHotKeyMonitoring()` or otherwise nil `stateCancellable`.
- `docs-auto-clear-policy`: document the auto-clear tap-failure recovery policy in a new decision record `D-24-01` and update the architecture monitoring-state contract to match the implementation.
- Validation expected before completion: `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test`, `xcodebuild -scheme FeishuSpeech -configuration Debug build`, and `swiftlint`.

## Node Ledger

| id | status |
|---|---|
| impl-auto-clear-tap-error | complete |
| review-code | complete |
| docs-auto-clear-policy | complete |
| finalize | complete |
## Required Agent Compliance

| Requirement | Status | Evidence | Skip Reason |
|-------------|--------|----------|-------------|
| tdd-guide (impl-auto-clear-tap-error) | subagent-invoked | evidence-binding: impl-auto-clear-tap-error 1e337cb6e03b | |
| code-reviewer | subagent-invoked | evidence-binding: review-code f444fc8cf0e8 | |
| doc-updater (docs-auto-clear-policy) | subagent-invoked | evidence-binding: docs-auto-clear-policy 59bfeea8267e | |
| finalize (finalize) | main-session-direct | evidence-binding: finalize a7185da5ffe8 | |
