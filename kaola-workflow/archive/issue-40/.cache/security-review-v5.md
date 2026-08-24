# Issue #40 v5 Security Review

- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
- Baseline: `b321ac5d6c04c91ced9afeb2240f9566d9b8d305`
- Scope: final uncommitted v5 production and tests against the owner contract and `architecture-blueprint-v5.md`
- Security-sensitive production diff SHA-256: `7b840f8240b62d2ed3c9895cb35f1ed656cc1da4486e12c228d28c43aa4edea5`
- Concurrency note: another workflow role was still changing tests during this review, so the binding fingerprint intentionally covers the inspected production files named in the findings rather than a moving whole-worktree diff.
- Blueprint SHA-256: `15f6dacc27306c9df978a5f73d5c36453fc7358354d137ff004704049781ef24`
- Review method: read-only adversarial trace of capture, confirmation, admission, raw AX validation, epoch gate, Unicode down/up, terminal cleanup, production construction, and relevant tests. Because blocking defects were admitted, no additional expensive test run was used as a clean-result gate; the implementation receipt's prior build/test results were treated only as corroboration.

## Findings

### R1 - Exact-cursor authority is declared without capturing or validating the original selection

Failure class: broken authorization and target binding.

Precondition and trigger:

1. Fn capture starts while application A, editable field X, and caret/range X1 are current.
2. AX reports that `AXSelectedTextRange` is settable.
3. Before the user confirms Send/Return, focus or the caret moves to field Y or range Y1 in the same application, either by the user or application code.
4. The user confirms the frozen draft.

Expected behavior: an `exactCursor` descriptor must be backed by the captured AX element plus a decoded, bounds-checked original `CursorTextRange`. Post-confirmation validation may restore only that captured element/range, read it back exactly, and otherwise fail before key-down. Ordinary non-secure AX capability misses must instead produce an application-bound descriptor containing no selection authority.

Observed behavior and evidence:

- `ReviewSubmissionRawTargetState` stores only the descriptor, application element, and optional focused element; there is no captured `CursorTextRange` or binding-specific evidence (`FeishuSpeech/Services/AccessibilityClient.swift:12-28`).
- Capture labels a target `exactCursor` solely because `AXSelectedTextRange` is settable (`FeishuSpeech/Services/AccessibilityClient.swift:619-627`). It never copies or decodes the selected range before returning the descriptor and raw state (`FeishuSpeech/Services/AccessibilityClient.swift:629-640`).
- Final AX validation creates a fresh system-wide focused element and accepts any safe editable element in the same PID (`FeishuSpeech/Services/AccessibilityClient.swift:661-677`). It does not branch on `target.descriptor.binding`, compare the fresh element to `target.focusedElement`, restore the captured element, set the original range, or read it back.
- The executor then ignores the binding and always prepares the pair for the captured application's PID/current responder (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:711-726`). Thus field Y receives the text even though the public descriptor claims field X/range X1 is exact.
- Capture also rejects an absent focused element as `accessibilityTimeout` (`FeishuSpeech/Services/AccessibilityClient.swift:597-605`) and rejects incomplete role/subrole evidence as `securityRejected` (`FeishuSpeech/Services/AccessibilityClient.swift:613-617`, helper collapse at `FeishuSpeech/Services/AccessibilityClient.swift:726-745`). This contradicts the existing ordinary non-secure AX-miss contract, whose explicit cases are no focused element, incomplete AX role, unavailable selection, and unverifiable selection (`FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift:48-97`). The coordinator converts every v5 capture failure into visible startup termination with `无法确认输入位置` (`FeishuSpeech/ViewModels/MainViewModel.swift:768-789`).
- The v5 raw-runtime tests do not exercise this production AX implementation. Their fake always manufactures `applicationBoundCurrentFocus` and never captures a selection (`FeishuSpeechTests/FinalTextOutputSecurityTests.swift:2291-2343`); there is no test reference to `SystemReviewSubmissionAXRuntime`.

