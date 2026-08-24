# Issue #40 v4 TDD RED receipt

Baseline under test: `4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a` (`4f9908f fix: make review readiness transparent (#40)`). The v4 tests were run against this baseline before any production repair. This receipt records only test-author work; no production, architecture, workflow, or mission file was changed.

## Acceptance surface encoded

- After the action2 recognition result and recorder stop barrier, the coordinator must publish `.editable` on the retained review surface immediately. Focus activation/key/editor/first-responder outcomes are telemetry/presentation assistance only; pending, timeout, cancellation, or a never-completing request cannot gate editability, Send/Return, draft text, authority, revision, or feedback.
- From capture through streaming preview, sealing, action2/barrier, frozen preview, and arbitrary per-character edits, the side-effect ledger remains empty: no delivery, AX write, keyboard/CGEvent post, pasteboard snapshot/read/write/restore/change-count access, copy, retry, or retarget.
- Only an explicit current Send/Return confirmation authorizes exactly one delivery. Duplicate or stale confirmation is a no-op. Delivery failure returns the exact draft to editable with typed feedback and no readiness retry; delivery uncertainty remains explicit and never auto-retries.
- Exact-cursor and application-bound review delivery use one modifier-free tagged Unicode keyDown/keyUp pair carrying the complete UTF-16 draft (including LF) to the captured PID. Preflight failure posts zero pairs; postflight uncertainty posts one pair and performs no retry. Pasteboard/Cmd+V collaborators remain unused.
- The product view must not expose `editablePending` or the user-facing readiness retry action; focus-controller tests remain lower-level telemetry tests.

## Test artifacts changed

- `FeishuSpeechTests/ReviewFirstMainViewModelTests.swift`
  - Replaced the old editable-readiness-gates-confirmation oracle with `test_reviewFirst_presentationFocusOutcomeCannotGateEditableOrConfirmation`, covering activation rejection, timeout predicates, cancellation, and a held never-completing request. It asserts retained panel identity, durable draft editing, explicit confirmation, no copy/output/AX mutation, and no readiness retry.
  - Added `test_reviewFirst_zeroSideEffectLedgerStaysEmptyFromCaptureThroughDraftEdits`, checking the ledger after capture start, streaming packet, recorder/action2 barrier, and each draft edit.
  - Updated delivery-failure coverage to require exact draft recovery in `.editable` without focus retry.
  - Extended test-only presenter/delivery fakes with a held readiness continuation and side-effect trace.
- `FeishuSpeechTests/FinalTextOutputSecurityTests.swift`
  - Added exact-cursor and application-bound route RED tests requiring the real Unicode poster to construct one modifier-free tagged pair with full multiline UTF-16 payload and captured PID, with no pasteboard/Cmd+V.
  - Added preflight zero-pair and postflight-uncertainty one-pair/no-retry assertions for both routes.
  - Strengthened the production Unicode-pair oracle to include LF in both key events.
- `FeishuSpeechTests/ReviewPasteboardLifecycleTests.swift`
  - Recast successful and uncertain review transactions as no-pasteboard/no-Cmd+V oracles, including snapshot/read/change-count/write/restore/scheduler counters and clipboard identity.
- `FeishuSpeechTests/TranscriptionReviewViewTests.swift`
  - Retained the v3 font/titlebar/no-retry/fixed-feedback checks and added source guards that reject durable `editablePending`, `onRetryReadiness`, and authority through `requestEditableReadiness`.

## RED command and result

