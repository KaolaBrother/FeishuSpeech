# Documentation Docking

verdict: DOCKED

## Changed Behavior

- Hot-key monitoring failures surface the fixed error `热键不可用，请检查辅助功能权限`.
- When monitoring recovers to `.active`, `MainViewModel` auto-clears only that stale hot-key monitoring error.
- Unrelated errors remain visible on monitoring recovery.
- `cleanup()` now uses the same hot-key stop path as ordinary shutdown so `stateCancellable` is released.
- `HotKeyService.forceState(_:)` is a DEBUG-only test helper.

## Docking Matrix

| Surface | Status | Evidence |
|---|---|---|
| README.md | no change needed | User-facing setup and troubleshooting text did not change. |
| docs/api.md | no change needed | No Feishu API, request/response, token, or network contract changed. |
| docs/architecture.md | updated | Documents monitoring-state recovery and cleanup teardown invariants. |
| docs/decisions/D-24-01.md | added | Records the #22/#23/#24 policy decision. |
| CHANGELOG.md | updated | Adds Unreleased test and fix notes for #22/#23/#24. |
| `.env.example` | not applicable | No environment variable or setup key changed. |
| kaola-workflow/ROADMAP.md | pending script refresh | `cmdFinalize`/sink merge refreshes roadmap after closing #22/#23/#24. |
| issue comments | not needed before sink | Merge sink will publish closure status for the bundled issues. |

## Gaps

None blocking. `swiftlint` remains unavailable on PATH and is recorded in final validation.
