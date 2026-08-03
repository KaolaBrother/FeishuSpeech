# Final security and privacy closure review: issue #26

Review date: 2026-08-03 (Asia/Shanghai)

Candidate: the complete current issue-26 worktree at
`/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`, compared with baseline
`9fed83fe45a917f1c99bbfe1ec3116d9d9911b0f`.

Accepted contract and evidence reviewed:

- `CLAUDE.md`, read in full before repository inspection
- `docs/decisions/D-25-01.md`
- `docs/streaming-speech-design.md`
- all changed and newly added issue-26 production and test files, including callers and sinks
- `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-26/mission-list.md`
- `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-26/transport-evidence.md`
- the later R8-R11 repair surfaces: completion-overlay timing, post-barrier recorder sealing,
  drain-aware custom ingress, deferred bounded action-3 cancellation, and coordinator helpers
- the final strict-lint cleanup, especially `AudioRecorder` helper extraction,
  `DirectRequestContext`, pasteboard identifier renames, import/order-only edits, and their callers
- the final README, changelog, API, architecture, decision, and streaming-design docking

Verdict: PASS. No candidate-caused security or privacy defect remains open. The later correctness
repairs do not reopen S1-S4 and introduce no new security-sensitive exposure. P1 and P2 remain
confirmed baseline weaknesses and are explicitly nonblocking for issue #26 attribution.

## Final strict-lint and documentation delta audit

### AudioRecorder helper extraction

The extracted `CapturedAudioSample` and `AudioConversionInput` values are private, memory-only
bundles. The callback still requires the exact active `AVCaptureOutput`, validates source format,
converts through the same `AVAudioConverter`, publishes only converted PCM to the existing bounded
ingress or compatibility buffer, and aborts on ingress overflow at
`FeishuSpeech/Services/AudioRecorder.swift:369-568`. Normal streaming stop still ends capture,
crosses the real delegate-queue barrier, then seals the ingress using post-barrier emission state at
`FeishuSpeech/Services/AudioRecorder.swift:208-250`. The extraction adds no file persistence,
recipient, blocking network call, raw-audio log, or relaxed byte bound.

### DirectRequestContext parameter bundle

`DirectRequestContext` is private and contains only the same path, headers, body, and already
resolved IP list that the direct-request helper previously received separately at
`FeishuSpeech/Services/FeishuAPIService.swift:31-36`. Its DEBUG construction uses the fixed
authentication path at lines 488-507. The sender forwards the fields unchanged to the fixed Feishu
host or existing URLSession fallback at lines 765-837 and logs neither headers nor body. The refactor
does not make host, URL, path, or header names transcript- or user-controlled and introduces no SSRF
or credential disclosure path.

### Pasteboard names and remaining lint-only edits

The `pasteboardType` loop-variable rename at
`FeishuSpeech/Services/TextInputSimulator.swift:203-226` is lexical only. The final-only sink retains
its control-character rejection, captured-PID posting, and pre/post destination validation at lines
39-60 and 87-121. The legacy snapshot/restore algorithm is unchanged, so P1 remains accurately
pre-existing. Import grouping, DEBUG helper renames, and formatting changes in application,
settings, Keychain, login-item, hot-key, model, view, and test files add no new trust boundary,
secret sink, authorization bypass, or unsafe external call.

### Documentation and UAT boundary

The final documentation consistently describes status-only UI/logging, copy-only recovery for
unsafe or stale final output, fixed two-second recovery feedback, bounded serial streaming, and no
whole-file replay. It explicitly keeps real-credential Feishu behavior and cross-application
Accessibility compatibility pending installed-Release owner UAT; it does not convert that pending
runtime evidence into a compatibility or security claim. Representative anchors are `README.md:61-69`,
`docs/api.md:189-201`, `docs/architecture.md:313-323`,
`docs/decisions/D-25-01.md:160-180`, and `docs/streaming-speech-design.md:464-474`.

## S1-S4 final closure audit

### S1 - Resolved - Action-capable transcript controls cannot reach synthetic paste

Failure class re-audited: injection / unsafe interpretation of external transcript content.

Concrete trigger: automatic final-only delivery receives CR, LF, tab, escape, NUL, DEL, or another
C0 or C1 control scalar from the external recognition response.

