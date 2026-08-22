verdict: PASS

# Issue #38 documentation update

The documentation-only pass transcribed the verified final source and tests into:

- `README.md` and `CHANGELOG.md` for the default-on review-first workflow, the compatibility setting, and validation status.
- `docs/architecture.md` and `docs/streaming-speech-design.md` for the independent capture/journal, recognition/retry/replay, and review UI axes; same-panel authority transition; captured-destination delivery; failure closure; and clipboard lifecycle.
- `docs/README.md` for navigation.
- `docs/decisions/D-38-01.md` for the new decision, with conditional supersession notes in `D-25-01.md` and `D-27-01.md` that preserve the review-disabled compatibility route.

No API endpoint, request/response schema, credential contract, CLI, environment variable, or setup contract changed, so `docs/api.md` and `.env.example` have no impact. Repository instructions and conventions also have no impact.

`git diff --check` passed, local Markdown link targets were checked, and the update changed documentation files only.

