# Issue #40 v5 Security Review R2

- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
- Baseline: `b321ac5d6c04c91ced9afeb2240f9566d9b8d305`
- Scope: current repaired uncommitted v5 production and tests against the owner contract and `architecture-blueprint-v5.md`
- Security-sensitive production diff SHA-256: `418062a75ae09272cda2230c245420d10f60da4148bfac88d2cb275fdfb6a7af`
- Blueprint SHA-256: `15f6dacc27306c9df978a5f73d5c36453fc7358354d137ff004704049781ef24`
- Supplied test receipt: `/tmp/issue40-focused-v5-r6.log`, 306 tests executed with zero failures. This review did not treat source-text assertions or that receipt as proof of runtime lifecycle/AX behavior. Because blocking defects were admitted by code trace, no additional expensive test run was used as a clean-result gate.

## Findings

### R1 - A stale capture completion can disarm the lifecycle observer for a newer live target

Failure class: broken authorization lifetime and target-lifecycle fencing.

Concrete precondition and reproduction path:

1. Session A starts and `captureTarget(A)` arms the facade's single lifecycle observer, while raw AX capture A remains blocked on the executor.
2. Session A aborts before its capture callback reaches MainActor. There is no capture cancellation or lifecycle lease tied to A.
3. A new session B is allowed because no review authority was created for A; `captureTarget(B)` overwrites the observer's target identity with B and queues raw capture B.
4. Raw capture A then completes. If it fails, the facade's older completion unconditionally calls `disarm()`. If it succeeds, MainViewModel rejects the stale generation and calls `releaseCapturedTarget(A)`, which also unconditionally calls `disarm()`.
5. Raw capture B succeeds afterward. Success does not re-arm the observer because B was armed before its raw capture was queued. B now owns a valid descriptor and submission authority while the lifecycle observer has no target identity.
6. Another application activates programmatically, or B terminates/relaunches, after the final synchronous AX sample but before Unicode down. No physical event is required. With the observer disarmed, the combined epoch does not advance, so the final gate can still post to B's fixed PID.

Expected behavior: observer authority must be a nonce/target-keyed lease. Only failure or release carrying the exact current lease/target ID may disarm it; a stale capture, stale release, or stale completion must be isolated from a newer target. No capture may succeed unless its matching lifecycle lease is still live.

Observed behavior and primary evidence:

- `SystemReviewSubmissionLifecycleObserver` holds only one mutable `targetIdentity`; `arm(for:)` overwrites it and `disarm()` clears it without a lease or target comparison (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:1007-1035`).
- `SystemReviewSubmissionFacade.captureTarget` arms before asynchronous raw capture, then any failure completion calls the same unkeyed `disarm()` (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:1297-1316`).
- `releaseCapturedTarget` accepts a target ID for executor cleanup but unconditionally disarms the singleton observer regardless of whether that ID is current (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:1342-1345`).
- The coordinator has an explicit stale-success path: if session identity/authority no longer matches, it releases the stale descriptor (`FeishuSpeech/ViewModels/MainViewModel.swift:768-778`). A new session is permitted when the prior pending capture never created `reviewSurfaceAuthority` (`FeishuSpeech/ViewModels/MainViewModel.swift:631-643`), and beginning it resets only coordinator capture fields before arming the next capture (`FeishuSpeech/ViewModels/MainViewModel.swift:664-693`).
- Once B succeeds, the facade never verifies lifecycle ownership again in `issueAttemptHandle`, admission, start, or release. The executor relies on epoch drift around its two AX validations and final gate (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:725-817`, `FeishuSpeech/Services/ReviewSubmissionExecutor.swift:895-973`).
- The focused suite has only a source-text lifecycle composition oracle (`FeishuSpeechTests/FinalTextOutputSecurityTests.swift:107-121`). No test overlaps two facade captures or proves that stale failure/release cannot disarm the newer target.

Exploitability and blast radius: this needs no code injection. A slow AX target capture plus ordinary abort/restart timing is enough to remove all activation, termination, and process-generation signals for the next transcript. A programmatic application activation can then change the user's visible destination without physical input while the confirmed transcript is still posted. The blast radius is the entire confirmed draft and any unintended editor/recipient context reached by the stale fixed-PID submission.

Required action and owner: security/output plus coordinator owner must introduce an opaque capture/lifecycle lease nonce. `arm` must return a lease, capture state/descriptor must bind it, and failure/release must be matching-only operations. A stale ID must never disarm the current observer. Before admission/start, the facade must prove that the target ID still owns the live lease; observer loss must fail closed. Add a behavioral test with blocked capture A, armed capture B, late A failure and late A success/release, then a B activation/termination signal before the gate, asserting epoch drift and zero posts.

