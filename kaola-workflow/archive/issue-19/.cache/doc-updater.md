# Doc Updater - issue-19

status: subagent-invoked
evidence: `.cache/n7-docs.md`

The doc-updater node already updated the behavior-bearing docs for issue #19:

- `docs/decisions/D-19-01.md`
- `docs/architecture.md`
- `docs/api.md`
- `CHANGELOG.md`

Post-review n4 repair only added testability injection defaults for `MainViewModel` (`AppSettings = AppSettings.load()` and `HotKeyWakeRecovering = HotKeyService.shared`) plus test-only injected settings/recoverer usage. This did not change the user-facing sleep/wake recovery contract documented by n7, so no additional docs update was required.
