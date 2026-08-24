# Issue #40 v2 documentation docking receipt

- Date: 2026-08-23
- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
- Branch: `workflow/issue-40`
- Issue authority read: `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/github-issue-body-v2.md`
- Architecture authority read: `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/architecture-blueprint-v2.md`
  (the blueprint is at the issue directory root, not in `.cache`)

## Changed source files requiring documentation reconciliation

- `FeishuSpeech/Controllers/ReviewWindowController.swift` — same-panel lifecycle and typed
  editable readiness now retain the panel/draft across transient failures.
- `FeishuSpeech/Models/TranscriptionReviewState.swift` — `editablePending`, durable draft,
  readiness, and delivery-feedback states are part of the documented state machine.
- `FeishuSpeech/Services/AccessibilityClient.swift` — exact AX versus ordinary non-secure
  capability-miss capture is typed; trust/security failures remain fail-closed.
- `FeishuSpeech/Services/ReviewDestinationDelivery.swift` — exact-target preference,
  application-bound fixed-PID fallback, consecutive identity/Secure Input checks, and no
  automatic retry/retarget/copy are documented.
- `FeishuSpeech/Services/TextInputSimulator.swift` — explicit review delivery remains the only
  output transaction; automatic recovery-copy/direct-output authority is removed.
- `FeishuSpeech/ViewModels/MainViewModel.swift` — both legacy setting values converge on the
  review route; capture and recognition remain independent; action 2 plus recorder barrier owns
  the same durable draft and failure retention.
- `FeishuSpeech/Views/SettingsView.swift` — settings no longer expose a bypass; legacy booleans
  remain decode/migration compatible only.
- `FeishuSpeech/Views/TranscriptionReviewView.swift` — Send/Return/Command+Return gate,
  Shift+Return newline, retry/edit/discard controls, and fixed feedback are documented.

The changed test files provide validation evidence but are not documentation surfaces. No
credential, Feishu API/transport, entitlement, or settings-schema migration was introduced.

## Documentation updated

- `README.md` — user workflow now describes one streaming preview, independent capture/provider
  roots, same-panel sealing and durable draft, explicit output gate, exact/fixed-PID fallback,
  and no automatic copy/direct/retry/retarget. The FAQ and structure mark former writer types as
  historical/dormant.
- `CHANGELOG.md` — added the Issue #40 v2 entry and marked earlier direct/continuous/final-only/
  recovery behavior as historical while retaining capture, recognition, replay, and security facts.
- `docs/README.md` — index descriptions now identify D-40-01 as the current authority, mark D-25/
  D-27 output routes historical, and distinguish the capture/recognition design's still-applicable
  ownership split from its superseded output boundary.
- `docs/architecture.md` — reconciled topology, review state, same-panel readiness/delivery
  failure retention, explicit output gate, legacy setting inertness, exact/fixed-PID security, and
  dormant historical writer contracts.
- `docs/streaming-speech-design.md` — reconciled one-route state diagrams, independent async roots,
  durable draft and retry/discard semantics, explicit keyboard gate, no-copy failure behavior, and
  historical writer/test sections.
- `docs/decisions/D-25-01.md` — preserved the old cursor-bound decision but explicitly superseded
  its direct/final-only/recovery paths for both legacy values.
- `docs/decisions/D-26-01.md` — marked continuous-output/manual-recovery behavior historical and
  retained retry/replay and release-sealing context.
- `docs/decisions/D-27-01.md` — changed its status to historical compatibility output; retained
  protected snapshot/replay/release/security context without presenting a selectable false-setting
  route.
- `docs/decisions/D-38-01.md` — marked strict-AX-only admission, selectable compatibility, and
  recovery-copy behavior superseded; reconciled unconditional preview, editablePending, same-panel
  draft retention, explicit gate, and historical D-27 context.
- `docs/decisions/D-39-01.md` — retained the Return/Enter/Shift+Return/IME policy and aligned the
  current confirmation control with Send; legacy settings cannot restore direct output.
- `docs/decisions/D-40-01.md` — established the current v2 authority: one preview for both values,
  independent capture/provider roots, action2+barrier draft freeze, explicit delivery only,
  exact/fixed-PID fallback, and no automatic recovery route.
- `docs/designs/capture-recognition-split-direct-connect.md` — added a narrow Issue #40 note:
  capture/recognition/transport ownership and no-UI-backpressure constraints remain applicable;
  its old output-boundary statements are historical.

