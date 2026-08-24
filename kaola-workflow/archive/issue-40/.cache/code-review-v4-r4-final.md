# Issue #40 v4 R4 Final Correctness Review

- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
- Baseline: `4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a`
- Scope: final repaired R4 production, tests, and documentation

## Verdict

PASS. The final R4 repair closes the prior confirmation-authority bypass and LF-retention defect. No blocker, high, or medium correctness finding remains in the complete current production, test, and documentation diff.

## R4 closure: drain-expiry recovery is inert

- `expirePostReleaseDrain` snapshots the latest preview before closing admission, invalidating the session identity, cancelling both asynchronous roots, and fencing the review transition (`FeishuSpeech/ViewModels/MainViewModel.swift:2272-2305`). It can retain text only through `presentRecoveryReviewSurface` (`:2307-2325`).
- Recovery requires the same generation, non-contentless review-safe text, and the 16,384 UTF-16 cap (`FeishuSpeech/ViewModels/MainViewModel.swift:2335-2345`). The shared classifier admits LF as inert text while rejecting other C0/C1/DEL controls (`FeishuSpeech/Services/TextInputSimulator.swift:1200-1208`). Empty, unsafe, oversized, stale, or otherwise ineligible values return false and remain on the fixed failure/preservation path.
- Before rendering recovery, production cancels pending read-only/focus work and transitions, clears `reviewSurfaceAuthority`, leaves the public review state as `.sealing`, and invokes only `renderReadOnly(.recovery, preview:)` (`FeishuSpeech/ViewModels/MainViewModel.swift:2348-2364`). It does not install `.editable`, call `renderDraft`, create a confirm callback, retry, retarget, or deliver.
- `ReviewWindowController.renderReadOnly` clears draft, confirm, and discard callbacks. Its recovery case installs a read-only view, disables key interaction, ignores mouse events, and removes close authority (`FeishuSpeech/Controllers/ReviewWindowController.swift:95-126`). `TranscriptionReviewView` presents recovery as incomplete-recognition/read-only feedback with no editor or Send control (`FeishuSpeech/Views/TranscriptionReviewView.swift:27-69`, `:95-127`).
- The executable R4 seam test proves that neither the fake real Send-button seam nor qualified Return is materialized and that delivery, accessibility writes, synthetic output, append, retry, and retarget counters remain zero; late completion leaves the retained preview unchanged (`FeishuSpeechTests/StreamingMainViewModelTests.swift:2006-2065`). The multiline oracle proves exact LF retention, no `.editable`, no terminal error, zero delivery/output, and inert late completion (`:2067-2111`). The reconciled empty/LF branch separately preserves the empty-value fail-closed oracle (`:1840-1943`).

## Authoritative editable and exactly-one attempt boundary

- Normal terminal action 2 closes recognition admission, chooses the terminal or last usable draft, and starts the recorder-barrier transition (`FeishuSpeech/ViewModels/MainViewModel.swift:1689-1751`). `awaitReviewRecorderBarrier` must complete before `finishReviewTransition` can install `.editable` and its callbacks (`:1754-1806`). Recording and recognition therefore remain independent asynchronous lines until their explicit barrier.
- The coordinator still starts `captureDrainTask` and `consumerTask` as separate roots (`FeishuSpeech/ViewModels/MainViewModel.swift:667-672`). Fn release closes capture and owns the asynchronous recorder-stop barrier without collapsing the recognition consumer (`:2191-2234`). The protected recorder, ingress, journal, streaming/provider, keep-alive, socket, and transport files remain byte-identical to the baseline.
- Product code contains one `reviewDestinationDelivery.deliver` call, at `FeishuSpeech/ViewModels/MainViewModel.swift:2010-2013`. `ReviewConfirmationIntent` is created only by the visible Send action and the qualified Return/Enter handler (`FeishuSpeech/Views/TranscriptionReviewView.swift:261`, `:380`). Duplicate/stale confirmation callbacks are fenced by review ID, revision, state, and in-flight authority before this call.
- Product search found no `NSPasteboard` or general-pasteboard read/write/snapshot/restore, no Cmd+V or virtual-key-V path, and no other product delivery call. Before authoritative action 2 plus the recorder barrier and a real explicit intent, the reviewed path therefore has no target AX write, Unicode/keyboard post, clipboard effect, append, delivery attempt, retry, or retarget.
- The remaining submission route prepares and validates a fixed-PID, tagged, modifier-free Unicode down/up pair. Binding-specific validation completes outside the epoch lock; the short activation-to-input gate immediately rechecks modifier and epoch state and contains only the mandatory pair (`FeishuSpeech/Services/TextInputSimulator.swift:232-263`, `:285-309`; `FeishuSpeech/Services/ReviewDestinationDelivery.swift:369-409`, `:632-667`). After key-down, key-up remains mandatory and any later fault or cancellation maps to submitted-unverified rather than a retry (`FeishuSpeech/Services/TextInputSimulator.swift:841-880`).

