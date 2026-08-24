# Issue #40 v4 Final Correctness Review

- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
- Baseline: `4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a`
- Scope: repaired final uncommitted v4 production, tests, and documentation

## Verdict

FAIL. The repaired candidate closes prior R1, R2, and R3, but the new drain-expiry repair admits a high-severity confirmation-authority bypass: a partial preview can become the ordinary send-enabled `.editable` state after the recorder barrier and drain timeout even though recognition never completed action 2. A real Send/Return gesture can then reach the sole delivery call. This violates the supplied final-action2-plus-recorder-barrier boundary.

finding: id=R4 scope=in_scope action=fix status=open severity=high fix_role=implementer rationale=drain-expiry-authorizes-confirmation-without-action2

### R4 - Drain expiry creates send authority without final action 2

- Failure class: state-machine authority bypass / premature external-output admission.
- Trigger: an accepted Fn interaction receives a safe nonempty partial snapshot, Fn is released, the recorder barrier completes, but the recognition session never returns authoritative action 2 before the bounded drain expires. The user then clicks the real Send button or presses a qualified Return/Enter in the provisional draft installed by the expiry branch.
- Expected: the latest partial may be retained durably, but no confirmation callback may reach delivery until authoritative action 2 and the recorder barrier have both settled. The v4 blueprint explicitly requires external output to begin only from the current explicit `onConfirm` callback after those two facts and requires `.editable` confirmation authority to have been installed by that transition (`architecture-blueprint-v4.md:60-73`, `:238-247`).
- Observed: `expirePostReleaseDrain` snapshots the partial after the timeout, invalidates the active recognition identity, and calls `presentProvisionalReviewDraft` (`FeishuSpeech/ViewModels/MainViewModel.swift:2272-2312`). That helper stores the partial as the authority draft, sets the ordinary `.editable` state, and calls `installEditableReviewSurface` (`:2335-2367`). The installed callback invokes `handleReviewConfirmation` (`:1809-1837`), whose guards prove only current review ID/revision, `.editable`, a draft, and no in-flight confirmation; it carries no action-2-settled provenance and therefore calls the sole `reviewDestinationDelivery.deliver` site (`:1950-2013`). A real UI intent consequently authorizes one external submission attempt even though recognition did not finish.
- Reproducible scenario: extend `test_postReleaseDrainExpiryMapsUncertainKeyboardDeliveryToProvisionalPreserved` with its existing noncooperative session and short drain timeout. After `activeSessionIdentityForTesting` becomes nil, call the fake presenter's real-button `invokeConfirm()` and settle. The current path appends the partial to `CoordinatorReviewDestinationDelivery.deliveredTexts`; that fake records every delivery at `FeishuSpeechTests/StreamingMainViewModelTests.swift:4715-4720`. The existing test stops after asserting immediate zero legacy output and never invokes the installed confirmation callback (`FeishuSpeechTests/StreamingMainViewModelTests.swift:1900-1959`), so the full GREEN matrix does not detect the bypass.
- Why existing guards do not prevent it: the opaque intent correctly proves a real Send/Return gesture, but it does not prove action 2. `presentProvisionalReviewDraft` constructs the same authority shape and state used by the valid action-2 transition, and `handleReviewConfirmation` has no terminal-recognition predicate to distinguish them. Generation invalidation at expiry suppresses late recognition callbacks but does not revoke the retained review authority.
- Secondary contract inconsistency: the same repair rejects an otherwise review-safe multiline partial solely because it contains LF (`FeishuSpeech/ViewModels/MainViewModel.swift:2342-2345`; `FeishuSpeechTests/StreamingMainViewModelTests.swift:1840-1892`). The shared classifier intentionally admits LF as inert multiline data (`FeishuSpeech/Services/TextInputSimulator.swift:1200-1208`), and the current v4 authority says exact LF-delimited drafts are preserved (`docs/decisions/D-40-01.md:123-128`; `docs/streaming-speech-design.md:603-615`). `CHANGELOG.md:8` says LF remains data while `CHANGELOG.md:10` calls it unsafe for this new branch. This is further evidence that the repair invented an ad hoc terminal/confirmation contract rather than preserving the designed action-2 transition.
- Minimal repair boundary: retain and display the last partial at drain expiry without installing the normal confirm-capable `.editable` callbacks or calling delivery; keep it as a durable non-authoritative draft/read-only recovery surface until an explicitly designed terminal authority exists. Do not silently treat LF as unsafe review data. Add an executable drain-expiry test that invokes the real Send and qualified Return seams and proves zero `ReviewDestinationDelivering.deliver` calls when action 2 never settled, plus a multiline retention oracle. Do not change the independent capture-drain or recognition-consumer roots.

