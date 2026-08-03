# Implement cursor-bound streaming Feishu transcription for issue #26

- item: Map D-25-01, the executable design, current production seams, and existing test patterns into an implementation blueprint.
  status: done
  dispatched: code-explorer; inspect the issue-26 worktree and write the full evidence-backed map to kaola-workflow/issue-26/exploration.md in the main repository root.
  result: kaola-workflow/issue-26/exploration.md maps the whole-file baseline, missing ingress/transport/AX seams, synchronized Xcode membership, privacy/retry/overflow conflicts, dependency order, risks, and validation commands with line evidence.

- item: Verify the current official Feishu streaming-recognition wire contract and distinguish documented facts from credential-bearing unknowns.
  status: done
  dispatched: knowledge-lookup; use primary Feishu documentation and write evidence to kaola-workflow/issue-26/transport-evidence.md in the main repository root.
  result: kaola-workflow/issue-26/transport-evidence.md confirms the endpoint, auth, fields, action/sequence rules, and 100-200 ms recommendation; PCM profile, terminal-body encoding, same-sequence token retry, and response-shape semantics remain explicit credential-bearing UAT unknowns.

- item: Define the streaming, byte-bounded audio, session identity, Accessibility destination, owned-range, and fallback contracts with RED-first tests.
  status: done
  dispatched: tdd-guide; author only issue-26 test artifacts in the claimed worktree, prove failure on baseline 9fed83f, and return the changed test paths plus exact RED signatures for recording in this mission list.
  result: Four new FeishuSpeechTests suites define ingress, transport, cursor/fallback, and streaming-state contracts; baseline 9fed83fe failed with missing production subjects (xcodebuild exit 65), while all test files parse and git diff --check passes.

- item: Produce a dependency-safe production blueprint that satisfies D-25-01 and the test-owned RED seams without weakening existing lifecycle guarantees.
  status: done
  dispatched: code-architect; inspect design evidence and current RED artifacts, then write the implementation/file/ownership plan to kaola-workflow/issue-26/architecture-blueprint.md in the main repository root.
  result: kaola-workflow/issue-26/architecture-blueprint.md fixes the component/file ownership, declaration barrier, integration order, generation/cleanup rules, privacy checks, validation matrix, UAT gates, and failure routing.

- item: Implement byte-bounded ordered audio ingress and the strict serial Feishu streaming session actor against the contract tests.
  status: done
  dispatched: implementer; own only new/required production model, ingress, and transport files in the issue-26 worktree, satisfy StreamingAudioIngressTests and FeishuStreamingSessionTests without editing tests, and report changed paths plus before/after evidence.
  result: Added StreamingSpeechModels.swift, ByteBoundedAudioIngress.swift, and FeishuStreamingSession.swift; 14 focused tests passed, Debug build and diff check passed, and SwiftLint remained unavailable on PATH.

- item: Implement the main-actor cursor-bound Accessibility writer and destination-validated final-only fallback against the contract tests.
  status: done
  dispatched: implementer; own only new cursor/Accessibility/fallback production files in the issue-26 worktree, satisfy CursorTextSessionTests without editing tests or overlapping the audio/transport implementer, and report changed paths plus before/after evidence.
  result: Added CursorTextModels.swift, AccessibilityClient.swift, and CursorTextSession.swift; 12 focused cursor tests and Debug build passed, with the unrelated coordinator RED file transparently excluded from that focused run.

- item: Extend the test oracle across recorder ingress integration, streaming provider/API seams, coordinator lifecycle/fallback behavior, legacy-state migration, and privacy invariants.
  status: done
  dispatched: tdd-guide; own test files only, add focused integration and migration coverage in the issue-26 worktree, prove the new assertions RED against the current partial implementation, and report paths plus exact failures.
  result: Added recorder and MainViewModel streaming integration suites and expanded API/hot-key/lifecycle tests; all test files parse, diff check passes, and RED failures isolate missing recorder, provider, final-output, and coordinator seams.