Expected safe behavior: no synthetic keyboard event; retain the exact value only for manual recovery
with fixed, transcript-free feedback.

Current evidence:

- `TextInputSimulator.isSafeForAutomaticPaste` rejects C0, DEL, and C1 controls at
  `FeishuSpeech/Services/TextInputSimulator.swift:118-121`.
- Refactored `MainViewModel.routeFinalOnly` applies that guard before the output adapter and routes a
  rejected value through the single manual-recovery helper at
  `FeishuSpeech/ViewModels/MainViewModel.swift:514-520` and `578-581`.
- `SystemFinalTextOutput.insertOnce` repeats the same guard at the synthetic sink before pasteboard or
  CGEvent work at `FeishuSpeech/Services/TextInputSimulator.swift:39-60`.
- `StreamingMainViewModelTests.test_finalOnlyActionCapableControlCharactersDowngradeToCopyOnly`
  proves CR, LF, tab, escape, and NUL produce zero synthetic input.

Conclusion: the helper refactor preserves the defense in depth, and no untrusted control character
can become an implicit submit or terminal action on the final-only synthetic path.

### S2 - Resolved - Final-only delivery remains bound to the captured process and revalidated element

Failure class re-audited: stale-target check-to-use race / sensitive transcript misdelivery.

Concrete trigger: process or focused-element ownership changes during final-only completion.

Expected safe behavior: target the captured process, validate the exact captured AX element before
and after posting, and retain manual recovery when delivery becomes uncertain.

Current evidence:

- `FinalTextOutput.insertOnce` still requires the captured `CursorDestinationToken` at
  `FeishuSpeech/Services/TextInputSimulator.swift:9-16`.
- Cmd+V still uses `CGEvent.postToPid(destination.processIdentifier)`, not the global HID stream, at
  `FeishuSpeech/Services/TextInputSimulator.swift:87-100`.
- The refactored validation helpers recheck current security, frontmost PID, and exact focused-element
  identity at `FeishuSpeech/ViewModels/MainViewModel.swift:522-565`.
- The output adapter validates before touching the pasteboard and again after posting at
  `FeishuSpeech/Services/TextInputSimulator.swift:47-60`.
- Failed or uncertain non-security delivery enters the centralized recovery helper at
  `FeishuSpeech/ViewModels/MainViewModel.swift:567-581`; a security-rejected preflight performs no
  clipboard recovery.
- `FinalTextOutputSecurityTests` and
  `StreamingMainViewModelTests.test_finalOnlyDeliveryRechecksCapturedDestinationAfterSafePlainTextInsertion`
  prove captured-PID posting, pre/post validation, and no mutation on failed preflight.

Conclusion: R8-R11 did not alter this output primitive or weaken its validation contract. Exact
AX-element atomicity remains a cross-application UAT concern because process-targeted CGEvent posting
cannot atomically bind an element; it is not a newly demonstrated candidate defect.

### S3 - Resolved - Security state remains fail-closed and dynamically revalidated

Failure class re-audited: fail-open security-state transition / protected target output.

Concrete trigger: Secure Event Input activates, the captured element becomes secure or unverifiable,
or an AX query fails after initial capture.

Expected safe behavior: invalidate/cancel the generation or reject the next output before target or
pasteboard mutation.

Current evidence:

- Capture requires trusted Accessibility, no Secure Event Input, an affirmatively safe editable
  role/subrole, and settable selected text at
  `FeishuSpeech/Services/AccessibilityClient.swift:54-76`.
- `currentSecurityState` rechecks trust, Secure Event Input, captured PID, role, and subrole at
  `FeishuSpeech/Services/AccessibilityClient.swift:121-167`.
- Live replacement checks current security during owned-range validation and immediately before both
  AX mutations at `FeishuSpeech/Services/CursorTextSession.swift:127-170`.
- Final-only helper validation fails closed on security errors or non-safe state before any output at
  `FeishuSpeech/ViewModels/MainViewModel.swift:514-565`.
- `MainViewModel` continues observing Secure Event Input and invalidates the active identity before
  asynchronous cancellation at `FeishuSpeech/ViewModels/MainViewModel.swift:101-136`.
