# Remove cursor-position confirmation and restore direct current-focus speech input

- item: Trace the released cursor-capture failure and define the smallest behavior change that removes AX position confirmation without weakening secure-input protections.
  status: done
  dispatched: self; evidence will be recorded inline and in repository source paths.
  result: MainViewModel.prepareCursorTarget currently turns any AX focused-element query failure or unsupported target into the blocking message at MainViewModel.swift:269/291; make AX live-range capture optional, retain system Secure Event Input rejection, and route final text once to the current focus when no AX session exists.

- item: Add regression coverage proving recording and transcription can start without a confirmable AX cursor element, with test custody separate from implementation.
  status: done
  dispatched: tdd-guide owns FeishuSpeechTests regression changes and must record a baseline RED command/result; production files are off-limits. Output lands directly in the issue-26 worktree plus a concise final report.
  result: FeishuSpeechTests/StreamingMainViewModelTests.swift now covers thrown/unavailable AX capture, exactly-once current-focus final output, and secure-target zero output; focused baseline run exited 65 with the expected startup-gate failures.

- item: Implement direct current-focus output without the cursor-location gate and make the regression suite pass.
  status: done
  dispatched: implementer owns the minimal production change in MainViewModel/TextInputSimulator-related seams plus a follow-up removing the coordinator's ambient Carbon Secure Input dependency while retaining the live check in SystemFinalTextOutput; tests remain read-only and no app/permission prompt is allowed.
  result: AX capture is now opportunistic; unavailable capture enters unbound streaming, and a nonempty final is delivered at most once through clipboard-free current-focus Unicode output with typed security rejection and one copy-only ordinary-failure recovery. The lifecycle-free full suite passes 181 of 181.

- item: Resolve the Xcode macOS test-worker materialization failure without launching the installed app or triggering permission requests, and obtain executable regression evidence if safely possible.
  status: done
  dispatched: build-error-resolver performs read-only test-infrastructure diagnosis and may run only a non-installed, non-permission-prompting test path; evidence lands in a concise final report and no tracked files may change.
  result: Hosted xcodebuild stalls before XCTest proxy initialization; a copied/re-signed direct xctest bundle safely ran 19 tests in 0.083s, with 18 passing and one deterministic ambient Secure Input failure that identifies the remaining coordinator fix.

- item: Add RED coverage for unbound current-focus delivery failure recovery, security rejection, stable frontmost targeting, and clipboard-free direct Unicode output.
  status: done
  dispatched: tdd-guide owns only FeishuSpeechTests follow-up changes, records baseline RED evidence through lifecycle-free direct XCTest or test compilation, and must not edit production or launch an app/permission prompt.
  result: StreamingMainViewModelTests and FinalTextOutputSecurityTests now specify distinct security rejection, exactly-once failure recovery, two-point Secure Input/frontmost-PID checks, and clipboard-free Unicode posting; focused build exits 65 on the missing production contracts as expected.

- item: Add RED coverage that preserves the concrete Unicode poster's security-rejection reason without a racy resample.
  status: done
  dispatched: tdd-guide owns only FinalTextOutputSecurityTests follow-up changes and must specify a typed poster result for posted, security-rejected, and ordinary-failure outcomes; production remains off-limits and no app/permission prompt is allowed.
  result: FinalTextOutputSecurityTests now requires FinalTextCurrentFocusPostResult and proves poster security rejection/ordinary failure/success propagate without a third ambient Secure Input resample; focused build exits 65 on the missing production type as expected.

- item: Review correctness and security, dock behavior documentation, and run lint, full tests, Debug build, and Release build.
  status: done
  dispatched: code-reviewer writes kaola-workflow/issue-26/code-review-uat-fix.md; security-reviewer writes kaola-workflow/issue-26/security-review-uat-fix.md; doc-updater owns README/CHANGELOG/docs behavior docking and reports changed paths. Validation remains with the main session.
  result: Code review PASS and security review PASS with zero blockers; documentation is docked across README, changelog, API, architecture, decision, and streaming-design references. Strict SwiftLint reports zero violations, Debug build-for-testing succeeds, the lifecycle-free suite passes 181/181, and Release build plus strict code-sign verification succeeds.

- item: Finalize the workflow run, keep issue 26 open for owner UAT, then replace Applications with the sole validated Release copy.
  status: done
  result: Finalization completed in keep-open mode. The validated Release 1.0 build 1 replaced `/Applications/FeishuSpeech.app`, strict code-sign and executable-hash checks passed, no application was launched, no permission prompt was requested, and the Applications scan found one installed copy.
