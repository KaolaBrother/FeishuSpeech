evidence-binding: n6-security-review 77cb3b5a5ea0
verdict: pass
findings_blocking: 0
finding: id=S1 scope=needs_user_decision action=follow_up status=open severity=low fix_role=implementer rationale=AppDelegate pending lifecycle replay uses an uncapped enum-only buffer before view-model injection; no sensitive state retained, but coalescing would harden against in-process notification spam.

# n6 Security Review - issue #19

## Findings

### CRITICAL
none

### HIGH
none

### MEDIUM
none

### LOW
S1 - Non-blocking hardening: `AppDelegate` queues sleep/wake lifecycle events in `pendingWorkspaceLifecycleEvents` when no `MainViewModel` has been injected yet (`FeishuSpeech/App/AppDelegate.swift:99`, `FeishuSpeech/App/AppDelegate.swift:101`) and drains the array on replay (`FeishuSpeech/App/AppDelegate.swift:114`, `FeishuSpeech/App/AppDelegate.swift:115`).

Exploitability: Low. An attacker would need same-process code capable of repeatedly posting workspace lifecycle notifications before the SwiftUI menu view calls `setViewModel`; normal production wiring creates `MainViewModel()` at `FeishuSpeech/App/FeishuSpeechApp.swift:6` and injects it from `onAppear` at `FeishuSpeech/App/FeishuSpeechApp.swift:11`.

Impact: Memory-only growth during that pre-injection window. The queued value is the private two-case `WorkspaceLifecycleEvent` enum (`FeishuSpeech/App/AppDelegate.swift:9`) and does not retain credentials, Feishu tokens, audio data, recognized text, event tap handles, or view-model state.

Minimal remediation: If this is worth hardening, coalesce pending lifecycle replay into bounded state, such as at most one pending `willSleep` and one pending `didWake`, or keep only the last pending lifecycle transition.

## Security Review Notes

Prose verdict: WARNING, non-blocking LOW hardening note only. Blocking findings: 0.

Reviewed the working-tree diff against `origin/main` / merge base `38b2e00ef0d92ca48e099b2ac3f863e537f9bd89` after `git fetch --prune origin`. `HEAD` equals `origin/main`; the issue #19 implementation is currently in the worktree diff.

- `FeishuAPIService.resetStateForWake()` calls `resetState()` and resets availability for a fresh wake probe (`FeishuSpeech/Services/FeishuAPIService.swift:381`, `FeishuSpeech/Services/FeishuAPIService.swift:387`). DEBUG state snapshots expose only booleans for token/expiry presence and an injected error description, not token or expiry values (`FeishuSpeech/Services/FeishuAPIService.swift:392`, `FeishuSpeech/Services/FeishuAPIService.swift:434`).
- `MainViewModel` preserves the production default `AppSettings.load()` through its default initializer argument (`FeishuSpeech/ViewModels/MainViewModel.swift:52`, `FeishuSpeech/ViewModels/MainViewModel.swift:54`), and saving still routes through `settings.save()` / `AppSettings.load()` comparison (`FeishuSpeech/ViewModels/MainViewModel.swift:420`, `FeishuSpeech/ViewModels/MainViewModel.swift:422`). The injection seam is not a credential persistence bypass.
- Sleep/wake handling cancels the current transcription generation, cancels the task, hides UI, force-cleans the recorder, stops timers, and returns hot-key state to idle (`FeishuSpeech/ViewModels/MainViewModel.swift:347`, `FeishuSpeech/ViewModels/MainViewModel.swift:360`). It does not call `stopRecording()` in the sleep path, so it does not intentionally package and submit pre-sleep recorder data after a sleep event.
- Stale transcription results are discarded before insertion and state reset (`FeishuSpeech/ViewModels/MainViewModel.swift:301`, `FeishuSpeech/ViewModels/MainViewModel.swift:306`). Recognized text logging remains present at `FeishuSpeech/ViewModels/MainViewModel.swift:298` and `FeishuSpeech/Services/FeishuAPIService.swift:609`, but both logging patterns existed on `origin/main`; this change does not newly expose recognized text beyond baseline behavior.
- AppDelegate lifecycle replay stores only `WorkspaceLifecycleEvent` enum cases while waiting for the weak view-model reference (`FeishuSpeech/App/AppDelegate.swift:16`, `FeishuSpeech/App/AppDelegate.swift:17`, `FeishuSpeech/App/AppDelegate.swift:99`) and removes observer tokens on termination (`FeishuSpeech/App/AppDelegate.swift:82`, `FeishuSpeech/App/AppDelegate.swift:85`).
- `HotKeyService.recoverAfterWake()` checks tap health without returning or publishing the `CFMachPort` (`FeishuSpeech/Services/HotKeyService.swift:232`, `FeishuSpeech/Services/HotKeyService.swift:262`). The new wake test hook takes booleans and returns only `restartCount` under `#if DEBUG` (`FeishuSpeech/Services/HotKeyService.swift:511`, `FeishuSpeech/Services/HotKeyService.swift:513`, `FeishuSpeech/Services/HotKeyService.swift:527`).

## Validation Evidence

- `git diff --check`: pass in this security-review session.
- Adaptive orient before evidence: `n6-security-review` was the only in-progress node and `.cache/n6-security-review.md` was absent.
- Existing cached validation from n5/n4 evidence included build-for-testing exit 0, focused issue #19 xctest exit 0 after loader-path repair, debug build exit 0, release build exit 0, and `swiftlint` unavailable in environment.