Serialized focused matrix:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-focused-red-derived -parallel-testing-enabled NO -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests test
```

Log: `/tmp/issue40-v4-final-red.log`

Result: exit `65`; 98 tests executed, 110 assertion failures.

| Suite | Tests | Failures | Verdict |
|---|---:|---:|---|
| `FinalTextOutputSecurityTests` | 27 | 43 | RED |
| `ReviewDestinationDeliveryTests` | 13 | 0 | existing security/delivery oracles remain green |
| `ReviewFirstMainViewModelTests` | 31 | 27 | RED |
| `ReviewPasteboardLifecycleTests` | 7 | 36 | RED |
| `ReviewWindowControllerReadinessTests` | 10 | 0 | retained focus telemetry oracles remain green |
| `TranscriptionReviewViewTests` | 10 | 4 | RED |
| **total** | **98** | **110** | **RED** |

Test result bundle: `/tmp/issue40-v4-final-red-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_19-55-07-+0800.xcresult`

Representative failure signatures proving the baseline is genuinely red:

- `ReviewFirstMainViewModelTests.test_reviewFirst_presentationFocusOutcomeCannotGateEditableOrConfirmation`: `XCTAssertEqual failed: (editablePending(...)) is not equal to (editable(...))`; the old coordinator still gates editability on focus readiness, and explicit confirmation delivers zero texts.
- `ReviewFirstMainViewModelTests.test_reviewFirst_deliveryFailureReturnsExactDraftToEditableWithoutFocusRetry`: `editablePending(... feedback: deliveryFailed)` is not equal to `.editable(... feedback: deliveryFailed)`; `readinessFailures` contains `timedOut(editorFirstResponder)` and the second explicit attempt is not delivered.
- `ReviewFirstMainViewModelTests.test_reviewFirst_zeroSideEffectLedgerStaysEmptyFromCaptureThroughDraftEdits`: `editablePending(... readiness: preparing(...))` is not equal to `.editable(...)` while the held focus request remains unresolved.
- `FinalTextOutputSecurityTests.test_reviewExactBindingUsesOneModifierFreeUnicodePairWithoutPasteboardOrCmdV` and `...test_reviewApplicationBoundDraftUsesOneModifierFreeUnicodePairWithoutPasteboardOrCmdV`: baseline records the full draft in the pasteboard writer and PID in the legacy poster while the required Unicode backend has no pair.
- `FinalTextOutputSecurityTests.test_systemUnicodePosterConstructsCompletePrivatePairBeforePostingDownThenUpOnce`: `deliveryFailed` is not `posted` for the multiline draft, proving the baseline safety gate rejects the required LF payload before pair construction.
- `ReviewPasteboardLifecycleTests.test_successfulReviewConfirmationNeverTouchesPasteboardOrCmdV`: snapshot/write/change-count/restore and Cmd+V counters are nonzero on the baseline.
- `TranscriptionReviewViewTests.test_frozenDraftExposesSendAndReturnWithoutRetryEditingControl`: production source still contains `editablePending` and `onRetryReadiness`.
- `TranscriptionReviewViewTests.test_reviewPanel_isOneNSPanelWithSafeReadOnlyAndEditableAuthorityModes`: production source still exposes `requestEditableReadiness()` and does not expose the v4 `requestPresentationFocus()` seam.

The focused controller readiness suite and `ReviewDestinationDeliveryTests` are intentionally retained as non-authority telemetry/security oracles and passed without weakening their existing exact/application-bound, multiline/keyboard, stale-callback, and exact-once assertions.

## R1-R5 security-amendment RED (same baseline)

The revised `architecture-blueprint-v4.md` amendment was read before adding these
oracles. This extension remains test-only and preserves the earlier 98-test
oracle. It covers the amended boundaries:

- 16,384 UTF-16 units are accepted, including the surrogate-pair edge; 16,385
  units are rejected before activation, event construction, or output.
- The prepared pair is exactly one modifier-free tagged Unicode keyDown/keyUp
  pair containing the complete UTF-16 draft (including LF), captured target PID,
  own source PID, identical source identity, empty flags, and exact tag. Any
  readback/provenance/tag/phase/payload/flags/PID fault fails closed with zero
  post.
- Cancellation and injected faults are phase-aware: before the submission
  boundary they produce no pair; after keyDown the keyUp attempt is mandatory,
  the outcome is `submittedUnverified`, and no retry is permitted.
- Combined Command/Shift/Option/Control/Fn modifiers, unstable modifier samples,
  and physical-input or activation-epoch changes before the boundary produce
  zero output; changes after the boundary are uncertain and never retried.
- The event-tap and AppKit local/global monitor filters require own PID plus the
  exact synthetic tag for exemption. Foreign, missing, or zero PID with that
  tag; own PID with a missing or wrong tag; and tap-disabled input all advance
  the epoch/fail closed. Prepared-pair exact tag/PID readback remains a separate
  assertion.
- Late focus completions are generation/attempt fenced. Confirmation has no
  zero-argument or optional-revision bypass: only opaque intent from a real Send
  button or qualified native Return/Enter can authorize delivery; stale,
  programmatic, and no-revision paths stay inert.

### Serialized amendment command

```text
set -o pipefail
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -derivedDataPath /tmp/issue40-v4-amend-final-red-derived \
  -parallel-testing-enabled NO \
  -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
  -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests \
  -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests \
  -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests \
  -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests \
  -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests \
  -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests test \
  | tee /tmp/issue40-v4-amend-final-red.log
