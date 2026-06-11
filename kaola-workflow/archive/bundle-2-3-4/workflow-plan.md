# Workflow Plan — bundle-2-3-4

<!-- plan_hash: 4d4bfe55ab86071bd874dd29648b4655d8919c373b853ede81b2fcdf4eca5320 -->

## Meta
issues: 2, 3, 4
labels: bug, P1-high, P1-high, P0-critical
closure_policy: all_or_nothing
summary: >
  Make the Feishu direct-IP HTTP path fail fast and stay responsive. Three coupled
  bugs all live in FeishuSpeech/Services/FeishuAPIService.swift (plus the timeout
  call site in MainViewModel.swift):
    #4 (P0) 30s transcription timeout does not cancel network work — app deaf in
            "识别中" for up to ~150s. Make DirectFeishuHTTPClient.send() cancellation
            -aware (withTaskCancellationHandler cancelling NWConnection); check
            Task.isCancelled between IP attempts and between retries.
    #2 (P1) NWConnection .waiting(error) is ignored (default: break) so dead IPs burn
            the full 30s timeout. Treat .waiting as fast failure (short grace, then
            finish(.failure)) so the IP loop advances in ms, not 30s.
    #3 (P1) 5 hardcoded CDN IPs with no DNS fallback. Keep direct-IP as fast path; add
            a fallback tier (system DNS / DoH resolve of open.feishu.cn and/or plain
            URLSession) when all direct IPs fail; optionally cache last-working IP.

## Plan Notes
- All three issues are semantically coupled in one file (DirectFeishuHTTPClient.send()
  state handler, the sendDirectRequest IP loop, and the withRetry/timeout path all
  interact). Per the cross-edition / semantic-coupling discipline (#309) the
  implementation is authored as ONE implement node over a shared canonical spec (the
  architecture decision record), NOT fanned out across the same file — file-disjoint
  parallel legs are impossible here and would risk divergent rewrites of send()/
  sendDirectRequest. Within the FILE_CEILING (FeishuAPIService.swift + MainViewModel.swift
  + D-2-01.md = 3 paths), so no split is needed.
- TEST-ROLE CHOICE: implementer, not tdd-guide. non_tdd_reason: the FeishuSpeechTests
  target is NOT wired into FeishuSpeech.xcodeproj (0 references in project.pbxproj), so
  `xcodebuild test` cannot run a new failing unit test, AND the change is async
  Network.framework cancellation / structured-concurrency integration glue (live-socket
  / cancellation-timing behavior) with no isolatable failing unit. Wiring a new test
  target into the .pbxproj is brittle project plumbing out of scope for this bug bundle.
  Correctness is enforced by the code-reviewer gate (G1) plus a dedicated
  adversarial-verifier gate probing the subtle async failure modes (cancellation race,
  continuation double-resume, NWConnection leak, fallback-tier deadlock).
- DECISION RECORD: docs/decisions/ is empty (only .gitkeep); no D-2-* / D-3-* / D-4-*
  recorded anywhere (docs/, CHANGELOG.md, README.md). Next free id for this bundle is
  D-2-01 (lead issue #2). code-architect (n2-design) is read-only (it returns the design
  to the executor, which threads it to the implementer); the implementer (n3-implement)
  authors docs/decisions/D-2-01.md as the durable canonical spec alongside the code it
  documents, so the record exists before the review/adversarial gates inspect it.
- KNOWLEDGE LOOKUP: #3 (DoH / system-DNS fallback for open.feishu.cn) and #4
  (withTaskCancellationHandler semantics with NWConnection.cancel(), and whether a
  throwing task group's child cancellation is prompt) depend on Apple Network.framework
  and Swift-concurrency behavior that cannot be confirmed from the local codebase alone
  — a knowledge-lookup head node feeds the architecture decision.
- SENSITIVITY: labels are bug / P*-priority only; the change touches network error/
  cancellation paths, not auth token storage, crypto, secrets, or new external trust
  boundaries (the existing app_id/app_secret handling is unchanged). No security-reviewer
  gate (G2) is required; if the validator derives sensitivity from labels it will say so
  and the plan will be repaired rather than clamped.

## Nodes

| id | role | depends_on | declared_write_set | cardinality | shape | model |
| --- | --- | --- | --- | --- | --- | --- |
| n1-research | knowledge-lookup | — | — | 1 | sequence | sonnet |
| n2-design | code-architect | n1-research | — | 1 | sequence | opus |
| n3-implement | implementer | n2-design | FeishuSpeech/Services/FeishuAPIService.swift, FeishuSpeech/ViewModels/MainViewModel.swift, docs/decisions/D-2-01.md | 1 | sequence | sonnet |
| n4-review | code-reviewer | n3-implement | — | 1 | sequence | opus |
| n5-adversarial | adversarial-verifier | n4-review | — | 1 | sequence | opus |
| n6-docs | doc-updater | n5-adversarial | README.md | 1 | sequence | sonnet |
| n7-finalize | finalize | n6-docs | CHANGELOG.md | 1 | sequence | sonnet |

## Node Ledger

| id | status |
| --- | --- |
| n1-research | pending |
| n2-design | pending |
| n3-implement | pending |
| n4-review | pending |
| n5-adversarial | pending |
| n6-docs | pending |
| n7-finalize | pending |
