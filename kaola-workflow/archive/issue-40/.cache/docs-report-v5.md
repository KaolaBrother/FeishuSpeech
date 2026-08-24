# Issue #40 v5 documentation docking report

Date: 2026-08-24
Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
Branch: `workflow/issue-40`
Scope: documentation and evidence receipt only. No production, test, project, workflow-state, issue,
GitHub, install, or commit operation was performed by this docking pass.

## Change surfaces reconciled

The current v5 production diff contains the review-window and native-key arbiter changes, review state and
coordinator changes, fixed-target delivery changes, Accessibility client changes, the new
`ReviewSubmissionExecutor`, and the protected hot-key interference-epoch adjustment. The recording and
recognition topology remains two independent asynchronous roots; the docs now describe the review preview
as a third presentation axis rather than adding a dependency or backpressure edge.

The implementation/test/evidence receipts were reconciled against:

- `kaola-workflow/issue-40/architecture-blueprint-v5.md`
- `kaola-workflow/issue-40/architecture-blueprint-v5-r3.md`
- `kaola-workflow/issue-40/test-green-v5.md`
- `kaola-workflow/issue-40/.cache/final-validation-v5.md` (superseding R5 section)
- `kaola-workflow/issue-40/.cache/code-review-v5-r6.md`
- `kaola-workflow/issue-40/.cache/security-review-v5-r6.md`
- the prior Issue #40 v4/R4 docs and evidence receipts

The final documented contract is: streaming complete snapshots render while the capture and recognition
lines proceed independently; Fn release closes capture; same-generation authoritative action 2 plus the
recorder barrier publishes one durable editable draft in the same nonactivating panel; the panel remains
520x320 (420x240 minimum, 760x600 maximum) with 18pt transcript text; and there is no `editablePending` or
retry-editing control. Only panel-local Send or qualified local Return/Enter confirms. Blank/IME-marked,
modified, repeated, wrong-window, non-key-panel, and non-descendant-responder Return events are rejected.

Before confirmation there is no target signal, AX setter, pasteboard/Cmd+V operation, activation, retry, or
retarget. The captured positive PID, complete application identity, opaque target ID, and lease remain fixed.
One immutable modifier-free Unicode pair is built/read back before the final leading/trailing security
sandwich; each AX object/message receives the shared absolute deadline and cancellation checkpoints,
with cancellation winning over deadline. Exactly one Unicode down is attempted and mandatory up follows.
After the boundary the only delivery terminal is `submitted-unverified`; it never claims target consumption,
resends, or re-exposes ordinary confirmation. Pre-boundary failure retains the draft. Drain-expiry recovery,
when eligible, is non-authoritative read-only data with no Send/Return or delivery authority.

## Files updated

- `README.md`: user-facing v5 preview, nonactivating Send/Return rules, Return rejection matrix, fixed target
  and no-side-effect boundary, pair/security/deadline semantics, final test counts, and stopped/pending UAT
  status.
- `CHANGELOG.md`: current Unreleased v5 entry, exact validation counts, one expected live-TCP skip, output
  ordering, terminal submitted-unverified semantics, and replacement Release/UAT pending status. Older v2-v4
  entries remain explicitly historical.
- `docs/README.md`: documentation index summary and decision-record navigation now point to v5 authority and
  evidence; no new navigation target was required.
- `docs/architecture.md`: v5 architecture contract, nonactivating panel and independent async topology,
  opaque fixed-target executor, pair-before-security-sandwich ordering, per-AX cancellation/deadline, and
  terminal outcome/validation boundary.
- `docs/streaming-speech-design.md`: v5 status/outcome/state model, local keyboard rejection behavior,
  executor delivery ordering, no-pasteboard path, retained read-only recovery, final counts, and live-UAT
  boundary.
- `docs/decisions/D-38-01.md`: historical decision now carries an explicit v5 amendment and no longer
  presents activation or post-boundary editable retry as current behavior; v5 evidence/counts replace its
  current verification summary.
- `docs/decisions/D-39-01.md`: Return/Enter decision now states v5 blank/IME/modified/repeat/wrong-window/
  non-descendant rejection and v5 final evidence while retaining multiline/IME keyboard policy.
- `docs/decisions/D-40-01.md`: current Issue #40 authority upgraded to v5 with the executor/control-plane,
  opaque lease, security sandwich, per-AX deadline/cancellation, one down/mandatory up, terminal
  submitted-unverified, final receipts, and API no-impact statement.

## Evidence and validation commands

The supplied authoritative receipt records:

- focused: **324/324**, zero skipped and zero failures;
- full target: **537 passed**, zero failures, one documented expected live-TCP skip;
- Debug and Release builds: PASS;
- strict SwiftLint: PASS, zero violations;
- correctness review v5-r6: PASS, blocking findings 0;
- security review v5-r6: PASS, blocking findings 0.

The security receipt separately records a locked-console R6 probe at 65 passed/3 failed UI-backed selectors;
that is documented as environment-only and is not represented as green product evidence. The two unlocked
authoritative validation runs are the basis for the counts above. The app was not launched or installed;
the v3 installed candidate remains rejected/stopped.

Commands run in the issue worktree:

```text
git status --short
git diff --stat -- README.md CHANGELOG.md docs
git diff --check -- README.md CHANGELOG.md docs
Ruby relative-Markdown-link checker over all eight updated docs
rg trailing-whitespace scan over all eight updated docs
rg stale-v4/R4-count/activation/post-boundary-retention scan
rg v5-contract/count/UAT/status evidence scan
git diff --name-only -- docs/api.md FeishuSpeech/Services/FeishuAPIService.swift FeishuSpeech/Models/SpeechResult.swift FeishuSpeech/Services/FeishuStreamingSession.swift
```

Results: relative Markdown links are valid; `git diff --check` is clean; the trailing-whitespace scan is
empty; the current v5 count/status scan is present; and `docs/api.md` has no diff. The source-diff command
also confirms no Feishu API/transport model surface requires a documentation update.

## Deliberately skipped surfaces and remaining risks

- `docs/api.md` was deliberately not changed: the v5 repair changes review presentation, authority, AX
  validation, and output delivery; Feishu request/response, token, transport, dependency, entitlement,
  and settings schema are unchanged.
- Production Swift and test files were read for reconciliation but not edited by this role. Test receipts
  are evidence, not documentation surfaces. `CLAUDE.md`, `AGENTS.md`, workflow mission/state files, roadmap
  mirrors, and GitHub issue content were intentionally not changed.
- Replacement Release build installation, sole-copy audit, and owner UAT remain required. The app remains
  stopped pending release installation. Automated tests cannot prove WindowServer nonactivating-panel
  behavior across a live session, real Feishu credentials, third-party AX behavior, or target consumption;
  `CGEventPostToPid` supplies no application receipt. No broad cross-application compatibility or visible
  target-consumption success is claimed.

