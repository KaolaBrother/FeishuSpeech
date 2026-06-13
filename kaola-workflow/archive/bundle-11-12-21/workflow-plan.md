# Workflow Plan — bundle-11-12-21

<!-- plan_hash: 657551c80472433a6deb10b3a8c661537bea4b547e09c5e45574951f1b817215 -->

## Meta
issues: 11, 12, 21
labels: bug, P2-medium, P3-low, workflow:in-progress
closure_policy: all_or_nothing
summary: >
  Fix three coupled Feishu API resilience bugs in one implementation lane:
  complete direct HTTP responses from Content-Length or terminal chunked bodies without
  waiting for connection close (#11), honor Feishu auth response expire values with a
  safety margin instead of a hardcoded token lifetime (#12), and make cancellation
  explicit in withRetry and the direct-IP loop (#21).

## Plan Notes
- All three issues are semantically coupled in the Feishu API path. #11 touches
  `DirectFeishuHTTPClient.send()` and response parsing, #12 touches `AuthResponse`
  plus token cache expiry, and #21 touches `withRetry` and `sendDirectRequest`.
  They are authored as one TDD implementation node rather than parallel lanes because
  the primary write surface is shared and file-disjoint fan-out would risk divergent
  edits to the same retry/direct-request contract.
- TEST-ROLE CHOICE: `tdd-guide`. These are bug fixes and meaningful failing tests can
  be written before the fix: direct HTTP completion from content length/chunked data,
  token expiry derived from the decoded `expire` field with fallback behavior, and
  cancellation short-circuit behavior before additional retries/IP attempts. The current
  Xcode project has app sources under a synchronized root group and no test target wired
  into `FeishuSpeech.xcodeproj/project.pbxproj`, so the TDD node owns the minimal
  project/test wiring needed for `xcodebuild -scheme FeishuSpeech -destination
  'platform=macOS' test` to execute the focused tests.
- DECISION RECORD: existing records are `D-1-01 (existing)`, `D-2-01 (existing)`,
  `D-5-01 (existing)`, `D-6-01 (existing)`, and `D-13-01 (existing)`; no `D-11-*`,
  `D-12-*`, or `D-21-*` record or mention exists in `docs/`,
  `CHANGELOG.md`, or `kaola-workflow/ROADMAP.md`. The next free lead-issue record for
  this bundle is `docs/decisions/D-11-01.md`.
- KNOWLEDGE LOOKUP: not required as a separate node. The issue bodies and local code
  fully specify the expected behavior; HTTP/1.1 Content-Length/chunked completion and
  Swift `CancellationError` propagation are standard implementation constraints that
  the code-architect and review gates can validate against the local code and tests.
- SENSITIVITY: the frozen label union is bug/priority/workflow only. The work changes
  network response completion, retry cancellation, and token lifetime calculation, but
  does not add storage for secrets, encryption, permissions, or new trust boundaries.
  No `security-reviewer` gate is required unless the validator derives sensitivity from
  labels and returns a typed repair error.

## Nodes

| id | role | depends_on | declared_write_set | cardinality | shape | model |
| --- | --- | --- | --- | --- | --- | --- |
| n1-explore-api-contract | code-explorer | — | — | 1 | sequence | sonnet |
| n2-design-api-recovery | code-architect | n1-explore-api-contract | — | 1 | sequence | opus |
| n3-fix-api-recovery | tdd-guide | n2-design-api-recovery | FeishuSpeech/Services/FeishuAPIService.swift, FeishuSpeech/Models/SpeechResult.swift, FeishuSpeechTests/FeishuAPIServiceTests.swift, FeishuSpeech.xcodeproj/project.pbxproj | 1 | sequence | opus |
| n4-code-review | code-reviewer | n3-fix-api-recovery | — | 1 | sequence | opus |
| n5-adversarial-api | adversarial-verifier | n4-code-review | — | 1 | sequence | opus |
| n6-docs | doc-updater | n5-adversarial-api | docs/api.md, docs/decisions/D-11-01.md | 1 | sequence | sonnet |
| n7-finalize | finalize | n6-docs | CHANGELOG.md | 1 | sequence | — |

## Node Ledger

| id | status |
| --- | --- |
| n1-explore-api-contract | complete |
| n2-design-api-recovery | complete |
| n3-fix-api-recovery | complete |
| n4-code-review | complete |
| n5-adversarial-api | complete |
| n6-docs | complete |
| n7-finalize | complete |
## Required Agent Compliance

| Requirement | Status | Evidence | Skip Reason |
|-------------|--------|----------|-------------|
| code-explorer (n1-explore-api-contract) | subagent-invoked | evidence-binding: n1-explore-api-contract 75add68733b1 | |
| code-architect (n2-design-api-recovery) | subagent-invoked | evidence-binding: n2-design-api-recovery 857d8a3e6ddf | |
| tdd-guide (n3-fix-api-recovery) | subagent-invoked | evidence-binding: n3-fix-api-recovery 85aa2b33149a | |
| code-reviewer | subagent-invoked | evidence-binding: n4-code-review 12f48d771db1 | |
| adversarial-verifier (n5-adversarial-api) | subagent-invoked | evidence-binding: n5-adversarial-api 8d416ee096e0 | |
| doc-updater (n6-docs) | subagent-invoked | evidence-binding: n6-docs 1f1ca433822e | |
| finalize (n7-finalize) | main-session-direct | evidence-binding: n7-finalize 91bad6d7fd30 | |
