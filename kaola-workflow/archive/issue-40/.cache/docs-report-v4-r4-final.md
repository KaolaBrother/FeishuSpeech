# Issue #40 v4 R4 final documentation reconciliation receipt

- Date: 2026-08-24
- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
- Branch: `workflow/issue-40`
- Scope: documentation-only reconciliation for the R4 drain-expiry authority repair
- GitHub: no issue comment, PR, or other external post was made
- Commit: no commit was made

## R4 evidence authority and final status

Receipts read for this reconciliation:

- `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/code-review-v4-final.md` — identified the R4 authority-bypass defect in the pre-repair drain-expiry branch.
- `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/implementation-v4-r4.md` — repaired the branch with a non-authoritative read-only `ReviewReadOnlyPhase.recovery` surface.
- `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/test-green-v4-r4-final.md` — final test-only GREEN receipt after the R4 repair.

The pre-repair R4 review correctly found that a drain-expiry partial could become ordinary `.editable` and reach delivery before action 2. The documentation now reflects the repaired contract:

- drain expiry may retain the latest same-generation, non-empty, safe, <=16,384 UTF-16 preview in the same panel as durable, non-authoritative `ReviewReadOnlyPhase.recovery`;
- LF remains inert review data and is retained exactly, including multiline LF-containing partials;
- the recovery surface is read-only/sealing, displays incomplete-recognition/read-only feedback, clears review authority and draft/confirm/discard callbacks, and materializes no Send button or qualified Return editor;
- no delivery, AX, Unicode/keyboard, pasteboard/copy, append, retry, or retarget can occur from recovery; only authoritative action 2 plus the recorder barrier may install ordinary `.editable` and confirmation callbacks;
- late completion is fenced/suppressed; empty, unsafe, oversized, stale, or otherwise ineligible snapshots remain fail-closed through fixed failure/preservation branches.

Final deterministic counts from `test-green-v4-r4-final.md`:

- R4 selectors: **3 passed / 0 failed / 0 skipped**;
- `StreamingMainViewModelTests`: **105 passed / 0 failed / 0 skipped**;
- complete focused matrix: **265 passed / 0 failed / 0 skipped**;
- full serialized macOS target: **483 passed / 0 failed / 1 skipped**. The only skip is the unrelated, explicitly guarded `DirectFeishuKeepAliveSessionTests.test_liveKeepAliveTCPIsNotOnVPNTunnelAddress`; no Issue #40 test was skipped.

R1 modifier ordering remains current: binding-specific identity/trust/Secure Input/frontmost validation runs outside the short submission gate; the fixed activation-to-input critical section rechecks live epochs and the final combined-session Command/Shift/Control/Option/Fn/Caps Lock modifiers before the prepared Unicode pair. A pre-down transition fails with zero posts.

The v3 installed candidate at `4f9908f` remains rejected/stopped. No v4 Release has been installed; sole-copy installation audit, independent final review, and owner UAT remain pending. No target-consumption, WindowServer, credential-bearing, or broad compatibility success claim is made.

## Changed source files requiring documentation reconciliation

R4 behavior changed these production surfaces and therefore required documentation review:

- `FeishuSpeech/ViewModels/MainViewModel.swift` — drain expiry now clears authority and renders read-only recovery; authoritative action 2 plus recorder barrier remains the sole editable transition.
- `FeishuSpeech/Models/TranscriptionReviewState.swift` — added the read-only `ReviewReadOnlyPhase.recovery` marker without changing the product state enum compatibility.
- `FeishuSpeech/Views/TranscriptionReviewView.swift` — recovery clears draft/confirmation/discard callbacks, disables key interaction, and does not materialize Send or qualified Return.
- `FeishuSpeech/Controllers/ReviewWindowController.swift` — same panel presents recovery feedback without activating an editable confirmation surface.

R1 source behavior remains documented in `TextInputSimulator.swift`, `ReviewDestinationDelivery.swift`, and `CurrentFocusAppendSession.swift`. The protected capture/recognition/transport files remain unchanged. Test files were evidence custody, not documentation surfaces, and were not edited by this pass.

## Documentation updated

