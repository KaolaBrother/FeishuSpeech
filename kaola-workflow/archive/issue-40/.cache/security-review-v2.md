# Issue #40 v2 security and privacy review

candidate: final working-tree production diff in `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40` against `60090c955fbd57d4b6e875acb8a9bdc42d61f032`, including the strict-lint-only `finishReviewTransition` structural split, inspected 2026-08-23

claim: Issue #40 v2 must retain one coordinator-owned draft, typed fail-closed readiness, stale-work fences, live destination security, and external output only after an explicit Send or supported Return confirmation.

surface: final production and test tree, with delta emphasis on `MainViewModel.finishReviewTransition`, `MainViewModel.editableReviewState`, the previously reviewed Accessibility-trust repair, the canonical Issue #40 v2 body, and `architecture-blueprint-v2.md`.

## Severity-ranked findings

No candidate-caused security or privacy defect was admitted. Prior security finding R1 remains closed.

## Final strict-lint delta review

- Pure typed extraction: `finishReviewTransition` retains its active-generation, authority identifier, terminal-pending, and transition-ID guards before any state change at `FeishuSpeech/ViewModels/MainViewModel.swift:1816-1828`. Speech-session cleanup, exact draft installation, authority revision, readiness-attempt increment, initial non-confirmable state, telemetry, presenter call, post-await task/authority/transition fences, final render, and transition cleanup remain in their original order at `FeishuSpeech/ViewModels/MainViewModel.swift:1830-1947`.
- State equivalence: the new synchronous `editableReviewState` helper at `FeishuSpeech/ViewModels/MainViewModel.swift:1950-1973` has no await, callback, output, logging, authority mutation, task mutation, or destination access. `.ready` alone returns `.editable` with the exact current authority-owned text, incomplete flag, and feedback. Every `.pending(failure)` returns `.editablePending(.blocked)` with the same text, incomplete flag, feedback, current readiness attempt, and typed failure. The extraction introduces no default or fail-open case.
- Explicit-confirm gate unchanged: initial pending readiness remains non-confirmable, while `confirmReviewDraft` still requires current review ID, callback revision, `.editable`, a current authority draft, and no in-flight confirmation before freezing text and creating one delivery task at `FeishuSpeech/ViewModels/MainViewModel.swift:2191-2249`.
- Stale fences and failure retention unchanged: the helper is called only after cancellation, review-ID, transition-ID, and current-draft checks at `FeishuSpeech/ViewModels/MainViewModel.swift:1899-1916`. Delivery completion still requires exact review ID, confirmation attempt, and in-flight authority, then restores the exact frozen text for every failure, uncertainty, security rejection, or cancellation without retry, retarget, or copy at `FeishuSpeech/ViewModels/MainViewModel.swift:2270-2315`.
- Topology unchanged: the extraction is confined to readiness-state construction. Capture drain and recognition consumer remain separate task roots at `FeishuSpeech/ViewModels/MainViewModel.swift:718-723`; the protected audio, ingress, journal, streaming session, API, provider, transport, retry, and replay paths remain byte-identical to baseline.

## R1 closure remains intact

- The strict-lint refactor did not touch the two R1 production files. Their current Git blob identities remain `7d03f3771a85165b72c5c2ef453357be1faaa413` for `AccessibilityClient.swift` and `4db749feb5c7d67fe1f18457dc39a1d80a65006c` for `ReviewDestinationDelivery.swift`, matching the previously reviewed repaired blobs.
- `AccessibilityTrustProviding` remains live at `FeishuSpeech/Services/AccessibilityClient.swift:77-97,383-388`. Application-current-focus delivery still checks trust before activation at `FeishuSpeech/Services/ReviewDestinationDelivery.swift:420-442`, at the start and end of both consecutive preflight composites, and at both boundaries of postflight at `FeishuSpeech/Services/ReviewDestinationDelivery.swift:493-553`.
- Trust loss before a knowable mutation returns `.securityRejected` before pasteboard or keyboard effects. Trust loss observed after the single post maps to `.deliveryUncertain`; the coordinator preserves the exact draft and cannot issue a second delivery without a later explicit confirmation.

## Re-verified security controls

