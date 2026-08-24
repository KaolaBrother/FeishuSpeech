# Issue #40 v4 documentation docking receipt

- Date: 2026-08-23
- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
- Branch: `workflow/issue-40`
- Scope: documentation-only reconciliation for the v4 preview/output contract
- GitHub: no issue comment, PR, or other external post was made
- Commit: no commit was made

## Current v4 authority and status

The current design authority is
`/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/architecture-blueprint-v4.md`.
The documentation now treats the following as the single current contract:

- every accepted recording/recognition interaction converges through one retained panel and one
  durable editable draft; the capture/recording and recognition/provider/retry/replay lines remain
  independent asynchronous roots;
- action 2 plus the recorder callback barrier publishes `.editable` directly; focus and activation
  are bounded presentation telemetry and cannot hide Send/Return, revoke the draft, or become a
  data-line dependency;
- no target output, synthetic signal, AX setter used as output, clipboard operation, copy/paste,
  automatic retry, or retarget occurs before a real Send or qualified Return/Enter confirmation;
- confirmation uses one opaque UI intent, one modifier-free Unicode key-down/key-up pair to the
  captured positive PID, full text up to 16,384 UTF-16 code units, provenance/readback and
  fail-closed epoch/security gates; post-boundary results are `submittedUnverified` and retain the
  exact draft for a later fresh explicit confirmation;
- the retry-editing/pending readiness product state is removed, transcript typography is 18pt, and
  the existing 520x320 initial / 420x240 minimum / 760x600 maximum panel geometry and titlebar-safe
  layout remain unchanged.

V4 automated evidence is green: the serialized focused matrix exited 0 with 264 executed tests, 51
explicitly skipped retired direct-output MainViewModel oracles, and 0 failures. The rejected v3
candidate at `4f9908f` was stopped. No v4 Release has been installed; sole-copy installation audit,
independent final review, and owner UAT remain pending. The docs make no target-consumption,
WindowServer, credential-bearing, or broad compatibility success claim.

## Changed source files requiring documentation reconciliation

The v4 implementation receipts identify these production files as behavior-relevant sources:

- `FeishuSpeech/Controllers/ReviewWindowController.swift` — same-panel transition now publishes
  `.editable` immediately after action 2 plus the recorder barrier; focus is advisory telemetry.
- `FeishuSpeech/Models/CursorTextModels.swift` — review delivery distinguishes local
  `submittedUnverified` from target-consumption success.
- `FeishuSpeech/Models/TranscriptionReviewState.swift` — direct editable state, opaque confirmation
  intent, draft retention, and phase-aware delivery feedback are the current review state model.
- `FeishuSpeech/Services/CurrentFocusAppendSession.swift` — fixed-tag plus own-PID monitoring and
  physical/activation epoch safety support the review delivery gate.
- `FeishuSpeech/Services/ReviewDestinationDelivery.swift` — exact-AX preference, captured-app
  fallback, one Unicode pair, live identity/security checks, and no retry/retarget.
- `FeishuSpeech/Services/TextInputSimulator.swift` — text-only Unicode pair construction,
  16,384-unit cap, readback/provenance, mandatory key-up, and submitted-unverified boundary;
  review pasteboard/Cmd+V behavior is removed.
- `FeishuSpeech/ViewModels/MainViewModel.swift` — both legacy setting values converge on review;
  capture/recognition remain independent; explicit confirmation owns delivery.
- `FeishuSpeech/Views/TranscriptionReviewView.swift` — 18pt preview/editor, immediate Send and
  qualified Return/Enter callbacks, and no retry-editing UI.

`HotKeyService.swift` was inspected as the protected hot-key/topology boundary and required no v4
edit. The concurrent test changes were consulted as validation evidence, not edited by this
documentation pass.

## Documentation updated

- `README.md` — documented the one-route preview workflow, independent async roots, direct editable
  transition, explicit Send/Return boundary, fixed-PID Unicode pair, 16,384 UTF-16 cap,
  submitted-unverified draft retention, 18pt/titlebar-safe UI, stopped v3 candidate, and pending
  v4 installation/UAT. Historical token/action-1 UAT wording is explicitly marked historical.
- `CHANGELOG.md` — added the v4 automated-green/install-pending entry; marked v2/v3 readiness,
  pasteboard/Cmd+V, and retry-editing descriptions as historical/superseded where they remain for
  traceability; retained the async topology and keyboard policy.
- `docs/README.md` — indexed the v4 current D-40-01 authority and reconciled the architecture,
  streaming design, D-38 base, and D-39 keyboard-policy descriptions.
- `docs/architecture.md` — reconciled the system flow, three independent axes, direct `.editable`
  state, advisory focus, real UI confirmation authority, fixed-PID Unicode delivery, no-pasteboard
  boundary, phase-aware uncertainty, and the v4 verification/install boundary. Dormant writer
  details remain explicitly historical.
