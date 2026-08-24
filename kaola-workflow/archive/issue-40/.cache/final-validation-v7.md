# Issue #40 v7 validation receipt

Date: 2026-08-24 (Asia/Shanghai)

- production commit: `614fb38329547fcd07af4609040f179a6f2a9792`
- production tree: `134f87a0943bd6cbff8b132a3a40a5ede58b80e6`
- install-state documentation head: `4126740d71b2a8df7e42c80196160d69b0719a6b`
- branch/remote: `workflow/issue-40` / `origin/workflow/issue-40`

Results:

- focused nine-suite matrix: 324 tests, 0 failures, 0 skips; `TEST SUCCEEDED`
- full serialized macOS target: 537 tests, 0 failures, 1 expected live-TCP skip;
  `TEST SUCCEEDED`
- Debug build: `BUILD SUCCEEDED`
- Apple Development-signed Release build: `BUILD SUCCEEDED`
- SwiftLint strict: 0 violations, 0 serious, 36 files
- `git diff --check`: pass

The delta removes ambient system-wide focus acquisition from initial target capture and adds
privacy-safe typed AX step logging. It does not change output intent, target delivery, Unicode events,
pasteboard behavior, confirmation authority, or the capture/recognition topology.