- Zero output before confirmation and no compatibility recovery: read-only preview, sealing, editable readiness, draft edits, permission/Secure Input preservation, readiness failure, discard, reset, sleep, and cleanup do not call AX text setters, pasteboard writes, direct insertion, or keyboard posting. `ReviewDestinationDelivering` exposes capture and deliver only; no automatic recovery-copy call site exists in the accepted route, and legacy settings cannot select direct output.
- Fixed authority: destination capture requires complete original application identity and revalidates it before returning authority at `FeishuSpeech/Services/ReviewDestinationDelivery.swift:301-345`. Delivery activates that identity once and sends only to the captured PID at `FeishuSpeech/Services/ReviewDestinationDelivery.swift:347-400`; no ambient PID becomes the target.
- Exact and fallback security: exact AX restore/postflight retain live trust, Secure Input, PID, role/security state, selection, and focus checks. Fallback retains two ordered trust/Secure Input/PID/complete-identity preflight composites, a fixed captured PID transaction, and one equivalent postflight. Unsafe text is rejected before activation and repeated before pasteboard mutation.
- Post-freeze security changes: permission loss or Secure Input preserves the exact authority-owned draft with fixed `.securityRejected` feedback and zero automatic output at `FeishuSpeech/ViewModels/MainViewModel.swift:385-483`. A later explicit confirmation independently rechecks live trust and Secure Input.
- Readiness and callbacks: typed readiness has no compatibility or default adapter. Draft callbacks require current surface revision, and presentation/readiness/delivery completions retain exact task, review, transition, and attempt checks. The extracted helper cannot weaken these fences because it receives only already-fenced value data and returns only a state value.
- Privacy and AppKit input: readiness telemetry remains limited to fixed event/result/predicate values, generation/attempt ordinals, and elapsed milliseconds; it contains no transcript, draft length/hash, target, clipboard, PID, application identity, credential, token, audio, or stream data. Return handling still keeps Shift-only, Option, Control, and marked-text input in the editor; only supported explicit confirmation reaches the coordinator gate.
- OWASP and high-risk pattern walk: the lint delta adds no dependency, network endpoint, authentication, deserialization, filesystem operation, shell/SQL construction, raw markup, URL fetch, credential comparison, secret literal, sensitive logging, AppKit selector construction, or new output call.

## Validation receipt

- Direct `xcresulttool` inspection of `/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-48-31-+0800.xcresult` reports Passed: 29 `ReviewFirstMainViewModelTests`, 0 failures, 0 skipped. The passing cases include explicit-confirm-only delivery, pending-readiness retention, cancellation/failure retention, duplicate confirmation suppression, stale presentation rejection, permission/Secure Input retention, exact draft freezing, and independent capture/recognition progress.
- `swiftlint lint --strict --config .swiftlint.yml` was rerun read-only on the final tree: exit 0, 0 violations, 0 serious, 35 Swift files. `git diff --check` passed.
- The prior R1 deterministic bundles remain valid because both R1 production blobs are unchanged: targeted trust-transition 4/4 passed, and affected destination/fallback/coordinator 57/57 passed, with no failures or skips.
- `git diff --exit-code 60090c955fbd57d4b6e875acb8a9bdc42d61f032` remained silent for all protected capture, recognition, audio, provider, transport, retry, and replay paths named by the workflow.

## Issue #40 v3 final delta review against aec7aad

candidate: final uncommitted v3 production, test, and documentation delta in `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40` against `aec7aad8ca29eab8cbde90b23be5dbe66ce454e2`, inspected 2026-08-23

claim: activation-request rejection is advisory only, but Send and supported Return confirmation remain unavailable until live application-active, panel-key, editor-materialized, editor-attached, and first-responder predicates all pass; removing Retry Editing must not add automatic delivery, retry, retarget, or copy; uncertainty and activation feedback must remain fixed and privacy-safe.

surface: final `ReviewWindowController.swift` and `TranscriptionReviewView.swift` production delta, three changed v3 test files, seven documentation files, installed-UAT correction, canonical Issue #40 v2 contract, and `architecture-blueprint-v2.md`; unchanged authority, destination-delivery, trust, exact-once, and protected async roots were identity-checked against `aec7aad`.

## V3 final severity-ranked findings

No candidate-caused security or privacy defect was admitted. Prior R2 is closed by the final feedback repair and focused regression coverage.

## R2 closure

- `.deliveryUncertain` now renders the fixed warning `输入状态不确定；再次发送可能造成重复输入。` at `FeishuSpeech/Views/TranscriptionReviewView.swift:180-181`. It explicitly tells the user that a later Send or Return may duplicate text after a possible post, satisfying the blueprint's human-decision and duplication-warning contract without adding automatic action.
- `test_deliveryUncertainFeedbackWarnsAboutPossibleDuplicateSendWithoutRetryEditing` at `FeishuSpeechTests/TranscriptionReviewViewTests.swift:124-153` checks the explicit resend and duplicate-risk wording and confirms that no Retry Editing button returns.
- `.activationFailed` is the fixed, transcript-free `无法激活目标应用；请确认后再发送。` at `FeishuSpeech/Views/TranscriptionReviewView.swift:170-171`. It contains no target name, PID, identity, transcript, length/hash, clipboard, credential, token, audio, or stream data. Its focused fixed-feedback test is at `FeishuSpeechTests/TranscriptionReviewViewTests.swift:156-187`.
- No production source contains `重试编辑`; the final view exposes Send only for `canConfirm == true` and retains no retry-editing control, shortcut, or automatic action.

