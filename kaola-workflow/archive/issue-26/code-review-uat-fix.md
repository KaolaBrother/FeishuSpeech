# Issue 26 cursor-gate UAT fix final closure review

## Scope

- Candidate: the complete current working-tree diff against `main` in `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`.
- Production: `CursorTextModels.swift`, `TextInputSimulator.swift`, and `MainViewModel.swift`.
- Regression coverage: `StreamingMainViewModelTests.swift` and `FinalTextOutputSecurityTests.swift`.
- Documentation: `README.md`, `CHANGELOG.md`, `docs/README.md`, `docs/api.md`, `docs/architecture.md`, `docs/decisions/D-25-01.md`, and `docs/streaming-speech-design.md`.
- Authoritative behavior: recording and transcription do not require AX cursor or focused-element confirmation; AX failure selects unbound final output; secure input, `autoInsert=false`, control-character handling, generation invalidation, stale callbacks, exactly-once delivery, transcript privacy, and existing captured bound modes remain intact.

## Prior finding closure

### R1 - Resolved - Current-focus delivery failure recovery

- prior_failure: the first candidate discarded `.deliveryFailed`, so an ordinary current-focus failure could silently lose the nonempty final without copy-only recovery or fixed feedback.
- repair: `FinalTextInsertionResult` now distinguishes `.securityRejected`; `routeCurrentFocusFinal` records the one attempt before calling the sink, treats `.inserted` and `.securityRejected` as terminal without recovery copy, and routes `.deliveryFailed` or `.destinationInvalid` through the established `copyForManualRecovery` path.
- proof: `SystemFinalTextOutput.insertAtCurrentFocusOnce` returns `.securityRejected` for sampled Secure Input and ordinary typed failures for unstable PID or event failure. Coordinator regressions prove one failed attempt, one recovery copy, fixed transcript-free feedback, and no duplicate attempt when a later terminal final arrives. A separate regression proves security rejection produces no insertion, synthetic-input count, or recovery copy.
- anchors: `FeishuSpeech/Models/CursorTextModels.swift:89-94`, `FeishuSpeech/Services/TextInputSimulator.swift:85-106`, `FeishuSpeech/ViewModels/MainViewModel.swift:517-536`, `FeishuSpeechTests/StreamingMainViewModelTests.swift:109-160`.

finding: id=R1 scope=in_scope action=none status=resolved severity=medium fix_role=implementer rationale=ordinary-current-focus-failures-now-recover-once-while-security-rejection-remains-copy-free

## Complete candidate result

No open in-scope findings remain above the admission threshold.

- AX capture exceptions and `.accessibilityUnavailable` both select unbound mode and allow capture plus streaming-provider startup. Affirmatively detected secure targets still stop before audio or network work.
- Unbound output accepts only safe, non-contentless finals with `autoInsert` enabled, makes at most one sink call per active generation, and clears its state on normal and abnormal termination. Existing active-identity checks continue to reject stale callbacks.
- Successful unbound delivery is clipboard-free direct Unicode. The sink samples Secure Input and the frontmost PID twice, rejects any secure sample, rejects missing or unstable PID, and performs one final Secure Input check immediately before posting.
- Ordinary unbound destination or event failures use one copy-only recovery with fixed transcript-free feedback. `.securityRejected` remains fail-closed with no pasteboard recovery. C0/C1, DEL, and whitespace-only handling remain unchanged.
- Captured live AX replacement and captured-PID pasteboard/Cmd+V final-only routing are unchanged apart from the additive typed result case; their pre/post destination and security validation remains in place.
- Candidate documentation matches the implementation and retains installed-Release credential and cross-application compatibility as explicit UAT gates rather than claiming universal target support.

## Final typed-poster delta

- `FinalTextCurrentFocusEventPosting` now returns the exhaustive typed result `.posted`, `.securityRejected`, or `.deliveryFailed` instead of a Boolean.
- `SystemFinalTextCurrentFocusEventPoster` classifies the live Secure Input check at the actual pre-post boundary as `.securityRejected`; event construction failure remains `.deliveryFailed`.
- `SystemFinalTextOutput.insertAtCurrentFocusOnce` maps those cases directly to `.inserted`, `.securityRejected`, and `.deliveryFailed`. It no longer performs a third ambient security sample that could misclassify the poster's exact rejection after state changed again.
- The updated oracle covers both poster-level security rejection and ordinary failure, verifies exact result preservation, verifies no extra security query, and confirms no bound-pasteboard or bound-event call.
- The delta is internal to the unbound event seam. It does not alter coordinator attempt accounting, recovery routing, captured live AX replacement, or captured-PID final-only delivery.

## Validation receipt

- Inspected the complete candidate diff, all changed files in context, callers, sinks, cleanup paths, and relevant bound/unbound regression suites.
- Supplied final lifecycle-free executable evidence: the complete suite passed 181 of 181.
- Independently ran `git diff --check main --`; it passed with no output.
- No application was launched, no macOS permission was requested, and no production, test, or documentation file was edited by this review.

verdict: pass
findings_blocking: 0
review_conclusion: PASS because the typed poster preserves exact security and ordinary failure outcomes, the prior output-loss finding remains resolved, and no final-delta regression is admitted.