- item: Implement identity-bound hot-key streaming/sealing transitions and fixed status-only presentation states while preserving event-tap and overlay race guarantees.
  status: done
  dispatched: implementer; own StreamingSpeechModels.swift identity addition, HotKeyState.swift, HotKeyService.swift, RecordingState.swift, RecordingOverlayView.swift, OverlayWindowController.swift, and only the exhaustiveness bridge in MainViewModel.swift, satisfying coordinator-state and migrated hot-key tests without editing tests.
  result: Identity allocation/invalidation, streaming-to-sealing idempotence, sealing press rejection, callback gating, fixed status-only states, and overlay updates landed; 4 coordinator-state and 25 HotKey tests plus Debug build passed.

- item: Attach the byte-bounded ingress to the existing AudioRecorder with ordered normal seal, typed abnormal close, overflow stop, and exactly-once resource cleanup.
  status: done
  dispatched: implementer; own AudioRecorder.swift and the minimal AudioIngressError/append-result extension in ByteBoundedAudioIngress.swift, satisfying AudioRecorderStreamingIntegrationTests without editing tests.
  result: AudioRecorder now shares capture/conversion with byte-bounded streaming ingress, seals after session/audio barriers, maps cancellation/capture/overflow terminal states, and stops on overflow; 16 audio/ingress/failure tests passed.

- item: Add the no-whole-file-retry streaming provider factory to FeishuAPIService and sanitize legacy sensitive API diagnostics.
  status: done
  dispatched: implementer; own FeishuAPIService.swift, FeishuStreamingSession.swift conformance, and a new disjoint streaming-provider protocol file, satisfying streaming factory tests without editing tests.
  result: Added streaming session/provider protocols and a single-attempt FeishuAPI factory with one forced refresh seam; scrubbed sensitive legacy diagnostics, and 40 streaming/API tests plus Debug build passed.

- item: Migrate hot-key and coordinator behavior to generation-owned streaming and sealing with exactly-once cleanup and status-only UI.
  status: done
  dispatched: implementer; own MainViewModel.swift, TextInputSimulator.swift, and at most one new FinalTextOutput protocol/adapter file, integrate completed audio/provider/cursor/state seams, satisfy StreamingMainViewModelTests and migrated lifecycle tests, and never edit tests.
  result: MainViewModel and TextInputSimulator now provide secure-first identity-bound streaming, live/final-only routing, finish-once sealing, invalidation-first cleanup, copy-only recovery, and no whole-file production path; the compiled 145-test bundle and Debug build passed.

- item: Resolve the verified cross-actor completion-observation race in the streaming coordinator test oracle without weakening final-output assertions.
  status: done
  dispatched: tdd-guide; reproduce the three coordinator failures, change only test synchronization to await observable final effects, and report focused evidence in the issue-26 worktree.
  result: Reproduction showed the unchanged oracle was correct and required no test edit; a production final-only routing defect was fixed, after which the coordinator implementer ran the suite 9/9 green.

- item: Review the integrated behavior for correctness, stale-callback safety, privacy, and security, then resolve verified findings.
  status: done
  dispatched: code-reviewer and security-reviewer; independently inspect the integrated issue-26 worktree and write full reports to kaola-workflow/issue-26/code-review.md and kaola-workflow/issue-26/security-review.md in the main repository root.
  result: Security review closed S1-S4 and retained only two pre-existing nonblocking notes; correctness review drove RED-first R8-R11 repairs and the final re-review passes with zero blockers after the isolated full macOS suite passed 171/171.

- item: Convert the independent correctness and security review triggers into RED regression tests without weakening D-25-01 behavior.
  status: done
  dispatched: tdd-guide; own tests only and cover the deduplicated audio-tail/barrier, bounded-cancel, AX fail-closed/dynamic-secure, optional-identity/token-envelope, exact-byte-bound, visible-feedback, control-character, and last-mile fallback findings in the issue-26 worktree.
  result: Extended six test suites plus FinalTextOutputSecurityTests with RED coverage for all 11 deduplicated review triggers; runtime REDs and missing seam compile failures were recorded, while test parsing and diff check passed.

