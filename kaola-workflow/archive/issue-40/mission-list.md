# Converge every speech path into one durable editable preview and allow output only after explicit confirmation

- item: Confirm the runtime failure mechanism and define the smallest safe application-bound fallback contract from the UAT evidence
  status: done
  dispatched: preview_target_explorer and preview_target_investigator perform read-only source/runtime analysis; findings return to root and are recorded inline here
  result: Four installed-app failures reproduce the strict pre-audio gate with TCC Accessibility and Microphone allowed. MainViewModel currently requires exact AX focus/range authority before preview/audio/provider startup. Issue #40 therefore keeps exact delivery when available and adds an original-application-identity fallback with fail-closed confirmation; target text/control data remains unobserved.

- item: Produce a dependency-safe architecture blueprint for typed exact versus application-bound review authority and its security/async invariants
  status: done
  dispatched: code-architect writes /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/architecture-blueprint.md
  result: architecture-blueprint.md defines typed exact/application bindings, secure versus ordinary AX-miss capture, identity-first fallback capture, fixed-PID multiline-safe Cmd+V delivery, two preflight samples, postflight uncertainty, protected async surfaces, dependency order, and UAT limits; git diff --check passed.

- item: Encode the approved preview and application-bound fallback behavior as focused failing tests while preserving exact-target and async invariants
  status: done
  dispatched: tdd-guide owns test-only edits in /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40/FeishuSpeechTests and records baseline RED evidence in /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/test-red.md
  result: Five focused test surfaces now cover typed capture, preview/async fallback, fixed-app exact-once confirmation, multiline clipboard lifecycle, and secure/identity/uncertainty failures. Baseline 98e1eb5 is RED because SystemFinalTextOutput lacks insertReviewAtCurrentFocusOnce; test-red.md records the serialized command and log.

- item: Implement the review authority and delivery fallback with exact-once security gates and no capture/recognition backpressure
  status: done
  dispatched: implementer owns only FeishuSpeech/Models/CursorTextModels.swift, FeishuSpeech/Services/AccessibilityClient.swift, FeishuSpeech/Services/TextInputSimulator.swift, FeishuSpeech/Services/ReviewDestinationDelivery.swift, and FeishuSpeech/ViewModels/MainViewModel.swift in the issue-40 worktree; test artifacts remain under tdd-guide custody
  result: Typed exact/application authority, identity-first AX classification, fixed-PID multiline Cmd+V, two-sample security/identity gates, postflight uncertainty, and coordinator startup integration are implemented in the five owned files. Debug and Release builds, swiftlint --strict, git diff --check, and protected-topology checks pass; focused tests are compile-blocked by two test-fixture defects.

- item: Repair the Issue #40 test fixtures without weakening the RED acceptance oracle, then run the focused serialized GREEN gate
  status: done
  dispatched: original tdd-guide retains test custody in /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40/FeishuSpeechTests and records focused GREEN evidence in /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/test-green.md
  result: Three test-fixture compile issues were repaired without weakening assertions; the exact serialized focused command executed 78 tests with 0 failures, git diff --check passed, and test-green.md records the evidence.

- item: Update user and architecture documentation, then complete focused/full tests, builds, lint, correctness review, and security review
  status: done
  dispatched: investigator writes /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/final-validation.md; doc-updater owns Issue #40 docs in the worktree and writes /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/docs-report.md; code-reviewer writes .cache/code-review.md; security-reviewer writes .cache/security-review.md
  result: Post-R1 validation is green: focused 79/79, full serialized 442 passed plus one intentional live-TCP skip, Debug/Release builds, swiftlint --strict, diff/link/protected-path checks all pass. Correctness and security re-reviews pass; eight user/architecture/ADR surfaces are docked with R1 facts.

- item: Close security finding R1 by making each fallback preflight a consecutive Secure Input, PID, and complete-identity composite sample and proving mid-sample secure transition is zero-mutation
  status: done
  dispatched: production implementer repairs only the delivery/sample production boundary in its existing owned files; the original tdd-guide will retain the corresponding test-oracle edit after a concurrency slot is free; security-reviewer will re-review the delta
  result: Each of two preflight composites and the postflight perform Secure(start), fixed PID, running/frontmost complete identity, Secure(end). Strengthened tests cover Secure transitions in either identity window with zero clipboard/event mutation; focused 79/79 and both re-reviews pass.

