# Documentation Update

Status: subagent-invoked
Evidence: `.cache/docs-auto-clear-policy.md`

The adaptive plan delegated `docs-auto-clear-policy` to the `doc-updater` role. It updated:

- `docs/architecture.md` with the `MonitoringState` failed/active recovery contract and cleanup teardown invariant.
- `docs/decisions/D-24-01.md` with the accepted policy for issues #22/#23/#24.

The in-plan finalize sink then updated `CHANGELOG.md` for the same delivered behavior.

All documented behavior was transcribed from local code and tests in this worktree.
