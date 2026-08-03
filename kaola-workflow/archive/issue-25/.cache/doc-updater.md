# Documentation updater — issue-25

status: complete-inline

The Kaola profile preflight reported `config_stale` from managed-block drift, so no role dispatch
was attempted. The main session performed the documentation audit against verified repository and
external API evidence.

## Ground truth reviewed

- Current FeishuSpeech `HotKeyService`, `AudioRecorder`, `FeishuAPIService`, `MainViewModel`, and
  `TextInputSimulator` behavior.
- KaolaTerminal commits `96b9422` (D-148) and `397ad67` (D-149).
- Official Feishu `stream_recognize` documentation and official Apple Accessibility range and
  attribute-settability documentation.

## Documentation actions

- Added `docs/decisions/D-25-01.md` as the accepted design-only decision.
- Added `docs/streaming-speech-design.md` as the executable architecture and test blueprint.
- Docked the planned state, audio, transport, cursor, fallback, lifecycle, and privacy contracts in
  `docs/architecture.md` and `docs/api.md`.
- Linked the design from `docs/README.md`.

## Deliberate no-impact surfaces

- Root `README.md`: no shipped behavior or setup changed.
- `CHANGELOG.md`: issue #25 ships no application behavior.
- `.env.example`: absent and no environment contract was introduced.
- Swift source and tests: intentionally unchanged by the design-only issue.
- `CLAUDE.md`: refreshed and pushed separately as commit `de6ebbe` before issue #25; no second
  user-instruction rewrite is mixed into this product-design branch.

verdict: DOCKED