- item: Fix review findings in byte-bounded ingress and AudioRecorder callback/barrier ownership, exposing first-packet-emitted state for coordinator sealing.
  status: done
  dispatched: implementer; own ByteBoundedAudioIngress.swift and AudioRecorder.swift only, satisfy exact-bound and queued-callback review tests without editing tests.
  result: Pending bytes now count toward the exact bound, continuation capacity is tracked conservatively, first-full-packet emission is queryable, and stop retains output identity through the real audioQueue barrier; 18 focused ingress/recorder/failure tests passed.

- item: Fix review findings in FeishuStreamingSession cancellation, optional response identity, and precise non-200 token classification.
  status: done
  dispatched: implementer; own FeishuStreamingSession.swift only, satisfy new transport review tests without editing tests.
  result: Optional response echoes are accepted only when absent or matching, exact invalid-token envelopes refresh once, and terminal cancellation is bounded even for uncooperative request work; 13 focused transport tests and Debug build passed.

- item: Fix review findings in Accessibility runtime/security proof and captured-PID final output delivery primitives.
  status: done
  dispatched: implementer; own CursorTextModels.swift, AccessibilityClient.swift, CursorTextSession.swift, and TextInputSimulator.swift only, satisfy AX and FinalTextOutputSecurity tests without editing tests.
  result: AX capability/security proofs now fail closed through an injectable runtime, live writes recheck security, and final-only delivery targets the captured PID with exact-element pre/post validation; 15 cursor and 4 final-output security tests plus Debug build passed.

- item: Integrate the review-fixed audio, AX, and output contracts into the generation-owned coordinator without weakening lifecycle or UI privacy guarantees.
  status: done
  dispatched: implementer; own MainViewModel.swift and RecordingState.swift only, wire ingress-emission sealing, dynamic Secure Event Input cancellation, captured-destination final output, control-character copy-only recovery, and fixed feedback states.
  result: Coordinator integration passed six focused streaming/state/security suites, three lifecycle/error suites, Debug build, and the isolated full macOS run of 166 tests with zero failures or skips.

- item: Convert correctness re-review findings R8-R11 into RED regression tests at the presentation, recorder-seal, transport-cancel, and drain-aware ingress boundaries.
  status: done
  dispatched: tdd-guide; own tests only, prove all four triggers fail on the current integrated candidate, and define the minimal production seams without weakening D-25-01.
  result: Four test suites reproduced R8-R11: missing readable presentation seam, post-barrier tail loss, missing serial abort after established action-0 cancellation, and false overflow after a consumer drain; the RED failures fixed the required production contracts.

- item: Resolve correctness re-review findings R8-R11 without weakening byte bounds, serial transport, stale-callback safety, or status-only privacy.
  status: done
  dispatched: three implementers with disjoint ownership for audio/ingress, streaming transport, and coordinator/overlay presentation.
  result: Completion feedback remains presented for two seconds behind a generation guard; recorder sealing consults post-barrier emission state; drained ingress bytes release exact capacity; established action-0 cancellation emits one bounded serial action 3 when possible. New focused suites pass 16/16 audio and 15/15 transport, the R8 presentation test and seven affected coordinator suites pass, Debug builds pass, and net-new scoped lint is clean.

- item: Dock verified behavior into user and architecture documentation and run focused tests, the full suite, Debug and Release builds, and SwiftLint.
  status: done
  dispatched: build-error-resolvers first remove all remaining strict SwiftLint baseline violations without disabling rules, then doc-updater docks only verified behavior before final Debug/Release/test validation.
  result: Seven user/architecture/API/decision/changelog documents now match runtime behavior; final full macOS tests pass 171/171 with zero failures or skips, strict SwiftLint reports 0/0 across 26 files, Debug and Release builds succeed, codesign verification passes, and final correctness/security reviews both pass.

- item: Record the live Feishu and Accessibility compatibility gate, or obtain the owner's explicit closure decision for any unavailable evidence.
  status: done
  result: Credential-bearing Feishu and broad cross-application AX UAT remain intentionally pending; the owner will self-test the installed Release, so the workflow uses keep-open terminal mode and does not claim broad compatibility or close issue #26 yet.
