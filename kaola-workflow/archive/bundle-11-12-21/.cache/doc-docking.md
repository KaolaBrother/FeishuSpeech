# Documentation Docking

verdict: DOCKED

## Changed Behavior

- Direct HTTP responses can now complete on complete `Content-Length` or terminal chunked bodies.
- Timeout handling parses complete buffered direct responses before throwing timeout.
- Feishu token cache lifetime honors `AuthResponse.expire` with a 300 second safety margin.
- Cancellation is terminal for retry, direct-IP iteration, and DNS fallback.
- The Xcode test target now runs the API regression tests plus existing passing test suites.

## Docking Matrix

| Surface | Status | Evidence |
|---|---|---|
| README.md | no change needed | Existing FAQ already covers user-facing API failure/reset behavior; this bundle is lower-level API contract detail. |
| docs/api.md | updated | Documents endpoint paths, direct HTTP completion, token cache, retry/cancellation, and test target caveat. |
| docs/architecture.md | no change needed | Existing architecture page covers component boundaries; this bundle did not change a cross-service architecture boundary. |
| docs/decisions/D-11-01.md | added | Records the #11/#12/#21 decision. |
| CHANGELOG.md | updated | Adds Unreleased test and fix notes for #11/#12/#21. |
| `.env.example` | not applicable | No environment variable or setup key changed. |
| kaola-workflow/ROADMAP.md | pending script refresh | `cmdFinalize`/sink merge refreshes roadmap after closing #11/#12/#21. |
| issue comments | not needed before sink | Merge sink will publish closure status for the bundled issues. |

## Gaps

None blocking. `swiftlint` remains unavailable on PATH and is recorded in final validation.
