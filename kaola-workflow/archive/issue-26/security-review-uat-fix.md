# Final security and privacy re-review: issue #26 cursor-gate UAT fix

Review date: 2026-08-03 (Asia/Shanghai)

Candidate: the final uncommitted issue #26 UAT-fix diff in
`/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`, based on
`c5d1dca`.

Accepted product constraint: when AX cursor/focused-element capture is unavailable, final output is
intentionally unbound and targets the current focus. This review does not require AX cursor or
focused-element confirmation and does not treat that accepted behavior itself as a candidate
defect.

Review constraints: static, read-only review of the final production, test, model, caller, and
documentation delta. The application and test host were not launched, no permission API was
invoked, and no production, test, or documentation file was edited. The supplied lifecycle-free
suite result is 181 passed out of 181 with zero failures; this review did not rerun it because
launching an app or test host was explicitly prohibited.

Verdict: **PASS**. No candidate-caused security or privacy defect remains open. R1, R2, and R3 are
closed. The deliberate unbound-current-focus timing boundary remains an accepted nonblocking
advisory.

## R1 closed - Current-focus delivery has proportionate security and stability gates within the accepted unbound contract

Failure class re-audited: output-target transition and sensitive transcript misdelivery.

The final candidate samples Secure Input and the frontmost PID twice, requires both PID samples to
match, and then calls a dedicated direct-Unicode poster. The concrete poster performs an immediate
third Secure Input check before posting one global text event. No partial response reaches this
path, and generation, `autoInsert`, content, control-character, and exactly-once gates all precede
the sink.

The user explicitly selected current-focus delivery without AX cursor/focused-element confirmation.
Within that product boundary, the candidate does not claim original-focus ownership and does not
silently substitute a stale captured process. The remaining last-sample timing boundary is recorded
as A1 rather than treated as a defect that would reverse the user's decision.

## R2 closed - Successful unbound delivery is clipboard-free and ordinary failure has explicit recovery

Failure class re-audited: shared-pasteboard transcript exposure and incomplete delivery handling.

`SystemFinalTextCurrentFocusEventPoster` encodes the final as UTF-16 on a `CGEvent` and does not read
or write `NSPasteboard.general`. `SystemFinalTextOutput.insertAtCurrentFocusOnce` does not call its
pasteboard dependency. The coordinator consumes the result once: `.inserted` completes without
clipboard mutation, ordinary `.deliveryFailed` or `.destinationInvalid` performs one deliberate
copy-only recovery with fixed transcript-free feedback, and `.securityRejected` performs neither
input nor copy.

Thus normal unbound delivery no longer destroys prior clipboard ownership or leaves a transcript
globally available. Clipboard use remains explicit recovery behavior rather than an implementation
side effect of automatic delivery.

## R3 closed - The concrete Secure Input decision now survives the poster boundary without resampling

Failure class re-audited: security-state TOCTOU and security-triggered clipboard exposure.

Primary anchors:

- `FeishuSpeech/Services/TextInputSimulator.swift:102-110`
- `FeishuSpeech/Services/TextInputSimulator.swift:128-136`
- `FeishuSpeech/Services/TextInputSimulator.swift:174-185`
- `FeishuSpeech/ViewModels/MainViewModel.swift:529-534`

`FinalTextCurrentFocusEventPosting.postUnicodeText` now returns the typed
`FinalTextCurrentFocusPostResult`. The concrete poster returns `.securityRejected` from the exact
immediate `IsSecureEventInputEnabled()` observation, while event construction failure returns
`.deliveryFailed`. `SystemFinalTextOutput` maps those values directly to
`FinalTextInsertionResult` and performs no ambient security resample to infer the cause.

The coordinator already treats `.securityRejected` as zero input and zero clipboard mutation, so a
transient security state cannot be downgraded after the poster returns. Focused tests cover direct
mapping of both poster results, prove that the secure result causes no additional state query, and
separately prove the coordinator's no-copy security branch.

## Accepted advisory - Residual current-focus timing boundary

Direct current-focus delivery cannot atomically bind the last Secure Input/PID samples to the
control that consumes a globally posted event. Focus or Secure Input may change after the concrete
guard and before event routing. Requiring an AX element token would remove the unbound behavior the
user explicitly selected, while targeting the sampled PID would change the meaning from current
frontmost focus to a potentially stale process. This residual is therefore an accepted product
constraint, not a candidate blocker. The repeated live samples, PID stability check,
control-character filter, one-event limit, typed security rejection, and zero-pasteboard successful
path are proportionate mitigations within that constraint.

## Other reviewed surfaces without an admitted candidate finding

- Control characters: C0, DEL, and C1 scalars cannot reach direct Unicode delivery; they take one
  explicit copy-only recovery path with fixed transcript-free feedback.
- Generation and exactly-once state: stale callbacks fail the active identity gate, and
  `deliveredCurrentFocusFinal` is set before the single sink attempt and cleared on normal or
  abnormal teardown.
- Settings: both fallback configuration and final routing preserve `autoInsert=false` as zero
  target and zero pasteboard mutation.
- Security activation observed by `PermissionManager` invalidates the active generation before
  asynchronous recorder and transport cleanup.
- Logs and UI surfaces contain only fixed state/capability text; no transcript, clipboard payload,
  token, credential, stream ID, or raw audio was added to logging or visible status.
- Successful unbound delivery neither reads nor writes `NSPasteboard.general`. Security rejection
  is distinct from ordinary failure through both output layers and reaches no recovery copy.
- No prompt API, dependency, user-controlled URL, shell sink, deserialization surface, or secret
  material was added. `git diff --check` passes.

finding: id=A1 scope=user_decision action=accept status=accepted severity=low fix_role=none rationale=unbound-current-focus-routing-retains-an-unavoidable-last-sample-race
verdict: pass
findings_blocking: 0
review_conclusion: The typed poster result closes the final security-state race, leaving no candidate-caused security or privacy blocker under the accepted current-focus contract.
