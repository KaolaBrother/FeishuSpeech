# Issue 40 code review

behavior_contract_version: 3
behavior_contract_hash: 308d49af0d19404ba0d50e28cee64b570df0a647c93f6b6f3636c3853835dfc7
resolved_profile_hash: 562154a00287ceaea5d950076aceca878134b4b32ebf5765d01da2f5c76701f4
candidate_baseline: 98e1eb53b6aaee369f6481303a289ca60b843262
candidate_scope: Issue 40 production and test working-tree diff

finding: id=R1 scope=in_scope action=none status=resolved severity=medium fix_role=implementer rationale=two-complete-composite-samples-now-close-the-security-window

## R1 closure - Fallback preflight now takes two complete composite samples

- Prior trigger: confirm an `applicationCurrentFocus` review destination while Secure Input becomes enabled inside either preflight identity window.
- Repair: `FeishuSpeech/Services/ReviewDestinationDelivery.swift:489-500` owns exactly two consecutive preflight iterations. Each iteration at `FeishuSpeech/Services/ReviewDestinationDelivery.swift:508-543` reads Secure Input at start, the raw frontmost PID, the captured PID's running complete identity, the frontmost complete identity, and Secure Input at end, in that order.
- Fixed target: `FeishuSpeech/Services/ReviewDestinationDelivery.swift:379-390` passes only `destination.application.processIdentifier` to the review paste primitive. `FeishuSpeech/Services/TextInputSimulator.swift:254-281` performs one pasteboard transaction and one Cmd+V attempt to that supplied PID; it contains no ambient PID discovery or retry.
- Exact call count: `FeishuSpeech/Services/TextInputSimulator.swift:241-250` invokes the typed preflight validator once and passes only its cached result into the shared paste transaction. The transaction does not repeat the destination sampling.
- Fail-closed proof: if Secure Input turns on while either iteration is reading identities, that iteration's ending read returns `.securityRejected`; both fixed-cardinality iterations finish, but the accumulated failure prevents snapshot, pasteboard write, and key posting. The strengthened oracle at `FeishuSpeechTests/ReviewFirstApplicationFallbackTests.swift:307-425` records the exact two-composite order and proves zero snapshot/write/Cmd+V when Secure Input changes during the second identity window. The same loop body covers the first window without a separate branch.
- Postflight: `FeishuSpeech/Services/ReviewDestinationDelivery.swift:502-505` runs one equivalent complete composite after the possible post. Any non-valid result is mapped to `.deliveryUncertain` at `FeishuSpeech/Services/TextInputSimulator.swift:269-275`, with no retry and no restore scheduling.
- Status: resolved. The original split-sample trigger is no longer reachable in the repair delta.

## Reviewed surfaces

- Typed AX capture rejects lost trust and affirmative secure input, and rechecks trust/security after ordinary capability misses.
- Composite capture binds and revalidates the complete original application identity before panel/audio/provider startup, and exact cursor binding remains preferred.
- Confirmation continues to freeze the untrimmed multiline draft synchronously, consume authority, dismiss before the first await, and route current failures through one manual recovery copy.
- The fallback uses the captured PID for one Cmd+V transaction, performs no AX recapture, and treats post/postflight uncertainty as terminal without retry or restore.
- Compatibility current-focus Unicode output and the capture/journal plus recognition/retry/replay topology are unchanged by the candidate production diff.
- Cancellation and stale review callbacks remain fenced by task cancellation, review identifier, revision, authority, and confirmation state.

## Validation receipt

- Re-read the R1 repair in both production files, the strengthened test, the updated 79-test GREEN evidence, the prior finding frontier, and relevant exact, compatibility, async, cancellation, and recovery callers.
- `git diff --check` passed.
- Protected capture, journal, recognition, retry, replay, review-window, overlay, and append-session production paths have no diff.
- The updated serialized focused GREEN evidence reports 79 selected tests passed with zero failures.
- A fresh focused run of `ReviewFirstApplicationFallbackTests.test_applicationBoundFallback_preflightUsesTwoOrderedCompositeSamples_andRejectsSecureTransitionBeforeMutation` passed with one test and zero failures.
- No new defect anchored to the R1 repair delta was admitted.

verdict: pass
findings_blocking: 0
review_conclusion: R1 is resolved, the strengthened security oracle passes, and the reviewed Issue 40 behavioral diff has no remaining admitted defect.
