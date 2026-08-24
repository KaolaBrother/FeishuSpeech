# Issue #40 v2 correctness review

candidate: final complete working-tree production and test delta after the strict-lint-only `finishReviewTransition` refactor in `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40` against `60090c955fbd57d4b6e875acb8a9bdc42d61f032`, inspected 2026-08-23

claim: Issue #40 v2 must preserve one coordinator-owned draft through every typed presenter and delivery outcome, expose external output only after Send or supported Return, fence stale work, fail closed on live security changes, and retain capture and recognition independence.

surface: all current production and test changes against `60090c9`, including `ReviewWindowControllerReadinessTests.swift`, with the canonical Issue #40 v2 body and `architecture-blueprint-v2.md` as authority and the installed UAT draft-loss defect as the highest-fidelity regression target.

## Severity-ranked findings

No candidate-caused correctness or regression defect remains admitted in the final tree.

## Prior finding closure

finding: id=R1 scope=in_scope action=none status=resolved severity=medium fix_role=implementer rationale=payloadless-fail-open-readiness-path-removed

- `ReviewEditableTransitionResult` contains only `.ready` and typed `.pending` at `FeishuSpeech/Models/TranscriptionReviewState.swift:36-39`.
- `ReviewSurfacePresenting` requires `renderDraft` and async `requestEditableReadiness` with no synchronous compatibility adapter at `FeishuSpeech/Controllers/ReviewWindowController.swift:483-496`.
- Initial and retry transitions handle only `.ready` and `.pending` at `FeishuSpeech/ViewModels/MainViewModel.swift:1912-1973` and `2110-2185`; no non-ready result becomes confirmable.

finding: id=R2 scope=in_scope action=none status=resolved severity=low fix_role=implementer rationale=accepted-edit-clears-feedback-and-presentation-retry-preserves-it

- Both accepted edit paths clear authority and projected-state feedback at `FeishuSpeech/ViewModels/MainViewModel.swift:237-267` and `1991-2023`.
- Presentation-only readiness retry preserves the current authority feedback without delivery at `FeishuSpeech/ViewModels/MainViewModel.swift:2032-2054`, `2110-2116`, and `2146-2155`.
- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:405-479` proves `.deliveryUncertain` survives the presentation retry, then an accepted edit clears it while delivery, copy, AX, keyboard, and direct-output ledgers remain unchanged.

finding: id=R3 scope=in_scope action=none status=resolved severity=medium fix_role=tdd-guide rationale=production-editor-materialization-and-attachment-now-executed

- `FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift:209-286` renders the real `TranscriptionReviewView` through the production `ReviewPanel` and `NSHostingView`, retains the production editor lookup and attachment closures, reaches the real editor before a deterministic first-responder timeout, and asserts `editor.window === panel`.
- The explicit retry returns `.ready`, reuses the same panel, and retains the discard callback. The deterministic activation, application-active, key-panel, editor, attachment, first-responder, timeout, cancellation, and retry matrix remains in the same running-controller suite.
- `FeishuSpeechTests/TranscriptionReviewViewTests.swift:95-114` now uses unconditional canonical `renderReadOnly` and `renderDraft` assertions; the obsolete silent `renderEditable` branches are gone.

finding: id=R4 scope=in_scope action=none status=resolved severity=low fix_role=tdd-guide rationale=feedback-and-monitoring-authority-edges-now-have-regression-oracles

- The uncertainty edit oracle at `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:453-477` proves the current callback clears stale feedback and causes no second delivery or other output.
- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:570-612` drives post-freeze `.failed(.tapCreationFailed)` and proves the exact edited draft, same surface identity, retained authority, fixed security feedback, no dismissal, and zero delivery, copy, AX, keyboard, or direct output.
- Production monitoring handling preserves post-freeze authority through `preserveReviewDraftAfterAmbientSecurityChange` at `FeishuSpeech/ViewModels/MainViewModel.swift:2756-2774`.

## Strict-lint delta closure

