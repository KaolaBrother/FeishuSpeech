# Documentation Docking — bundle-5-9-10

## Changed Code/Config/Test/Workflow Files Reviewed
- FeishuSpeech/Services/HotKeyService.swift — tap-lifecycle, monitoringState, NSLock, private thread
- FeishuSpeech/Services/HotKeyState.swift — MonitoringState, TapFailureReason enums
- FeishuSpeech/ViewModels/MainViewModel.swift — $monitoringState binding
- FeishuSpeech/Services/AudioRecorder.swift — sessionQueue, optimistic isRecording
- FeishuSpeech/Services/PermissionManager.swift — secureInputEnabled, refreshSecureInputStatus
- FeishuSpeech/Views/MenuBarView.swift — secure-input status UI
- FeishuSpeech/App/AppDelegate.swift — timer refresh call
- FeishuSpeechTests/HotKeyServiceTests.swift — 11 new tests
- FeishuSpeechTests/PermissionManagerTests.swift — 5 new tests (new file)
- CHANGELOG.md, docs/decisions/D-5-01.md, docs/architecture.md

## Documents Checked

### CHANGELOG.md ✅
Updated by node6. User-visible entries under [Unreleased]:
- Added: Observable MonitoringState (issue #5)
- Added: Secure-input menu-bar warning (issue #10)
- Fixed: Tap on dedicated thread (issue #9)
- Fixed: Unbounded capped-backoff retry (issue #5)
- Fixed: previousFlags reset on restart (issue #9)
Coverage: Complete.

### docs/decisions/D-5-01.md ✅
Created by node6. ADR covers: dedicated CFRunLoop thread, sessionQueue for AVCaptureSession, MonitoringState with backoff, previousFlags reset + Fn resync, PermissionManager polling. Consequences table covers threading invariants. Verified traceable to actual code (types, methods, property names match implementation).

### docs/architecture.md ✅
Updated by node6. New section "HotKeyService — tap-lifecycle and threading contract" added after existing state-machine section. Threading-invariant table, MonitoringState description, previousFlags lifecycle rule, secure-input detection note. No free-form invention detected.

### README.md — NO UPDATE NEEDED
Reason: no public API changes, no new features (these are reliability fixes), no new env vars, no new setup steps.

### docs/api.md — NO UPDATE NEEDED
Reason: no Feishu API integration changes.

### AGENTS.md — NO UPDATE NEEDED
Reason: threading contracts documented in docs/architecture.md and docs/decisions/D-5-01.md per the documentation map. No new conventions require AGENTS.md changes.

## Gaps Found and Fixed
None. node6 covered all necessary documentation before this docking check.

## Anti-Fabrication Check
- docs/decisions/D-5-01.md uses type names (MonitoringState, TapFailureReason, previousFlagsLock, sessionQueue, ensureTapRunLoop, refreshSecureInputStatus) that are traceable to actual Swift source files
- No invented field names, enum values, or example numbers detected
- Decision rationale references actual line numbers confirmed in source

## Final Verdict
DOCKED
