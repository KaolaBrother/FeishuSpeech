# Issue #40 documentation docking — v9 closure

Date: 2026-08-24
Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
Branch: `workflow/issue-40` (HEAD/origin: `584e09d`)
Scope: documentation files and this evidence receipt only. No production code, tests, git state,
workflow state, mission list, roadmap mirror, GitHub issue, install state, or commit was changed by
this documentation pass.

Verdict: **DOCKED**

## Ground truth reconciled

The v9 repair in commit `584e09d` maps successfully read non-native focused roles such as `AXWebArea`
to the existing ordinary non-secure frozen-application fallback. Recording/capture and
recognition/provider remain independent asynchronous roots. No output is authorized before panel-local
Send or qualified Return/Enter. Secure Input, Accessibility trust, identity/frontmost drift,
cancellation, deadline, modifier/interference, and lifecycle checks remain fail closed.

The owner reported on 2026-08-24 that the installed v9 now looks good with no observed problem. Owner
UAT passed for the exercised `Fn -> durable editable preview -> explicit panel-local Send/qualified
Return` flow. This is deliberately a scoped acceptance statement: it does not claim broad
cross-application compatibility or an OS-level acknowledgement that a target consumed a posted
Unicode pair.

Validation/install evidence reconciled:

- focused security/delivery matrix: 100 passed, 0 failed;
- full macOS target: 539 passed, 1 expected live-TCP skip, 0 failed;
- strict SwiftLint: 0 violations;
- Apple Development-signed `/Applications/FeishuSpeech.app` is the sole copy;
- install verification PID: `21271`;
- CDHash: `5bbecdf0c1f33a1cb2e477021c98a75ee32392bd`;
- executable SHA-256: `c2e9f2797c86789e69394e68dbd8c308767f5bd5cbb971d839e2213cd681d0ea`;
- GitHub evidence comment: <https://github.com/KaolaBrother/FeishuSpeech/issues/40#issuecomment-5395110907>.

The local receipts used for reconciliation are `.cache/github-v9-owner-uat-pass.md` and
`.cache/input-position-uat-repair-v9.md`.

## Documentation files changed

- `README.md` — replaced the v5/replacement-install/UAT-pending banner with the precise 2026-08-24
  v9 scoped owner-UAT result; clarified that the non-native-role fallback preserves fail-closed
  security and does not imply broad compatibility or OS target consumption; marked v5 validation
  paragraphs as historical where they still describe stopped candidates.
- `CHANGELOG.md` — added the current v9 installed-UAT verification entry, including the repair,
  exercised flow, test/lint totals, sole-copy identity, and explicit closure limits; marked v5
  pending-install/UAT text as historical and converted the remaining verification section to
  additional unexercised runtime/broad-compatibility risks.
- `docs/README.md` — updated the navigation summaries for the current v9 authority and scoped owner
  UAT result.
- `docs/architecture.md` — reconciled the verification boundary with the v9 100/539 receipts,
  sole-copy installation, and scoped owner UAT; retained independent async roots, zero-before-confirm,
  and fail-closed security boundaries; qualified additional credential-bearing/provider scenarios as
  outside the exercised flow.
- `docs/streaming-speech-design.md` — updated the v9 status, live installed-Release gate, submission
  acknowledgement caveat, and completion boundary; retained broader target/application and transport
  scenarios as unverified rather than turning scoped UAT into a compatibility claim.
- `docs/decisions/D-39-01.md` — reconciled the retained Return/Enter policy status and verification
  summary with the 2026-08-24 scoped v9 owner-UAT result.
- `docs/decisions/D-40-01.md` — updated the current decision status, v9 fallback evidence, test/lint
  totals, sole-copy/PID/hash receipt, owner-UAT closure scope, and explicit no-broad-compatibility or
  OS-consumption caveat. The record continues to state that Feishu API/request/response/token/transport/
  dependency/entitlement/settings contracts are unchanged and `docs/api.md` is unaffected.

