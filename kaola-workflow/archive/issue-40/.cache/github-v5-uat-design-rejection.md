## 2026-08-24 third installed UAT: v4 rejected — proven Send deadlock and flawed Return/focus model

Owner UAT failed:

- Clicking **Send** changed the panel to “正在发送…” and the application stopped responding.
- Bare **Return/Enter** was not reliable because confirmation depended on the preview editor actually owning key/first-responder focus, while the user remained oriented to the original typing application.

FeishuSpeech was sampled live before being stopped. The installed candidate `b321ac5d6c04c91ced9afeb2240f9566d9b8d305` is rejected. No merge/closure/success claim remains valid.

### Measured Send root cause

All 2,620 main-thread samples were blocked in this exact stack:

`handleReviewConfirmation → deliver → performFinalPair → postCompleteSyntheticPairIfInterferenceEpochIsUnchanged → interferenceEpoch.getter → NSLock`

Production `CurrentFocusInputInterferenceEpoch.performIfUnchanged` holds its non-recursive lock while invoking caller work. That callback immediately reads `inputMonitor.interferenceEpoch`, whose concrete getter tries to acquire the same lock. The main actor self-deadlocks permanently; the hotkey event-tap thread then blocks behind it in `observePreDispatch`.

Sample: `/tmp/FeishuSpeech_2026-08-24_084734_25BZ.sample.txt`, SHA-256 `d2e8399687c8001ba1e3bc92b7df8ca81e4f3b2390421fcb40319735b9ebd6a0`.

The stall occurs **before `postPair()`**. For this sampled attempt:

- no Unicode key-down/up was posted;
- no pasteboard, copy, paste, Cmd+V, or image operation exists in the v4 accepted path;
- no FeishuSpeech process remains after stop; combined-session modifier flags are zero;
- exact-cursor focus/range AX restoration before the gate remains unmeasured because the sample does not identify the captured binding.

Changing `NSLock` to `NSRecursiveLock` is not an acceptable repair. The API flaw is executing arbitrary/reentrant caller code while the gate owns its internal lock.

### Why the green suite missed it

- Delivery/security tests injected unlocked monitors whose epoch was a plain property and whose gate directly invoked the callback.
- Concrete epoch tests never combined the production monitor with the review-delivery callback that recursively read the epoch.
- Native Return tests directly made a synthetic test window key/editor first responder and called `keyDown`; they did not prove installed AppKit routing.
- No main-actor heartbeat or whole-submission deadline test existed.

### Return/focus design flaws

1. Production creates a regular titled panel, not `.nonactivatingPanel`.
2. `renderDraft` only orders the panel front; a separate best-effort task activates FeishuSpeech, makes the panel key, and makes the editor first responder. Failure is telemetry only.
3. Every draft edit cancels that focus task without restarting it.
4. Bare Return exists only in `ReviewDraftTextView.keyDown`; without editor first-responder status it goes elsewhere. The button shortcut is Command+Return, not a bare-Return fallback.
5. A global Return monitor is not a safe workaround: if Return belongs to the original target, FeishuSpeech must not reinterpret it as confirmation or leak/suppress it unpredictably.

KaolaTerminal does **not** provide a macOS panel implementation to copy. Its preview is inline SwiftUI/iOS in the same terminal application/session. What should be adopted is its lifecycle: independent capture/recognition, final-barrier-to-editable, destination captured at gesture start, and one explicit Send. It provides no proof for AppKit activation, nonactivating panels, foreign-app caret restoration, or Return routing.

### Submission-lifecycle flaws

- `.confirming` disables editing and Cancel before delivery.
- Only the target-activation substep is bounded; the whole AX/WindowServer/gate/post transaction has no bounded settlement or responsive escape.
- After an irreversible key-down boundary, returning to an ordinary Send-enabled editor would allow accidental duplicate output and conflicts with the requested one-time submission.

### Recommended v5 contract

- Treat the **captured delivery target** and **preview keyboard receiver** as separate authorities.
- Return/Enter may create confirmation only when the preview is genuinely key and its editor is first responder; no global Return reinterpretation.
- Prototype and prove a macOS nonactivating key-panel model if the original target application must remain active underneath. The SDK defines `.nonactivatingPanel` as a panel that does not activate its owning application, but KaolaTerminal does not validate the required real WindowServer behavior.
- Replace the arbitrary closure gate with a narrow operation that owns the prepared pair, compares the epoch, and posts down/up without any callback that can reenter the gate.
- Bound the entire pre-boundary transaction; any pre-boundary failure restores the exact draft and focused preview.
- Once key-down is attempted, key-up remains mandatory and the attempt becomes terminal/submitted-unverified: no automatic retry and no ordinary Send/Return re-exposure.

Required next RED gates include a concrete production-monitor deadlock regression with a deadline and main-actor heartbeat, installed/native panel Return routing, non-key Return non-authorization, Send settlement timeout, original-target restoration, and one-shot terminal behavior.

Evidence:

- `kaola-workflow/issue-40/.cache/runtime-diagnosis-v5.md`
- `kaola-workflow/issue-40/.cache/installed-release-v4.md`
- `kaola-workflow/issue-40/architecture-blueprint-v4.md` (superseded interaction/synchronization portions)

Operational state: the rejected app is stopped. No code repair or relaunch was performed during this diagnosis.
