# Issue #27 security and privacy review

candidate: 26825b829cd654f46a445b0505d82b165dc27e40..62832ad28ce13c8fa31320cfe194da0df9610cac
surface: release drain authority, output ownership, input safety gates, stale result suppression, cleanup, diagnostics, and migrated tests

## Verdict

PASS. No candidate-caused P0, P1, P2, or P3 security or privacy finding was admitted.

The post-release authority remains generation-scoped and cannot select a new output target. `beginSealing` closes capture without invoking either cursor-capture path, and `prepareContinuousOutputIfNeeded` expressly refuses its one pre-release rebind once `captureClosed` is true (`FeishuSpeech/ViewModels/MainViewModel.swift:1654-1660`, `1826-1860`). The AX route continues using the original destination token and revalidates frontmost PID, focused element, selection or caret, owned range text, and security state around replacement (`FeishuSpeech/Services/CursorTextSession.swift:79-193`, `210-216`). The keyboard route continues using the PID captured when its generation owner was armed (`FeishuSpeech/ViewModels/MainViewModel.swift:590-604`, `1717-1747`).

Terminal authority does not bypass output safeguards. `handleFinal` classifies content before selecting a route, supplies the authoritative value only to the existing owner, and closes response admission after that route returns (`FeishuSpeech/ViewModels/MainViewModel.swift:1496-1510`, `1512-1604`). `CurrentFocusAppendSession.finalize` retains the same generation and closed-state checks, safe-text filter, fixed-PID destination and Secure Input sampling, and physical-interference gate used by held snapshots; monitoring closes only after the terminal replacement attempt (`FeishuSpeech/Services/CurrentFocusAppendSession.swift:276-405`, `413-487`). Exact replacement remains Swift `Character` longest-common-prefix reconciliation followed by the precise Backspace count and suffix (`CurrentFocusAppendSession.swift:288-331`). The system poster rejects action-capable C0, C1, DEL, and keyboard-route LF input, constructs all events before posting, checks Secure Input, and posts each complete synthetic down/up pair through the shared epoch gate (`FeishuSpeech/Services/TextInputSimulator.swift:361-446`, `559-575`).

The extended lifecycle retains fail-closed stale-result controls. Every admitted packet or final operation checks both the active generation and the monotonic attempt identifier before output handling (`FeishuSpeech/ViewModels/MainViewModel.swift:993-1023`, `1131-1136`). The lock-protected operation race permits only one timeout or operation settlement; late success is suppressed, and a late factory-created session is cancelled (`MainViewModel.swift:1025-1081`). Drain expiry and abnormal termination close response and retry admission, invalidate the generation and both output owners, clear state, and only then cancel remote work (`MainViewModel.swift:1895-1935`, `1979-2016`, `2028-2073`). Normal completion closes admission before clearing the generation (`MainViewModel.swift:1944-1977`).

The candidate adds no credential, transcript, response-body, audio, stream-ID, target-content, clipboard-content, or content-hash logging. New lifecycle logs contain only generation, attempt, typed phase or operation, retry streak, delay, packet counts, and a boolean preservation flag (`FeishuSpeech/ViewModels/MainViewModel.swift:923-930`, `981-987`, `1042-1049`, `1138-1152`, `1929-1934`). Existing response receipts remain limited to typed route/outcome and length/diff counts (`MainViewModel.swift:1617-1651`). Factory credentials are copied only into the provider call and are not interpolated into a receipt (`MainViewModel.swift:678-699`). Error mapping strips arbitrary descriptions into typed failure classes (`MainViewModel.swift:1083-1105`). No dependency, authentication-storage, filesystem, deserialization, shell, or externally controlled URL surface changed in the candidate.

## Test evidence

