evidence-binding: n5-docs 859fd7e3f3d8
Doc-updater updated docs from current code/test ground truth only.
Changed files:
- docs/decisions/D-15-01.md: added accepted decision record for recorder fail-fast failures, main-thread abort/publish coordination, no-transcribe failure handling, and runtime no-prompt microphone refresh.
- docs/architecture.md: documented RecordingFailure cases, AVFoundation notification mappings, conversion-error exhaustion, main-hop before cleanup/published state mutation, MainViewModel failure handling, and the 2-second accessibility/microphone/secure-input poll.
- CHANGELOG.md: added issue #15 fixed entries for immediate recording failure surfacing and runtime microphone permission refresh.
Validation/read checks:
- Reviewed D-15-01.md, architecture.md, and CHANGELOG.md contents against AudioRecorder, MainViewModel, PermissionManager, AppDelegate, MainViewModelTests, and PermissionManagerTests behavior.
- git diff --check -- docs/decisions/D-15-01.md docs/architecture.md CHANGELOG.md => passed.
