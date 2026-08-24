# Issue #40 documentation docking report

Date: 2026-08-23

Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`

## Changed files requiring documentation reconciliation

The five changed production files all alter review-first behavior or its typed authority boundary,
so they require documentation updates:

- `FeishuSpeech/Models/CursorTextModels.swift` — adds exact-vs-application-current-focus bindings,
  typed capture outcomes, review validation, and identity-aware insertion results.
- `FeishuSpeech/Services/AccessibilityClient.swift` — distinguishes exact capture, ordinary
  non-secure cursor capability misses, Secure Input, and lost Accessibility trust.
- `FeishuSpeech/Services/ReviewDestinationDelivery.swift` — captures and revalidates the complete
  original application before/after AX, prefers exact AX, and routes the fallback through the
  captured application PID.
- `FeishuSpeech/Services/TextInputSimulator.swift` — adds the multiline-safe review current-focus
  Cmd+V transaction, while the delivery layer performs two consecutive composite preflight samples
  ordered Secure Input start -> raw captured PID -> running/frontmost identities -> Secure Input
  end, plus the equivalent postflight shape; compatibility Unicode output remains unchanged.
- `FeishuSpeech/ViewModels/MainViewModel.swift` — accepts the typed fallback capture before panel,
  audio, provider, journal, or consumer startup and preserves the existing review lifecycle.

The changed review tests and the new `FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift`
do not introduce independent product contracts, but their verified 79/79 focused GREEN evidence is
recorded in the user-facing and architecture documentation.

## Documentation updated

- `docs/decisions/D-40-01.md` — new implemented authority for Issue #40: identity-first capture,
  exact AX preference, ordinary non-secure AX-miss fallback, typed rejection boundaries, two
  consecutive composite preflight/postflight security/PID/identity samples, fixed-PID multiline Cmd+V, exact-once recovery, and
  the explicit limit that fallback proves the original application rather than the original control
  or caret. Records the 79/79 focused evidence and UAT boundary.
- `docs/decisions/D-38-01.md` — header and live-preview/capture/delivery/consequence sections now
  state that D-40 supersedes only strict-AX-only startup admission; exact AX remains preferred and
  ordinary non-secure misses may use the captured application's current focus.
- `docs/decisions/D-39-01.md` — retains the keyboard policy while identifying target capture as
  D-38 amended by D-40.
- `README.md` — documents the two review bindings, fixed-PID fallback delivery, capability limit,
  and troubleshooting for `无法确认输入位置`; ordinary non-secure final-only/editable AX misses
  are no longer expected to show that startup message, while secure/incomplete/drifting identity
  remains fail closed.
- `CHANGELOG.md` — records the Issue #40 added fallback and startup false-rejection fix, 79/79
  focused validation, and the required installed Release UAT matrix.
- `docs/README.md` — adds the D-40 decision and updates the streaming-design index description.
- `docs/architecture.md` — updates the review topology, typed identity-first capture, exact and
  fallback delivery/pasteboard boundaries, concurrency ownership, 79/79 evidence, and UAT risks.
- `docs/streaming-speech-design.md` — updates outcome/state diagrams, capture and delivery design,
  UI warnings, implementation slices, automated coverage, UAT matrix, and completion history.

## Deliberately skipped surfaces

- `docs/api.md` — no impact. Issue #40 changes no Feishu request/response, token, transport, or API
  integration contract.
- `docs/conventions.md`, project/build/configuration docs, and compatibility-route decision records
  — no behavior or convention change in their scope; the compatibility Unicode route remains
  unchanged.
- Workflow state, mission list, roadmap mirror, production code, tests, and other documentation
  files — outside the assigned documentation ownership.

## Validation commands

The repository does not provide a Markdown-link checker, and these binaries were unavailable:
`markdown-link-check`, `lychee`, `markdownlint`, and `mdl`. I ran the following local checks over
the eight assigned Markdown surfaces:

- `git diff --check` — passed.
- Ruby relative Markdown-link existence check over `README.md`, `CHANGELOG.md`, `docs/README.md`,
  `docs/architecture.md`, `docs/streaming-speech-design.md`, `docs/decisions/D-38-01.md`,
  `docs/decisions/D-39-01.md`, and `docs/decisions/D-40-01.md` — passed for all eight files.
- `rg -n '[[:blank:]]+$'` trailing-whitespace check over those same eight files — passed.
- Stale-evidence scan over the eight docs plus this report — no obsolete count references; all
  Issue #40 evidence now reads 79/79.

The implementation/test custody artifacts record the strengthened R1 serialized focused GREEN
command and its result: 79 tests passed with 0 failures in `kaola-workflow/issue-40/test-green.md`.
No build or test rerun was needed for this documentation-only reconciliation.

## Remaining documentation and product risks

- Installed Release UAT must verify an ordinary non-secure final-only/editable target that formerly
  showed `无法确认输入位置`, an exact-AX target, Secure Input/password rejection, app switching
  during confirmation, multiline confirmation, and manual recovery after forced post/postflight
  uncertainty.
- The fallback can prove only the original complete application. It cannot prove or restore the
  original intra-application control/caret, and `CGEvent.postToPid` cannot acknowledge third-party
  Cmd+V consumption.
- Therefore no documentation claims broad third-party acceptance, WindowServer activation success,
  visible text insertion, or automatic recovery after a possible post.

## Result location

The documentation changes are in the issue-40 worktree at the paths listed above. This record is
stored at `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/docs-report.md`.
