evidence-binding: issue38-code-review a4c9e7d210bf

behavior_contract_version: 3
resolved_profile_hash: 562154a00287ceaea5d950076aceca878134b4b32ebf5765d01da2f5c76701f4
context: issue-38-closure
candidate: final-uncommitted-worktree
claim: review-first-live-preview-edit-confirm
surface: correctness-state-authority-compatibility-async-independence
evidence: focused-59-of-59-full-408-executed-1-skipped-0-failures-debug-release-strict-lint-green

## Closure of prior findings

### R1 - Resolved

The review-only classifier now admits LF U+000A while continuing to reject tab, CR, NUL, DEL, and C1 controls before destination or pasteboard mutation. Both the composite delivery preflight and the two-phase output use the same classifier.

Production anchors:

- `FeishuSpeech/Services/TextInputSimulator.swift:170-203` validates the exact frozen draft with `isSafeForReviewConfirmation` and passes the unmodified string to the pasteboard writer.
- `FeishuSpeech/Services/TextInputSimulator.swift:701-710` admits only LF among control scalars.
- `FeishuSpeech/Services/ReviewDestinationDelivery.swift:343-350` applies the same review-confirm classifier before activation.

Test anchors:

- `FeishuSpeechTests/ReviewDestinationDeliveryTests.swift:205-225` proves that an exact two-line LF draft is inserted without normalization.
- `FeishuSpeechTests/ReviewDestinationDeliveryTests.swift:227-248` proves that tab and CR still fail before preflight, pasteboard mutation, or synthetic input.

finding: id=R1 scope=in_scope action=none status=resolved severity=medium fix_role=implementer rationale=multiline-confirm-now-preserves-exact-lf-draft

### R2 - Resolved

The successful review transaction now snapshots every data-bearing type from every prior pasteboard item before mutation. Restoration is scheduled only after preflight, one process-targeted Cmd+V pair, and successful postflight validation. Key-post or postflight uncertainty schedules no restoration and leaves the frozen draft for manual recovery. A third-party pasteboard mutation invalidates restoration: the scheduled operation checks the expected post-write change count, and the concrete restore checks it again immediately before clearing the board.

Production anchors:

- `FeishuSpeech/Services/TextInputSimulator.swift:186-203` snapshots before mutation and schedules restoration only on the certain `inserted` path.
- `FeishuSpeech/Services/TextInputSimulator.swift:206-219` rejects a scheduled restore after any intervening change count.
- `FeishuSpeech/Services/TextInputSimulator.swift:816-854` captures all item/type data and rechecks change count before restoration.
- `FeishuSpeech/Services/TextInputSimulator.swift:191-198` leaves key-post and postflight uncertainty terminal, with no restore scheduling.

Test anchors:

- `FeishuSpeechTests/ReviewPasteboardLifecycleTests.swift:21-51` proves successful restoration of both text and non-text prior items after the bounded opportunity.
- `FeishuSpeechTests/ReviewPasteboardLifecycleTests.swift:53-81` proves that an intervening third-party write is preserved and no restore occurs.
- `FeishuSpeechTests/ReviewPasteboardLifecycleTests.swift:83-109` proves preflight rejection performs no snapshot-visible mutation, scheduling, event, or restoration.
- `FeishuSpeechTests/ReviewPasteboardLifecycleTests.swift:111-165` proves key-post and postflight uncertainty are terminal, never retry, never auto-restore, and retain the frozen draft.

finding: id=R2 scope=in_scope action=none status=resolved severity=medium fix_role=implementer rationale=successful-review-paste-restores-with-third-party-change-guards

## Full frontier review

### Independent asynchronous axes

No review presenter, editor-readiness continuation, or pasteboard operation was added to capture drain, journal admission/wakeup, streaming session creation, retry sleep, journal replay, packet send, finish, or watched-operation settlement.

