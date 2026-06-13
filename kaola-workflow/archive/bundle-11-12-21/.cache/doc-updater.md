# Documentation Update

Status: subagent-invoked
Evidence: `.cache/n6-docs.md`

The adaptive plan delegated `n6-docs` to the `doc-updater` role. It updated:

- `docs/api.md` with the Feishu API contract, direct HTTP completion rules, timeout buffered parse fallback, token expiry cache rules, cancellation semantics, and test target caveat.
- `docs/decisions/D-11-01.md` with the accepted decision record for issues #11/#12/#21.

The finalize node then updated `CHANGELOG.md` for the same delivered behavior.

Structured API details in `docs/api.md` were transcribed from local code and tests: Feishu endpoint paths, request/response model names, cache lifetime rules, and retry/cancellation behavior.
