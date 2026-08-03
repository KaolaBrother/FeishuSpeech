# Security re-review: resilient hold streaming candidate

Candidate: current integrated uncommitted issue-26 tree in `.kw/worktrees/issue-26`, including the R11 abnormal-termination and recorder-barrier repair.

Scope: immediate revocation of output and retry authority, remote transport cancellation, Secure Input and stable-destination gates, pasteboard and selection safety, transcript-free diagnostics and feedback, bounded replay retention, exact-once cleanup, and late-event isolation.

## Prior security finding resolution

finding: id=R1 scope=in_scope action=none status=resolved severity=medium fix_role=security rationale=established-attempt-abandonment-uses-shared-exactly-once-cancel

R1 remains resolved. Attempt abandonment clears the active session reference, creates one shared cancellation task before suspension, and makes competing attempt-level callers await the same task (`MainViewModel.swift:818-830`). Abnormal termination now also snapshots and awaits an already-running cancellation when another owner has cleared the active session (`MainViewModel.swift:1298-1323`). The transport accepts one cancel intent and makes at most one bounded action-3 attempt after an established stream (`FeishuStreamingSession.swift:257-339`). No duplicate abort, concurrent action 2/action 3, or stale-session mutation of a successor was found.

finding: id=R2 scope=in_scope action=none status=resolved severity=medium fix_role=security rationale=retry-remains-a-strict-transient-allowlist

R2 remains resolved. API retry is limited to timeout, network-unavailable or failed network, HTTP 408/425/429, and 5xx. Stream retry is limited to network, timeout, the same HTTP set, and backend code 10024. Authentication, invalid request or response, malformed response, response-identity mismatch, cancellation, unknown errors, and other HTTP values fail closed (`MainViewModel.swift:640-713`). Every continuation after backoff rechecks the active identity, retry admission, task cancellation, and seal state.

finding: id=R3 scope=in_scope action=none status=resolved severity=low fix_role=security rationale=release-and-abnormal-termination-close-retry-before-asynchronous-cleanup

R3 remains resolved. Fn release closes creation and backoff admission before asynchronous sealing (`MainViewModel.swift:1203-1229`). Abnormal termination performs the same closure before any await (`MainViewModel.swift:1298-1306`). A session returned by cancelled creation cannot be admitted and is cancelled directly (`MainViewModel.swift:469-504`). No post-release or post-termination successor request, credential capture, or retry sleep is reachable.

## R11 security delta

resolution: id=R11 status=resolved note=abnormal-termination-revokes-output-and-transport-authority-before-recorder-wait

R11 is resolved. `terminateAbnormally` snapshots the exact ingress, transport, consumer, in-flight cancellation, and recorder barrier, then synchronously closes retry admission, invalidates the generation and both output-session types, fails ingress, removes coordinator references, cancels the consumer, hides output UI, and forces recorder cleanup before its first await (`MainViewModel.swift:1298-1317`). It starts or joins transport cancellation before waiting for the old recorder barrier (`MainViewModel.swift:1319-1331`). The old generation therefore loses all authority even if recorder teardown remains blocked.

The pending recorder barrier is retained independently from the cleared interaction state and has an identifier-checked owner (`MainViewModel.swift:49-52,94-96,1249-1267`). `beginStreaming` rejects a successor while that latch exists (`MainViewModel.swift:291-295`). Abnormal terminal state publication and hot-key idle reset remain behind the barrier, while output and network authority do not. A normal sealing completion racing abnormal termination rechecks the now-invalid identity and cannot clear or publish through the abnormal owner's barrier. Multiple abnormal callers can join the same barrier; only the caller that clears its matching identifier publishes terminal state.

### No late output after revocation