- `FeishuSpeech/ViewModels/MainViewModel.swift:635-640` still creates distinct `captureDrainTask` and `consumerTask` roots.
- `FeishuSpeech/ViewModels/MainViewModel.swift:865-908` drains recorder ingress into `HoldPacketJournal` without any review-state or presenter reference.
- `FeishuSpeech/ViewModels/MainViewModel.swift:910-1195` retains the independent recognition consumer, attempt factory, retry, replay, packet-send, capture-complete, and action-2 finish topology without a review presenter call or readiness await.
- `FeishuSpeech/ViewModels/MainViewModel.swift:695-735` places read-only presentation on a revision- and review-ID-gated fire-and-forget main-actor task. The recognition receipt only replaces in-memory state and enqueues this task.
- `FeishuSpeech/ViewModels/MainViewModel.swift:2003-2065` closes terminal response authority and spawns a separate transition task; the terminal receipt returns without awaiting the recorder barrier or editor readiness.
- `FeishuSpeech/ViewModels/MainViewModel.swift:2068-2196` waits for the existing recorder barrier and editor readiness only inside that review transition task, after action-2 has settled. Neither data-line task stores or awaits it.
- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:479-557` covers capture-before-start, journal progress with a gated read-only presenter, independent action-2 progress, the recorder barrier, and editable-transition failure without making presentation an input to either data line.

### Review state and same-panel authority

- Output mode and `autoInsert` are sampled once at accepted-Fn start at `FeishuSpeech/ViewModels/MainViewModel.swift:554-569`; later Settings changes cannot reroute the active interaction.
- Review capture creates only a review authority and `.streaming` state at `FeishuSpeech/ViewModels/MainViewModel.swift:665-693`; it does not arm `CursorTextSession`, an append session, a pasteboard writer, or a synthetic event.
- Generation, packet-index, admission, replay, and duplicate gates at `FeishuSpeech/ViewModels/MainViewModel.swift:1751-1800` accept only newly owned changed opaque snapshots and replace the read-only preview in full.
- Release retains the latest preview in `.sealing` at `FeishuSpeech/ViewModels/MainViewModel.swift:2600-2616`; the existing recorder stop/barrier remains independent at lines 2628-2644.
- Action-2 freezes the authoritative final or exact incomplete fallback before editable authority at `FeishuSpeech/ViewModels/MainViewModel.swift:2003-2045`; late recognition is fenced by closed admission, invalidated identity, review ID, and revision.
- `ReviewWindowController` owns one retained `ReviewPanel` at `FeishuSpeech/Controllers/ReviewWindowController.swift:35-43` and `74-108`. Read-only streaming/sealing uses that panel with key and mouse authority disabled at lines 49-71. Editable mode reuses it, enables key authority, activates FeishuSpeech, and requires the exact editor responder at lines 159-338.
- Dismissal clears callbacks and hosted transcript content at `FeishuSpeech/Controllers/ReviewWindowController.swift:393-413`; window close routes through the same discard callback at lines 415-425.
- Same-surface, stale-render, late-callback, human-edit, sampled-setting, and unresolved-draft/new-Fn behavior are covered by `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:22-199` and `365-478`, while the panel identity and input-mode contract are covered by `FeishuSpeechTests/TranscriptionReviewViewTests.swift:13-121`.

### Exact destination and exactly-once delivery

- Review capture does not query or write `kAXSelectedTextAttribute`. It binds the exact AX element, original selection, PID, bundle ID, executable URL, and launch date; incomplete identity fails closed.
- `FeishuSpeech/Services/ReviewDestinationDelivery.swift:267-319` revalidates exact running/frontmost identity, waits once for bounded activation, restores the captured destination, and performs one process-targeted paste transaction.
- `FeishuSpeech/Services/AccessibilityClient.swift:185-274` writes only focused state and the original selected range, verifies the exact focused element and selection before delivery, and performs focus/security postflight without selected-text writes.
- `FeishuSpeech/ViewModels/MainViewModel.swift:2233-2260` consumes confirm authority synchronously before the first delivery await. Repeated confirm and stale callbacks cannot create a second task.
- `FeishuSpeech/ViewModels/MainViewModel.swift:2277-2303` treats all certain and uncertain failures as terminal, copies the exact frozen draft at most once for non-cancellation recovery, and never retargets or retries.
- Identity reuse, wrong-app activation, bounded timeout, focus/selection order, preflight zero-mutation, postflight uncertainty, and one-post behavior are covered by `FeishuSpeechTests/ReviewDestinationDeliveryTests.swift:16-203` and `250-321`.

### Compatibility and lifecycle cleanup

- When review-first is disabled, existing cursor/append selection remains in `prepareCursorTarget` and uses the sampled compatibility value at `FeishuSpeech/ViewModels/MainViewModel.swift:743-825` and `1895-1905`.
- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift:582-606` covers compatibility behavior with both `autoInsert` values, and existing streaming tests explicitly opt into the compatibility route without changing their historical oracle.
- Discard, reset, sleep, wake, permission loss, Secure Input, abnormal termination, and cleanup revoke review ID/revision, cancel transition/presentation/delivery tasks, clear transcript state, and perform no recovery copy unless a current non-cancellation delivery failure owns it. The relevant cleanup is centralized at `FeishuSpeech/ViewModels/MainViewModel.swift:2305-2326`, `2775-2817`, and `3060-3082`.

## Validation and residual gaps

The dispatch supplied focused validation of 59 of 59 passing tests, full validation of 408 executed with 1 skipped and 0 failures, Debug and Release build success, and strict lint success. Repository policy says not to rerun already-passed checks, so this review used those results as supplied evidence and independently inspected the source and oracle surfaces.

Residual gaps are non-blocking and require owner/runtime UAT rather than another source repair:

- Source-string panel tests do not prove real WindowServer behavior for an accessory-policy app. A real run must confirm that `orderFrontRegardless` preserves original target focus and that the same panel becomes key with its editor focused after action-2.
- No source test can prove real microphone/credential-bearing Feishu behavior, real Accessibility restoration across third-party apps, or actual `CGEventPostToPid` consumption. Delivery correctly remains fail-closed where evidence is available and treats post-boundary uncertainty as terminal.
- The pasteboard tests deterministically cover prior-item restoration and an intervening third-party write. They do not model two successful review confirmations completed within the one-second restoration window; production change-count guards prevent stale restoration from overwriting the newer board, but owner UAT can verify the desired clipboard result for this extremely rapid sequence.

verdict: pass
findings_blocking: 0
review_conclusion: Both prior delivery findings are resolved, and the final source preserves independent capture, recognition, and review authority without blocking defects.
