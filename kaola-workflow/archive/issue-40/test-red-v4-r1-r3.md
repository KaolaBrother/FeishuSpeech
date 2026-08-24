# Issue #40 v4 TDD RED receipt — R1/R2/R3

Date: 2026-08-23 (Asia/Shanghai)

Baseline under test: `4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a` (`git rev-parse HEAD` matched exactly).

Scope: test-only custody. The lane changed only:

- `FeishuSpeechTests/FinalTextOutputSecurityTests.swift`
- `FeishuSpeechTests/StreamingMainViewModelTests.swift`

No production source, architecture, mission-list, or other workflow file was changed by this lane.

## R1 executable RED

The new table-driven test is:

`FinalTextOutputSecurityTests.test_v4BindingSpecificFinalValidationModifierTransitionIsPreBoundaryForExactAndApplicationRoutes`

It exercises both exact-cursor and application-current-focus delivery, and each of Command, Shift, Control, Option, Fn, and the corresponding application-route final validation. The injected modifier sampler flips only after the earlier empty stabilization sample and before binding-specific final validation. Epochs remain unchanged. The oracle requires a pre-submission `.deliveryFailed` result, zero Unicode backend posts, and zero alternate output calls.

Command:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-r1-r3-finaltext -parallel-testing-enabled NO -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests test
```

Receipt: `/tmp/issue40-v4-r1-r3-finaltext/Logs/Test/Test-FeishuSpeech-2026.08.23_22-34-31-+0800.xcresult`

Result: `Executed 32 tests, with 20 failures (0 unexpected)`.

Failure signature (all 10 route/modifier combinations):

```text
FinalTextOutputSecurityTests.test_v4BindingSpecificFinalValidationModifierTransitionIsPreBoundaryForExactAndApplicationRoutes
XCTAssertEqual failed: ("deliveryUncertain") is not equal to ("deliveryFailed")
XCTAssertEqual failed: ("[keyDown, keyUp]") is not equal to ("[]")
```

This is the required RED: current production crosses the Unicode submission boundary after a modifier transition that the oracle requires to remain pre-boundary.

## R3 executable hook oracle

The former source-string checks were replaced by executable tests in `FinalTextOutputSecurityTests.swift`:

- `test_v4ReviewUnicodePairHooksAreExecutablePhaseAndPIDOracles`
- `test_v4ReviewUnicodePairCancellationBeforeAndAfterBoundaryIsPhaseAware`

They invoke the real `SystemFinalTextCurrentFocusEventPoster` with an injected event backend and `ReviewUnicodePosterHooks`, and assert phase plus captured PID. Before-down/after-down/before-up/after-up/postflight scenarios require the exact failure/result class and no pre-boundary posts; after the down boundary they require one down and the mandatory up, with `.submittedUnverified(.uncertain)` rather than a pre-boundary cancellation/failure. The tests executed in the same 32-test run; the R3 hook cases passed, while the separate R1 cases supplied the 20 RED failures above.

## R2 skip removal and migration accounting

The `retiredCompatibilityOutputTests` set and `setUpWithError` blanket skip were removed. The pre-migration no-skip run proved the tests were real: 103 tests executed with 173 failures, mostly obsolete direct AX/append expectations.

Command and receipt:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-r2-streaming -parallel-testing-enabled NO -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test
```

`/tmp/issue40-v4-r2-streaming/Logs/Test/Test-FeishuSpeech-2026.08.23_22-34-52-+0800.xcresult`

```text
Executed 103 tests, with 173 failures (0 unexpected)
```

After migration, the full class still ran all 103 tests. The final bounded run before this receipt was:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-r2-streaming-f -parallel-testing-enabled NO -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test
```

`/tmp/issue40-v4-r2-streaming-f/Logs/Test/Test-FeishuSpeech-2026.08.23_22-57-51-+0800.xcresult`

```text
Executed 103 tests, with 2 failures (0 unexpected)
```

The two failures were then isolated after the final test migration:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-r2-followup -parallel-testing-enabled NO -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_recoverableMidStreamFailureReplaysJournalThenResumesSameGeneration -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_postReleaseDrainExpiryMapsUncertainKeyboardDeliveryToProvisionalPreserved test
```

`/tmp/issue40-v4-r2-followup/Logs/Test/Test-FeishuSpeech-2026.08.23_22-59-02-+0800.xcresult`

