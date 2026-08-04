# Issue #26 held-output code review closure

## Outcome

**PASS** - the full seven-file candidate has no admitted defects. Prior findings R1 through R4 are resolved.

finding: id=R1 scope=in_scope action=none status=resolved severity=low fix_role=implementer rationale=complete-pair-is-constructed-before-either-post

### R1 resolution - Isolated key-up is prevented

The poster creates one private-state source and constructs key-down and key-up from that same source before either event can be posted. Failure to create the source or either event returns `.deliveryFailed` with zero posts. Tests cover every construction failure and verify the shared source, identical UTF-16 payload, empty flags, bound PID, and down-then-up ordering.

finding: id=R2 scope=in_scope action=none status=resolved severity=medium fix_role=implementer rationale=validated-unsafe-zero-post-text-copies-exactly-once

### R2 resolution - Safe zero-post manual recovery is restored

Initial and rebound captured routes start with `.capturedZeroPost` eligibility. Unsafe suppression preserves eligibility because it makes no post, while any post, duplicate, revision, destination loss, security rejection, delivery uncertainty, or stale result permanently removes it. An eligible unsafe retained value can therefore copy once only after the final captured validation succeeds; provisional ownership never falls through to an alternate full-text output.

finding: id=R3 scope=in_scope action=none status=resolved severity=medium fix_role=implementer rationale=final-secure-sample-follows-complete-pair-construction

### R3 resolution - Secure Input is sampled at the final pre-post boundary

`SystemFinalTextCurrentFocusEventPoster.postUnicodeText` now validates the input, constructs the private source and complete key-down/key-up pair, and only then samples the injected live Secure Input provider. A positive sample returns `.securityRejected` with zero posts. On success, the two `postUnicodeEvent` calls are adjacent and perform no intervening source or event construction and no additional security check. The production backend receives only handles it created itself, so its internal concrete-handle casts cannot fail on this path. The deterministic trace test proves `source -> construct-down -> construct-up -> secure -> post-down -> post-up`, and a construction hook that enables Secure Input at key-up construction proves zero posts.

finding: id=R4 scope=in_scope action=none status=resolved severity=medium fix_role=implementer rationale=zero-post-recovery-closes-then-revalidates-live-captured-target

### R4 resolution - Unsafe zero-post recovery revalidates the exact captured target

`recoverUnsafeCapturedTextIfEligible` permanently changes eligibility to `.unavailable` before any final validation or clipboard mutation. It then requires the retained `finalOnlyDestination` to pass `validateFinalOnlyDestination`, which checks the production factory's live Secure Input provider, the captured token's current security state, the exact retained PID, and `CFEqual` identity with the current focused AX element. Any secure state, unverifiable security, PID loss, focused-element drift, or accessibility query failure returns without copy and cannot later retry. Production-factory coordinator tests cover stable and failed validation for both initial and first-partial rebound routes.

## Held and release routing closure

- Initial `.finalOnly` capture arms the captured append owner during startup. Each eligible partial received while Fn remains held reaches `applyOpaqueHypothesis` in the same callback.
- First-partial rebound to `.finalOnly` arms the captured append owner and then applies that triggering partial before returning from `handlePartial`.
- Once sealing starts, nonterminal partial and final callbacks cannot apply more output. Release stops capture and terminal handling finalizes the existing owner exactly once; it is not the first-output trigger and does not duplicate the full text.
- Retry/replay ownership, auto-insert-disabled behavior, factory-miss final-only fallback, stale-generation invalidation, and no-fallback behavior after post attempt or uncertainty remain covered and consistent with the candidate contract.

## Verified surfaces

- Candidate diff: seven files, SHA-256 `2aecb470ddc5095eb5da014605f69b494e8a53b0b882618efde916ad7f670085`; `git diff --check` passed.
- Supplied post-repair GREEN record is time-bound after the latest source and test edits: 94 focused tests passed with zero failures under serial, coverage-disabled execution. The four direct R3/R4 tests also passed independently in that record.
- Supplied owned-file SwiftLint completed with zero violations and zero serious findings across the four changed production files.
- An independent clean-DerivedData rerun compiled and signed the current candidate successfully, but Xcode's test coordinator stalled before any test worker materialized and was interrupted after more than two minutes. The diagnostic showed a runner-materialization wait rather than a test case failure; no candidate defect is inferred from that infrastructure event.
- Static closure covered all changed production files, their injected backends and factories, coordinator callers, state cleanup, and every changed test file. No application interaction, Fn simulation, permission request, credential access, or product-file edit was performed by this review.

verdict: pass
findings_blocking: 0
review_conclusion: The complete candidate now satisfies atomic output, live security validation, captured recovery, and held-versus-release routing requirements.