- Cursor and coordinator tests cover secure, unverifiable, throwing-query, and mid-interaction Secure
  Event Input transitions and prove zero subsequent AX, final-only, or clipboard output.

Conclusion: the coordinator helper split retains the previously reviewed fail-closed ordering.

### S4 - Resolved - Shared-pasteboard recovery now has a human-readable fixed presentation interval

Failure class re-audited: sensitive data exposure / missing privacy feedback.

Concrete trigger: stale destination, control-bearing final, or uncertain delivery puts the transcript
on the general pasteboard for manual recovery.

Expected safe behavior: no further synthetic input; present a fixed, transcript-free message on an
actually visible surface for a bounded readable interval.

Current evidence:

- Every current recovery branch reaches `copyForManualRecovery`, which couples the clipboard write
  with `.manualRecoveryCopied` feedback at `FeishuSpeech/ViewModels/MainViewModel.swift:514-581`.
- Completion strings are fixed and transcript-free at
  `FeishuSpeech/Models/RecordingState.swift:52-63` and rendered directly by
  `FeishuSpeech/Views/RecordingOverlayView.swift:3-16`.
- `publishCompletionFeedback` asks the presenter for the fixed two-second interval at
  `FeishuSpeech/ViewModels/MainViewModel.swift:676-684`.
- Normal completion returns coordinator state to idle without hiding a presented completion message
  at `FeishuSpeech/ViewModels/MainViewModel.swift:603-622`.
- `OverlayWindowController.presentCompletionFeedback` clamps requested visibility to one through five
  seconds, puts the fixed view frontmost, and hides only after the guarded task expires at
  `FeishuSpeech/Controllers/OverlayWindowController.swift:69-95`.
- New show/hide calls cancel the prior task and advance a generation, preventing stale feedback from
  hiding or overwriting a successor interaction at
  `FeishuSpeech/Controllers/OverlayWindowController.swift:98-125`.
- `test_completionFeedbackRemainsActuallyPresentedForBoundedReadableIntervalWhileStateReturnsIdle`
  verifies the real presenter seam rather than merely observing a transient Combine state.

Conclusion: the later R8 repair strengthens S4. Clipboard recovery is no longer silent, and the
presentation contains no transcript, credential, stream identity, or focused-control contents.

## Later R8-R11 repair security and privacy audit

### Overlay timing and presentation task

The new task is MainActor isolated, weakly captures the controller, has a one-to-five-second bound,
and is generation guarded. It renders only `RecordingState` fixed content. A new presentation or
explicit hide cancels it. No transcript is captured by the task or persisted in the overlay.

### Post-barrier recorder sealing

`AudioRecorder.stopStreamingRecording` stops capture, crosses the real delegate queue barrier while
the current output identity remains valid, then consults ingress emission state and seals at
`FeishuSpeech/Services/AudioRecorder.swift:208-250`. This can retain audio already captured before
stop; it does not extend microphone capture, persist audio, or cross a new recipient boundary.

### Drain-aware custom ingress

The replacement ingress owns queued PCM, pending PCM, terminal state, byte accounting, and waiters
under one lock at `FeishuSpeech/Services/ByteBoundedAudioIngress.swift:42-246`. Dequeue subtracts the
exact packet size at lines 192-196; append checks queued plus pending bytes at lines 74-105. The
production ceiling remains 1,920,000 bytes. Audio is memory-only, ordered, explicitly terminated on
overflow, and neither logged nor written to disk.

### Deferred bounded action-3 cancellation

Established action-0 cancellation records terminal intent, rejects waiters, cancels active work, and
waits only within the existing one-second deadline before one serial best-effort action 3 at
`FeishuSpeech/Services/FeishuStreamingSession.swift:216-291`. Action 3 uses empty audio, the fixed
Feishu HTTPS endpoint, the existing bearer token, and the same sanitized error boundary. It is
suppressed after action 2 and cannot overlap another request. No new URL, replay, transcript, raw
response, token log, or credential sink is introduced.

### Coordinator helper refactor

The split helpers preserve the order of content filtering, dynamic security proof, PID/element
validation, sink-level validation, recovery copy, and fixed feedback. Generation invalidation still
precedes asynchronous cleanup, and late events remain no-ops. No helper accepts a broader input or
bypasses S1-S4 controls.

