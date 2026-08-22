evidence-binding: issue38-security-review f28b61a9c403

behavior_contract_version: 3
resolved_profile_hash: c315205c80f34c2584ced36221c6abe49df39722997ae11a2f276f9a9e378959
context: issue-38
candidate: current-final-worktree
claim: final-source-first-security-and-privacy-rereview
surface: transcript confidentiality, exact destination authority, Accessibility restoration, secure-input rejection, pasteboard lifecycle, no-retarget/no-retry delivery, exactly-once recovery, stale callbacks, and asynchronous-axis independence

## Outcome

No candidate-caused security or privacy defect remains. The previous clipboard-lifecycle medium finding is repaired in the current candidate, and the source-first rereview admits zero blocking findings.

## Repair verification

- The production review confirmation path accepts exact LF-delimited multiline drafts while still rejecting NUL, tab, carriage return, DEL, and C1 controls before any destination or pasteboard mutation. The same classifier is used by delivery prevalidation and the two-phase output at `FeishuSpeech/Services/ReviewDestinationDelivery.swift:343-358` and `FeishuSpeech/Services/TextInputSimulator.swift:170-204,701-710`. Focused tests prove exact multiline preservation and control rejection at `FeishuSpeechTests/ReviewDestinationDeliveryTests.swift:205-248`.
- Successful review delivery snapshots all data-bearing types from every preexisting pasteboard item before mutation, writes once, posts one Cmd+V pair to the captured PID, requires postflight validation, and schedules restoration only for the inserted result at `FeishuSpeech/Services/TextInputSimulator.swift:170-218,816-853`.
- The delayed restoration checks that `NSPasteboard.general.changeCount` still equals the count produced by this candidate's write before restoring, and the restore helper repeats that guard before clearing or writing. A third-party clipboard change is therefore not overwritten. The deterministic lifecycle suite proves full multi-item restoration, third-party-change preservation, preflight non-mutation, and terminal uncertainty without restore or retry at `FeishuSpeechTests/ReviewPasteboardLifecycleTests.swift:21-165`.
- Key-post or postflight uncertainty schedules no automatic restore and returns `deliveryUncertain`; `MainViewModel` then performs the single review-ID-gated exact frozen-text manual-copy recovery and never retries at `FeishuSpeech/Services/TextInputSimulator.swift:186-203` and `FeishuSpeech/ViewModels/MainViewModel.swift:2277-2303`. The recovery primitive preserves exact text and deliberately leaves it on the general pasteboard at `FeishuSpeech/Services/TextInputSimulator.swift:780-792`. Exactly-once and no-copy-on-cancellation tests are anchored at `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:310-363`.

## Verified security and privacy controls

- Transcript content is held in review state and the visible `Text` or `TextEditor`, but is not interpolated into log calls, window titles, status feedback, accessibility labels, help strings, bundle identity, or destination tokens. Review lifecycle logs are fixed strings at `FeishuSpeech/Controllers/ReviewWindowController.swift:49-72,393-412`, `FeishuSpeech/Services/ReviewDestinationDelivery.swift:219-230`, and `FeishuSpeech/Services/TextInputSimulator.swift:206-218,830-853`. The visible transcript remains naturally available to assistive technology as required by the product surface; it is not duplicated into metadata.
- Review capture fails closed unless Accessibility trust is present, Secure Event Input is off, the focused element PID equals the frontmost PID, role and subrole are supported and nonsecure, the original selection is valid, and focus plus selection-range attributes are settable. It performs no setter and never queries or writes `kAXSelectedTextAttribute` at `FeishuSpeech/Services/AccessibilityClient.swift:185-228`; the oracle is `FeishuSpeechTests/ReviewDestinationDeliveryTests.swift:16-57`.
- The application authority contains PID, bundle identifier, executable URL, and launch date. Capture and delivery require equality of the complete identity, and activation observes before making one bounded request to that exact PID at `FeishuSpeech/Models/CursorTextModels.swift:32-43` and `FeishuSpeech/Services/ReviewDestinationDelivery.swift:61-100,103-230,267-319`.
- Before pasteboard mutation, delivery requires the exact captured application to be running and frontmost, restores only focus and the original selected range on the captured AX element, verifies exact focused-element equality and selection, and rechecks security. Postflight rechecks exact application identity, frontmost authority, focused element, and secure-input state without requiring the pre-paste selection at `FeishuSpeech/Services/AccessibilityClient.swift:230-274` and `FeishuSpeech/Services/ReviewDestinationDelivery.swift:326-395`.
- Wrong-app focus, PID reuse, activation timeout, target drift, secure-input activation, AX uncertainty, key-post uncertainty, and postflight uncertainty all terminate without ambient-focus fallback, retargeting, or delivery retry. The production key pair is process-targeted at `FeishuSpeech/Services/TextInputSimulator.swift:417-430`; focused destination tests are at `FeishuSpeechTests/ReviewDestinationDeliveryTests.swift:250-321`.
- Confirmation consumes editable authority synchronously before starting the async delivery task. Repeated confirmation is a no-op; discard and lifecycle revocation cancel transition, presentation, and delivery tasks, clear review strings and callbacks, and stale review IDs cannot copy or deliver at `FeishuSpeech/ViewModels/MainViewModel.swift:2198-2325` and `FeishuSpeech/Controllers/ReviewWindowController.swift:393-425`.
- The capture journal producer and recognition consumer remain separate tasks at `FeishuSpeech/ViewModels/MainViewModel.swift:635-640`. `drainCapturedAudio` and `consumeAudio` at lines 865-1110 contain no review presenter call or review readiness await. Read-only presentation is a cancellable fire-and-forget main-actor task at lines 695-735; action-2 creates a separate review transition task at lines 2003-2064, so editor readiness does not become a prerequisite for journal admission, retry, replay, sealing, or terminal session completion. Concurrency oracles are at `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:479-580`.

## Validation receipts and static evidence

- The dispatch supplied focused validation `59/59`, full validation `408 executed / 1 skipped / 0 failures`, Debug and Release build success, and strict SwiftLint success for this final candidate. This rereview did not rerun those already completed heavy commands.
- A source count independently confirms 59 test functions across the five issue-focused test surfaces. `git diff --check` completed with no output during this rereview.
- No dependency, entitlement, bundle-identity, network endpoint, authentication, credential-storage, or secret-material change is introduced by the reviewed candidate.

## Residual risks

- The streaming preview and editable draft are intentionally visible on screen and naturally exposed to assistive technology while the review panel exists. This is accepted product behavior, not a duplicate metadata leak.
- Manual recovery intentionally leaves the exact frozen draft on `NSPasteboard.general`; fixed feedback tells the user it was copied without embedding transcript content.
- Successful insertion keeps the transcript on the general pasteboard for the bounded one-second consumption opportunity. A process crash or termination in that interval can prevent restoration; this is an inherent residual of pasteboard-based Cmd+V delivery, not a candidate control bypass.
- `CGEvent.postToPid` has no application-level consumption acknowledgement. Exact identity, AX focus, security, and postflight checks constrain authority, while no-retry behavior avoids duplicate insertion when outcome is uncertain. Real WindowServer, AX target, Feishu credential, and paste-consumption UAT remains useful beyond the supplied automated receipts.

verdict: pass
findings_blocking: 0
review_conclusion: The final issue 38 candidate closes the prior clipboard exposure and preserves fail-closed exact-target delivery, transcript privacy, exactly-once recovery, and independent asynchronous capture and recognition lines.
