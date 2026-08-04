# Issue 27 test-contract migration 2

## Record

- Starting commit: `6066a72d94aee5ec6382027037cb3cabbb638d15`
- Test-only commit: `c067d2d` (`test: align coordinator with terminal drain contract`)
- Test artifact: `FeishuSpeechTests/StreamingMainViewModelTests.swift`
- Production files modified by the implementation agent were not touched or staged.

## Failure signature before migration

The pre-migration coordinator class executed 83 tests with 10 assertion failures in the eight tests below. Evidence: `/tmp/feishuspeech-issue27-migration2-before-xctest.log`.

Three tests timed out in `waitUntil` because they expected Fn-up to terminate immediately while the current coordinator correctly retained same-generation recovery authority. Other failures showed the prearmed owner, authoritative final, and explicit empty-final feedback that the old assertions rejected.

## Per-test migration

1. `test_appendFactoryMissPreservesNoOutputAcrossSealedRecovery`
   - Previous failure: timeout waiting for the coordinator to become idle after a recoverable finish failure.
   - Migration: provides a successful successor and proves the captured packet is replayed once before action 2 settles.
   - Preserved safety: the missing append factory never routes retained or authoritative text through one-shot output, clipboard, or synthetic input.
   - Result: passed.

2. `test_appendNoUsableTerminalTextAfterSealedRecoveryClosesOwnerWithFeedback`
   - Previous failure: timeout caused by repeatedly returning the same failing transport.
   - Migration: models a recoverable first attempt followed by a successor whose authoritative final is empty.
   - Preserved safety: the prearmed owner is finalized exactly once, replay does not duplicate its accepted text, no fallback output occurs, and feedback contains no transcript.
   - New observable contract: exactly one `.emptyFinalPreservedPartial` completion.
   - Result: passed.

3. `test_contentlessUpdatePreservesOwnerAcrossSealedRecoveryAndAuthoritativeFinal`
   - Previous failure: timeout plus expected `idle` while the coordinator correctly remained `sealing` during recovery.
   - Migration: proves contentless history cannot erase the last usable frontier; the captured journal is replayed, the changed recovered snapshot is admitted, and action 2 finalizes the one prearmed owner.
   - Preserved safety: no one-shot, clipboard, or current-focus fallback output.
   - Result: passed.

4. `test_firstPartialSecureRebindRevokesPrearmedOwnerWithoutAppendOrFallbackOutput`
   - Previous failure: expected zero append-factory calls but observed one.
   - Migration: requires the fixed-generation owner to be armed before the first response and invalidated exactly once when secure rebind is rejected.
   - Preserved safety: no hypothesis is posted, the security error is transcript-free, and no fallback or clipboard output occurs.
   - Result: passed.

5. `test_initialAndReboundUnsafeFinalUsesPrearmedOwnerWithoutPostingOrCopying`
   - Previous failure: rebound route expected zero finalizations but observed one.
   - Migration: both initial and rebound routes must close their prearmed, fixed-generation owner exactly once when authoritative action 2 arrives.
   - Preserved safety: unsafe control text produces zero post attempts, synthetic input, one-shot output, clipboard writes, and transcript-bearing feedback.
   - Result: passed.

6. `test_staleReleaseDoesNotWriteWhileEmptyFinalPublishesTranscriptFreeFeedback`
   - Previous failure: expected no completion but observed `.emptyFinalPreservedPartial`.
   - Migration: keeps stale destination loss silent and write-free while requiring explicit empty-final feedback for a verified partial.
   - Preserved safety: no copied text, no stale write, no error overlay, and no transcript in feedback.
   - Result: passed.

7. `test_noOwnerCompletionRemainsSilentWhileEmptyHeldOwnerPublishesBoundedFeedback`
   - Previous failures: both last and visible completion were expected nil but were `.emptyFinalPreservedPartial`.
   - Migration: distinguishes a truly unavailable owner, which remains silent, from an empty authoritative final after verified output, which publishes exactly one bounded completion.
   - Preserved safety: visible feedback remains transcript-free.
   - Result: passed.

8. `test_unboundFirstPartialRebindsOnceAndCommitsAuthoritativeFinalOnSameBinding`
   - Previous failure: expected the last partial (`revised frontier`) after release but observed the authoritative final (`final frontier`).
   - Migration: keeps all three live snapshots before Fn-up, then requires action 2 to replace the same owned range with the final text.
   - Preserved safety: capture count remains two total (initial attempt plus one rebind), proving no release-time recapture or destination switch; no current-focus fallback is used.
   - Result: passed.

## Validation

Build command:

`xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue27-migration2 build-for-testing`

Build result: `TEST BUILD SUCCEEDED`.

Focused execution command:

`xcrun xctest -XCTest FeishuSpeechTests.StreamingMainViewModelTests /tmp/feishuspeech-issue27-migration2/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest`

Focused result against current production: 83 tests executed, 0 failures, 0 unexpected.

Evidence:

- pre-migration failures: `/tmp/feishuspeech-issue27-migration2-before-xctest.log`
- post-migration build: `/tmp/feishuspeech-issue27-migration2-build2.log`
- post-migration focused execution: `/tmp/feishuspeech-issue27-migration2-green.log`

The test bundle was executed directly to avoid launching the application UI or requesting macOS permissions.