Exploitability and blast radius: no code injection is required. Moving focus/caret inside the already captured application between Fn capture and confirmation is enough to send the user's transcript to a different editor, chat, document, or recipient context. This can disclose the complete confirmed transcript and defeats the exact-cursor authorization boundary. On ordinary AX misses, the same root cause also denies the required application-bound fallback and reproduces the visible `无法确认输入位置` failure.

Required action and owner: security/output implementation owner must make raw state binding-specific. Exact capture must retain the captured element and a decoded original range; final pre-boundary validation must restore and read back that exact range on that exact element. Application-bound capture must carry no element/range authority and must be selected only for typed ordinary non-secure capability misses. Secure input, trust loss, deadline, target identity, or frontmost drift must fail closed. Add tests against the concrete system AX runtime for all four ordinary misses and for exact element/range drift with zero post.

finding: id=R1 scope=in_scope action=fix status=open severity=high fix_role=security rationale=exact_cursor_descriptor_has_no_captured_range_and_can_send_to_a_different_same_process_editor

### R2 - The accepted v5 facade never installs lifecycle observation, leaving a validation-to-key-down activation race

Failure class: missing fail-closed lifecycle authorization.

Precondition and trigger:

1. The captured target application passes the raw identity/frontmost validation.
2. Before the commit gate calls Unicode key-down, another application becomes frontmost programmatically, or the captured process terminates/relaunches, without a physical input event.
3. The target change occurs after the one synchronous AX sample and before key-down.

Expected behavior: before taking the combined-epoch baseline, the accepted v5 attempt must fail closed unless activation, frontmost, termination, process-generation, and observer-loss signals are synchronously wired into the same combined epoch. Any delivered lifecycle signal before down must reject the gate. Modifier stabilization must also finish before that baseline.

Observed behavior and evidence:

- The only concrete activation observer advances `CurrentFocusCombinedInterferenceEpoch` from `NSWorkspace.didActivateApplicationNotification` (`FeishuSpeech/Services/CurrentFocusAppendSession.swift:972-1027`).
- `SystemReviewSubmissionFacade` owns only the control plane, executor, ticket issuer, and event relay, and its initializer creates no lifecycle monitor (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:904-939`). The facade protocol exposes no monitor-arm or lifecycle-signal API (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:825-850`).
- The default coordinator selects this facade and explicitly leaves legacy review delivery nil (`FeishuSpeech/ViewModels/MainViewModel.swift:368-377`). The only production constructors of `WorkspaceCurrentFocusActivationMonitor` remain legacy provisional/delivery factories, so they are not live on the accepted v5 path (`FeishuSpeech/Services/CurrentFocusAppendSession.swift:771-785`, `FeishuSpeech/Services/ReviewDestinationDelivery.swift:487-527`).
- The implementation receipt independently acknowledges this missing wiring: the new facade does not instantiate the activation monitor and leaves ownership as a coordinator item (`kaola-workflow/issue-40/.cache/implementation-v5-output.md:165-169`).
- Raw validation samples identity/frontmost once (`FeishuSpeech/Services/AccessibilityClient.swift:644-677`), while claim captures the expected global epoch before that validation (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:260-279`, `FeishuSpeech/Services/ReviewSubmissionExecutor.swift:645-672`). Pair preparation and the final gate perform no further application/frontmost sample (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:711-803`). With no lifecycle observer, the epoch therefore remains unchanged when programmatic activation occurs in this interval.
- The v5 production path also has no `CGEventSource.flagsState` call or modifier stabilization despite defining `.modifierInstability`; existing modifier tests exercise the legacy exact/application delivery, not `SystemReviewSubmissionFacade` or `ReviewSubmissionExecutor`.

Exploitability and blast radius: a target or another local application can programmatically activate during the post-validation window. The gate still posts to the old fixed PID, so output occurs after the user's visible target context changed. Target termination plus PID reuse widens this to another process identity if the lifecycle loss is not observed. Existing physical-event-tap coverage does not close a programmatic activation/termination path because no physical event is required.

Required action and owner: security/output plus coordinator owner must make the accepted facade own and fail-closed arm the activation/frontmost, target termination/process-generation, and observer-loss sources for the entire target/attempt authority lifetime, feeding the shared epoch synchronously. Capture the baseline only after those observers and modifier stabilization are live. Add concrete facade integration tests that change frontmost application and terminate/relaunch the target after raw validation but before the gate, asserting zero down/up; also test observer installation/loss failure.

