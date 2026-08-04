# Issue #26 documentation docking

Date: 2026-08-04
Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`

## Result

SUCCESS for documentation docking. The current documentation now describes the implemented local
journal-indexed held-response policy and no longer presents raw response prefix similarity,
action-2 final text, or release-time fallback as output authority. Installed Release owner UAT
remains explicitly pending.

## Evidence reconciled

- Installed build 5 recorded 66 HTTP-200 transactions over 13.55 seconds while one-word visible
  output stalled. This proves continued transport, not response content or target acceptance.
- FeishuSpeech and KaolaTerminal expose opaque response scalars. Cumulative, delta, disjoint, and
  revision relationships remain unverified.
- Each eligible held response owns its stable journal packet index once and concatenates its raw
  scalar to a growing UTF-16 frontier. Equal, disjoint, shorter, and revised values on distinct
  indices all advance under this user-selected local policy.
- Replay never re-owns history; a previously failed unowned index may claim once when replay first
  succeeds.
- Release closes response-ledger and retry admission before draining. Action 2, in-flight packets,
  and late partial/final callbacks cannot create, append, replace, rewrite, Cmd+V, or copy output.
- Recognition availability is independent of output eligibility. Disabled, unsafe, and ownerless
  usable held recognition remains zero-output/zero-copy without becoming a false empty result or
  stream error.
- Diagnostics contain only transcript-free lengths, shapes, indices, ownership, and typed outcomes.
- Fixed PID, exact AX element, Secure Input, drift, uncertain-delivery, permanent suspension, and
  no-resend boundaries remain in force.
- Lifecycle-free XCTest evidence is 272/272 passing; correctness and security reviews pass. No
  vendor semantic, visible target acceptance, end-to-end success, or broad compatibility is claimed.

## Documentation impact

- `README.md`: rewrote the user workflow, no-live-output FAQ, runtime evidence, release boundary,
  recognition/output separation, privacy diagnostics, replay ownership, and pending UAT statement.
- `CHANGELOG.md`: docked the one-word diagnosis, response ledger, release suppression, removed
  release-time fallbacks, recognition-availability fix, 272/272 evidence, and updated UAT risks.
- `docs/architecture.md`: added the response-output ledger to system ownership and reconciled replay,
  AX/PID writers, release finalization, fallback removal, privacy receipts, and verification boundary.
- `docs/api.md`: changed the internal integration contract from latest replay/final authority to
  journal-index ownership, local frontier assembly, terminal non-admission, and transcript-free
  receipts; retained the provider-semantic unknown.
- `docs/streaming-speech-design.md`: updated goals, state/owner model, coordinator, AX/append paths,
  release/lifecycle behavior, diagnostics, evidence, test coverage, and completion gate.
- `docs/decisions/D-26-01.md`: replaced the superseded resilient-output decision text with the
  current journal-indexed held-response decision and its exact safety/UAT boundary.
- `docs/decisions/D-25-01.md`: added only a concise supersession/status note. The historical body was
  deliberately retained so prior issue #25 reasoning remains understandable; conflicting body text
  is explicitly non-authoritative.
- `docs/README.md`: updated navigation labels so D-26-01 is clearly current and D-25-01 historical.

## Deliberately skipped surfaces

- `CLAUDE.md` and `AGENTS.md`: no project-rule, workflow, setup, or canonical-instruction change.
- `docs/conventions.md`: no coding, test-authoring, Git, or review convention changed.
- Other ADRs: issue #26 does not change their decisions. D-25-01 needed only the targeted
  supersession note above.
- Code, tests, and project configuration: documentation ownership explicitly excluded them; existing
  concurrent changes were preserved and not edited.

## Validation commands

Run from the issue worktree:

```text
rg -n -i "latest accepted replay|latest replay|catch-up-frontier|final authority|action-2.*author|non-empty final.*replace|final exact|extending final|release-time.*available|copy-only|manual copy|manual-copy|94 tests|263|270|190 passed|34/34|16/16|opaque replacement state|strictly extending UTF-16|revisions.*suppress|duplicates are no-ops" README.md CHANGELOG.md docs/{README,architecture,api,streaming-speech-design}.md docs/decisions/D-26-01.md

ruby -e 'files=ARGV; bad=[]; files.each{|f| s=File.read(f); s.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each{|p| next if p =~ %r{^(https?://|#)}; target=p.split("#",2).first; path=File.expand_path(target,File.dirname(f)); bad << "#{f}: #{p}" unless File.exist?(path)}}; puts bad; exit(bad.empty? ? 0 : 1)' README.md CHANGELOG.md docs/README.md docs/architecture.md docs/api.md docs/streaming-speech-design.md docs/decisions/D-25-01.md docs/decisions/D-26-01.md

rg -n '[ \t]+$' README.md CHANGELOG.md docs/README.md docs/architecture.md docs/api.md docs/streaming-speech-design.md docs/decisions/D-25-01.md docs/decisions/D-26-01.md

rg -n '^#{1,6}[^ #]' README.md CHANGELOG.md docs/README.md docs/architecture.md docs/api.md docs/streaming-speech-design.md docs/decisions/D-25-01.md docs/decisions/D-26-01.md

git diff --check
```

Results: stale-contract hits are limited to explicit supersession/removal statements in D-26-01 and
current docs; all relative Markdown links resolve; no trailing whitespace or malformed heading
markers remain; `git diff --check` passes.

No application lifecycle, Fn event, microphone, credentials, permission prompt, installed bundle,
clipboard content, AX content, target content, or transcript was used during documentation docking.

## Remaining documentation risks

- Installed Release owner UAT may require a follow-up update if visible target acceptance, provider
  response-shape distribution, or cross-application behavior differs from local evidence.
- D-25-01 intentionally retains historical superseded text. Readers must follow its prominent
  supersession note to D-26-01 for the current contract.