## V3 final controls verified intact

- Advisory activation is not authorization: `requestEditableReadiness` records a fixed advisory result when `requestActivation()` is false and continues only into the real predicate loop at `FeishuSpeech/Controllers/ReviewWindowController.swift:243-289`. `.ready` is returned only after live application-active, panel-key, real editor lookup, editor attachment to the retained panel, successful first-responder assignment, and first-responder identity all pass at `FeishuSpeech/Controllers/ReviewWindowController.swift:298-395`. A false activation request with an inactive application returns typed `.applicationActive`, never ready.
- Pending/typeable cannot confirm: `.editablePending` renders an editable draft with `canConfirm: false` at `FeishuSpeech/Views/TranscriptionReviewView.swift:64-75,144-157`; `editableContent` withholds the confirmation callback, the Send button exists only when `canConfirm` is true, and native Return reaches `guard canConfirm` before any coordinator callback at `FeishuSpeech/Views/TranscriptionReviewView.swift:117-133,249-268,367-390`. Pending input can edit the retained draft but cannot authorize Send, bare Return, keypad Enter, or Command+Return.
- The two changed production files contain no call to delivery, AX text mutation, keyboard posting, pasteboard write, compatibility route, recovery copy, retarget, or automatic readiness action. Failed readiness stays typed, non-confirmable, same-panel, and discardable with zero output.
- The v3 production delta remains limited to `ReviewWindowController.swift` and `TranscriptionReviewView.swift`. Git object comparison against `aec7aad` proves `AccessibilityClient.swift` (`7d03f3771a85165b72c5c2ef453357be1faaa413`), `ReviewDestinationDelivery.swift` (`4db749feb5c7d67fe1f18457dc39a1d80a65006c`), `TextInputSimulator.swift`, `MainViewModel.swift`, `TranscriptionReviewState.swift`, settings, hot-key, audio, ingress, journal, and streaming-session production files are unchanged.
- Consequently prior R1 remains closed: live Accessibility trust, exact AX and application-current-focus identity, fixed captured PID, Secure Input, consecutive preflight composites, postflight classification, unsafe-text rejection before mutation, exact-once transaction, stale review/transition/attempt fences, exact failure retention, no automatic delivery retry/retarget/copy, settings migration, and independent capture/recognition roots are unchanged by v3.
- Readiness telemetry remains fixed event/result/predicate/attempt/elapsed fields only at `FeishuSpeech/Controllers/ReviewWindowController.swift:397-411`. Panel title remains the fixed `输入前预览` at line 142. Font, titlebar, and feedback changes add no sensitive telemetry or metadata.
- AppKit and input review found no selector construction, user-derived command execution, raw markup, pasteboard output, ambient application selection, or new cross-application mutation in the changed files. The transcript appears only in its intended review body/editor and is absent from title, fixed feedback, logs, and added accessibility/help metadata.
- The final documentation delta explicitly preserves fail-closed actual readiness predicates, pending non-confirmability, fixed-PID and exact-target boundaries, no automatic copy/delivery retry/retarget, privacy-safe telemetry, and independent capture/recognition roots. It introduces no credential, token, transcript, target, clipboard, or application-identity evidence.

## V3 final validation receipt

- A fresh serialized final-tree run selected all `TranscriptionReviewViewTests`, all `ReviewWindowControllerReadinessTests`, and the real-production-surface coordinator test. `/tmp/issue40-v3-security-final-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_18-03-43-+0800.xcresult` records 21/21 passed, 0 failed, 0 skipped. This includes both repaired feedback tests, removal of Retry Editing, actual readiness predicate failures, same-panel retention, real editor attachment, zero output before explicit confirmation, and one delivery afterward.
- Existing final-tree security receipts remain green: keyboard 13/13, coordinator 30/30, application fallback 16/16, destination delivery 13/13, pasteboard lifecycle 7/7, and final text-output security 23/23, all with zero failures.
- `git diff --check` passed. A production search found no Retry Editing text and no output/pasteboard/compatibility call in either changed production file.

verdict: pass
findings_blocking: 0
review_conclusion: The final v3 candidate closes R2 with an explicit duplicate-output warning and preserves fail-closed readiness, explicit-confirm-only delivery, application-bound trust and identity controls, privacy-safe feedback and telemetry, stale fences, failure retention, and independent capture and recognition topology.
