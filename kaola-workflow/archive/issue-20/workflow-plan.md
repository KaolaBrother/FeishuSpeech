# Workflow Plan — issue #20

<!-- plan_hash: 273dfa1c2b4057964e39ea1dc9c4922037b6a4230e8e7ca2d459fc7dc4a8dd7c -->

## Meta
labels: enhancement, P3-low, workflow:in-progress

## Nodes

| id | role | depends_on | declared_write_set | cardinality | shape | model |
|---|---|---|---|---|---|---|
| coverage-audit | code-explorer | — | — | 1 | sequence | sonnet |
| test-seam-plan | planner | coverage-audit | — | 1 | sequence | opus |
| api-http-retry-tests | tdd-guide | test-seam-plan | FeishuSpeech/Services/FeishuAPIService.swift, FeishuSpeechTests/FeishuAPIServiceTests.swift, FeishuSpeechTests/MockURLProtocol.swift | 1 | sequence | sonnet |
| state-interplay-tests | tdd-guide | test-seam-plan | FeishuSpeech/Services/HotKeyService.swift, FeishuSpeech/ViewModels/MainViewModel.swift, FeishuSpeechTests/HotKeyServiceTests.swift, FeishuSpeechTests/MainViewModelTests.swift | 1 | sequence | sonnet |
| review | code-reviewer | api-http-retry-tests, state-interplay-tests | — | 1 | sequence | opus |
| token-cache-security-review | security-reviewer | review | — | 1 | sequence | opus |
| finalize | finalize | token-cache-security-review | CHANGELOG.md | 1 | sequence | — |

## Planner Notes

- `api-http-retry-tests` covers direct HTTP parsing edge cases, retry behavior, token-cache invalidation on speech 400/401 responses, and removal or justified repurposing of dead `MockURLProtocol`.
- `state-interplay-tests` covers HotKeyService/MainViewModel interactions from the prior state-machine regression family without relying on real event taps.
- `token-cache-security-review` is present because the API lane may alter auth/token-cache test seams or invalidation behavior.

## Node Ledger

| id | status |
|---|---|
| coverage-audit | complete |
| test-seam-plan | complete |
| api-http-retry-tests | complete |
| state-interplay-tests | complete |
| review | complete |
| token-cache-security-review | complete |
| finalize | complete |
## Required Agent Compliance

| Requirement | Status | Evidence | Skip Reason |
|-------------|--------|----------|-------------|
| code-explorer (coverage-audit) | subagent-invoked | evidence-binding: coverage-audit 500c5ed3f824 | |
| planner (test-seam-plan) | subagent-invoked | evidence-binding: test-seam-plan 671a0d5519db | |
| tdd-guide (api-http-retry-tests) | subagent-invoked | evidence-binding: api-http-retry-tests 1f649f27a915 | |
| tdd-guide (state-interplay-tests) | subagent-invoked | evidence-binding: state-interplay-tests 3185215c5054 | |
| code-reviewer | subagent-invoked | evidence-binding: review cd499c929161 | |
| security-reviewer | subagent-invoked | evidence-binding: token-cache-security-review d095f8d29f88 | |
| finalize (finalize) | main-session-direct | evidence-binding: finalize bf43cadbc203 | |