## Prior finding closure

### R1 resolved - final validation is outside the epoch lock

Binding-specific exact/application validation now completes before `performFinalPair` enters the activation-then-input critical section (`FeishuSpeech/Services/TextInputSimulator.swift:232-263`, `:285-309`; `FeishuSpeech/Services/ReviewDestinationDelivery.swift:632-667`). Inside the short gate, production immediately rechecks both epochs, drift observations, and Command/Shift/Control/Option/Fn/Caps Lock before calling the already-prepared pair; only the mandatory down/up pair is inside (`FeishuSpeech/Services/ReviewDestinationDelivery.swift:369-409`). The executable exact/application matrix changes Command, Shift, Control, Option, and Fn during binding-specific validation and proves `.deliveryFailed`, zero posts, and only pair construction (`FeishuSpeechTests/FinalTextOutputSecurityTests.swift:735-828`). The supplied final receipt records all 32 security tests passing.

### R2 resolved - all 51 formerly skipped async tests execute

The `retiredCompatibilityOutputTests` set and `setUpWithError` skip are absent. Independent name accounting found all 51 former entries still present as executable methods in the current 103-method class, with zero missing. Their unique async oracles remain live: retry/journal replay and packet ordering are asserted at `FeishuSpeechTests/StreamingMainViewModelTests.swift:935-990`; repeated factory backoff at `:992-1023`; release during retry and action-2 finishing at `:1050-1085`; and successful-packet reset of the 250 ms, 500 ms, 250 ms sequence at `:1584-1637`. The supplied final receipt records 103/103 Streaming tests and 263/263 focused tests with zero skips.

### R3 resolved - phase and cancellation behavior is executable

The tests now construct the real poster with injected hooks and assert exact posted phases and captured PID for before-down, after-down, before-up, after-up, and postflight (`FeishuSpeechTests/FinalTextOutputSecurityTests.swift:601-676`). Separate executable cancellation cases prove zero events before the boundary and mandatory down/up with submitted-unverified uncertainty after the boundary (`:678-733`). Production attempts key-up unconditionally after down and maps every later fault/cancellation to uncertainty (`FeishuSpeech/Services/TextInputSimulator.swift:841-880`).

## Additional checks

- Product search found no `NSPasteboard`, general-pasteboard read/write/snapshot/restore, Cmd+V, or virtual-key V path in `FeishuSpeech`. The accepted review output primitive remains the tagged, fixed-PID Unicode pair.
- `ReviewConfirmationIntent` is constructed only at the visible Send action and qualified native Return handler (`FeishuSpeech/Views/TranscriptionReviewView.swift:242-247`, `:347-370`). Outside R4's missing action-2 provenance, the normal coordinator has one delivery call and freezes one draft per explicit attempt.
- The protected audio recorder, ingress, journal, streaming session/provider, keep-alive socket, and transport files are byte-identical to baseline. `MainViewModel` still launches separate capture-drain and recognition-consumer tasks, and normal action 2 still awaits the recorder barrier before publishing `.editable`.
- `git diff --check` passed. Per the reviewer contract, the expensive test suite was not repeated after admitting R4; the supplied final receipt reports 482 tests passed with one unrelated live-TCP environmental skip.

verdict: fail
findings_blocking: 1
review_conclusion: Prior race and coverage defects are resolved, but drain expiry currently grants explicit delivery authority before authoritative recognition completion and therefore cannot pass final correctness review.
