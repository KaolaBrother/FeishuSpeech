# Issue #40 v4 Correctness Review

- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
- Baseline: `4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a`
- Scope: final uncommitted v4 production and tests

## Verdict

FAIL. The review admits one high-severity correctness defect and two medium-severity test-coverage defects. The zero-preconfirmation-output route, pasteboard removal, explicit UI intent, recorder barrier, and draft-retention direction are present, but the current submission gate can still post after a modifier transition and the GREEN matrix omits material asynchronous and post-boundary behavior.

finding: id=R1 scope=in_scope action=fix status=open severity=high fix_role=implementer rationale=modifier-transition-can-cross-before-first-post

### R1 - Modifier or physical interference during final validation can still post the pair

- Failure class: race / output-admission violation.
- Trigger: the user has explicitly confirmed, modifier stabilization and the first final modifier sample report empty, and Command, Shift, Control, Option, Fn, or Caps Lock becomes held while the binding-specific `validateBeforeMutation` work is running. The exact route makes multiple potentially blocking Accessibility calls and AX focus/selection writes in this interval.
- Expected: because a relevant modifier is held before the first Unicode key-down submission, the attempt remains in `notStarted`, posts zero events, and retains the draft.
- Observed: `performFinalPair` samples modifiers before `finalValidation`, then calls `postPair` without another sample. `SystemFinalTextOutput.insertOnce` runs `validateBeforeMutation` inside that `postPair` closure and immediately invokes the prepared pair afterward. The shared physical-input epoch lock is held over this work, so an event-tap writer attempting to record the modifier or other physical event is blocked until after both posts. Postflight can downgrade the result to uncertainty, but it is too late to preserve zero output.
- Primary anchor: `FeishuSpeech/Services/ReviewDestinationDelivery.swift:390-412`.
- Secondary anchors: `FeishuSpeech/Services/TextInputSimulator.swift:255-268`; `FeishuSpeech/Services/CurrentFocusAppendSession.swift:196-201`; `FeishuSpeech/Services/CurrentFocusAppendSession.swift:765-772`; `FeishuSpeech/Services/AccessibilityClient.swift:245-275`.
- Reproducible scenario: use the exact-binding delivery with a modifier sampler that returns empty for stabilization and the sample at `ReviewDestinationDelivery.swift:399`, then changes to `.maskCommand` from the fake `restoreAndValidateBeforeDelivery` call. Keep the input and activation epochs unchanged and use the real `SystemFinalTextOutput` with a counting Unicode backend. The current order reaches one key-down/key-up pair; only the postflight sample sees Command and returns an uncertain result. A real user can reach the same ordering by pressing a modifier while the AX focus/selection restore is in progress.
- Why guards do not prevent it: the last pre-boundary modifier guard is before the final validator, and the input epoch writer uses the same lock that is held around the validator and posts. No behavioral test changes a modifier from inside final validation; the current modifier test only searches source text for mask names at `FeishuSpeechTests/FinalTextOutputSecurityTests.swift:620-646`.
- Minimal repair boundary: restructure the transaction so binding-specific AX/application validation does not run while physical-input epoch writers are blocked, then enter the short combined critical section, recheck the resulting epochs and all relevant modifier flags immediately before the first post, and keep only the mandatory down/up submission inside it. Add a deterministic exact and application-bound test that flips a relevant modifier during final validation and proves zero backend posts.

finding: id=R2 scope=in_scope action=fix status=open severity=medium fix_role=tdd-guide rationale=blanket-skip-removes-async-stability-oracles

### R2 - The 51 retired tests also retire live recording and recognition stability coverage

- Failure class: regression coverage gap.
- Trigger: any regression in the still-active capture drain, retry/backoff, journal replay, release barrier, or terminal-admission paths, including failure to reset retry backoff after a successful packet.
- Expected: tests whose old direct-output assertions are obsolete are migrated to preview-only assertions while their asynchronous recording and recognition oracles continue to execute.
- Observed: `setUpWithError` skips all 51 named methods before their bodies run. Several names and bodies cover active asynchronous behavior rather than only the retired output authority. In particular, `test_successfulPacketAfterRepeatedBackend10024ResetsRetryBackoffStreak` is the only test that proves a successful packet resets delays from 250 ms, 500 ms back to 250 ms, yet it is skipped. The same set also suppresses replay, drain-deadline, release, reset, and transport-cancellation scenarios.
- Primary anchor: `FeishuSpeechTests/StreamingMainViewModelTests.swift:16-76`.
- Secondary anchor: `FeishuSpeechTests/StreamingMainViewModelTests.swift:1654-1699`.
- Proof: repository search finds no other assertion for the `250_000_000, 500_000_000, 250_000_000` reset sequence. The v4 receipt reports these 51 tests as intentionally skipped, so a retry-reset regression cannot fail the claimed GREEN matrix.
- Minimal repair boundary: remove the blanket name-based skip. Rewrite or split each affected method so obsolete AX/direct-output expectations are replaced with read-only preview and zero-output assertions, while transport, retry, replay, barrier, and cancellation assertions still execute. At minimum restore every unique async oracle and provide an explicit mapping from retired output-only assertions to active replacements.

finding: id=R3 scope=in_scope action=fix status=open severity=medium fix_role=tdd-guide rationale=post-boundary-safety-tests-only-search-source-strings

### R3 - Mandatory key-up and post-boundary uncertainty are not behaviorally tested

- Failure class: critical-boundary test gap.
- Trigger: cancellation or an injected fault occurs after key-down, before key-up, or after key-up.
- Expected: before-down cancellation posts zero; every after-down path attempts exactly one key-up to the same PID; every crossed-boundary path returns submitted-unverified or uncertain and never cancellation or failed-before-submission.
- Observed: the advertised v4 test only loads the production source and searches for words such as `submissionBoundaryCrossed`, `mandatory key-up attempt`, and hook names. No test constructs `ReviewUnicodePosterHooks` or drives `beforeDown`, `afterDown`, `beforeUp`, `afterUp`, `postflight`, or cancellation behavior. An implementation that retains those strings but suppresses key-up would remain GREEN.
- Primary anchor: `FeishuSpeechTests/FinalTextOutputSecurityTests.swift:601-666`.
- Secondary anchor: `FeishuSpeech/Services/TextInputSimulator.swift:866-916`.
- Minimal repair boundary: replace the source-string oracles with table-driven executable tests over every hook/cancellation boundary. Assert exact posted phase/PID sequences and typed results, including zero events before the boundary and down plus mandatory up after it.

## Additional review notes

- Product search found no `NSPasteboard`, pasteboard mutation, Cmd+V, or virtual-key V path in `FeishuSpeech`; the only accepted production post primitive is `CGEvent.postToPid` in `TextInputSimulator.swift`.
- `ReviewConfirmationIntent` has a file-private initializer and is created only by the visible Send action or qualified native Return/Enter path. `MainViewModel` has one `reviewDestinationDelivery.deliver` call and freezes the coordinator-owned draft before it.
- Final action-two waits for `awaitReviewRecorderBarrier` before publishing `.editable`; partial and nonterminal final events remain read-only previews.
- `git diff --check` and Swift syntax parsing of all changed production files passed. Per the review contract, the expensive full build/test run was not repeated after admitting concrete defects. The supplied GREEN receipt reports 264 focused executions, 51 skips, and zero failures.

verdict: fail
findings_blocking: 3
review_conclusion: The candidate preserves the intended preview authority but still needs the modifier race fixed and executable async safety coverage restored before installation.
