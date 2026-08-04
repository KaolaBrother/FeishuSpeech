# Fix repeated and revised Feishu streaming snapshots with safe keyboard replacement and deliver one testable Release

- item: Prove the build-6 repetition regression and the agreed grapheme-aware replacement contract with production-shaped failing tests.
  status: done
  dispatched: TDD Guide owns regression tests in the issue-27 worktree and will land a failing test commit on workflow/issue-27, reporting the commit and focused RED command here.
  result: Commit 167a50f adds production-shaped RED coverage; direct xctest proves concatenation, retry duplication, and suppressed shorter/revised/emoji replacement failures while sealing already passes.

- item: Implement snapshot ownership separation and serialized Backspace-plus-Unicode replacement while preserving retry, sealing, destination, and privacy boundaries.
  status: done
  dispatched: Implementer owns production changes in MainViewModel, CurrentFocusAppendSession, TextInputSimulator, and only narrowly required input-monitor seams in the issue-27 worktree; output will land as a production commit on workflow/issue-27.
  result: Production commits 409452a and ae71ff8 implement raw snapshot ownership, duplicate suppression, grapheme replacement transactions, tagged external-input suspension, release sealing, and transcript-free receipts; implementer verified 280/280 and strict lint clean.

- item: Migrate stale concatenation and revision-suppression tests to the accepted snapshot-replacement contract and cover any missing transaction safety boundary.
  status: done
  dispatched: TDD Guide owns test-only expectation migration and missing issue-27 safety cases in FeishuSpeechTests; output will land as a separate test commit on workflow/issue-27.
  result: Test-only commits 3d1e54b and 1b9c3b6 migrate stale oracles and add transaction construction, ordering, tagging, Unicode, external-input, retry, and sealing coverage; focused direct XCTest passes 22/22, 15/15, and 74/74 against production shape.

- item: Audit the completed mutation for correctness and security, then resolve every in-scope finding.
  status: done
  dispatched: Code Reviewer and Security Reviewer independently perform the final audit of the full issue-27 range through ec4ddd6; only two PASS receipts will close the mission.
  result: Correctness and security independently PASS after R1-R9 closure; production ec4ddd6, real-gate tests cd1132c, and canonical provenance 6e5d262 agree with no actionable findings.

- item: Prove the admitted replay-ownership, multiline-admission, input-monitor, and diagnostic review findings with focused failing tests.
  status: done
  dispatched: TDD Guide owns test-only RED coverage for review findings R1-R4 and the same-app/registration/race security cases; output will land as a test commit on workflow/issue-27.
  result: Test-only commit 98d75b6 reproduces unsafe/contentless replay re-ownership, LF suppression, monitor-arm failure, same-app/queued input races, and stale appendedSuffix outcomes against ae71ff8.

- item: Fix every admitted correctness and security review finding without weakening the snapshot-replacement contract.
  status: done
  dispatched: Implementer owns production-only repairs for review findings R1-R4 and the paired synchronous input-monitor security boundary; output will land as a fix commit on workflow/issue-27.
  result: Commit 6266415 reserves ineligible packet indices, admits LF safely, requires paired synchronous input monitoring, reports replacedOwnedTail accurately, and passes 289/289 with strict lint clean.

- item: Prove the external-target input-ordering race and action-capable LF keyboard risk under the narrowed security contract.
  status: done
  dispatched: TDD Guide owns test-only RED coverage for a pre-dispatch interference epoch and AX-only LF admission; output will land as a test commit on workflow/issue-27.
  result: Test-only commit 47d90ed proves missing epoch sampling, key/mouse queued races, unguarded multi-Backspace posting, and LF keyboard emission while retaining green AX multiline behavior.

- item: Close the final audit defects with synchronous HID interference authority and route-specific LF handling.
  status: done
  dispatched: Implementer owns production-only synchronous interference epoch, guarded transaction, and AX-only LF repairs; output will land as a fix commit on workflow/issue-27.
  result: Commit d138624 integrates the HID interference epoch, guards every destructive event, rejects LF on generic keyboard output while preserving AX multiline data, and passes 292/292 with strict lint clean.

- item: Reconcile decision and user-facing documentation with HID-epoch authority and AX-only multiline output.
  status: done
  dispatched: Documentation specialist owns docs-only security-narrowing updates after d138624; output will land as a documentation commit on workflow/issue-27.
  result: Commit 396d7c0 docks AX-only multiline data, generic keyboard action-control rejection, HID epoch authority, supplemental monitors, and fail-closed arming across decisions and user docs.

