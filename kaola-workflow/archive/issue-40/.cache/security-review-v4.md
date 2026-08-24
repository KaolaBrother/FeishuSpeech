# Issue #40 v4 Security Review

- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
- Baseline: `4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a`
- Scope: final uncommitted v4 production and tests

## Outcome

No blocker, high, medium, or low candidate-caused security defect was admitted. The reviewed product path fails closed before confirmation, uses no pasteboard or virtual-key paste operation, and exposes only a phase-aware targeted Unicode submission after an opaque UI confirmation intent.

## Claim-by-claim evidence

1. Zero pre-confirmation side effects: `MainViewModel` explicitly discards the legacy direct-output dependencies (`FeishuSpeech/ViewModels/MainViewModel.swift:327-359`), streams recognition only into the read-only review state/presenter (`:1619-1668`), waits for action-2 and the recorder barrier before publishing `.editable` (`:1689-1806`), and handles every draft edit as in-memory authority/state mutation only (`:1889-1915`). The only call to `reviewDestinationDelivery.deliver` is under the opaque confirmation handler after the draft has been frozen and capped (`:1950-2019`). The focused zero-side-effect ledger exercises capture, streaming, sealing, and multiple character-by-character edits without delivery, copy, final output, current-focus output, or AX selected-text writes (`FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:1040-1098`).

2. No accepted-path pasteboard or Cmd+V behavior: the review output compatibility types are empty marker protocols/classes and the implementation states and enforces Unicode delivery (`FeishuSpeech/Services/TextInputSimulator.swift:415-421`, `:691-699`). Repository search found no `NSPasteboard`, general pasteboard, pasteboard clear/write/read/restore operation, `kVK_ANSI_V`, or Command+V event construction in `FeishuSpeech`. The focused lifecycle tests prove both exact and application-bound confirmation leave the pasteboard/copy-paste doubles untouched and never retry (`FeishuSpeechTests/ReviewPasteboardLifecycleTests.swift:20-223`).

3. UTF-16 cap and exact payload: the product confirmation gate rejects over 16,384 UTF-16 code units before calling delivery (`FeishuSpeech/ViewModels/MainViewModel.swift:1950-1973`). The poster independently enforces the same cap before source/event construction, builds down and up from the same complete `[UInt16]`, and requires readback of phase, complete payload, empty flags, tag, own PID, and target PID (`FeishuSpeech/Services/TextInputSimulator.swift:800-863`). The production backend reads the event Unicode payload back and compares exact units (`:1122-1166`). Boundary coverage uses a non-BMP surrogate pair at exactly 16,384 units and rejects 16,385 before construction (`FeishuSpeechTests/FinalTextOutputSecurityTests.swift:514-574`).

4. Prepared-pair provenance: both events share the one private-state source and complete payload (`FeishuSpeech/Services/TextInputSimulator.swift:821-841`), are tagged and target-bound before submission (`:842-845`), and must pass exact phase/payload/flags/tag/source-PID/target-PID readback (`:846-859`, `:1122-1142`). The self-event identity predicate is conjunctive tag plus `getpid()` (`:622-631`).

5. Irreversible boundary and mandatory up: submission remains `notStarted` until the down post, changes immediately to `submissionBoundaryCrossed`, records later faults without suppressing the synchronous up attempt, and maps every post-boundary fault, cancellation, or postflight drift to `submittedUnverified`, never cancellation (`FeishuSpeech/Services/TextInputSimulator.swift:734-739`, `:866-916`). Deterministic construction, cancellation, down, up, and postflight seams are exercised by the focused security tests (`FeishuSpeechTests/FinalTextOutputSecurityTests.swift:576-666`).

6. Modifiers and epochs: delivery arms both epoch-capable monitors before activation (`FeishuSpeech/Services/ReviewDestinationDelivery.swift:290-319`), requires two stable empty combined-session modifier samples across Command, Shift, Control, Option, Fn, and Caps Lock (`:339-367`), captures post-activation baselines (`:321-337`), and checks modifier state plus activation/input epochs under the fixed activation-then-input critical-section order immediately around the complete pair (`:369-413`). The shared input epoch lock makes epoch comparison and the complete pair indivisible from pre-dispatch physical-input advancement (`FeishuSpeech/Services/CurrentFocusAppendSession.swift:176-215`).

