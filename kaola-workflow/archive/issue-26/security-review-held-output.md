# Issue 26 held-output security and privacy review

Date: 2026-08-03

result: PASS
verdict: pass
findings_blocking: 0
finding: id=R1 scope=in_scope action=none status=resolved severity=medium fix_role=security rationale=complete-pair-is-constructed-before-either-pid-post
finding: id=R2 scope=in_scope action=none status=resolved severity=medium fix_role=security rationale=final-secure-input-sample-now-immediately-precedes-first-post
finding: id=R3 scope=in_scope action=none status=resolved severity=medium fix_role=security rationale=unsafe-zero-post-recovery-now-revalidates-and-closes-before-copy

## Scope and evidence

Completed a final review of the entire current seven-file working-tree diff, every changed
production file and test in context, the unchanged AX security implementation, the issue evidence
under `kaola-workflow/issue-26/`, and the latest RED/GREEN records under
`/private/tmp/issue26-held-output-r3-*`.

The supplied final validation reports:

- four targeted R2/R3 security tests passed with zero failures;
- all 94 focused `FinalTextOutputSecurityTests`, `CurrentFocusAppendSessionTests`, and
  `StreamingMainViewModelTests` passed with zero failures;
- owned-file SwiftLint passed with zero violations;
- `git diff --check` passed.

No application was launched by this review, no Fn input was simulated, and no credential,
transcript, focused-control content, or clipboard content was inspected.

## R1 resolution - Atomic private Unicode event pair

Status: RESOLVED

Resolution anchors: `FeishuSpeech/Services/TextInputSimulator.swift:233-254` and
`FeishuSpeechTests/FinalTextOutputSecurityTests.swift:131-191`.

The production poster creates one `.privateState` event source and constructs both key-down and
key-up events from that identical source before either event can be posted. Both events carry the
same UTF-16 payload, explicit empty flags, and the same positive bound PID. Source, key-down, or
key-up construction failure returns `.deliveryFailed` with zero PID posts. Once posting begins,
key-down is immediately followed by the already constructed key-up, with no fallible construction
or security gate between the pair.

The deterministic seam proves source identity, construction order, down/up order, payload, flags,
PID, and zero-post behavior for every construction failure. The prior one-sided event defect remains
closed.

## R2 resolution - Last-moment Secure Input gate

Status: RESOLVED

Resolution anchors: `FeishuSpeech/Services/TextInputSimulator.swift:233-253` and
`FeishuSpeechTests/FinalTextOutputSecurityTests.swift:131-158,194-218`.

The poster now performs all inert source/down/up construction first, then queries the injected live
Secure Input provider at line 249 immediately before the first PID post. An affirmative sample
returns `.securityRejected` and discards the complete pair without posting either event. No sample
is placed between key-down and key-up, so the security gate cannot split the pair.

The new ordered trace proves the production sequence:

```text
source -> construct-down -> construct-up -> secure -> post-down -> post-up
```

The transition test enables Secure Input from the key-up construction hook and proves that the
final sample observes it after construction, returns `.securityRejected`, and records zero posts.

## R3 resolution - Unsafe zero-post manual recovery

Status: RESOLVED

Resolution anchors: `FeishuSpeech/ViewModels/MainViewModel.swift:1113-1151,1239-1257`,
`FeishuSpeech/Services/CurrentFocusAppendSession.swift:62-87,476-482`, and
`FeishuSpeechTests/StreamingMainViewModelTests.swift:1973-2135`.

Manual clipboard recovery remains eligible only for a captured final-only session whose observed
append outcomes prove zero poster attempts and whose retained text is non-contentless but unsafe for
automatic insertion. Inserted/appended, duplicate, revision, destination-loss, security-rejection,
delivery-uncertain, and stale outcomes all close eligibility. Unbound append sessions never receive
captured recovery eligibility.

Before recovery can copy, the coordinator now:

1. changes eligibility to `.unavailable`, making the decision one-shot even if validation fails;
2. requires the original retained `finalOnlyDestination` token;
3. queries the system append factory's live Secure Input provider;
4. requires the captured token's current security state to remain affirmatively safe;
5. requires the original PID to remain frontmost; and
6. requires the currently focused AX element to be exactly `CFEqual` to the captured element.

Only `.valid` reaches `copyForManualRecovery`. Security activation, secure or unverifiable token,
PID loss, exact-element drift, or AX query failure closes eligibility with no clipboard write. The
append owner remains exclusive, so a failed recovery validation cannot fall through to Unicode,
Cmd+V, current-focus one-shot output, another destination, or a second recovery attempt.

The production-path tests cover both initial and rebound final-only routes. They prove one fixed,
transcript-free copy for the stable safe zero-post case and zero Unicode posts, zero Cmd+V/current-
focus output, zero clipboard copy, and no manual-copy feedback across focused-element drift, live
Secure Input, secure token, unverifiable token, frontmost-PID loss, and AX query failure. Existing
tests also retain no-copy behavior after provisional attempts, delivery uncertainty, security or
destination outcomes, retry/replay, reset, and post-seal callbacks.

## Other reviewed security and privacy controls

- Captured production append sessions retain the supplied immutable PID and validate live Secure
  Input, frontmost PID, captured token security, and exact AX element twice before and once after
  every Unicode post.
- App activation away permanently suspends the append session. Returning to the same app cannot
  reopen output.
- The physically held Fn and ambient modifiers are isolated by the private source and explicit empty
  event flags.
- C0, C1, and DEL-bearing values never become automatic Unicode events. Contentless values do not
  create an output attempt.
- Once an append session has attempted delivery or become uncertain, it remains the exclusive owner;
  finalization cannot fall through to a full resend, Cmd+V, current-focus output, or clipboard copy.
- `sealStarted`, generation identity, retry admission, replay frontier, reset, and lifecycle
  invalidation prevent late callbacks from opening or replacing an output owner.
- New production logs, enum descriptions, and visible statuses remain fixed and transcript-free. No
  new secret, credential, token, app/window title, AX content, clipboard content, or audio logging
  was introduced.
- No dependency, entitlement, permission, authentication, network, filesystem, serialization, or
  public API surface changed in this candidate.

## Residuals and installed-UAT boundary

`CGEventPostToPid` has no target-control acknowledgement. `.posted` means the complete pair was
submitted, not that the target accepted or displayed the Unicode payload. Installed owner UAT is
still required before claiming visible held-output compatibility; a target that ignores the pair
must remain a PARTIAL product outcome without retry, global HID posting, destructive editing, or
clipboard fallback after uncertainty.

PID and exact AX element checks cannot atomically bind a CoreGraphics event to a caret. The caret can
move within the same AX element, or focus can change in the irreducible interval after the final
sample and before target handling. Postflight validation permanently suspends later output but
cannot retract an already submitted pair. This residual is explicitly contained by no retry,
no alternate target, no full resend, and neutral transcript-free uncertainty feedback.

review_conclusion: The final candidate closes all admitted security and privacy findings while preserving atomic paired posting, exact captured ownership, fail-closed uncertainty, and transcript-free recovery behavior.