- `docs/streaming-speech-design.md` — reconciled design/state diagrams, ownership/structure,
  preview and focus behavior, keyboard contract, zero-side-effect ledger, Unicode/cap/provenance
  gates, submitted-unverified semantics, automated evidence, and the pending live UAT matrix.
- `docs/decisions/D-38-01.md` — retained the historical D-38 decision while correcting its state
  diagram and labeling strict-AX startup, readiness authority, pasteboard/Cmd+V, and retry-editing
  behavior as superseded by v4.
- `docs/decisions/D-39-01.md` — retained the Return/Enter, Shift+Return/Enter, Command+Return, and
  marked-text policy; stated that v4 changes delivery only and removes pasteboard/Cmd+V.
- `docs/decisions/D-40-01.md` — created the current v4 ADR covering one durable preview, unchanged
  async topology, direct `.editable`, explicit opaque confirmation, exact/application-bound target
  authority, text-only one-pair output, cap/readback/epoch gates, draft retention, evidence links,
  and the rejected-v3/no-v4-installed boundary.

The D-40-01 evidence links were corrected to resolve from the worktree documentation directory to
the shared issue evidence directory:
`architecture-blueprint-v4.md`, `test-green-v4.md`, `implementation-v4-ui.md`,
`implementation-v4-output.md`, `github-v3-uat-failure-v4.md`,
`github-residual-system-diagnosis-v4.md`, and `installed-release-v2.md`.

## Deliberately skipped surfaces

- `docs/api.md` — no Feishu API request/response, token, transport, dependency, entitlement, or
  settings-schema contract changed. The current output contract is documented in architecture,
  streaming design, and D-40-01; older dormant writer material in the API document remains outside
  this issue's behavior change.
- `docs/conventions.md` — no coding, setup, or repository convention changed.
- `docs/decisions/D-18-01.md`, `D-25-01.md`, `D-26-01.md`, `D-27-01.md`, `D-28-01.md`,
  `D-32-01.md`, and `D-34-01.md` — credential, historical writer, capture/journal, recognition,
  and transport decisions were not rewritten; the affected current boundary is cross-referenced
  from the updated v4 architecture/design records.
- `docs/designs/capture-recognition-split-direct-connect.md` — capture/recognition/transport
  ownership and no-UI-backpressure behavior are unchanged; current v4 routing is stated in the
  updated architecture/design/ADR surfaces.
- Archived workflow records, `CLAUDE.md`, `AGENTS.md`, workflow state, mission lists, roadmap,
  production source, and tests — protected or outside documentation-docking scope; none were
  edited by this pass.

## Validation performed

All commands below were run from the issue worktree and apply only to the documentation pass:

1. `git diff --check` — passed.
2. A local Ruby relative-Markdown-link check over the eight changed documentation files — passed;
   no broken local links. External links were excluded from local filesystem resolution.
3. `rg -n '[[:blank:]]+$' README.md CHANGELOG.md docs/README.md docs/architecture.md
   docs/decisions/D-38-01.md docs/decisions/D-39-01.md docs/decisions/D-40-01.md
   docs/streaming-speech-design.md` — passed with no trailing whitespace.
4. Contract/stale-term inspection over the same files — passed after manual review: current text
   uses `streaming -> sealing -> editable -> confirming`, direct Send/Return availability,
   no-pasteboard/no-Cmd+V output, 16,384 UTF-16, submitted-unverified retention, and pending
   installation/UAT; remaining `editablePending`, pasteboard, Cmd+V, and retry terms are historical
   or explicitly forbidden current behavior.
5. `git diff --name-only -- README.md CHANGELOG.md docs` — confirmed exactly these eight documentation
   files changed in the documentation tree. Concurrent production/test changes remain present and
   were preserved.

The v4 build/test result was consulted from `test-green-v4.md`; this documentation pass did not
rerun build, tests, lint, installation, or live UAT.

## Remaining documentation/product risks

- No replacement v4 Release is installed, so sole-copy installation and owner UAT are still
  required. The v3 installed candidate remains rejected/stopped, not a success baseline.
- Local `CGEventPostToPid` submission has no application-level consumption receipt. Real target
  acceptance, WindowServer focus/activation, Accessibility restoration, Secure Input/password
  rejection, live credentials, modifier/epoch races, and cross-application Unicode behavior remain
  unverified until owner UAT.
- `docs/api.md` intentionally retains historical internal writer details; if it is later promoted
  as a user-facing output contract, it needs a separately authorized historical annotation/update.

## Result location

Updated documentation is in the eight worktree paths listed above. This complete receipt is at:
`/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/docs-report-v4.md`.