## Deliberately skipped surfaces

- `docs/api.md` — skipped by explicit blueprint authority: no Feishu API, request/response, token,
  or transport contract changed, and the blueprint says this surface has no impact. Its retained
  internal historical writer material is not the Issue #40 output authority; current routing is
  documented in `docs/architecture.md`, `docs/streaming-speech-design.md`, and D-40-01.
- `docs/conventions.md` — no behavior, API, setup, or workflow convention changed.
- `docs/decisions/D-18-01.md` — credential Keychain contract is unchanged; the legacy `autoInsert`
  field remains a decode/preservation detail already reconciled in the current architecture docs.
- `docs/decisions/D-28-01.md`, `D-32-01.md`, and `D-34-01.md` — protected capture/recognition and
  transport decisions did not change; only their ownership relationship is referenced where needed.
- Archived `kaola-workflow/archive/**` records — historical workflow evidence is not rewritten.
- `CLAUDE.md`, `AGENTS.md`, workflow state, mission lists, roadmap, source, and tests — outside
  documentation-docking scope or protected/concurrent files; none were edited.

## Validation

Commands run by this documentation-only pass from the issue worktree:

1. `git diff --check` — passed.
2. Local Ruby relative-Markdown-link check over all twelve updated documentation files — passed;
   no broken relative links.
3. Trailing-whitespace scan (`rg -n '[[:blank:]]+$'`) over all twelve updated documentation
   files — passed with no matches.
4. Aggregate contract-text check for `editablePending`, `recognition/provider`, both legacy
   settings, same-panel retention, no automatic recovery, fixed PID, and keyboard gate terms —
   passed.
5. `git diff --name-only -- README.md CHANGELOG.md docs` — confirmed only the twelve listed
   documentation files changed in the documentation tree.

Existing workflow evidence in `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/final-validation.md`
was consulted but not rerun by this doc-only pass: focused 79/79, full serialized 442 tests with
one intentional live-TCP skip and zero failures, Debug/Release builds, strict SwiftLint, protected
async-topology checks, and the prior eight-surface Markdown-link check. This pass did not claim a
new build, test, lint, install, or live UAT result.

## Remaining documentation/product risks

- Installed Release UAT remains pending for same-panel WindowServer readiness, exact AX delivery,
  application-bound fixed-PID delivery, Secure Input/password rejection, focus/PID races, and
  third-party Cmd+V acceptance. Local event submission is not target acceptance.
- Draft authority is in-memory and generation-scoped; process termination or explicit lifecycle
  cleanup can revoke it. No disk persistence was added.
- `docs/api.md` retains older internal writer details by explicit no-impact authority; if that
  surface is later promoted as a user-facing output contract, it needs a separately authorized
  historical annotation/update.

## Result location

Updated documentation is in the twelve worktree paths listed above. This full receipt is at:
`/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/docs-report-v2.md`.

## Issue #40 v3 installed-UAT correction (2026-08-23)

This append records the documentation reconciliation for the installed-UAT v3 correction. The
authoritative evidence was read from:

- `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/installed-release-v2.md`
  — owner UAT failed on the installed Release candidate: the same draft remained in a persistent
  `重试编辑` presentation, transcript text was too small, and streaming content overlapped the
  upper-left titlebar controls; panel size was acceptable and must not be enlarged.
- `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/github-uat-failure-v3.md`
  — the correction scope is to remove pending retry-editing UI, increase typography without panel
  enlargement, keep titlebar-safe read-only content, and leave Issue #40 open pending replacement
  Release installation and owner UAT.
- `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/implementation-v2.md`
  — v3 source scope and local verification receipt.

### Source changes requiring v3 documentation reconciliation

- `FeishuSpeech/Views/TranscriptionReviewView.swift` — shared 18pt transcript preview/editor
  typography; no visible `重试编辑`; pending is non-confirmable and Send/Return remains gated by
  `.editable`.
- `FeishuSpeech/Controllers/ReviewWindowController.swift` — unchanged 520x320 initial panel with
  420x240 minimum and 760x600 maximum; no `.fullSizeContentView`; activation request is advisory,
  while actual application-active, panel-key, editor-materialized/attached, and editor-first-
  responder predicates remain fail-closed.