- item: Finalize Issue #40 through the GitHub sink, install the verified Release as the sole local copy, and perform live UAT checks
  status: done
  dispatched: self records the final candidate receipt, docks closure artifacts, runs the resumable merge sink and closure audit, then builds/installs the merged Release and verifies sole-copy/process identity; owner performs the third-party target acceptance gesture
  result: Finalization was halted before merge/closure because installed candidate 60090c9 failed owner UAT: Fn release reached sealing but the editable transition copied/revoked/dismissed the only draft. The candidate is rejected and the superseding work remains in Issue #40.

- item: Diagnose why physical Fn release destroys the live preview before sealing can become an editable draft, while retaining independent capture and recognition lines with preview-only UI ownership
  status: done
  dispatched: self correlates the installed-process timeline with coordinator/window state; preview_release_explorer traces all release-to-dismiss paths; preview_release_investigator reproduces the readiness transition and existing test gap read-only; findings are recorded in /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/release-dismiss-diagnosis.md
  result: Fn release and the independent capture/recognition barrier are healthy. The production editable-panel transition returns failed; the old recovery path then copies the draft, revokes authority, dismisses the panel, and returns idle. Existing tests fake or statically inspect the WindowServer boundary and explicitly assert this obsolete copy-and-dismiss behavior. The exact failed readiness predicate is uninstrumented; no implementation was changed.

- item: Dock the complete UAT evidence, superseding single-output contract, target architecture, implementation plan, file structure, and acceptance gates into GitHub Issue #40
  status: done
  dispatched: self rewrites the canonical issue body, posts a dated UAT docking receipt, and verifies the remote body and marker byte-for-content through GitHub
  result: Issue #40 is open with the P1/in-progress labels and canonical title "converge every speech path into a durable editable preview before output". The remote body matches .cache/github-issue-body-v2.md; comment 5384551727 records the supersession and evidence receipt. Candidate 60090c9 remains explicitly rejected for release.

- item: Produce a superseding dependency-safe architecture for durable draft authority, typed presenter readiness, one explicit output gate, and unchanged asynchronous capture/recognition roots
  status: done
  dispatched: code-architect performs read-only source/design analysis and writes /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/architecture-blueprint-v2.md
  result: architecture-blueprint-v2.md defines coordinator-owned durable draft authority, three independent axes, editablePending/typed readiness, one-panel retry semantics, Send/Return-only delivery, no clipboard/direct recovery, inert legacy settings, exact/application security retention, file ownership, TDD dependency order, validation commands, migration, and installed-UAT gates.

- item: Replace obsolete copy-and-dismiss/direct-output test authority with focused failing tests for the canonical single-preview contract
  status: done
  dispatched: tdd-guide owns test-only edits under /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40/FeishuSpeechTests and records baseline RED evidence in /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/test-red-v2.md
  result: ReviewFirstMainViewModelTests now replaces obsolete compatibility, readiness-copy, and delivery-copy assertions with durable draft, zero pre-confirm output, explicit retry/discard, and both-settings preview oracles. Baseline 60090c9 compiled and executed 26 tests with 51 expected failures; test-red-v2.md records signatures and result bundle.

- item: Implement the single-preview route, durable editable draft, retryable presenter and delivery failures, and privacy-safe readiness telemetry while preserving exact and application-bound security
  status: done
  dispatched: implementer owns the v2 production surfaces in /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40/FeishuSpeech and writes implementation evidence to /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/implementation-v2.md; test artifacts remain under tdd-guide custody
  result: Production now has one preview-only route, coordinator-owned durable draft authority, typed async readiness with no fail-open adapter, explicit-confirm-only delivery, retained failure drafts, inert legacy route settings, and post-freeze permission/Secure Input preservation. Focused production suites and build pass; implementation-v2.md records the evidence.