finding: id=R2 scope=in_scope action=fix status=open severity=high fix_role=security rationale=accepted_v5_path_has_no_lifecycle_observer_so_programmatic_target_drift_can_precede_key_down_without_epoch_drift

## Remaining claim audit

- Pre-confirmation side effects: no candidate path from Fn, streaming, recognition, sealing, preview, or edit callbacks reaches `ReviewUnicodeCommitter`; production construction selects the v5 facade and does not select legacy delivery (`FeishuSpeech/ViewModels/MainViewModel.swift:368-385`). No accepted-path pasteboard, Cmd+V, target activation, retargeting, AX setter, or global Return monitor was found. The panel Return arbiter is panel-local, rejects repeats/modifiers/marked text, and consumes only an event delivered to the exact key panel (`FeishuSpeech/Controllers/ReviewWindowController.swift:11-35`, `FeishuSpeech/Controllers/ReviewWindowController.swift:545-567`).
- Confirmation provenance: current production call sites are the visible Send action and qualified panel Return (`FeishuSpeech/Views/TranscriptionReviewView.swift:278-295`, `FeishuSpeech/Controllers/ReviewWindowController.swift:545-567`). Attempt handles have a private nonce/ID and a fileprivate initializer, and admission checks the nonce, positive ID, active record, immutable request, and deadline (`FeishuSpeech/Models/CursorTextModels.swift:127-169`, `FeishuSpeech/Services/ReviewSubmissionExecutor.swift:119-165`). No current production bypass was found, although the intent factory remains module-internal rather than type-level unforgeable (`FeishuSpeech/Views/TranscriptionReviewView.swift:14-32`).
- Payload and event provenance: the committer rejects more than 16,384 UTF-16 code units, materializes `Array(frozenDraft.utf16)`, constructs one down/up pair from one private source, sets empty flags plus exact tag and own source PID on both, and reads back payload/flags/tag/source PID before returning the pair (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:393-477`, `FeishuSpeech/Services/ReviewSubmissionExecutor.swift:489-537`). This preserves surrogate/non-BMP code units without scalar reconstruction.
- Commit/cancellation and terminal behavior: cancellation and gate admission linearize through the attempt lock, the first down call is followed synchronously by exactly one mandatory up while the lock is held, and post-boundary receipts remain `submittedUnverified` rather than claiming target consumption (`FeishuSpeech/Services/ReviewSubmissionExecutor.swift:185-244`, `FeishuSpeech/Services/ReviewSubmissionExecutor.swift:729-803`). Matching terminal handling removes ordinary Send/Return authority and never retries (`FeishuSpeech/ViewModels/MainViewModel.swift:2290-2332`).
- Event-tap provenance: interfering events advance the combined epoch unless both the exact synthetic tag and own source PID identify them; tap-disabled timeout/user-input always advances (`FeishuSpeech/Services/CurrentFocusAppendSession.swift:204-237`). This covers physical signals delivered to the existing Fn event tap, but does not repair R2's absent lifecycle source.
- Recording/recognition topology: startup still creates independent capture-drain and consumer tasks and renders the read-only streaming preview (`FeishuSpeech/ViewModels/MainViewModel.swift:700-722`). No candidate output call was introduced on those asynchronous lines.
- Residual delayed image-paste cause: the accepted v5 delivery path contains no pasteboard snapshot/read/write/restore and no Cmd+V or retry/retarget loop. Structurally, the prior clipboard-delayed-image mechanism is absent from the accepted output path. R1 and R2 still prevent a security PASS because the remaining Unicode output can target an unauthorized editor/context.

## Verdict

Two candidate-caused high-severity authorization defects remain. Passing unit tests do not cover the concrete system AX runtime or a lifecycle signal through the accepted facade, so they do not falsify either reproduction path.

verdict: fail
findings_blocking: 2
review_conclusion: The v5 implementation removes clipboard based output residue but still lacks exact cursor evidence and live lifecycle fencing before confirmed Unicode submission.
