# Workflow Plan — bundle-13-14-16-17

<!-- plan_hash: 3ee6d9347f8c8fc82100d9d165e15a27bcace8976a5b8cbeb8b9202c2ef942ac -->

## Meta
project: bundle-13-14-16-17
issues: #13, #14, #16, #17
labels: bug, P1-high, P2-medium, P3-low
sink: merge
closure_policy: all_or_nothing

## Nodes

| id | role | depends_on | declared_write_set | cardinality | shape | model |
| --- | --- | --- | --- | --- | --- | --- |
| n1-clipboard-race | implementer | — | FeishuSpeech/Services/TextInputSimulator.swift | 1 | sequence | sonnet |
| n2-empty-result-feedback | tdd-guide | n1-clipboard-race | FeishuSpeech/ViewModels/MainViewModel.swift, FeishuSpeechTests/MainViewModelTests.swift | 1 | sequence | sonnet |
| n3-timer-runloop-mode | implementer | n2-empty-result-feedback | FeishuSpeech/ViewModels/MainViewModel.swift | 1 | sequence | sonnet |
| n4-overlay-generation-guard | implementer | n3-timer-runloop-mode | FeishuSpeech/Controllers/OverlayWindowController.swift | 1 | sequence | sonnet |
| n5-code-review | code-reviewer | n4-overlay-generation-guard | — | 1 | sequence | opus |
| n6-docs | doc-updater | n5-code-review | docs/decisions/D-13-01.md, CHANGELOG.md, docs/architecture.md | 1 | sequence | sonnet |
| n7-finalize | finalize | n6-docs | CHANGELOG.md, kaola-workflow/ROADMAP.md | 1 | sequence | — |

## Plan Notes

All four fixes are co-located bug fixes under `FeishuSpeech/` (coarse area `FeishuSpeech`, not
shared-infra). Because every write touches the same coarse area, the write-role legs CANNOT be a
pairwise-disjoint fan-out (the disjointness check is RED on a `FeishuSpeech/` coarse-area overlap),
so the implement work is authored as a serialized `sequence` along the file lanes. #14 and #16 both
write `FeishuSpeech/ViewModels/MainViewModel.swift` — the same file — so they MUST serialize
(n2 → n3) regardless; #13 and #17 are distinct files but still share the `FeishuSpeech/` area and so
also serialize.

Role selection (default `tdd-guide`; `implementer` only with a recorded `non_tdd_reason`):

- **n1 (#13 — clipboard restore races synthetic Cmd+V):** `implementer`.
  `non_tdd_reason`: `TextInputSimulator` is an `enum` of static methods doing system-level
  `NSPasteboard` mutation and `CGEvent` keyboard posting (`.cghidEventTap`) with no dependency-
  injection seam — there is no meaningful failing unit test for "the old clipboard was not pasted"
  without the live frontmost-app paste loop. Fix: `changeCount`-based confirmation / adaptive delay
  before restore; check `changeCount` before overwriting; save/restore all pasteboard types
  (not just `.string`); on `CGEventSource`/paste failure leave the recognized text on the clipboard
  and notify the user ("已复制到剪贴板"). G1 (`code-reviewer`) covers it.
- **n2 (#14 — empty recognition result is a silent no-op):** `tdd-guide`.
  `MainViewModel` already has a testable harness (`MonitoringTestableMainViewModel`,
  `MainViewModelTests`) and the empty-result branch is observable model state — a failing test can
  assert that an empty `recognition_text` produces brief feedback (transient overlay "未识别到内容"
  and/or a distinct stop sound) instead of a silent return. Write the failing test FIRST, then make
  it pass. Touches `MainViewModel.swift` (the `if settings.autoInsert && !text.isEmpty` branch at
  ~225) plus the test file.
- **n3 (#16 — maxDurationTimer uses default run-loop mode):** `implementer`.
  `non_tdd_reason`: the defect is a run-loop scheduling-mode flag — the 60s timer is added in
  `.default` mode and does not fire during event-tracking (menu-open) mode. Run-loop-mode firing
  behavior is not exercisable by a unit test without a live event-tracking run loop. Fix:
  `RunLoop.main.add(timer, forMode: .common)` (mirroring the existing permission-poll pattern in
  `AppDelegate`). Same file lane as n2, so it depends on n2. G1 covers it.
- **n4 (#17 — overlay hide animation completion hides a newly-shown overlay):** `implementer`.
  `non_tdd_reason`: `OverlayWindowController` is a `@MainActor` singleton driving a live `NSPanel`
  and `NSAnimationContext` completion handler; the race (a `hide()` completion `orderOut`ing a panel
  re-shown by a fresh `show()`) is a window/animation-lifecycle side-effect with no injectable seam.
  Fix: a generation counter bumped by `show()`; the hide completion only `orderOut`s when its
  captured generation is still current. G1 covers it.

Gates and sink:

- **G1 (`code-reviewer`, n5):** post-dominates all four code-producing nodes (n1–n4) — single join
  gate. Modeled `opus` because the four fixes are subtle concurrency/race/run-loop changes
  (clipboard-restore race, animation-completion race, run-loop mode) where review quality is
  reasoning-bound.
- **G2 (`security-reviewer`):** none. Labels are `bug` + priority only; no auth/secrets/crypto/
  network-trust surface is touched (`appSecret`/Keychain is issue #18, out of scope). No sensitive
  production write, so no security-reviewer node is required.
- **n6 (`doc-updater`):** the bundle changes user-visible behavior (clipboard fallback + toast,
  empty-result feedback) so docs/decision records update before finalize. ONE bundle decision record
  `D-13-01` covers all four issues (mirroring `D-5-01 (existing)`, which records the #5/#9/#10
  bundle) — `D-13-01` is the next-free number in the `D-13-*` series (no `D-13/14/16/17` record
  exists in `docs/decisions/`). CHANGELOG.md gets `### Fixed` entries (issue #13/#14/#16/#17);
  `docs/architecture.md` notes the TextInputSimulator clipboard-restore contract and the overlay
  generation guard.
- **n7 (`finalize`):** docs/state bookkeeping only — CHANGELOG.md and the generated
  `kaola-workflow/ROADMAP.md` mirror. No product code on the sink (G1 would fire otherwise).

## Node Ledger

| id | status |
| --- | --- |
| n1-clipboard-race | complete |
| n2-empty-result-feedback | complete |
| n3-timer-runloop-mode | complete |
| n4-overlay-generation-guard | complete |
| n5-code-review | complete |
| n6-docs | complete |
| n7-finalize | complete |
## Required Agent Compliance

| Requirement | Status | Evidence | Skip Reason |
|-------------|--------|----------|-------------|
| implementer (n1-clipboard-race) | subagent-invoked | evidence-binding: n1-clipboard-race 2196f8714a4e | |
| tdd-guide (n2-empty-result-feedback) | subagent-invoked | evidence-binding: n2-empty-result-feedback 11d0368621bd | |
| implementer (n3-timer-runloop-mode) | subagent-invoked | evidence-binding: n3-timer-runloop-mode 1be7132f5d89 | |
| implementer (n4-overlay-generation-guard) | subagent-invoked | evidence-binding: n4-overlay-generation-guard c4cd5c2a7f3d | |
| code-reviewer | subagent-invoked | evidence-binding: n5-code-review 2cdc9c0fc0f5 | |
| doc-updater (n6-docs) | subagent-invoked | evidence-binding: n6-docs 1de7d82456b4 | |
| finalize (n7-finalize) | main-session-direct | evidence-binding: n7-finalize 4e38b69d22f7 | |
