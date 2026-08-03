# Issue #26 resilient-hold correctness review

verdict: pass
findings_blocking: 0

## Prior finding closure

resolution: id=R1 status=resolved note=typed-stream-cancellation-is-normalized-as-sealed-control-flow-and-all-callers-share-one-in-flight-cancel-task
resolution: id=R2 status=resolved note=failed-action2-return-and-throw-now-cancel-once-before-sealed-fallback-and-transport-remains-abort-eligible
resolution: id=R3 status=resolved note=first-partial-rebind-now-switches-exhaustively-secure-fails-closed-and-finalOnly-preserves-its-token
resolution: id=R4 status=resolved note=release-cancels-held-delay-and-session-creation-and-rechecks-admission-before-successor-creation
resolution: id=R5 status=resolved note=sealed-recovery-now-routes-retained-output-for-all-writer-modes-and-publishes-fixed-feedback-when-no-usable-result-exists
resolution: id=R6 status=resolved note=contentless-live-final-and-replay-values-no-longer-overwrite-the-last-usable-hypothesis
resolution: id=R7 status=resolved note=production-and-docs-now-use-the-narrow-reviewed-allowlist-with-unknown-and-identity-classes-terminal
resolution: id=R8 status=resolved note=replay-retention-now-charges-delivered-queued-and-pending-captured-bytes-under-one-ingress-lock
resolution: id=R9 status=resolved note=ordinary-sealed-completion-now-awaits-recorder-ownership-release-before-idle-or-successor-admission
resolution: id=R10 status=resolved note=typed-positive-and-terminal-tables-now-cover-425-and-the-complete-reviewed-status-boundaries
resolution: id=R11 status=resolved note=abnormal-termination-revokes-generation-writers-ingress-consumer-and-transport-before-recorder-wait-while-the-independent-latch-blocks-successors

## Review receipt

- Candidate: current uncommitted integrated issue-26 diff in `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`, based on `e743ecc`.
- Claim reviewed: complete issue-26 resilient-hold candidate and final R11 closure, with immediate abnormal authority revocation, recorder-barrier successor exclusion, coherent terminal publication, shared transport cancellation, retained-output recovery, bounded replay, and exact retry classification.
- Surface inspected: every changed production and test surface in the current candidate; recorder and ingress ownership dependencies; cursor, append, final-only, and current-focus output paths; transport finish and cancel behavior; lifecycle and hot-key callers; documentation; and the complete R1-R11 finding frontier.
- R11 proof: `terminateAbnormally` snapshots owned resources, then closes retry admission, invalidates generation and both output-session types, fails ingress, cancels the consumer, hides output UI, and forces recorder cleanup before its first await (`FeishuSpeech/ViewModels/MainViewModel.swift:1298-1317`). It then starts or joins the exact transport cancellation before awaiting the identifier-owned recorder barrier (`MainViewModel.swift:1319-1331`). `beginStreaming` rejects successors while that independent latch exists (`MainViewModel.swift:291-295`), and normal completion rechecks the invalidated identity before it can clear or publish through the barrier (`MainViewModel.swift:1249-1270`).
- R11 coverage: held-barrier reset with a live `CursorTextSession` and held-barrier hot-key failure with an append session prove immediate writer invalidation, no late partial or final write, one transport cancel before barrier release, no successor admission, and idle or fixed-error publication only after recorder ownership is released (`FeishuSpeechTests/StreamingMainViewModelTests.swift:610-766`).
- Static validation: `git diff --check` passed. `xcodebuild -scheme FeishuSpeech -configuration Debug build` succeeded. `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' build-for-testing` succeeded. `swiftlint` reported 0 violations in 27 files.
- Dynamic validation: the current-source focused coordinator suite passed 61 of 61 tests with zero failures at 2026-08-03 19:37:20; the log postdates both reviewed R11 source and test files. A separate standard full `xcodebuild ... test` attempt compiled the app and tests but was interrupted after its test host blocked before XCTest execution in `SecItemCopyMatching` from `AppSettings.load`; sampling localized this to the machine Keychain path rather than the candidate recorder or transport logic, and no test failure was emitted.

review_conclusion: The complete candidate now resolves R1 through R11, including immediate abnormal authority revocation and recorder-latched terminal publication, with no remaining admitted correctness or coverage defect.