finding: id=R1 scope=in_scope action=fix status=open severity=high fix_role=security rationale=stale_capture_failure_or_release_can_disarm_the_newer_targets_lifecycle_fence_and_allow_post_after_programmatic_target_drift

### R2 - Two required ordinary AX-miss fallback classes are admitted at capture but rejected at submission

Failure class: fail-closed availability regression in the application-root fallback contract.

Concrete precondition and input: the original frontmost application has Secure Input disabled, Accessibility trust available, and stable full process identity, but AX either exposes no focused element or exposes a current responder whose role/subrole attribute is unavailable. The same ordinary capability miss remains present when the user explicitly confirms the draft.

Expected behavior: these owner-approved ordinary non-secure misses bind only the captured application root and later address that captured PID's current responder while stable identity, frontmost status, Secure Input, trust, modifiers, and interference proofs remain valid. The fallback deliberately carries no exact element/selection authority.

Observed behavior and evidence:

- Capture correctly maps an unavailable focused element to `applicationBoundState` (`FeishuSpeech/Services/AccessibilityClient.swift:638-657`).
- Capture also maps unavailable role or subrole to `.ordinaryCapabilityMiss` and then to `applicationBoundState` (`FeishuSpeech/Services/AccessibilityClient.swift:695-715`, `FeishuSpeech/Services/AccessibilityClient.swift:993-1032`).
- At confirmation, the application-bound validator asks the captured application root for its current focused element, but the same unavailable focused-element result returns `.accessibilityTimeout` (`FeishuSpeech/Services/AccessibilityClient.swift:804-823`).
- If the focused element exists but retains the same unavailable role/subrole, `validateFocusedState` maps `.ordinaryCapabilityMiss` to `.accessibilityFailure` (`FeishuSpeech/Services/AccessibilityClient.swift:784-801`). Thus the fallback that capture intentionally admitted cannot submit in two of the four documented ordinary-miss cases.
- The existing four-case contract explicitly includes no focused element and incomplete AX role (`FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift:48-97`), but that test exercises legacy `SystemReviewDestinationDelivery`, not `SystemReviewSubmissionAXRuntime`. The v5 tests that mention the concrete AX path are source-text assertions rather than behavioral runtime tests (`FeishuSpeechTests/FinalTextOutputSecurityTests.swift:15-160`).

Exploitability and blast radius: this is fail-closed rather than a confidentiality escalation, but it makes confirmed output unavailable for ordinary AX-limited applications and preserves the user's original `无法确认输入位置`/delivery-failure class of experience. It affects every transcript in those target applications.

Required action and owner: the output implementer must define a typed application-root validation result that preserves ordinary capability misses instead of reclassifying them as timeout/failure. Continue to fail closed for Secure Input, lost trust, wrong PID/full identity/frontmost drift, malformed/wrong-type AX values, deadline, and unverifiable security. Add behavioral tests for all four ordinary misses through capture, confirmation, and one fixed-PID pair, plus secure/unverifiable negative controls.

finding: id=R2 scope=in_scope action=fix status=open severity=medium fix_role=implementer rationale=application_root_fallback_is_admitted_but_cannot_submit_when_no_focus_or_incomplete_role_remains

## Adversarial claim audit