## Confirmed pre-existing weaknesses - nonblocking for issue #26

### P1 - Medium - Legacy pasteboard restore can overwrite newer ownership

Scope: pre-existing at baseline `9fed83fe`; issue #26 did not introduce the algorithm, and the new
captured-PID final-only adapter does not invoke its snapshot/restore path.

Anchors: `FeishuSpeech/Services/TextInputSimulator.swift:160-176` and `217-233`, materially identical
to baseline lines 55-71 and 98-114.

The legacy path treats a changed `NSPasteboard.changeCount` as consumption and then restores the old
snapshot unconditionally. If another application takes clipboard ownership during polling, this can
overwrite newer clipboard data or resurrect previously copied sensitive content.

Action: restore only while FeishuSpeech still owns the same pasteboard generation; never overwrite a
new owner, bound snapshot lifetime, and test external ownership changes.

### P2 - Medium - Tenant-token cache is not keyed to configured credentials

Scope: pre-existing at baseline `9fed83fe`; issue #26's streaming factory inherits the existing
singleton cache behavior.

Anchors: `FeishuSpeech/Services/FeishuAPIService.swift:641-678` and
`FeishuSpeech/ViewModels/MainViewModel.swift:826-838`.

`getAccessToken(appId:appSecret:)` returns any unexpired cached token without checking which App ID
created it. Saving changed credentials does not invalidate or re-key the cache, so the next request
can use the prior application's tenant token until reset, expiry, or rejection.

Action: bind cached tokens to a non-logged credential identity, invalidate on credential changes,
and test that switching App ID forces authentication before audio is sent.

## Other security surfaces reviewed with no candidate finding

- Streaming requests use one fixed HTTPS Feishu URL; user input cannot select the URL, host, path, or
  header name.
- App ID, App Secret, tenant token, stream ID, audio bytes, transcript, response body, backend message,
  focused-control contents, and clipboard payload are absent from candidate production logs and
  completion feedback.
- Non-200 token parsing is byte bounded and refreshes only for the exact known invalid-token code.
  Public failures remain typed and sanitized; optional response identities are checked when present.
- No established-stream replay or whole-file production fallback is reachable from MainViewModel.
- Mutable transport state remains actor isolated; ingress mutable state is lock protected; overlay
  state and cursor destinations remain MainActor isolated.
- No dependency or Xcode project-membership change was introduced. A static changed-tree scan found
  no private-key or production credential material.

## Validation receipt

- Read the complete current production and test candidate, with specific re-tracing of all later
  R8-R11 repair files, callers, and sinks.
- `git diff --check 9fed83fe45a917f1c99bbfe1ec3116d9d9911b0f --` passed with no output.
- The Xcode project membership file is unchanged from baseline.
- Static scans found no private-key material, hardcoded production credential, transcript/token/body
  logging, user-controlled network target, or whole-file fallback in the production coordinator.
- Focused `xcodebuild` passed all 65 tests in `FinalTextOutputSecurityTests`,
  `CursorTextSessionTests`, `StreamingMainViewModelTests`, `StreamingAudioIngressTests`,
  `AudioRecorderStreamingIntegrationTests`, and `FeishuStreamingSessionTests`, with zero failures
  before the final lint cleanup.
- The current final-validation evidence supplied with this review records strict SwiftLint at zero
  warnings and zero errors, the complete macOS suite at 171 passed with zero failures or skips, and
  a successful Release build. Per the repository validation policy, this delta review did not
  redundantly rerun those already-passed gates.
- Credential-bearing Feishu behavior and the cross-application/live AX matrix remain separate UAT
  gates. They are not code-security failures without evidence that current code violates the
  accepted contract.

finding: id=P1 scope=pre_existing action=track status=open severity=medium fix_role=security rationale=legacy-clipboard-restore-overwrites-newer-pasteboard-ownership
finding: id=P2 scope=pre_existing action=track status=open severity=medium fix_role=security rationale=tenant-token-cache-is-not-keyed-by-configured-credentials
verdict: pass
findings_blocking: 0
review_conclusion: Final delta closure confirms S1 through S4 remain resolved, P1 and P2 remain pre-existing, and lint or documentation refactors introduce no confirmed security or privacy blocker.