- `README.md` — replaced the drain-expiry `.editable` claim with exact LF-preserving, non-authoritative read-only recovery and updated final counts to 265/0/0, 105/105, and 483+1.
- `CHANGELOG.md` — recorded the R4 authority repair, no Send/Return/delivery from recovery, authoritative action-2 requirement, LF retention, final modifier ordering, and final test counts.
- `docs/README.md` — updated the index summaries to describe `ReviewReadOnlyPhase.recovery`, its lack of confirmation authority, and the final R4 counts.
- `docs/architecture.md` — added the recovery branch to the top-level structure and shared finalization rules, explicitly separated it from `.editable`, retained exact LF, and updated the final 265/105/483 test evidence.
- `docs/streaming-speech-design.md` — reconciled state/release-failure diagrams, drain-expiry behavior, implementation slice, automated evidence, and completion boundary with the read-only recovery contract and R4 counts.
- `docs/decisions/D-38-01.md` — marked `.editable(isPossiblyIncomplete)` as authoritative action-2-only and documented drain recovery as non-authoritative read-only with exact LF retention.
- `docs/decisions/D-39-01.md` — preserved the keyboard policy while documenting that drain recovery has no Return/Send/delivery authority and updating current R4 counts.
- `docs/decisions/D-40-01.md` — updated the current ADR with R4 recovery semantics, final test links/counts, and the preserved R1 modifier ordering.

D-40-01 now links to the final R4 test receipt, R4 implementation receipt, R4 correctness review, and prior R1 evidence. No current documentation states that a drain-expiry partial becomes ordinary `.editable`.

## Deliberately skipped surfaces

- `docs/api.md` — no Feishu API/request/response, token, transport, dependency, entitlement, or settings-schema change.
- `docs/conventions.md` — no repository or coding convention changed.
- `docs/decisions/D-18-01.md`, `D-25-01.md`, `D-26-01.md`, `D-27-01.md`, `D-28-01.md`, `D-32-01.md`, and `D-34-01.md` — credential, historical writer, capture/recognition, and transport decisions were not changed by R4.
- `docs/designs/capture-recognition-split-direct-connect.md` — protected asynchronous capture/recognition topology is unchanged and is covered by the updated architecture/design/ADR surfaces.
- Archived workflow records, `CLAUDE.md`, `AGENTS.md`, workflow state, mission list, roadmap, production source, and tests — protected or outside documentation scope; none were edited.

## Validation performed

Commands run from the issue worktree:

1. `git diff --check` — passed.
2. Local Ruby relative-Markdown-link check over all eight updated docs — passed; no broken local links, including the final R4 evidence links.
3. Trailing-whitespace scan with `rg -n '[[:blank:]]+$'` over all eight updated docs — passed.
4. Stale-count scan — passed: no pre-R4 `264`, `51 retired`, `51 explicitly`, `263 passed`, `482 passed`, or `all 103` current claims remain.
5. Recovery-authority scan — passed: no `.editable(isPossiblyIncomplete)`, `provisional editable`, or equivalent drain-expiry editable claim remains; `ReviewReadOnlyPhase.recovery`, exact LF retention, no Send/Return/delivery, and action-2-plus-barrier authority are present.
6. Final-count/contract scan — passed: R4 3/3, Streaming 105/105, focused 265/265, full 483 passed + 1 live-TCP skip, final modifier ordering, and install/UAT pending are present.
7. `git diff --name-only -- README.md CHANGELOG.md docs` — confirmed exactly the eight owned docs changed in the documentation tree. Concurrent production/test changes remain preserved.

The R4 build/test/lint evidence was read from the supplied receipts; this documentation pass did not rerun build, tests, lint, installation, or GUI owner UAT.

## Remaining documentation/product risks

- No v4 Release is installed, so sole-copy audit and owner UAT remain required before closure.
- `CGEventPostToPid` has no target-consumption receipt; visible target acceptance, WindowServer behavior, Accessibility restoration, Secure Input/password rejection, live credentials, and cross-application Unicode behavior remain unverified.
- The read-only recovery surface is deterministic and test-covered, but owner UAT still needs to verify its panel feedback, exact LF display, inert Send/Return behavior, late-completion suppression, and subsequent authoritative action-2 transition in an installed Release.
- `docs/api.md` intentionally retains historical internal writer details; promoting it to a user-facing output contract would require a separately authorized documentation change.

## Result location

The eight updated documentation files are in the issue worktree. This complete R4 receipt is at:

`/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/docs-report-v4-r4-final.md`
