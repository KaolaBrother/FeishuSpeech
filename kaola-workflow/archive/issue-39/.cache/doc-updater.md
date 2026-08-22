verdict: PASS

# Issue #39 documentation update

The documentation-only pass transcribed the verified Return/Enter behavior into `README.md`,
`CHANGELOG.md`, `docs/README.md`, `docs/architecture.md`,
`docs/streaming-speech-design.md`, `docs/decisions/D-38-01.md`, and the new
`docs/decisions/D-39-01.md`.

Current behavior is documented as unmodified Return or keypad Enter confirming, Shift variants
inserting LF, Command+Return remaining a compatibility confirmation, and marked-text Return staying
with the input method. Escape, Cancel, close, and whitespace behavior remain explicit. D-39-01
supersedes only D-38-01's historical editable bare-Return rule.

No API, credential, transport, setup, environment, dependency, or public schema changed, so
`docs/api.md`, `.env.example`, and conventions have no impact. Markdown relative links and
`git diff --check` passed.

