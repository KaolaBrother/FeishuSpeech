# Documentation Docking — issue-1

## Changed Files Reviewed

### Implementation / Test
- `FeishuSpeech/Services/AudioRecorder.swift` — `forceCleanup()` moved to top of `startRecording()`, guard removed
- `FeishuSpeech/ViewModels/MainViewModel.swift` — DI seam added; `forceCleanup()` in cancel/error/reset
- `FeishuSpeechTests/AudioRecorderRecoveryTests.swift` — new: 3-scenario recovery test suite

### Documentation
- `docs/decisions/D-1-01.md` — new ADR for three-part forceCleanup() recovery contract
- `docs/architecture.md` — "AudioRecorder — session lifecycle and recovery" section added
- `CHANGELOG.md` — entry under [Unreleased] Fixed

## Documents Checked

| Document | Status | Notes |
|----------|--------|-------|
| `CHANGELOG.md` | PRESENT | Entry: `「重置服务」现在能正确恢复卡住的麦克风…（issue #1）` |
| `docs/architecture.md` | UPDATED | Recovery section with forceCleanup() contract and D-1-01 cross-ref |
| `docs/decisions/D-1-01.md` | CREATED | ADR: problem, three-part decision, alternatives, consequences |
| `README.md` | SKIPPED | No new user-visible feature; existing "重置服务" button unchanged |
| `docs/api.md` | SKIPPED | No Feishu API changes |
| `.env.example` | SKIPPED | No new env vars introduced |
| `docs/conventions.md` | SKIPPED | No new project conventions introduced |
| `AGENTS.md` | SKIPPED | No new recipe; forceCleanup() contract is in D-1-01.md |

## Issue Acceptance Criteria vs Delivered

| Acceptance Criterion | Delivered |
|----------------------|-----------|
| Stop recorder in `handleCancelledState` / `handleErrorState` | `audioRecorder.forceCleanup()` added to both paths ✅ |
| `startRecording()` runs `forceCleanup()` before `isRecording` guard | Guard removed; `forceCleanup()` is now the unconditional first call ✅ |
| `resetService()` calls `audioRecorder.forceCleanup()` | Added at top of `resetService()` ✅ |

## Gaps Found
None.

## Final Verdict: DOCKED