- Exact target capture and restoration: repaired. Raw exact state now retains the captured AX element and original `CursorTextRange`; selection bounds are checked, exact focus and range are restored only after a claimed confirmation attempt, and both are read back before preparation can reach the gate (`FeishuSpeech/Services/AccessibilityClient.swift:15-31`, `FeishuSpeech/Services/AccessibilityClient.swift:716-780`, `FeishuSpeech/Services/AccessibilityClient.swift:826-859`). Application-bound state contains neither element nor selection authority (`FeishuSpeech/Services/AccessibilityClient.swift:861-875`). R2 is the remaining fallback availability defect.
- Secure/unverifiable classification: explicit Secure Input or lost Accessibility trust rejects at capture and both submission validations; secure subrole and malformed/wrong-type role, subrole, selection, or focused-element values fail closed (`FeishuSpeech/Services/AccessibilityClient.swift:611-663`, `FeishuSpeech/Services/AccessibilityClient.swift:666-692`, `FeishuSpeech/Services/AccessibilityClient.swift:741-781`, `FeishuSpeech/Services/AccessibilityClient.swift:891-960`, `FeishuSpeech/Services/AccessibilityClient.swift:993-1047`).
- Lifecycle and target binding: the accepted facade now normally installs activation, termination, launch-generation, local input, and global input observation before target capture and retains it until release (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:996-1152`, `FeishuSpeech/Services/ReviewSubmissionExecutor.swift:1233-1345`). Callbacks advance only the shared epoch and dual tag plus own-PID events are exempt. R1 breaks that proof only through unkeyed stale disarm.
- Modifiers and physical ordering: the executor requires two empty combined-session samples for Command, Shift, Control, Option, Fn, and Caps Lock, repeats a final sample after the second AX validation, and samples again before every epoch-reservation attempt (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:11-20`, `FeishuSpeech/Services/ReviewSubmissionExecutor.swift:670-717`, `FeishuSpeech/Services/ReviewSubmissionExecutor.swift:759-817`, `FeishuSpeech/Services/ReviewSubmissionExecutor.swift:895-919`). Physical event-tap input and tap-disabled events synchronously announce combined-epoch drift unless both exact tag and own PID match (`FeishuSpeech/Services/CurrentFocusAppendSession.swift:204-237`, `FeishuSpeech/Services/TextInputSimulator.swift:597-606`). Pending observer work is announced before bounded reservation waiting and is included in pre-gate/postflight stability (`FeishuSpeech/Services/CurrentFocusAppendSession.swift:261-372`).
- Cancellation and irreversible boundary: cancellation and commit compare the exact handle under the same control lock. `beginTerminalizing` gives an already-latched cancellation precedence over another pre-boundary failure. The down call is the sole irreversible boundary and is followed synchronously by exactly one mandatory up while both reservations are held; after boundary, cancellation remains advisory and the receipt stays `submittedUnverified` (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:194-253`, `FeishuSpeech/Services/ReviewSubmissionExecutor.swift:320-377`, `FeishuSpeech/Services/ReviewSubmissionExecutor.swift:895-985`).
- Event provenance and payload: production creates one private-source down/up pair, sets empty flags, exact UTF-16 payload, exact tag, and own source PID on both, then reads all fields back. The 16,384 UTF-16 cap is enforced before construction and surrogate/non-BMP code units are preserved as exact UTF-16 (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:418-502`, `FeishuSpeech/Services/ReviewSubmissionExecutor.swift:504-562`). Both posts use the same immutable captured PID.
- Intent, handle, and envelope authority: `ReviewConfirmationIntent` construction is now `fileprivate` to the controller and only the visible Send handler and qualified panel Return arbiter mint it (`FeishuSpeech/Controllers/ReviewWindowController.swift:11-64`, `FeishuSpeech/Controllers/ReviewWindowController.swift:327-383`, `FeishuSpeech/Controllers/ReviewWindowController.swift:641-664`). Handles retain a private nonce/ID and fileprivate initializer, while admission validates nonce, positive ID, request, deadline, and one-active record (`FeishuSpeech/Models/CursorTextModels.swift:127-200`, `FeishuSpeech/Services/ReviewSubmissionExecutor.swift:128-174`). No current production forge/bypass path was found.
- No forbidden output route: the accepted v5 coordinator selects `SystemReviewSubmissionFacade` and leaves legacy delivery nil (`FeishuSpeech/ViewModels/MainViewModel.swift:368-377`). No pasteboard access, Cmd+V, application activation call, retarget lookup, default Send shortcut, or global confirmation callback occurs in the accepted path. The lifecycle global key monitor only advances interference and cannot confirm or consume Return (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:1067-1132`). The preview arbiter handles only an exact event delivered to the retained key panel and rejects repeats, modifiers, and marked text (`FeishuSpeech/Controllers/ReviewWindowController.swift:38-85`).
- Terminal no-resend and no transcript surface: a submitted-unverified receipt releases the target, clears all draft/authority/request/handle projections, sets `.idle`, dismisses the panel, and resets the hot-key axis (`FeishuSpeech/ViewModels/MainViewModel.swift:2338-2375`). No terminal transcript is logged by the reviewed path. Pre-boundary failure retains the exact draft and requires a new real gesture; post-boundary completion never re-exposes Send.
- Recording/recognition topology and residual paste cause: the capture-drain and recognition consumer remain separate asynchronous tasks, and streaming/sealing/edit callbacks have no route to the committer. The accepted v5 path contains no clipboard snapshot/read/write/restore, Cmd+V, delayed retry, retarget, or image-paste mechanism. The prior delayed clipboard-image root cause is structurally absent.

## Verdict

The prior exact-cursor evidence and ordinary lifecycle-installation defects are materially repaired, but lifecycle ownership is not stale-safe and therefore the accepted target can lose activation/termination fencing before confirmed output. The focused green receipt does not exercise this overlap. The application-root fallback also remains unavailable for two required ordinary AX-miss classes.

verdict: fail
findings_blocking: 2
review_conclusion: Current v5 still permits a stale capture to remove the newer target lifecycle fence and does not complete two required application-root fallback paths.
