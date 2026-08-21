# Documentation docking — issue #33

verdict: DOCKED

## Changed files reviewed

- `FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift` — `prohibitedInterfaceTypes = [.other]`; `DirectKeepAliveTransport`
- `FeishuSpeech/Services/TransportAttemptContext.swift` — keep-alive primary, URLSession connect-class fallback, sticky flags
- `FeishuSpeechTests/DirectFeishuKeepAliveSessionTests.swift`
- `FeishuSpeechTests/TransportAttemptContextTests.swift`

## Documents checked

| Surface | Action |
|---|---|
| `README.md` | Feature bullet + VPN FAQ |
| `CHANGELOG.md` | Unreleased Fixed, issue #33 |
| `docs/api.md` | Transport paragraph inverted |
| `docs/architecture.md` | Same |
| `docs/README.md` | D-32-01 listed; D-28-01 order superseded |
| `docs/decisions/D-32-01.md` | New ADR |
| `docs/decisions/D-28-01.md` | Pointer, body not rewritten |
| `docs/designs/capture-recognition-split-direct-connect.md` | Historical #28–#31; index pointer only (no-impact on body) |
| `.env.example` | Absent; no-impact |

## Gaps found and fixed

None after doc-updater. `doc-update.md` verdict DOCKED.

## No-impact reasons

- Overlay copy unchanged
- `file_recognize` unchanged
- Slice budgets unchanged
- No settings toggle