- item: Reconcile documentation and complete focused/full tests, builds, lint, topology checks, correctness review, and security review
  status: done
  dispatched: doc-updater owns Issue #40 user/architecture/ADR documentation only; investigator owns final serialized tests, Debug/Release builds, strict lint, diff/link/topology and forbidden-route evidence; original correctness and security reviewers independently re-review the repaired candidate
  result: Final candidate passes 181 focused tests plus 51 intentional retired-oracle skips and the full serialized target with 407 passed plus 52 intentional skips; Debug/Release builds, swiftlint --strict with zero violations, diff/protected/forbidden-route/docs checks, correctness review, and security review all pass. Twelve user/architecture/ADR docs are docked; final-validation-v2.md, code-review-v2.md, security-review-v2.md, and docs-report-v2.md record the evidence.

- item: Finalize Issue #40 through the GitHub sink, install the verified merged Release as the sole runnable copy, and complete owner UAT without bypassing the preview
  status: in-flight
  dispatched: self owns validation binding, finalize transaction, merge sink, Release build/install, sole-copy audit, installed-process launch, GitHub evidence, and owner UAT handoff

- item: Repair the failed installed-Release UAT so the frozen draft becomes directly sendable, remove the retry-editing control, enlarge transcript text without resizing the panel, and keep streaming content below the titlebar controls
  status: done
  dispatched: code-explorer diagnoses the pending-readiness and AppKit/SwiftUI layout boundary read-only; tdd-guide owns focused RED/GREEN UI and coordinator acceptance tests; implementer owns the minimal production repair; doc-updater docks the UAT correction; correctness and security reviewers independently re-review the v3 delta before final validation and replacement installation
  result: V3 uses shared 18pt transcript typography without changing panel bounds, removes pending Retry Editing UI, treats accessory activation requests as advisory while retaining all actual fail-closed readiness predicates, constrains content below titlebar controls, and restores accurate activation/duplicate-risk feedback. Focused 122/122 and full serialized 416 passed plus 52 intentional skips; builds, strict lint, docs, correctness, and security reviews pass with zero blockers.

- item: Correct the second installed UAT failure by decoupling durable-draft confirmation authority from best-effort AppKit focus readiness so Send and Return are available immediately after freeze
  status: done
  dispatched: code-architect defines the v4 authority boundary; tdd-guide replaces obsolete readiness-gates-confirmation oracles with explicit-confirm and delivery-security oracles; UI/coordinator implementer owns MainViewModel, review state/view/controller; output/security implementer owns TextInputSimulator, ReviewDestinationDelivery, CurrentFocusAppendSession, and HotKeyService; docs, full validation, independent reviews, replacement install, and owner UAT remain required
  result: V4 exposed the residual lock/focus and security gaps and was superseded by the accepted v5 implementation. The final candidate has an immediately editable nonactivating preview, preview-local Send/qualified Return, no pre-confirmation output path, no clipboard/Cmd+V/activation/retarget, and one bounded terminal Unicode transaction; R6 reviews and all automated gates pass.

- item: Define the v4 zero-side-effect and one-confirmation transaction architecture after the residual image-paste diagnosis
  status: done
  dispatched: code-architect writes /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/architecture-blueprint-v4.md read-only
  result: V4 removes editablePending and retry readiness from product authority, makes focus readiness telemetry-only, requires zero output ledgers before explicit final confirmation, deletes pasteboard/Cmd+V review delivery, and specifies one modifier-free tagged Unicode pair with retained live trust/identity/Secure Input/stale/exact-once gates.

- item: Harden the v4 Unicode transaction and explicit-confirm provenance against the pre-implementation security review before allowing production changes
  status: done
  dispatched: security-reviewer records five blocking boundaries; code-architect revises architecture-blueprint-v4.md; tdd-guide incorporates UTF-16, phase-aware submission, modifier/interference, typed UI-intent, tag/PID, and submitted-unverified oracles before implementation
  result: Final architecture closes R1-R5 with a 16,384 UTF-16 cap/readback, phase-aware mandatory-up submission, modifier and interference/activation epochs, opaque real-UI confirmation intent, tag plus own-PID filtering in both monitors, submitted-unverified semantics, and explicit OS limitations. Pre-implementation security review passes; the 145-test RED matrix records 181 expected failures against 4f9908f.