## Prior R1-R3 closure

- R1 remains resolved. The exact/application executable matrix transitions Command, Shift, Control, Option, and Fn during binding-specific final validation and proves `.deliveryFailed`, zero posted events, and only prepared pair construction (`FeishuSpeechTests/FinalTextOutputSecurityTests.swift:735-828`). This falsifies both exact-cursor and application-current-focus modifier races before the down-event boundary.
- R2 remains resolved. `StreamingMainViewModelTests` contains 105 executable `test_` methods and no `XCTSkip`, `retiredCompatibilityOutputTests`, or `setUpWithError` blanket skip. Independent name accounting confirms that all 51 formerly skipped methods remain present. Their unique retry/journal/drain/barrier oracles remain executable, including ordered replay (`FeishuSpeechTests/StreamingMainViewModelTests.swift:935-990`), repeated factory backoff (`:992-1023`), release-during-retry terminal completion (`:1050-1085`), and successful-ACK reset of the 250 ms, 500 ms, 250 ms sequence (`:1584-1637`).
- R3 remains resolved. Real injected poster hooks assert before-down, after-down, before-up, after-up, and postflight phase/PID behavior (`FeishuSpeechTests/FinalTextOutputSecurityTests.swift:601-676`). Separate cancellation tests prove zero events before the boundary and mandatory down/up with submitted-unverified uncertainty after the boundary (`:678-733`).

## Documentation and complete-diff review

- All 25 currently changed production, test, and documentation files were reviewed in context against the baseline. The eight final documentation surfaces consistently describe drain expiry as exact LF-capable, non-authoritative `ReviewReadOnlyPhase.recovery`, with no editor, Send/qualified Return, or delivery authority; only action 2 plus the recorder barrier may install `.editable` (`README.md:9`; `CHANGELOG.md:10`; `docs/README.md:5`; `docs/architecture.md:401-410`; `docs/decisions/D-38-01.md:276-294`; `docs/decisions/D-39-01.md:36-38`; `docs/decisions/D-40-01.md:155-166`; `docs/streaming-speech-design.md:377-389`).
- The final docs no longer contain the superseded drain-expiry `.editable`, LF-unsafe, 263/103/482, or skipped-compatibility claims. Current evidence is consistently recorded as 3/3 R4 selectors, 105/105 Streaming, 265 focused with zero skips/failures, and 483 full-target passes plus one unrelated live-TCP environmental skip. Installation and owner UAT remain explicitly pending rather than being overstated.

## Validation

- Independent R4 selector run: 3 tests, 0 failures, 0 skips; xcresult `/tmp/issue40-v4-code-review-r4/Logs/Test/Test-FeishuSpeech-2026.08.24_00-02-31-+0800.xcresult`.
- Independent full `StreamingMainViewModelTests` run: 105 tests, 0 failures, 0 skips in 7.872 seconds; xcresult `/tmp/issue40-v4-code-review-r4/Logs/Test/Test-FeishuSpeech-2026.08.24_00-04-31-+0800.xcresult`.
- Supplied final green receipt: 265 focused tests passed with zero failures/skips; full serialized target recorded 483 passed, zero failed, and one unrelated guarded live-TCP skip.
- Final `git diff --check` passed. Stale documentation scans and product pasteboard/Cmd+V/delivery-call scans passed.

## Non-blocking runtime boundary

Automated review cannot prove target application consumption of `CGEventPostToPid` or replace signed Release installation and owner UAT. The documentation correctly leaves sole-copy installation, real microphone/credentials, WindowServer, Accessibility restoration, Secure Input/password rejection, multiline/emoji receipt, and cross-application confirmation acceptance pending. These are external verification boundaries, not candidate-caused blocker/high/medium code defects.

verdict: pass
findings_blocking: 0
review_conclusion: The complete R4 candidate now preserves drain-expiry text only as inert read-only recovery, retains authoritative action-two confirmation boundaries, and passes independent correctness gates without blocking findings.