7. Dual provenance and loss of observability: the CGEvent tap advances the epoch before its state-machine handling (`FeishuSpeech/Services/HotKeyService.swift:200-214`) and the epoch observer always advances for both tap-disabled event types before any synthetic exemption (`FeishuSpeech/Services/CurrentFocusAppendSession.swift:204-215`). Both that observer and the AppKit local/global monitor use the same conjunctive tag-and-own-PID predicate (`:212-215`, `:795-809`, `:834-837`; predicate at `FeishuSpeech/Services/TextInputSimulator.swift:622-631`). Tests cover foreign PID, zero PID, missing tag, wrong tag, own tag/PID, and unconditional tap-disabled advancement (`FeishuSpeechTests/CurrentFocusAppendSessionTests.swift:562-802`).

8. Opaque confirmation authority: `ReviewConfirmationIntent` has only a `fileprivate` initializer (`FeishuSpeech/Views/TranscriptionReviewView.swift:14-24`). Production construction occurs only in the real Send action (`:229-247`) or native Return/Enter handler after editability, IME, and modifier qualification (`:347-370`). The coordinator has no zero-argument or optional-revision confirm API; it accepts the opaque intent together with exact review/revision authority and an in-flight exact-once fence (`FeishuSpeech/ViewModels/MainViewModel.swift:1809-1837`, `:1950-1985`). Native and source-fence tests cover the boundary (`FeishuSpeechTests/TranscriptionReviewViewTests.swift:394-470`, `:547-905`).

9. No consumption claim and durable uncertain draft: review result vocabulary says `submittedUnverified`, not consumed/inserted (`FeishuSpeech/Services/ReviewDestinationDelivery.swift:41-51`); legacy `.inserted` is conservatively converted to `.submittedUnverified` at the review boundary (`:883-903`). Postflight instability becomes uncertain (`:685-699`). Every delivery result, including submitted-unverified, returns the exact frozen text to editable review with uncertainty feedback and never silently revokes it (`FeishuSpeech/ViewModels/MainViewModel.swift:2044-2120`).

10. Asynchronous recording/recognition topology: recording capture drain and streaming consumer remain separate tasks (`FeishuSpeech/ViewModels/MainViewModel.swift:650-672`). Fn release enters sealing, stops the recorder behind its own barrier task, and independently maintains the post-release recognition drain (`:2191-2269`). Action-2 freezes the draft only after awaiting that recorder barrier (`:1689-1761`).

## Residual image-paste diagnosis

The old delayed-image mechanism is structurally removed: no accepted production path snapshots, changes, restores, reads, or writes the general pasteboard, and no Cmd+V event exists. The sole post-confirmation mutation is the immediately attempted, modifier-free, target-PID Unicode down/up pair (`FeishuSpeech/Services/TextInputSimulator.swift:800-905`, `:1145-1151`). Therefore the prior clipboard-image restoration race cannot be generated by this candidate. CoreGraphics still provides no target-consumption receipt, which is why the result remains submitted-unverified and the exact draft remains editable.

## Validation receipt

- `git diff --check`: pass.
- `swiftlint lint --strict` on all eight changed production files: 0 violations.
- Focused test command covering `FinalTextOutputSecurityTests`, `ReviewFirstMainViewModelTests`, `ReviewPasteboardLifecycleTests`, and `ReviewDestinationDeliveryTests`: pass, exit 0; xcresult `/tmp/issue40-v4-security-review/Logs/Test/Test-FeishuSpeech-2026.08.23_22-23-24-+0800.xcresult`.
- Reviewed production SHA-256 values: `ReviewWindowController.swift` `8317415f6f3da68176a80d58d076d6504bdf89557b6a5db76810aa7f23b8886b`; `CursorTextModels.swift` `c3b526a8bbbfddcb04dc3f8bc73f29c80a870a7b8063e25f6892db4ae7bbb5de`; `TranscriptionReviewState.swift` `290ec72d0a92975d8923609f74987ff1fbe57c95391e061855ca40e9ec874846`; `CurrentFocusAppendSession.swift` `61713f32625e6ac6ba7af0950bce2da23122587eef2ef09a28edbfd136db85bc`; `ReviewDestinationDelivery.swift` `b953fa65f0b701637613afa0852a6491a216e444083a314cc1e8c560eb90cc6f`; `TextInputSimulator.swift` `db7e0e924500d4ecdcac8f9983a27bc32c7dbb3989649b2a26535372aac7c27e`; `MainViewModel.swift` `476c3f0d8d3ea661103eb45899af987e69954223f4e8dc568fd6d971e5548c2a`; `TranscriptionReviewView.swift` `92b832b36248766b60c285eefb031cc7fdf835e6133d6235b62e3d696b446d30`.

verdict: pass
findings_blocking: 0
review_conclusion: The v4 candidate closes the preconfirmation output boundary and the residual clipboard image race without admitting a candidate-caused security defect.