The concurrent test edits were consulted as evidence but were not documentation surfaces and were
not edited by this doc-only pass. The protected capture/recording and recognition/provider roots,
action-2 plus recorder-barrier draft freeze, explicit Send/Return gate (Shift+Return/Enter newline),
exact-target preference, fixed-PID fallback, and no automatic copy/direct/retry/retarget contract
remain unchanged.

### Documentation updated in this v3 pass

- `README.md` — removed the user-facing pending `重试编辑` claim; documented advisory activation,
  fail-closed actual predicates, 18pt typography, unchanged panel bounds, titlebar-safe read-only
  content, and the failed/open installed-UAT status.
- `CHANGELOG.md` — added the v3 installed-UAT correction entry and changed the v2 verification
  wording from visible “readiness retry” to readiness re-evaluation.
- `docs/README.md` — indexed the v3 UI correction and marked installed UAT failed/open.
- `docs/architecture.md` — documented panel geometry/typography, removal of full-size content,
  advisory activation, actual fail-closed predicates, and no pending retry-editing control.
- `docs/streaming-speech-design.md` — reconciled state diagrams, same-panel draft retention,
  readiness re-evaluation, titlebar-safe geometry, 18pt typography, and the `.editable`-only output
  gate.
- `docs/decisions/D-38-01.md` — preserved the historical D-38 retry-editing wording as explicitly
  superseded by D-40-01 v3 while updating current state/retention text.
- `docs/decisions/D-40-01.md` — added the current v3 UI/readiness amendment, exact geometry and
  predicates, no visible pending retry-editing control, explicit output gate, and failed/open UAT
  boundary.

`docs/api.md`, `docs/conventions.md`, credential/transport decisions, archived workflow records,
source, tests, workflow state, mission lists, and roadmap files were deliberately skipped. No API,
transport, setup, entitlement, settings-schema, or asynchronous-topology contract changed; the
existing v2 receipt's skip decisions remain valid.

### v3 validation evidence and limits

The implementation receipt records the following local evidence (consulted, not rerun by this
documentation-only pass): four focused UI tests passed; the real production-surface frozen-draft
test passed; `ReviewWindowControllerReadinessTests` passed 10/10; `ReviewFirstMainViewModelTests`
30/30; `ReviewFirstApplicationFallbackTests` 16/16; `FinalTextOutputSecurityTests` 23/23; and
`ReviewPasteboardLifecycleTests` 7/7. Strict SwiftLint reported zero violations for the v3 pass.
The existing final-validation-v2 receipt additionally records 407 passed, 52 skipped, 0 failed in
the full serialized suite, with Debug/Release builds passing. None of this is installed-UAT proof.

Commands run by this v3 documentation-only pass:

1. `git diff --check` — passed.
2. Relative Markdown-link validation over the changed documentation surfaces — passed; no broken
   relative links.
3. Trailing-whitespace scan over changed documentation — passed.
4. Contract-text scan for v3 UI/readiness terms and stale pending retry-editing claims — passed;
   remaining Retry Editing mentions are explicitly marked as historical/superseded or describe
   retained draft retry/edit/discard semantics, not a pending button.
5. `git diff --name-only -- README.md CHANGELOG.md docs` and protected-path status inspection —
   confirmed documentation-only edits by this pass; concurrent source/test modifications were
   preserved.

Installed UAT v3 remains failed/open. The replacement Release installation and owner UAT are still
required; this receipt makes no release, merge, closure, archive, or UAT-pass claim.

## V3R2 closure — fixed delivery feedback literals (2026-08-23)

Correctness review `V3R2` in `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/code-review-v2.md`
identified one documentation-only mismatch in the current (nonhistorical) UI/settings contract.
The design document previously promised the superseded retry-oriented strings. `docs/streaming-speech-design.md`
now matches the production `TranscriptionReviewView` contract exactly:

- `.deliveryFailed`: `输入失败；草稿已保留，请编辑后显式发送。`
- `.deliveryUncertain`: `输入状态不确定；再次发送可能造成重复输入。`

The old literals `输入失败；草稿已保留，请显式重试或取消。` and
`输入状态不确定；重试可能造成重复输入。` are absent from the current documentation. No
historical decision or source/test/workflow file was changed.

V3R2 validation rerun from the issue worktree:

1. `git diff --check` — passed.
2. Relative Markdown-link validation across the 7 changed documentation files — passed.
3. Stale-string/contract scan — passed: corrected literals present, old literals absent, and v3
   readiness/pending contract terms remain present.

V3R2 is documentation-closed. Installed UAT remains failed/open as recorded above.