```

The command ran against `4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a` and exited
`65`. The exact result bundle is
`/tmp/issue40-v4-amend-final-red-derived/Logs/Test/Test-FeishuSpeech-2026.08.23_20-19-23-+0800.xcresult`.

| Suite | Tests | Failures | Verdict |
|---|---:|---:|---|
| `CurrentFocusAppendSessionTests` | 38 | 9 | RED |
| `FinalTextOutputSecurityTests` | 33 | 87 | RED |
| `ReviewDestinationDeliveryTests` | 13 | 0 | retained lower-level oracle green |
| `ReviewFirstMainViewModelTests` | 31 | 27 | RED |
| `ReviewPasteboardLifecycleTests` | 7 | 36 | RED |
| `ReviewWindowControllerReadinessTests` | 11 | 7 | RED |
| `TranscriptionReviewViewTests` | 12 | 15 | RED |
| **total** | **145** | **181** | **RED** |

Full log: `/tmp/issue40-v4-amend-final-red.log`.

Representative failure signatures:

- `CurrentFocusAppendSessionTests.test_syntheticEventEpochExemptionRequiresOwnPIDAndExactTag`: the baseline leaves epoch at `0` for a foreign PID with the correct tag (expected `1`), then similarly fails zero-PID, missing-tag, wrong-tag, and tap-disabled advancement. `test_workspaceInputMonitorExemptsTaggedSyntheticEventsAndFnTransitions` likewise records no advancement for a foreign PID with the same tag.
- `FinalTextOutputSecurityTests.test_v4ReviewUnicodePairAcceptsExactUTF16CapAndRejectsSurrogateOverflowBeforeConstruction`: the 16,385-UTF-16 draft is reported `posted` instead of `deliveryFailed`, with two constructed and posted events instead of zero.
- `FinalTextOutputSecurityTests.test_v4PreparedPairReadbackFaultsFailBeforeAnyPost`: each injected tag/source-PID/source-identity/flags/phase/payload/target-PID fault reports `posted` and retains two posted events instead of failing closed before post.
- `FinalTextOutputSecurityTests.test_v4PreparedPairExposesDeterministicFaultAndCancellationBoundaries`: production source contains none of the required before-build/after-build/before-down/after-down/before-up/after-up/postflight/cancellation seams.
- `FinalTextOutputSecurityTests.test_v4UnicodePosterSourceDeclaresCapReadbackAndOwnProcessProvenance`: production source lacks the required `16_384`, `draftTooLong`, `eventSourceUnixProcessID`, `getpid()`, and readback/provenance declarations.
- `ReviewFirstMainViewModelTests.test_reviewFirst_deliveryFailureReturnsExactDraftToEditableWithoutFocusRetry`: baseline remains `.editablePending(... timedOut(editorFirstResponder) ...)` rather than the exact `.editable(... deliveryFailed)` draft; the readiness failure list is populated and the retry path is not explicit-only.
- `ReviewWindowControllerReadinessTests.test_v4PresentationFocusCompletionIsFencedByReviewGenerationAndAttempt`: the production controller has no `reviewID`, generation, or `focusAttemptID` fence and still exposes the obsolete readiness-retry seam.
- `TranscriptionReviewViewTests.test_v4OnlyOpaqueIntentFromRealSendOrQualifiedNativeReturnCanAuthorizeDelivery`: no real Send button materializes in the baseline hosting setup, and source guards find the old zero-argument/optional-revision/review-ID confirmation path.

Changed test custody for this amendment is limited to
`CurrentFocusAppendSessionTests.swift`, `FinalTextOutputSecurityTests.swift`,
`ReviewFirstMainViewModelTests.swift`, `ReviewPasteboardLifecycleTests.swift`,
`ReviewWindowControllerReadinessTests.swift`, and `TranscriptionReviewViewTests.swift`.
No production, architecture, workflow, or mission file was changed. The 13
`ReviewDestinationDeliveryTests` remain green, so their exact/application-bound,
multiline/keyboard, stale-callback, and exact-once security oracles were not
weakened.