- `CurrentFocusAppendSessionTests`: 37/37 passed. This includes fixed PID, destination and Secure Input preflight/postflight, interference and tap-loss epochs, atomic event pairs, exact grapheme replacement, authoritative-final safety-monitor lifetime, unsafe control rejection, stale generation, and post-close no-write coverage.
- `StreamingMainViewModelTests`: 83/83 passed. This includes post-release fixed-owner finalization, AX and keyboard authoritative finals, old-generation and post-cleanup suppression, timeout recovery, noncooperative late-packet suppression, security activation cleanup, unsafe final rejection, and no clipboard or one-shot fallback.
- `FinalTextOutputSecurityTests`: 19/19 passed. This retains production event construction, Secure Input, fixed PID, zero-post-on-failure, and physical-interference pair-gate coverage.
- `CursorTextSessionTests`: 15/15 passed. This retains verified AX range ownership, destination and generation mismatch rejection, Secure Input fail-closed behavior, and late-event suppression.
- `git diff --check 26825b829cd654f46a445b0505d82b165dc27e40..HEAD`: clean.

verdict: pass
findings_blocking: 0
review_conclusion: The candidate preserves all reviewed output security and privacy boundaries while extending recognition authority through bounded release drain.

## Final Re-review - cbbbf2f

candidate: 62832ad28ce13c8fa31320cfe194da0df9610cac..cbbbf2feb71a23f3253e4b579a876789514a9b32
tests: 25aa505 and production repair cbbbf2f

PASS. No P0, P1, P2, or P3 security or privacy finding remains in the final repair.

The new output-preservation state is derived only from the existing fixed owner's actual delivery outcome. AX output records committed state from the owned `CursorTextSession`, while keyboard output distinguishes committed delivery from uncertainty; unsafe text, keyboard-route line feed, destination rejection, stale generation or attempt, and security rejection cannot be promoted to committed output (`FeishuSpeech/ViewModels/MainViewModel.swift:1365-1559`, `1811-1842`). The state controls only terminal feedback and does not introduce another output route, clipboard path, target capture, PID selection, or one-shot fallback.

AX terminal finalization now inspects the original owner's post-final state and accepts only a committed result. Owner invalidation or drift is classified as delivery uncertainty and produces transcript-free preservation feedback instead of success (`FeishuSpeech/ViewModels/MainViewModel.swift:1630-1665`). The fixed target, focused-element ownership, PID checks, Secure Input gates, physical-interference epoch, unsafe-control rejection, and exact grapheme-aware Backspace replacement remain implemented by the unchanged cursor and keyboard sessions.

The lock-protected race gate now checks the injected monotonic deadline atomically with success settlement, so an operation completing at or beyond the drain deadline cannot gain output admission (`FeishuSpeech/ViewModels/MainViewModel.swift:20-52`, `1057-1136`). The clock injection is internal and defaults to `ContinuousClock.now`; it does not create an externally controlled trust boundary. Explicit cancellation also settles the gate, cancels child and watchdog tasks, and finishes event delivery. A factory result arriving after timeout or cancellation is suppressed and the late-created streaming session is cancelled rather than admitted. Existing generation and attempt checks still precede packet and terminal handling (`FeishuSpeech/ViewModels/MainViewModel.swift:1025-1055`, `1186-1191`).

Drain expiry closes response and retry admission, invalidates active identity and owners, and clears output state before remote cancellation (`FeishuSpeech/ViewModels/MainViewModel.swift:1952-2016`). Its feedback differentiates committed, uncertain, and absent output without exposing recognized text. The only new diagnostic value is the closed `OutputPreservationState` enum rendered as public metadata; no transcript, audio, credential, response body, target content, or content hash is logged.

Independent final-suite execution passed: `StreamingMainViewModelTests` 91/91, `CurrentFocusAppendSessionTests` 37/37, `FinalTextOutputSecurityTests` 19/19, and `CursorTextSessionTests` 15/15. The added lifecycle tests cover AX drift after finalization, no-safe-output expiry, delivery uncertainty, exact-deadline admission rejection, cancellation settlement, zero-budget finish suppression, and late noncooperative factory cleanup without removing existing security coverage.

verdict: pass
findings_blocking: 0
review_conclusion: The final repair closes the reviewed lifecycle races without weakening fixed-target output security, stale-result suppression, or diagnostic privacy boundaries.
