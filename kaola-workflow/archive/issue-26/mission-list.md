# Fix immediate streaming failure and guarantee overlay teardown on every terminal path

- item: Trace the installed Release failure from existing logs and code, without launching the app or requesting permissions.
  status: done
  dispatched: investigator performs read-only inspection of existing unified logs and the streaming/overlay terminal paths, while knowledge-lookup checks the implemented endpoint and payload against official Feishu documentation; neither may launch the app, request permissions, use credentials, or edit tracked files, and both return evidence in final reports to the main session.
  result: Real-process logs show token authentication rejected before a streaming session was created; official Feishu contract review found no endpoint or payload mismatch. The stuck overlay is a local `.error` feedback loop: 3,961 callbacks and cleanups in five seconds continuously advanced the overlay generation, preventing `orderOut`. The stuck PID was terminated without relaunching the app.

- item: Add baseline-RED regression coverage for immediate streaming failure cleanup and overlay dismissal, with test custody separate from production implementation.
  status: done
  dispatched: tdd-guide owns only FeishuSpeechTests changes in the issue-26 worktree, specifies that immediate provider startup/terminal failure dismisses the overlay and fully tears down the active streaming generation, records lifecycle-free baseline RED evidence, and reports the changed test paths and command to the main session.
  result: StreamingMainViewModelTests and HotKeyServiceTests now prove one teardown/hide for terminal failure, fixed transcript-free authentication feedback, late-callback rejection, and one observable publication for repeated identical errors. Lifecycle-free REDs fail on duplicate teardown, generic auth copy, and three identical state publications.

- item: Repair the live streaming failure and terminal overlay lifecycle while preserving current-focus delivery and transcript privacy.
  status: done
  dispatched: implementer owns the minimal production changes in MainViewModel and HotKeyService, must satisfy the test-owned RED contracts, preserve sanitized authentication feedback and current-focus output, and must not edit tests, launch the app, access credentials, or trigger permission prompts.
  result: MainViewModel now stops after a terminal packet, invalidates the active generation once, and ignores HotKey error echoes when no session is active; HotKeyService suppresses duplicate identical errors and provider authentication failures use fixed private feedback. The three focused regressions pass, the full lifecycle-free suite passes 184/184, strict lint reports zero violations, and Debug build-for-testing succeeds.

- item: Review correctness and security, dock the UAT behavior, and run lifecycle-free tests, strict lint, Debug, and Release validation.
  status: done
  dispatched: code-reviewer and security-reviewer independently audit the four-file implementation/test diff and write receipts without edits; doc-updater owns only behavior and UAT documentation, including the pre-stream authentication boundary, guaranteed terminal teardown, sanitized feedback, and owner-testing requirement.
  result: Correctness and security reviews both PASS with zero blocking findings. README, changelog, API, architecture, streaming design, and D-25-01 are docked. The final code/test candidate passes 184/184 lifecycle-free tests, strict SwiftLint reports zero violations, Debug build-for-testing succeeds, and Release 1.0 (build 1) builds and passes strict code-sign verification.

- item: Finalize and sink the UAT repair, keep issue #26 open for owner testing, then replace Applications with one verified Release without launching it.
  status: done
  dispatched: the main session owns the consumer validation receipt, documentation docking receipt, run-gap sweep, keep-open finalize/sink transaction, verified Applications replacement, and cleanup; it will not launch the app or request macOS permissions.
  result: Validation, documentation, reviews, gap sweep, keep-open metadata, and the implementation commit are ready for the mechanical finalize/sink transaction. Release 1.0 (build 1) was byte-compared to the built candidate, passes strict code-sign verification, and is the sole installed copy at /Applications/FeishuSpeech.app; the application remains stopped and no permission request was triggered.