- item: Reconcile the v2 test oracle with typed fixed feedback, cancellation draft retention, and the production asynchronous readiness protocol without weakening zero-output or durable-draft assertions
  status: done
  dispatched: original tdd-guide retains test-only custody in /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40/FeishuSpeechTests, repairs the four stale focused methods and audits legacy direct-output suites, then records GREEN evidence in /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/test-green-v2.md
  result: Test custody is reconciled to the canonical contract. Main coordinator 28, application fallback 12, production readiness 7, streaming coordinator 103 with 51 obsolete direct-output cases retired, and 76 low-level/review-view tests pass; test-green-v2.md retains RED-to-GREEN evidence.

- item: Independently review the v2 implementation for correctness, regression, security, privacy, exact-once behavior, and preservation of the capture/recognition topology
  status: done
  dispatched: code-reviewer writes /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/code-review-v2.md and security-reviewer writes /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/security-review-v2.md; both are read-only
  result: Security review passes with zero blocking findings. Correctness review fails on R1 fail-open legacy readiness, R2 stale delivery feedback after edit, and R3 missing production ReviewWindowController readiness coverage; .cache/code-review-v2.md and .cache/security-review-v2.md record the evidence.

- item: Repair the v2 readiness fail-open, stale feedback, and post-freeze permission handling, then close the production-controller test gap and repeat independent reviews
  status: done
  dispatched: original implementer retains production-only custody for correctness R1/R2, durable post-freeze authority, and security re-review R1 live AX-trust sampling; original tdd-guide retains test-only custody for R3, the legacy-setting matrix, and revoked-trust confirmation coverage; independent reviewers re-review each resulting delta
  result: All R1-R4 findings are closed. Live AX trust is sampled across fallback admission, both consecutive preflight composites, and postflight; trust loss preserves exact authority with zero pre-mutation output. Real production editor attachment, feedback-clear-on-edit, monitoring-failure retention, all legacy setting combinations, and same-panel retry are executable. Final correctness and security verdicts pass with zero blocking findings.

- item: Close v4 correctness R1-R3 before installation by moving final validation outside the epoch lock, rechecking modifiers immediately before the first post, and restoring executable async and post-boundary oracles
  status: done
  dispatched: original tdd-guide owns test-only RED/GREEN repair for exact and application-bound modifier transitions, all 51 retired async tests, and executable mandatory-key-up fault injection; output/security implementer owns the minimal production transaction reorder only after RED evidence; correctness and security reviewers must re-review before replacement installation
  result: Exact/application modifier transitions are now pre-boundary zero-post failures, executable mandatory-up tests pass, all 103 StreamingMainViewModelTests execute with no blanket skips, and final matrices were green; correctness re-review closed R1-R3 but exposed superseding drain-expiry authority bypass R4.

- item: Close v4 correctness R4 so drain expiry preserves a partial preview without granting Send or Return authority before final recognition action 2
  status: done
  dispatched: original tdd-guide owns test-only RED/GREEN for real Send and qualified Return zero-delivery plus multiline retention; UI/coordinator implementer owns the minimal durable non-authoritative recovery surface; correctness and security reviewers repeat final review before installation
  result: Drain expiry now retains exact safe text including LF only in non-authoritative read-only recovery with no Send/Return/delivery callback. R4 3/3, Streaming 105/105, focused 265/265, full 483 plus one live-TCP skip, Debug/Release, strict lint, correctness, security, docs, and topology gates all pass.

- item: Diagnose the third installed UAT failure and review the Send, Return, focus, synchronization, and one-shot submission design against measured runtime and KaolaTerminal
  status: done
  dispatched: investigator proves the installed hang from a live process sample; code-architect reviews the authority, synchronization, focus, and lifecycle design; code-explorer compares the actual KaolaTerminal preview implementation read-only; self stops the rejected app and docks evidence into Issue #40
  result: PID 99976 proved a deterministic same-thread NSLock self-deadlock before Unicode posting; delivery tests used unlocked substitutes and missed the concrete composition. Return is preview-editor-local but key/first-responder acquisition is advisory, while Send disables all recovery behind an unbounded whole transaction. KaolaTerminal supplies lifecycle semantics only, not a macOS AppKit focus implementation. The installed candidate is rejected and stopped.

