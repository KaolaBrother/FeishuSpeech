# Documentation docking — issue-25

verdict: DOCKED

## Changed files reviewed

- `docs/README.md`
- `docs/api.md`
- `docs/architecture.md`
- `docs/decisions/D-25-01.md`
- `docs/streaming-speech-design.md`

## Documents and contracts checked

- Issue #25 Summary, Current code facts, Proposed design, Test plan, and Acceptance criteria.
- Current whole-file endpoint and retry documentation remains explicitly labeled as implemented.
- Planned streaming documentation is explicitly labeled design-only and not implemented.
- Packet sizes, duration math, action/sequence rules, partial semantics, destination invalidation,
  final-only fallback, secure-target rejection, settings preservation, privacy, and future test
  slices agree across ADR, full design, architecture, and API docs.
- Official Feishu and Apple sources plus exact KaolaTerminal commit references are present.

## Gaps found and resolved

- Prevented a false cumulative/delta claim by locking every partial to opaque full-range replacement.
- Prevented stale-focus misrouting by binding writes to the original AX element and requiring
  pre/post range verification.
- Prevented unsafe compatibility behavior by rejecting per-partial paste, synthetic deletion, and
  whole-file fallback after stream establishment.
- Kept `autoInsert` semantics unchanged; removal or redefinition remains a separate product choice.

## No-impact reasons

- No code, test, build, dependency, environment, or shipped user behavior changed.
- Xcode build/test reruns are not triggered by documentation-only edits.
- `swiftlint` is not installed in the current shell, and no Swift lint surface changed.