- item: Prove atomic check-to-post, monitor-arm baseline, and event-tap-disable interference boundaries with focused failing tests.
  status: done
  dispatched: TDD Guide owns test-only RED coverage for the final audit race boundaries; output will land as a test commit on workflow/issue-27.
  result: Test-only commit 8ebf31e proves non-atomic arm baseline, check-to-post event ordering, and missing tap-disable epoch mutation with 8 focused RED failures.

- item: Implement a shared atomic interference gate across arming, HID epoch mutation, and each synthetic key pair.
  status: done
  dispatched: Implementer owns production-only atomic gate, atomic arm-token, and tap-disable loss-of-observability repairs; output will land as a fix commit on workflow/issue-27.
  result: Commit ec4ddd6 atomically serializes monitor arming, HID epoch mutation, complete key pairs, and tap-disable loss of observability; full direct suite passes 296/296 with strict lint clean.

- item: Reconcile the legacy mid-transaction race test with the new atomic poster seam without weakening either assertion.
  status: done
  dispatched: TDD Guide owns the contradictory test-only seam repair identified during atomic-gate implementation; output will land as a test commit on workflow/issue-27.
  result: Test-only commit 81dbfc8 migrates the legacy race oracle to the atomic complete-pair seam; both focused atomic tests and all 35 CurrentFocus tests pass against the pending production repair.

- item: Exercise the production SystemFinalTextCurrentFocusEventPoster and real shared gate under atomic drift ordering.
  status: done
  dispatched: TDD Guide owns production-boundary test coverage for review finding R9 in FinalTextOutputSecurityTests; output will land as a test-only commit on workflow/issue-27.
  result: Test-only commit cd1132c directly exercises the production poster and gate under pre-pair, mid-transaction, and insertion-only drift; full direct suite passes 300/300.

- item: Refresh canonical issue-27 provenance and describe the lock held across each complete key pair.
  status: done
  dispatched: Documentation specialist owns the final commit/test provenance and atomic-pair wording for review finding R8; output will land as a docs-only commit on workflow/issue-27.
  result: Docs-only commit 2c643ed records ec4ddd6 plus final test provenance and the atomic arm/pair/tap-disable safety contract across decisions, design, API, architecture, README, and changelog.

- item: Attribute final production-gate test evidence to cd1132c in every canonical issue-27 source.
  status: done
  dispatched: Documentation specialist owns the narrow R8 provenance correction in D-27-01, streaming design, and API docs; output will land as a docs-only commit on workflow/issue-27.
  result: Docs-only commit 6e5d262 attributes real production-poster/gate closure to cd1132c in D-27-01, streaming design, and API while retaining earlier race-test history accurately.

- item: Dock the owner-approved keyboard snapshot-replacement correction against the prior issue-26 design and user-facing documentation.
  status: done
  dispatched: Documentation specialist owns docs-only docking in the issue-27 worktree; output will land as a separate documentation commit on workflow/issue-27.
  result: Commit cc43b9c adds D-27-01 and docks the snapshot-replacement contract across D-25/D-26, streaming design, architecture, API, README, docs index, and changelog.

- item: Pass focused tests, the full suite, strict lint, and Debug and Release builds.
  status: done
  dispatched: Investigator owns an isolated clean validation of workflow/issue-27 through build 7; results will be reported with commands, counts, app metadata, signature verification, and clean-worktree evidence.
  result: Independent gate at 77e8b41 passes strict lint, build-for-testing, 300/300 full direct tests, focused 35/35 + 19/19 + 77/77, Debug/Release builds, 1.0 (7) metadata, signature verification, privacy scan, and clean state.

- item: Stamp Release 1.0 with the next build number so owner UAT can distinguish it from build 6.
  status: done
  dispatched: Implementer owns the narrow project-version metadata update and verification; output will land as a config-only commit on workflow/issue-27.
  result: Config-only commit 77e8b41 sets repository-default CURRENT_PROJECT_VERSION 7 for app/tests, retains MARKETING_VERSION 1.0, and builds Release metadata as 1.0 (7).

- item: Prepare the finalized issue-27 archive and replace Applications with one unlaunched Release copy for owner UAT.
  status: done
  dispatched: self owns consumer validation receipt, docking, gap sweep, summary, workflow sink, closure audit, and sole Applications Release replacement; outputs land in the issue-27 archive and /Applications/FeishuSpeech.app.
  result: Finalization archived the keep-open UAT cycle; /Applications/FeishuSpeech.app is the sole matching Applications bundle at Release 1.0 build 7, signature-valid and unlaunched, with build 6 and isolated build artifacts moved recoverably to Trash.
