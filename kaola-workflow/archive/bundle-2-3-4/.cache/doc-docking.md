# Documentation Docking — bundle-2-3-4

## Changed Code / Config / Test / Workflow Files Reviewed

From `git status` in worktree (`workflow/bundle-2-3-4`):
- `FeishuSpeech/Services/FeishuAPIService.swift` — modified (CancelBox, .waiting fast-fail, withTaskCancellationHandler, sendViaURLSession)
- `CHANGELOG.md` — modified (entries for #2, #3, #4)
- `README.md` — modified (FAQ entry for 识别卡在「识别中」很久)
- `docs/decisions/D-2-01.md` — untracked/new (ADR for bundle)
- `kaola-workflow/bundle-2-3-4/` — untracked (workflow artifacts)

## Acceptance Criteria (from workflow-plan.md)

Issue #2: NWConnection .waiting state fast-fail
- `case .waiting(let error): finish(.failure(error))` added in stateUpdateHandler ✓
- Reduces per-IP timeout from 30-75s to ~1ms ✓

Issue #3: URLSession DNS fallback after all direct IPs fail
- `sendViaURLSession()` method added ✓
- Called in `sendDirectRequest` after IP loop exhaustion ✓

Issue #4: withTaskCancellationHandler propagates task cancellation to NWConnection
- `CancelBox` type added (NSLock-protected, @unchecked Sendable) ✓
- `withTaskCancellationHandler` wraps the continuation ✓
- Reduces worst-case "识别中" hang from ~150s to ~30s ✓

## Documents Checked

| Document | Status | Evidence |
|----------|--------|---------|
| README.md | UPDATED | FAQ entry "识别卡在「识别中」很久" added under 常见问题 (n6-docs) |
| CHANGELOG.md | UPDATED | #2 Fixed entry, #3 Added entry, #4 Fixed entry under [Unreleased] (n7-finalize) |
| docs/decisions/D-2-01.md | CREATED | Full ADR: problem, decisions, alternatives, consequences (n3-implement) |
| docs/api.md | SKIPPED (no-impact) | Public interface of FeishuAPIService unchanged; stub would require fabricating Feishu schema |
| docs/architecture.md | SKIPPED (no-impact) | URLSession fallback is internal impl detail; covered in D-2-01 ADR; stub |
| .env.example | SKIPPED (no-impact) | No new env vars introduced |
| Inline comments | SKIPPED (no-impact) | No public interfaces changed; CancelBox is private; changes are in private methods |

## Review Findings Cross-Check

n4 code-reviewer: verdict=pass, findings_blocking=0, finding R1 (advisory, follow-up: explicit CancellationError check in withRetry) — non-blocking
n5 adversarial-verifier: verdict=pass, findings_blocking=0, 6 probes all not-refuted, finding R1 (same advisory) — non-blocking

All CRITICAL and HIGH findings: none.

## Gaps Found and Fixed

None. All public behavior, user-visible changes, and fix rationale are captured.

## Final Verdict

DOCKED