Every streaming event first requires the current generation. R11 clears that generation on the main actor before cancelling asynchronous work, so a held or late partial, final, failure, replay frontier, or action-2 response becomes a no-op. The captured `CursorTextSession` is invalidated by dropping its destination and setting an invalid state (`CursorTextSession.swift:42-70`), while the current-focus append session closes and stops activation monitoring (`CurrentFocusAppendSession.swift:176-216,268-277`). Sealed recovery also checks active identity after the recorder await (`MainViewModel.swift:716-742,1249-1260`). No path can route a late value to AX replacement, current-focus Unicode posting, final-only insertion, manual-recovery clipboard, or completion feedback after abnormal authority revocation.

### Secure Input, PID, and destination gates

Secure Input observation additionally invalidates output authority synchronously at the publisher boundary (`MainViewModel.swift:182-194`). Live AX replacement verifies frontmost PID, exact focused AX element, security state, expected selection or caret, and previously owned text before each mutation, then verifies the resulting owned range (`CursorTextSession.swift:79-215`). Captured final-only insertion rechecks security, frontmost PID, and exact AX element through its preflight and postflight validation (`MainViewModel.swift:1134-1195`).

The unbound append path samples Secure Input and the bound frontmost PID twice before posting and once after, and permanently suspends on destination change, security rejection, or delivery uncertainty (`CurrentFocusAppendSession.swift:108-173,176-243`). The one-shot current-focus fallback double-samples Secure Input and PID, and the event poster checks Secure Input immediately before the HID post (`TextInputSimulator.swift:85-110,174-186`). The documented same-PID caret-movement limitation remains a best-effort residual only on the AX-unavailable branch; R11 introduces no broader trust boundary.

### Pasteboard, selection, and privacy

Continuous append posts only an initial safe string or exact unseen UTF-16 suffix. It performs no selection, deletion, cursor navigation, Command-V, or pasteboard operation. Live AX replacement mutates only the verified owned range and never attempts rollback after uncertainty. Final-only Command-V remains bound to a captured PID with exact AX validation; manual-recovery copying is confined to explicit non-security recovery outcomes. R11 invalidates all writers before cleanup waits, so abnormal termination cannot enter any of these clipboard or selection paths.

Replay retention remains bounded to 1,920,000 captured bytes across delivered replay packets, queued packets, and pending coalescing bytes. Tail silence is not double-charged, packet journal ownership is cleared at abnormal termination, and ingress termination is lock-serialized (`ByteBoundedAudioIngress.swift:92-217,220-289`; `MainViewModel.swift:1298-1310,1354-1371`).

Retry logs expose only ordinal values. Streaming diagnostics contain only action, sequence, HTTP status, response size, numeric business code, and typed outcome. Append diagnostics contain only typed suspension reasons. No transcript, audio bytes, credentials, bearer token, stream identifier, raw response body, or backend message is logged or embedded in new status, feedback, or error surfaces. The R11 tests deliberately use private marker text and confirm it is absent from visible feedback.

## Validation evidence

- Current-source focused R11 and coordinator validation passed 61 of 61 lifecycle-free tests with zero failures (`/private/tmp/feishuspeech-issue26-r11-after2-suite.log`). This includes held-barrier reset with a live AX writer, held-barrier hot-key failure with an append writer, transport cancellation before barrier release, successor rejection while the latch is held, Secure Input revocation, late-generation no-ops, retry boundaries, and transcript-free output outcomes.
- The current source built successfully for testing (`/private/tmp/feishuspeech-issue26-r11-after2-build.log`), and focused strict SwiftLint reported zero violations (`/private/tmp/feishuspeech-issue26-r11-final-lint.log`). A later integrated build-for-testing and Release build also succeeded (`/private/tmp/issue26-final-build-for-testing.log`, `/private/tmp/issue26-final-release-build.log`).
- `git diff --check` passes on the current tree.
- This review did not launch the app, invoke permission UI, inspect credentials or transcript content, or alter application state.

verdict: pass
findings_blocking: 0
review_conclusion: R11 now revokes output, retry, and transport authority before recorder serialization, while the existing security, privacy, and bounded-memory controls remain intact.
