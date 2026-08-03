# Documentation docking receipt

verdict: DOCKED

Changed production and test files reviewed:

- `FeishuSpeech/Services/FeishuStreamingSession.swift`
- `FeishuSpeechTests/FeishuStreamingSessionTests.swift`

Documents checked and updated:

- `README.md`
- `CHANGELOG.md`
- `docs/api.md`
- `docs/architecture.md`
- `docs/streaming-speech-design.md`
- `docs/decisions/D-25-01.md`

The user-visible failure cause, request-versus-response trust boundary,
KaolaTerminal-compatible `recognition_text` / `text` handling, retained error and
privacy boundaries, 190-test validation count, and owner-UAT limitation are
docked. `docs/README.md`, environment examples, repository instructions, and the
roadmap have no structural or setup impact from this response-decoding repair.

gaps: none