```text
Executed 2 tests, with 1 failure (0 unexpected)
StreamingMainViewModelTests.test_recoverableMidStreamFailureReplaysJournalThenResumesSameGeneration — passed
StreamingMainViewModelTests.test_postReleaseDrainExpiryMapsUncertainKeyboardDeliveryToProvisionalPreserved — XCTAssertFalse failed at StreamingMainViewModelTests.swift:1953
```

The remaining failure is retained as a product-facing drain-expiry oracle: after the retained preview and release barrier, the current implementation still records an error state where the v4 durable editable-draft path requires non-error review presentation. It was not weakened or converted into a passing assertion.

All migrated direct-output expectations now assert review-surface previews where observable and zero append/AX/Unicode/keyboard/copy output. Append-session/factory fixtures remain only as inert injected doubles; MainViewModel is asserted not to call them. Capture/recognition/retry/journal/drain/barrier/cancellation/reset/terminal assertions remain active.

### Explicit 51-method accounting

All 51 names formerly in the skip set now execute in the 103-test class. The mapping below records the active replacement oracle for each method:

1. `test_appendFactoryMissPreservesNoOutputAcrossSealedRecovery` — factory inert; preview and zero output.
2. `test_appendNoUsableTerminalTextAfterSealedRecoveryClosesOwnerWithFeedback` — recognition/recovery/barrier active; review-only completion and zero output.
3. `test_appendPreservationFinalOutcomesPublishOneTranscriptFreeCompletion` — outcome matrix active; no overlay/direct output.
4. `test_appendSecurityRejectionTerminatesImmediatelyWithFixedSecurityError` — capture/stream/seal active; preview and zero output.
5. `test_autoInsertFalseCreatesNoAppendSessionAndSuccessfulAXRebindDoesNotUseIt` — both settings paths active; no append factory or AX writes.
6. `test_axOwnerDriftBeforeDifferingActionTwoPreservesPartialAndPublishesNonSuccess` — captured authority drift active; retained preview and zero output.
7. `test_contentlessUpdatePreservesOwnerAcrossSealedRecoveryAndAuthoritativeFinal` — contentless/recovery topology active; preview-only.
8. `test_delayedFactoryReadySendsJournalIndexZeroThenLiveTailWithoutReowningHistory` — delayed factory/journal replay active; preview-only.
9. `test_disjointLivePacketResponsesOfferCompleteSnapshotsWhileFnRemainsHeld` — live packet ordering active; preview-only.
10. `test_distinctLivePacketIndicesOfferOnlyChangedCompleteSnapshots` — snapshot/index suppression active; preview-only.
11. `test_emptyFinalAndStreamFailurePreserveVerifiedPartial` — empty-final/failure path active; zero output.
12. `test_emptyFinalNeverCreatesFinalOnlyOutputAndClosesOwnerWithHeldSnapshot` — empty-final path active; no append finalization.
13. `test_equalTextOnDistinctLivePacketIndicesIsOwnedButOfferedOnce` — duplicate snapshot suppression active; preview-only.
14. `test_failedUnboundRebindIsAttemptedOnceAndAutoInsertFalseDoesNotRebind` — legacy rebind expectation migrated to one review capture.
15. `test_finishReadyAtDrainDeadlineCannotReplaceCommittedPartialBeforeExpiryTaskRuns` — drain deadline active; review-only state.
16. `test_firstPartialFinalOnlyRebindArmsAppendAndCommitsAuthoritativeFinal` — old rebind/append migrated to captured review destination and preview.
17. `test_firstPartialSecureRebindRevokesPrearmedOwnerWithoutAppendOrFallbackOutput` — secure fixture remains active; no provisional owner/output.
18. `test_hangingFactoryTimesOutAsRecoverableAndSuccessorLeavesSilentActiveState` — factory timeout/successor active; preview-only.
19. `test_hotKeyFailureDuringHeldSealingRevokesAppendWriterAndCancelsTransportBeforeBarrier` — hot-key failure, cancellation, and recorder barrier active; append inert.
20. `test_ineligibleEventsNeverAdvanceTheLatestSnapshot` — content/unsafe packet admission active; preview plus zero Unicode output.
21. `test_ineligiblePacketStillReservesItsIndexAgainstChangedHistoricalReplay` — replay index reservation active; preview plus zero append.
22. `test_initialAndReboundFinalOnlyAttemptOrUncertaintyNeverCopiesOrResendsFullText` — terminal outcome matrix active; no copy/retry/retarget.
23. `test_initialAndReboundUnsafeFinalUsesPrearmedOwnerWithoutPostingOrCopying` — unsafe text path active; zero output.
24. `test_initialFinalOnlyArmsAppendAndCommitsEqualAuthoritativeFinalWithoutDuplicateOutput` — migrated to one preview and no append.
25. `test_initialFinalOnlyFocusedElementDriftFailsClosedWithoutAppendOrRecoveryOutput` — drift/security oracle active; zero output.
26. `test_initialFinalOnlyResetInvalidatesOwnerBeforeLateCallbacks` — reset/generation fence active; no late output.
27. `test_initialFinalOnlyRetryKeepsCapturedOwnershipAtChangedReplaySnapshot` — retry/replay ownership active; preview-only.
28. `test_initialFinalOnlyTerminalFinalizeOccursOnceAndPostCleanupCallbacksStaySuppressed` — terminal admission active; no append finalization.
29. `test_liveAXOwnerReceivesEachCompleteSnapshotForDisjointPacketResponses` — live capture/recognition active; review previews and zero AX.
30. `test_liveModeOffersHeldSnapshotThenCommitsAuthoritativeFinalOnCapturedElement` — held/final snapshots active; review capture and zero AX.
31. `test_noOwnerCompletionRemainsSilentWhileEmptyHeldOwnerPublishesBoundedFeedback` — empty-final topology active; no legacy overlay output.
32. `test_postReleaseDrainExpiryMapsUncertainKeyboardDeliveryToProvisionalPreserved` — drain-expiry oracle active; remaining RED recorded above.
33. `test_postReleaseDrainExpiryPreservesOutputAndSuppressesLatePacketCompletion` — drain expiry/late callback suppression active; review-only.
34. `test_recoverableFinishAfterSealRetriesJournalAndAcceptsSuccessorFinal` — sealed retry/journal active; no direct output.
35. `test_recoverableMidStreamFailureReplaysJournalThenResumesSameGeneration` — live retry/journal/generation active; follow-up passed.
36. `test_releaseActionTwoUsesPrearmedOwnerForTerminalOnlyAndOwnedSnapshotReplacement` — release/action-two migrated to final preview; no Unicode replacement.
37. `test_releaseDrainsInFlightPacketThenAppliesAuthoritativeFinalOnAXRoute` — recorder/transport drain and final preview active; no AX.
38. `test_releaseDuringRecoverableBackoffReplaysCapturedPacketAndFinishesSuccessor` — backoff/replay active; preview-only.
39. `test_releaseDuringRetryBackoffAdmitsSuccessorAndFinishesCapturedJournal` — retry admission/barrier active; no direct output.
40. `test_releaseFinalizesKeyboardReplacementWithAuthoritativeActionTwoTextExactlyOnce` — action-two path migrated to review draft and zero output.
41. `test_releaseKeepsTerminalAdmissionOpenThenSuppressesPostCleanupCallbacks` — terminal admission/stale callback oracle active.
42. `test_repeatedRecoverableSessionFactoryFailuresBackOffWithoutEarlyError` — factory retry/backoff active; preview-only.
43. `test_resetDuringHeldSealingRevokesLiveWriterAndCancelsTransportBeforeRecorderBarrier` — reset/barrier/cancel active; no append.
44. `test_retryOwnsOnlyThePreviouslyFailedJournalIndexAndNeverReownsHistory` — journal ownership active; preview-only.
45. `test_retryReplaySuppressesHistoricalPacketsAndReconcilesFirstNewSnapshotOnce` — historical replay suppression active; preview-only.
46. `test_staleReleaseDoesNotWriteWhileEmptyFinalPublishesTranscriptFreeFeedback` — stale release/empty final active; no target mutation.
47. `test_successfulPacketAfterRepeatedBackend10024ResetsRetryBackoffStreak` — backend retry streak active; preview-only.
48. `test_trulyUnboundModeOffersChangedCompleteSnapshotsBeforeRelease` — unbound snapshot progression active; preview-only.
49. `test_unboundAuthoritativeFinalUsesExistingOwnerWhileEmptyFinalPreservesSnapshot` — final/empty-final active; no append finalization.
50. `test_unboundFirstPartialRebindsOnceAndCommitsAuthoritativeFinalOnSameBinding` — legacy rebind migrated to one review capture and retained preview.
51. `test_unboundRetryKeepsOwnershipAndPublishesOnlyChangedReplaySnapshot` — retry/replay ownership active; preview-only.

## Validation

```text
git diff --check -- FeishuSpeechTests/FinalTextOutputSecurityTests.swift FeishuSpeechTests/StreamingMainViewModelTests.swift
```

Result: clean.

This receipt is intentionally RED against the stated baseline. It is not a claim that the production implementation is complete.