- item: Define and implement the v5 macOS confirmation-focus contract before another installed candidate
  status: done
  dispatched: owner authorized completion; code-architect formalizes the v5 nonactivating local-key preview, non-reentrant commit gate, bounded pre-boundary lifecycle, and terminal post-boundary authority; security review, TDD, split production implementation, independent reviews, validation, replacement install, and owner UAT follow in dependency order
  result: V5 completed the nonactivating local-key preview, bounded non-reentrant submission transaction, fixed opaque target lease, final security sandwich, and 324/537 green gates. Its installed UAT then exposed the superseding delayed-Accessibility lifecycle-observer defect; v6 retains the v5 confirmation/output boundary and repairs that startup ordering.

- item: Diagnose and eliminate the final v5 test hang in the real Send-click path without weakening explicit-confirmation coverage
  status: done
  dispatched: investigator proved the invalid synchronous AppKit mouseDown helper blocks before production submission and recorded /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/send-click-test-hang-diagnosis.md; tdd-guide now owns the test-only real-panel event-injection correction and repeated anti-hang evidence without manufacturing an intent
  result: The helper now queues a real down/up pair and pumps AppKit for a bounded 50 ms, so misses cannot block in NSTextView tracking. The coordinator selector passed five serialized repetitions, ReviewFirstMainViewModelTests passed 33/33, ReviewWindowControllerReadinessTests passed 17/17, and test-green-v5.md records baseline hang plus GREEN evidence.

- item: Close the final v5 R3 review blockers at the last target sample, per-AX cancellation/deadline boundary, expired-start terminalization, and real production Return matrix
  status: done
  dispatched: code-architect recorded the dependency-safe R3 amendment in /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/architecture-blueprint-v5-r3.md; tdd-guide established test-only RED for post-pair drift, expired start, coordinator recovery, and real-panel whitespace Return; output implementer now owns AccessibilityClient/ReviewSubmissionExecutor production repairs and the UI implementer owns the ReviewWindowController whitespace-return gate; both independent reviewers re-review the final delta
  result: Pair construction is followed by a leading/binding/trailing final composite before every commit reservation; all 15 System AX step IDs have fixed exact/application-bound cancellation and deadline matrices; expired starts terminalize exactly once and restore the draft; the real panel owns the complete Return/IME/modifier matrix. Focused 324/324, full 537 plus one expected live-TCP skip, Debug/Release, strict lint, correctness R6, and security R6 all pass.

- item: Diagnose and repair the installed v5 UAT failure where Fn reports that the input position cannot be confirmed before the preview starts
  status: done
  dispatched: owner required inline work; self stopped the rejected candidate, correlated runtime/TCC/source evidence, implemented the production-only repair, ran validation, signed and installed the Release, audited sole-copy state, and recorded the evidence without further delegation
  result: V6 fixed the one-shot lifecycle-monitor/Accessibility authorization race, but authorized installed logs then proved four deeper securityRejected captures. V7 removed ambient system-wide capture authority; v8 commit f9ed961 persisted privacy-safe value-only capture diagnostics. The privacy-safe probe reproduced the remaining compatibility shape: Safari focus was AXWebArea with no subrole/settable selection while Secure Input was false and Accessibility trust true. V7/v8 incorrectly classified every successfully read non-AXTextField/non-AXTextArea role as unverifiable, blocking the designed application-bound fallback. V9 commit 584e09d classifies non-native roles as ordinary capability misses while retaining fail-closed Secure Input, trust, identity/frontmost, cancellation, and deadline gates. Focused security/delivery 100/100, full 539 plus one expected skip, strict lint, signed Release install, and sole-copy audit pass. On 2026-08-24 the owner exercised the installed Fn-to-durable-editable-preview-to-explicit-confirmation path and reported it looked good with no remaining observed problem, authorizing finalization; broad cross-application compatibility and OS target-consumption acknowledgement remain outside the claim.
