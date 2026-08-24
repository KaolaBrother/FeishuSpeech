## V3 repair installed for second owner UAT — 2026-08-23

Candidate: `4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a` on `workflow/issue-40`.

Closed observations from the failed installed UAT:

- Transcript preview and editor now share an explicit 18pt font. Panel dimensions remain unchanged.
- Pending UI no longer exposes a `重试编辑` button, action, shortcut, or text. Send/Return remains available only in the genuinely `.editable` state.
- A false accessory-app activation request is advisory; the same panel continues polling the actual application-active, panel-key, real-editor materialization/attachment, and first-responder predicates. Actual unmet predicates still fail closed.
- Full-size titlebar content was removed, so streaming/sealing content remains below the traffic-light controls while the same panel and size are retained.
- Fixed feedback preserves explicit-send semantics: target activation failure names the target application, and uncertain delivery warns that another send may duplicate output.

Final v3 evidence:

- Focused selectors: 122 passed, 0 failed.
- Full serialized target: 416 passed, 52 intentional skips, 0 failed.
- Debug/Release builds, strict lint, diff/protected/forbidden-route/docs checks: passed.
- Independent correctness review: PASS, 0 blockers.
- Independent security review: PASS, 0 blockers.
- Installed Release SHA-256: `91731ffe1b2e0fac6943b96ae1ff34bc7335d72757a9af4f1bd59de7d48d9690`.
- `/Applications` / `~/Applications` audit: exactly one installed `FeishuSpeech.app`; exactly one process runs from `/Applications/FeishuSpeech.app`.

Issue #40 remains open for the second owner UAT. Required checks: no streaming/titlebar overlap; text size is acceptable; Fn release leads to direct editable Send/Return without `重试编辑`; explicit Return sends exactly once. No transcript content should be posted.
