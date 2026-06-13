evidence-binding: finalize a7185da5ffe8
finalize-bookkeeping: updated CHANGELOG.md for bundle #22/#23/#24
changed_files:
  - CHANGELOG.md
summary:
  - Added Unreleased test coverage note for MainViewModel MonitoringState failure/recovery and cleanup subscription release tests.
  - Added Unreleased fix note for auto-clearing stale hot-key failure on .active recovery, cleanup routing through stopHotKeyMonitoring(), and DEBUG-only forceState(_:) helper.
validation:
  - git diff --check -- CHANGELOG.md passed.