- `finishReviewTransition` retains the same authority identifier, active generation, terminal-pending, transition identifier, task-cancellation, and current-draft guards before state projection at `FeishuSpeech/ViewModels/MainViewModel.swift:1816-1904`.
- The new pure `editableReviewState` helper at `FeishuSpeech/ViewModels/MainViewModel.swift:1950-1973` is an exact typed mapping: `.ready` returns `.editable`, while `.pending(failure)` returns `.editablePending(.blocked(attempt:failure:))`; both preserve text, incompleteness, and feedback.
- State assignment still occurs after readiness telemetry and before one `renderDraft` call at `FeishuSpeech/ViewModels/MainViewModel.swift:1906-1945`. The callback closures keep the same captured review ID and mutable callback revision, and transition task/ID cleanup still occurs only after rendering at lines 1946-1947.
- The extraction changes no confirmation, delivery, retry, authority-revoke, presentation, capture, recognition, or security code. R1 through R4 remain closed.

## Re-verified correctness controls

- Both legacy settings are preview-only. Production `MainViewModel` has no runtime branch on `reviewBeforeInsert` or `autoInsert`; `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:962-1022` executes all four Boolean combinations and records read-only preview with zero pre-confirmation delivery, AX, keyboard, direct-insert, and copy output.
- The sole coordinator delivery construction is inside `confirmReviewDraft` after current review ID, callback revision, editable state, current draft, content, and no-in-flight guards at `FeishuSpeech/ViewModels/MainViewModel.swift:2191-2249`. Duplicate confirmation is suppressed by the immediate confirming state and in-flight fence.
- Bare Return, keypad Enter, Command+Return, and Send route through the same confirmation callback; Shift-only Return inserts one newline, unsupported modifiers and marked text pass through, and empty content cannot confirm. The native implementation is at `FeishuSpeech/Views/TranscriptionReviewView.swift:235-385` and its 13 keyboard tests are green.
- Delivery completion rechecks review ID, confirmation attempt, and in-flight authority at `FeishuSpeech/ViewModels/MainViewModel.swift:2270-2280`. Every non-inserted outcome retains the exact frozen draft and feedback, performs presenter readiness only, and requires a later explicit confirmation for any second delivery at lines 2283-2312.
- Review ID, transition ID, callback revision, surface revision, generation, confirmation attempt, and task cancellation fences prevent late recognition, presentation, readiness, draft, confirmation, or delivery work from mutating newer authority. Focused stale-recognition, stale-presentation, duplicate-snapshot, discard, and duplicate-confirm tests remain green.
- Permission revocation, Secure Input, and hot-key monitoring failure after freeze preserve the exact authority-owned draft through `preserveReviewDraftAfterAmbientSecurityChange` at `FeishuSpeech/ViewModels/MainViewModel.swift:432-483` and `2756-2774`; they do not output or dismiss.
- Application-current-focus delivery samples live Accessibility trust before activation, at both ends of two preflight composites, and at both ends of postflight at `FeishuSpeech/Services/ReviewDestinationDelivery.swift:253-299`, `420-442`, and `493-553`. Pre-mutation loss returns `.securityRejected` with zero mutation; postflight loss returns `.deliveryUncertain` after one transaction and preserves the exact draft.
- The final trust-transition tests at `FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift:226-557` cover revoked-after-capture, coordinator draft retention, preflight transition, and postflight uncertainty. Exact tokens retain live AX trust, Secure Input, PID, focus, selection, and identity validation.
- Product call-site search found no automatic recovery-copy route, legacy output-mode route, or pre-confirmation target preparation. `ReviewDestinationDelivering` exposes only capture and deliver; dormant legacy enum/test-double helpers have no Issue #40 product call site.
- `git diff --exit-code 60090c9` is silent for `AudioRecorder.swift`, `ByteBoundedAudioIngress.swift`, `HoldPacketJournal.swift`, and `FeishuStreamingSession.swift`. Review presentation runs on separate cancellable task lanes; no UI await or presenter backpressure appears in capture, ingress, journal, provider retry/replay, or recognition-consumer loops.
- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:728-825` proves destination capture ordering, provider/capture drain independence, gated presentation independence, recorder-barrier ownership, and recognition completion without external output.

## Validation receipt

- Read-only inspection covered every changed production file and all current test deltas against `60090c9`; `git diff --check 60090c9` is green.
- Direct `xcresulttool` inspection of `/tmp/issue40-r3r4-targeted-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_16-33-52-+0800.xcresult` reports Passed: 4 tests, 0 failures, 0 skipped.
- Direct `xcresulttool` inspection of `/tmp/issue40-r3r4-full-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_16-34-05-+0800.xcresult` reports Passed: 54 tests, 0 failures, 0 skipped across controller readiness, coordinator, review view, and keyboard suites.
- Direct `xcresulttool` inspection of `/tmp/issue40-r1-trust-derived-full/Logs/Test/Test-FeishuSpeech-2026.08.23_16-25-24-+0800.xcresult` reports Passed: 57 tests, 0 failures, 0 skipped across delivery, application fallback, and coordinator suites.
- Direct `xcresulttool` inspection of the post-refactor result bundle `Test-FeishuSpeech-2026.08.23_16-48-31-+0800.xcresult` reports Passed: all 29 `ReviewFirstMainViewModelTests`, 0 failures, 0 skipped.
- A fresh `swiftlint lint --strict --config .swiftlint.yml` exits 0 with 0 violations across 35 Swift files; protected async-path comparison and `git diff --check` also exit 0.
- The final security review independently records `verdict: pass` and zero blocking findings for the live-trust, destination, exact-once, stale-fence, and privacy surfaces.

## Issue #40 v3 delta review against aec7aad

candidate: final Issue #40 v3 working-tree production, test, and documentation delta in `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40` against `aec7aad8ca29eab8cbde90b23be5dbe66ce454e2`, inspected 2026-08-23 after the feedback-copy repair and documentation landing

claim: the installed UAT defects must be closed without changing panel size: one shared transcript font of at least 18pt, no Retry Editing control or wording, Send and confirmation only in truly editable state, advisory activation request with fail-closed real readiness predicates, titlebar-safe content, accurate failure feedback, and no regression to explicit-confirmation, fixed-target security, stale fences, or independent capture and recognition topology.

surface: the two changed v3 production files, all three changed v3 test files, all seven changed v3 user/architecture/decision documents, their callers and state/output dependencies, the v3 UAT and documentation receipts, the v2 Issue contract and architecture blueprint, and the recorded focused/security/lifecycle result bundles.

### Severity-ranked findings

No candidate-caused correctness, regression, test-coverage, or documentation defect remains admitted in the final v3 tree.

### Prior V3 finding closure

finding: id=V3R2 scope=in_scope action=none status=resolved severity=low fix_role=doc-updater rationale=design-document-feedback-literals-now-match-production

- The current UI/settings contract at `docs/streaming-speech-design.md:705-708` now records `输入失败；草稿已保留，请编辑后显式发送。` and `输入状态不确定；再次发送可能造成重复输入。`, byte-for-text matching the final production feedback at `FeishuSpeech/Views/TranscriptionReviewView.swift:178-181`.
- Repository-wide current-document/source search finds neither superseded retry-oriented literal nor the removed false editor-preparation/preview-activation copy. The remaining Retry Editing mentions in documentation are explicitly historical/superseded or state that no such control is visible; product source contains no `重试编辑`, Retry Editing text, or retry-action invocation.
- The doc-updater closure receipt records green relative-link, stale-string/contract, trailing-whitespace, and diff checks for the changed documentation. Direct final-tree `git diff --check aec7aad` is also green.

finding: id=V3R1 scope=in_scope action=none status=resolved severity=low fix_role=implementer rationale=delivery-activation-feedback-now-accurately-names-target-application

- The reachable post-delivery activation case now renders `无法激活目标应用；请确认后再发送。` at `FeishuSpeech/Views/TranscriptionReviewView.swift:168-172`, accurately distinguishing captured-target activation from already-completed editor readiness and retaining the later explicit-send boundary.
- `.deliveryUncertain` now explicitly warns `再次发送可能造成重复输入` at lines 180-181. Neither fixed string contains Retry Editing text or introduces an action.
- Focused feedback tests at `FeishuSpeechTests/TranscriptionReviewViewTests.swift:123-188` assert the target-application wording, removal of the false preparation wording, the duplicate-send warning, and continued absence of `重试编辑`. Direct result inspection reports Passed: 2 tests, 0 failures for the focused repair and Passed: all 10 view tests, 0 failures.

### Final V3 acceptance closure

- Shared transcript typography is explicit and measurable: nonempty streaming/sealing text uses `TranscriptionReviewTypography.transcriptFontSize`, and the native editable `NSTextView` uses the same 18pt constant at `FeishuSpeech/Views/TranscriptionReviewView.swift:10-12`, `93-105`, and `284-297`. The focused runtime test measures both controls at at least 18pt and equal at `FeishuSpeechTests/TranscriptionReviewViewTests.swift:16-70`.
- The user-facing Retry Editing button, action call, shortcut, and wording are absent from production. `.editablePending` remains typeable but passes `canConfirm: false`; only `.editable` passes `canConfirm: true`, the Send button exists only inside that gate, and both button and native Return converge on `confirmDraft` at `FeishuSpeech/Views/TranscriptionReviewView.swift:56-75`, `117-166`, and `218-268`. The coordinator independently requires exact `.editable` plus current review ID/revision/draft and no in-flight confirmation at `FeishuSpeech/ViewModels/MainViewModel.swift:2191-2249`.
- A false activation request is advisory only at `FeishuSpeech/Controllers/ReviewWindowController.swift:243-288`. Readiness remains fail-closed on the actual active-application, key-panel, materialized-editor, same-panel attachment, and verified-first-responder predicates and produces a typed timeout when any stays unmet at lines 298-395. The ten-test production-controller matrix covers advisory false with ready and delayed predicates, false with never-active timeout, every other predicate, cancellation, same-panel retry, callback retention, and real production editor attachment at `FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift:8-349`.
- Removing `.fullSizeContentView` keeps content below the standard titlebar while the explicit outer frame remains 520 by 320 and panel identity is reused at `FeishuSpeech/Controllers/ReviewWindowController.swift:72-74`, `121-154`, and `157-174`. Production-panel tests prove no traffic-light intersection and unchanged frame size through streaming, sealing, and editable rendering at `FeishuSpeechTests/TranscriptionReviewViewTests.swift:190-275`.
- The v3 production diff changes only `ReviewWindowController.swift` and `TranscriptionReviewView.swift`; it does not alter coordinator authority, delivery, fixed destination, live Accessibility/Secure Input checks, clipboard transaction, capture, ingress, journal, provider retry/replay, audio, or recognition code. The v2 R1 through R4 closures, explicit-confirm sole output gate, stale generation/revision/readiness/confirmation fences, exact draft retention, and independent capture/recognition topology therefore remain mechanically unchanged.
- The changed README, changelog, architecture, streaming design, D-38, and D-40 surfaces consistently record 18pt typography, unchanged panel bounds, titlebar-safe content, no visible pending Retry Editing control, `.editable`-only confirmation, advisory activation with actual fail-closed predicates, independent async roots, accurate delivery feedback, and failed/open installed-UAT status.

### V3 validation receipt

- `git diff --check aec7aad8ca29eab8cbde90b23be5dbe66ce454e2` exits 0, and the changed-production file list contains only the controller and review view named above.
- Direct `xcresulttool` inspection of `Test-FeishuSpeech-2026.08.23_18-03-38-+0800.xcresult` reports Passed: 122 tests, 0 failures, 0 skipped across `TranscriptionReviewViewTests` 10, keyboard 13, readiness 10, MainViewModel 30, destination delivery 13, application fallback/live trust 16, final-output security 23, and pasteboard lifecycle 7.
- Direct inspection also confirms the repair-specific bundle `18-00-59` passed 2 of 2, the full view bundle `18-01-06` passed 10 of 10, and the coordinator activation/delivery-retention case `18-01-30` passed 1 of 1. The earlier `18-00-34` bundle is the expected RED receipt before the feedback repair, not final-tree evidence.
- The implementation receipt records strict SwiftLint with zero violations. The final documentation link/stale-string scans and direct source-to-contract comparison close V3R2.

verdict: pass
findings_blocking: 0
review_conclusion: The final Issue 40 v3 tree closes V3R1 and V3R2, preserves every earlier correctness and security closure, and now aligns source, tests, and current documentation for typography, panel geometry, readiness, explicit confirmation, fixed-target delivery, stale authority, feedback, and independent capture and recognition topology with no admitted defect.