## Checklist surfaces checked but deliberately unchanged

- `docs/api.md` — no impact. Issue #40 v9 changes focused-role classification and review/delivery
  authority; Feishu request/response, token, provider, transport, dependency, and error contracts did
  not change. Its generic credential-bearing and target-acceptance UAT cautions remain valid for
  additional scenarios outside this scoped owner flow.
- `docs/conventions.md` — no impact. No coding, testing, Git, or review convention changed.
- `docs/designs/capture-recognition-split-direct-connect.md` — no impact. It is the earlier
  issues #28–#31 capture/recognition/transport design; its separate network/replay UAT gate is not the
  v9 review-flow acceptance claim.
- `docs/decisions/D-25-01.md`, `D-26-01.md`, `D-27-01.md`, and `D-38-01.md` — historical or
  superseded decision snapshots. Their dated pending-UAT language is retained as historical evidence;
  the current authority is D-40-01 and now records the v9 scoped closure.
- `docs/decisions/` other than D-39-01 and D-40-01 — no current Issue #40 behavior, API contract,
  setup, or architecture boundary changed there.
- `AGENTS.md`, `CLAUDE.md`, workflow `workflow-state.md`/`mission-list.md`, `kaola-workflow/ROADMAP.md`,
  production Swift, tests, and GitHub content — explicitly out of this role's write scope; not changed.

## Commands and validation

Read/reconciliation commands included:

```text
sed -n '1,260p' CLAUDE.md
sed -n '1,260p' .kw/worktrees/issue-40/CLAUDE.md
git status --short --branch
git show --format=fuller --stat --summary 584e09d
rg -n -i 'owner UAT|pending|review|preview|confirm|secure input|fallback|issue.?40' README.md CHANGELOG.md docs
nl -ba README.md CHANGELOG.md docs/README.md docs/architecture.md docs/api.md docs/conventions.md docs/streaming-speech-design.md docs/decisions/D-39-01.md docs/decisions/D-40-01.md
nl -ba .cache/github-v9-owner-uat-pass.md .cache/input-position-uat-repair-v9.md
```

Validation commands:

```text
git diff --check
git diff --name-only
Ruby one-shot relative-Markdown-link checker over `README.md`, `CHANGELOG.md`, and `docs/**/*.md`
rg -n -i 'owner UAT remains pending|owner UAT is still required|pending owner UAT|owner UAT remains required' README.md CHANGELOG.md docs/README.md docs/architecture.md docs/streaming-speech-design.md docs/decisions/D-39-01.md docs/decisions/D-40-01.md
rg -n '100/100|539|live-TCP|SwiftLint|21271|5bbecdf0c1f33a1cb2e477021c98a75ee32392bd|c2e9f2797c86789e69394e68dbd8c308767f5bd5cbb971d839e2213cd681d0ea|2026-08-24' README.md CHANGELOG.md docs/README.md docs/architecture.md docs/streaming-speech-design.md docs/decisions/D-39-01.md docs/decisions/D-40-01.md
```

Results: `git diff --check` passed; the relative Markdown-link checker passed; the changed-file list
contains only the seven documentation files listed above; the current-state stale-pending scan is
clear except for explicitly historical v5/v7 wording; and the v9 evidence/count/hash scan is present.
Build, test, and SwiftLint were not rerun by this docs-only role because the supplied v9 receipts already
record those gates and no production/test file changed in this pass.

## Remaining documentation risks

The docs intentionally do not claim broad cross-application Accessibility/Unicode compatibility,
additional credential-bearing retry/replay/provider scenarios, or OS-level target consumption. The
`CGEventPostToPid` path remains locally submitted/unverified after its boundary; no acknowledgement,
automatic retry, global HID fallback, rollback, clipboard route, or retarget is implied. Historical
decision records still contain their original candidate-era pending/failure language and are labeled or
contextualized as historical rather than rewritten.

Result landed in the Issue #40 worktree at the seven paths above. This full evidence record landed at:
`/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/doc-updater.md`.
