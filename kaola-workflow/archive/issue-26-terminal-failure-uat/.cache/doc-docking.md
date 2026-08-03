# Documentation Docking

verdict: DOCKED

## Changed files reviewed

- `FeishuSpeech/Services/HotKeyService.swift`
- `FeishuSpeech/ViewModels/MainViewModel.swift`
- `FeishuSpeechTests/HotKeyServiceTests.swift`
- `FeishuSpeechTests/StreamingMainViewModelTests.swift`

## Documents checked

- `README.md` and `CHANGELOG.md`: user-visible fixed authentication feedback, guaranteed overlay dismissal, exact-once teardown, and owner-UAT boundary are recorded.
- `docs/api.md`: tenant-token acquisition precedes the streaming endpoint; authentication detail remains private.
- `docs/architecture.md` and `docs/decisions/D-25-01.md`: terminal ownership, generation invalidation, duplicate error suppression, and overlay ordering are recorded.
- `docs/streaming-speech-design.md`: coordinator, privacy, regression coverage, and real-tenant completion boundary are reconciled.
- `.env.example`: no impact because credential names, environment variables, and setup schema did not change.
- `kaola-workflow/ROADMAP.md`: no scope or priority change; issue #26 stays open for owner UAT.
- Issue comments: the sink will post the keep-open completion receipt after merge.

## Gaps

None. The documentation explicitly does not claim that the streaming endpoint succeeded: observed UAT was rejected during tenant-token acquisition, while valid credentials, permission, publication, edition eligibility, and live streaming remain owner-UAT gates.
