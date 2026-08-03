# Documentation docking — issue-26

verdict: DOCKED

## Changed implementation and test surfaces reviewed

- `FeishuSpeech/Models/RecordingState.swift`
- `FeishuSpeech/Services/CurrentFocusAppendSession.swift`
- `FeishuSpeech/Services/TextInputSimulator.swift`
- `FeishuSpeech/ViewModels/MainViewModel.swift`
- `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift`
- `FeishuSpeechTests/FinalTextOutputSecurityTests.swift`
- `FeishuSpeechTests/StreamingMainViewModelTests.swift`

## Documents checked and updated

- `README.md` now states that usable partials are routed while Fn remains held and release only seals/finalizes.
- `CHANGELOG.md` records the captured final-only continuous owner, modifier-neutral PID-bound paired Unicode events, exact target/security validation, neutral feedback, and 263 passing tests.
- `docs/api.md` documents the coordinator/output contract, event construction order, security gates, and no-fallback boundary.
- `docs/architecture.md` documents captured and unbound append ownership and the target-acknowledgement limitation.
- `docs/streaming-speech-design.md` aligns state, trust, retry, release, and residual-UAT behavior.
- `docs/decisions/D-26-01.md` records the supersession of release-only captured final-only output.

`docs/README.md` already indexes the streaming design and D-26 decision; navigation did not change. `.env.example` and setup configuration were unaffected. The roadmap remains sourced from GitHub issue #26 and will stay open for installed owner UAT.

## Gaps

No documentation gap remains. `CGEventPostToPid` has no target-control acknowledgement, so the documents consistently limit the local claim to pair submission and retain installed owner UAT as the visible-output boundary.
