
# Issue #40 v2 final validation receipt

Date: 2026-08-23 (Asia/Shanghai)
Role: read-only final investigator
Candidate worktree: /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40
Candidate branch/HEAD: workflow/issue-40 / 60090c955fbd57d4b6e875acb8a9bdc42d61f032
HEAD subject: fix: keep review available without exact AX cursor (#40)
Comparison baseline: 60090c955fbd57d4b6e875acb8a9bdc42d61f032
Receipt path: /Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/final-validation-v2.md

Authority set: architecture-blueprint-v2.md, test-red-v2.md, test-green-v2.md, test-red-v3.md, test-green-v3.md, and the canonical Issue #40 v2/v3 body. The current candidate contains shared, uncommitted production/test/documentation work; this validation did not edit those files. The only file written by this investigator is this receipt.

## Final verdict

PASS for the complete final Issue #40 v3 gate. The final-tree v3 focused and serialized tests, Debug/Release builds, canonical strict lint, protected async-path checks, forbidden output-route searches, documentation link/reference checks, and whitespace checks are all green. No blocker remains.

The final v3 measurements are recorded in the dated v3 rerun section at the end of this receipt. Earlier v2 failures, pre-repair lint evidence, and all pre-delta evidence are historical/provisional and are not used as the final verdict.

The sections through the earlier handoff preserve the pre-repair evidence for narrowing and provenance. Their counts and lint result are superseded by the final post-lint-repair rerun at the end of this receipt.

## Setup

Environment commands and observations:

    sw_vers
    uname -m
    xcodebuild -version
    swift --version
    swiftlint version
    git rev-parse --show-toplevel
    git rev-parse HEAD
    git status --short

Observed environment:

- macOS 26.6.2, build 25G83; arm64 MacBook Pro M5 Max.
- Xcode 26.6 (17F113).
- Swift 6.3.3; swift-driver 1.148.6.
- SwiftLint 0.65.0.
- The candidate had 24 modified tracked files and one untracked readiness-test file before this receipt was written. No production, test, or documentation file was reverted or edited by this validation.

## Observation table

| Measurement | Command/result | Exit |
|---|---|---:|
| Final affected suites | 57 total: 57 passed, 0 skipped, 0 failed | 0 |
| Final blueprint-focused selectors | 230 total: 179 passed, 51 skipped, 0 failed | 0 |
| Final complete FeishuSpeech target | 457 total: 405 passed, 52 skipped, 0 failed | 0 |
| Debug build | BUILD SUCCEEDED | 0 |
| Release build | BUILD SUCCEEDED | 0 |
| Strict lint | One MainViewModel.swift:1816:13 cyclomatic-complexity error | 2 |
| Diff whitespace | No output from git diff --check | 0 |
| Protected path diff | No output; all nine protected paths equal baseline | 0 |
| Changed-document local links | No broken local targets | 0 |
| Changed-document decision references | No missing decision files | 0 |
| Forbidden accepted-path searches | No accepted-production matches | 1 (no matches) |
| Legacy route-setting search | No matches | 1 (no matches) |

## Final affected suites

Exact command:

    xcodebuild -scheme FeishuSpeech -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test

Exit: 0

Result bundle:
 /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-29-15-+0800.xcresult

| Suite | Passed | Skipped | Failed |
|---|---:|---:|---:|
| ReviewDestinationDeliveryTests | 13 | 0 | 0 |
| ReviewFirstApplicationFallbackTests | 16 | 0 | 0 |
| ReviewFirstMainViewModelTests | 28 | 0 | 0 |
| Total | 57 | 0 | 0 |

This includes the live Accessibility-trust regression cases. The affected final-tree leg is green.

## Blueprint-focused selectors

Exact command:

    xcodebuild -scheme FeishuSpeech -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/AppSettingsCredentialStorageTests -only-testing:FeishuSpeechTests/StreamingMainViewModelTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests test

Exit: 0

Result bundle:
 /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-29-58-+0800.xcresult

| Suite | Passed | Skipped | Failed |
|---|---:|---:|---:|
| AppSettingsCredentialStorageTests | 16 | 0 | 0 |
| FinalTextOutputSecurityTests | 23 | 0 | 0 |
| ReviewDestinationDeliveryTests | 13 | 0 | 0 |
| ReviewFirstApplicationFallbackTests | 16 | 0 | 0 |
| ReviewFirstMainViewModelTests | 28 | 0 | 0 |
| ReviewPasteboardLifecycleTests | 7 | 0 | 0 |
| ReviewWindowControllerReadinessTests | 7 | 0 | 0 |
| StreamingMainViewModelTests | 52 | 51 | 0 |
| TranscriptionReviewViewKeyboardTests | 13 | 0 | 0 |
| TranscriptionReviewViewTests | 4 | 0 | 0 |
| Total | 179 | 51 | 0 |

## Complete serialized test target

Exact command:

    xcodebuild -scheme FeishuSpeech -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test

Exit: 0

Result bundle:
 /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-30-23-+0800.xcresult

| Suite | Passed | Skipped | Failed |
|---|---:|---:|---:|
| AppSettingsCredentialStorageTests | 16 | 0 | 0 |
| AudioRecorderFailureTests | 4 | 0 | 0 |
| AudioRecorderStreamingIntegrationTests | 7 | 0 | 0 |
| BoundTLSSocketTests | 3 | 0 | 0 |
| CurrentFocusAppendSessionTests | 37 | 0 | 0 |
| CursorTextSessionTests | 15 | 0 | 0 |
| DirectFeishuKeepAliveSessionTests | 5 | 1 | 0 |
| EmptyResultFeedbackTests | 3 | 0 | 0 |
| FeishuAPIServiceTests | 36 | 0 | 0 |
| FeishuStreamingSessionTests | 24 | 0 | 0 |
| FinalTextOutputSecurityTests | 23 | 0 | 0 |
| HoldPacketJournalTests | 5 | 0 | 0 |
| HotKeyServiceTests | 29 | 0 | 0 |
| HotKeyStateTests | 4 | 0 | 0 |
| MainViewModelTests | 8 | 0 | 0 |
| MonitoringStateBindingTests | 4 | 0 | 0 |
| PermissionManagerTests | 7 | 0 | 0 |
| ReviewDestinationDeliveryTests | 13 | 0 | 0 |
| ReviewFirstApplicationFallbackTests | 16 | 0 | 0 |
| ReviewFirstMainViewModelTests | 28 | 0 | 0 |
| ReviewPasteboardLifecycleTests | 7 | 0 | 0 |
| ReviewWindowControllerReadinessTests | 7 | 0 | 0 |
| StreamingAudioIngressTests | 15 | 0 | 0 |
| StreamingCoordinatorStateTests | 6 | 0 | 0 |
| StreamingDrainPolicyTests | 3 | 0 | 0 |
| StreamingMainViewModelTests | 52 | 51 | 0 |
| TranscriptionReviewViewKeyboardTests | 13 | 0 | 0 |
| TranscriptionReviewViewTests | 4 | 0 | 0 |
| TransportAttemptContextTests | 11 | 0 | 0 |
| Total | 405 | 52 | 0 |

Skip extraction command:

    xcrun xcresulttool get test-results tests --path '/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-30-23-+0800.xcresult' --format json | ruby -rjson -e 'root=JSON.parse(STDIN.read); walk=lambda{|n,&b| Array(n).each{|x| b.call(x); walk.call(x["children"],&b) if x.is_a?(Hash) && x["children"]}}; skips=[]; walk.call(root["testNodes"]){|n| skips << n["name"] if n["nodeType"]=="Test Case" && n["result"]=="Skipped"}; puts skips.join("\n")'

The 52 skips were classified as follows:

- One intentional live-network skip: test_liveKeepAliveTCPIsNotOnVPNTunnelAddress(). It avoids an extra live socket because the live TCP test previously hung the XCTest host; Issue #34 forbids extra live sockets.
- Fifty-one retired StreamingMainViewModelTests direct-output oracles. Each records: Retired obsolete direct-output MainViewModel oracle; canonical preview route is covered by ReviewFirstMainViewModelTests.
- No test failures were hidden by the skip set.

## Builds, lint, and whitespace

Exact commands and results:

    xcodebuild -scheme FeishuSpeech -configuration Debug build

Exit: 0; BUILD SUCCEEDED.

    xcodebuild -scheme FeishuSpeech -configuration Release build

Exit: 0; BUILD SUCCEEDED.

    swiftlint --strict

Exit: 2. Sole reported violation:

    FeishuSpeech/ViewModels/MainViewModel.swift:1816:13: error: Cyclomatic Complexity Violation: Function should have complexity 10 or less; currently complexity is 12 (cyclomatic_complexity)

This is classified as a product quality-gate defect in the candidate tree, not an environment or stale-oracle failure. No source change was made.

    git diff --check

Exit: 0; no output.

Build warnings observed but non-blocking:

- xcodebuild reports multiple matching destinations and selects the arm64 My Mac destination.
- The test/build logs include the expected host-environment warnings for Accessibility and microphone permissions, login-item operation not permitted, linkd autoShortcut Code4097, and NSCGS/CoreAnimation. They did not cause test failures.
- A Swift 6 captured-variable warning was observed in a test compile (FeishuAPIServiceTests.swift:313, mutation of captured delays in concurrently executing code); the final tests still passed.

## Protected path verification

Exact command:

    git diff --exit-code 60090c955fbd57d4b6e875acb8a9bdc42d61f032 -- FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/ByteBoundedAudioIngress.swift FeishuSpeech/Services/HoldPacketJournal.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Models/StreamingSpeechModels.swift FeishuSpeech/Models/StreamingSpeechProvider.swift FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift FeishuSpeech/Services/BoundTLSSocket.swift FeishuSpeech/Services/TransportAttemptContext.swift

Exit: 0; no path differences and no output.

SHA-1 comparison (working tree versus baseline for each protected path):

| Protected path | Current | Baseline |
|---|---|---|
| FeishuSpeech/Services/AudioRecorder.swift | 18232a39248ad6f252a98ca815674918a5526bef | 18232a39248ad6f252a98ca815674918a5526bef |
| FeishuSpeech/Services/ByteBoundedAudioIngress.swift | 4bc7bcfa403ea756a65d2c12753875e66945c24f | 4bc7bcfa403ea756a65d2c12753875e66945c24f |
| FeishuSpeech/Services/HoldPacketJournal.swift | 11dc1cf394da8cb51738444980f98b25789e6225 | 11dc1cf394da8cb51738444980f98b25789e6225 |
| FeishuSpeech/Services/FeishuStreamingSession.swift | fb4982923fc2a4e05a93221ab6ce172247799df3 | fb4982923fc2a4e05a93221ab6ce172247799df3 |
| FeishuSpeech/Models/StreamingSpeechModels.swift | 7ca8d9c312511efd9183326068d6665584eed608 | 7ca8d9c312511efd9183326068d6665584eed608 |
| FeishuSpeech/Models/StreamingSpeechProvider.swift | eaa50c5709c563a05088be3598ffdf5adb57aba9 | eaa50c5709c563a05088be3598ffdf5adb57aba9 |
| FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift | 52f1475e505af628709ccdc15c74e5e6ac092f21 | 52f1475e505af628709ccdc15c74e5e6ac092f21 |
| FeishuSpeech/Services/BoundTLSSocket.swift | c49d3fd9ac9ebc3d52b784e360d51fb63e1abf7b | c49d3fd9ac9ebc3d52b784e360d51fb63e1abf7b |
| FeishuSpeech/Services/TransportAttemptContext.swift | 22416290c612973235b4d9c6dfd7e96067a08275 | 22416290c612973235b4d9c6dfd7e96067a08275 |

The allowed final trust-race delta is limited to these changed production paths:

- FeishuSpeech/Services/AccessibilityClient.swift — current 7d03f3771a85165b72c5c2ef453357be1faaa413; baseline b28d1c3986a16c4dca946829cbe60dab5fb771bb.
- FeishuSpeech/Services/ReviewDestinationDelivery.swift — current 4db749feb5c7d67fe1f18457dc39a1d80a65006c; baseline 275256e70ebf9c67b63ef1c634d01e01e5c66b72.

The corresponding final tests cover trust revocation after capture, trust revocation in the composite preflight interval, and trust revocation during postflight. The final affected 57-test leg above is green.

## Forbidden-path and route searches

Accepted-path direct/copy/manual-recovery search:

    rg -n 'copyForManualRecovery|manualRecoveryCopied|recoverReviewSurfaceFailure|reviewCopyRecoveryIssued|copyToPasteboard' FeishuSpeech --glob '*.swift' | rg -v 'Models/(CursorTextModels|RecordingState)\.swift'

Exit: 1; no output.

MainViewModel direct-output search:

    rg -n 'insertOnce|insertReviewAtCurrentFocusOnce|replaceSelectedText|simulateTextInput' FeishuSpeech/ViewModels/MainViewModel.swift

Exit: 1; no output.

Interaction-mode bypass search:

    rg -n 'InteractionOutputMode|activeInteractionOutputMode|sampledAutoInsert|isReviewFirstMode' FeishuSpeech

Exit: 1; no output.

Legacy route-setting branch search:

    rg -n 'reviewBeforeInsert.*\?|if .*reviewBeforeInsert|switch .*reviewBeforeInsert|if .*autoInsert|switch .*autoInsert|prepareCursorTarget\(|compatibility\(' FeishuSpeech/ViewModels/MainViewModel.swift FeishuSpeech/Services FeishuSpeech/Controllers FeishuSpeech/Views --glob '*.swift'

Exit: 1; no output.

An unfiltered legacy-symbol search reports only dormant compatibility/model declarations, not accepted call sites:

- FeishuSpeech/Models/RecordingState.swift: legacy presentation cases/icons/feedback at lines 8, 18, 31, 46, and 61.
- FeishuSpeech/Models/CursorTextModels.swift: manualRecoveryCopied case at line 116 and its helper return at line 132.

Those residual model symbols are not a production direct-output/manual-recovery bypass. Tests retain fakes/retired references needed for their oracles.

Capture/streaming versus review topology search:

    rg -n 'captureDrainTask|consumerTask|holdPacketJournal|retrySleepTask|sessionCreationTask' FeishuSpeech/ViewModels/MainViewModel.swift; rg -n 'renderEditable|renderDraft|requestEditableReadiness|await .*reviewSurface|await .*present' FeishuSpeech/ViewModels/MainViewModel.swift

Observed task ownership is in the MainViewModel capture/consumer/journal/retry/session cleanup region (lines 292-303 and 718/721 plus lifecycle cleanup); review render/readiness calls occur at lines 499, 1871, 1919, 1958, 1992, 1998, 2005, 2085, 2134, 2173, and 2247. This is structural evidence that capture/streaming delivery does not await the review presenter in its ingestion lane; it is an inference from the search, not a substitute for runtime proof.

## Documentation checks

The final changed Markdown set was:

    CHANGELOG.md
    README.md
    docs/README.md
    docs/architecture.md
    docs/decisions/D-25-01.md
    docs/decisions/D-26-01.md
    docs/decisions/D-27-01.md
    docs/decisions/D-38-01.md
    docs/decisions/D-39-01.md
    docs/decisions/D-40-01.md
    docs/designs/capture-recognition-split-direct-connect.md
    docs/streaming-speech-design.md

The final relative-link checker over exactly those 12 files exited 0 with no broken local targets. The final decision-reference checker over exactly those 12 files exited 0 with no missing D-<n>-<n> files. The final trailing-whitespace scan exited 1 with no matches.

Literal final documentation-check commands and results:

    ruby -e 'require "pathname"; bad=[]; ARGV.each{|f| base=Pathname(f).dirname; File.read(f).scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each{|u| next if u.start_with?("http://","https://","mailto:","#"); target=u.split("#",2).first; next if target.empty?; path=(base+Pathname(target)).cleanpath; bad << "#{f}:#{u}" unless path.exist?}}; abort bad.join("\n") unless bad.empty?' CHANGELOG.md README.md docs/README.md docs/architecture.md docs/decisions/D-25-01.md docs/decisions/D-26-01.md docs/decisions/D-27-01.md docs/decisions/D-38-01.md docs/decisions/D-39-01.md docs/decisions/D-40-01.md docs/designs/capture-recognition-split-direct-connect.md docs/streaming-speech-design.md

    ruby -e 'missing=[]; ARGV.each{|f| text=File.read(f); text.scan(/D-[0-9]+-[0-9]+/).uniq.each{|d| missing << "#{f}:#{d}" unless File.file?("docs/decisions/#{d}.md")}}; abort missing.join("\n") unless missing.empty?' CHANGELOG.md README.md docs/README.md docs/architecture.md docs/decisions/D-25-01.md docs/decisions/D-26-01.md docs/decisions/D-27-01.md docs/decisions/D-38-01.md docs/decisions/D-39-01.md docs/decisions/D-40-01.md docs/designs/capture-recognition-split-direct-connect.md docs/streaming-speech-design.md

    rg -n '[[:blank:]]+$' CHANGELOG.md README.md docs/README.md docs/architecture.md docs/decisions/D-25-01.md docs/decisions/D-26-01.md docs/decisions/D-27-01.md docs/decisions/D-38-01.md docs/decisions/D-39-01.md docs/decisions/D-40-01.md docs/designs/capture-recognition-split-direct-connect.md docs/streaming-speech-design.md

The first two commands exited 0 with no output. The final command exited 1 with no output, which is the expected no-match result.

Semantic stale-contract search had only historical/superseded text:

- docs/decisions/D-26-01.md:178 describes the old zero-attempt unsafe/failed-owner manual-recovery behavior as superseded historical context.
- docs/decisions/D-38-01.md contains the historical reviewBeforeInsert == false wording.
- docs/architecture.md:251 explicitly marks the old branch superseded.
- Current README language states no automatic copy/direct output/retry/retarget behavior.

Docs were checked after their last observed in-flight updates had settled. No documentation change was made by this validation.

## Provisional failure and narrowing record

A post-delta affected command was first run before the test fixtures were updated to inject the new trust provider:

- Bundle: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-16-24-+0800.xcresult
- Exit: 65.
- 55 executed, 34 failed, 0 skipped; all 34 failures were in ReviewFirstApplicationFallbackTests.
- The failure signatures were real AXIsProcessTrusted() false and zero trust/PID samples because the fixture still used the default provider. Delivery, pasteboard, and final-security suites passed.

The same stale-fixture failure reproduced in the first post-delta full-target run:

- Bundle: /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-17-43-+0800.xcresult
- Exit: 65.
- 453 total, 401 passed, 52 skipped, 34 failed, with the same fallback-only signature.

Narrowing leg: updating only the fallback test fixture to inject the controlled trust provider eliminated all 34 failures; the final affected leg became 57/57 and the final full target became 405 passed, 52 skipped, 0 failed. Classification: stale oracle/fixture, not a product defect and not an environment failure. No fixture change was made by this investigator; the final tree supplied the repaired tests.

## Reproduction status, inferences, and unmeasured items

Reproduction status: the final post-repair affected, blueprint-focused, and full test gates reproduce green on the current candidate with serialized execution, one worker, and the exact result bundles recorded in the final rerun section. Canonical strict lint also reproduces green.

Labeled inferences:

1. High confidence: the protected capture/ingress/journal/provider/transport/retry/replay/audio paths did not change from baseline; both git diff --exit-code and per-file hashes agree.
2. High confidence: the final trust race behavior is exercised by the three new controlled-provider regression cases and remains green in both the affected and full serialized runs.
3. High confidence: no accepted production path directly invokes the searched manual-recovery/copy/direct-output bypass symbols, and no legacy route-setting branch matches the forbidden search.
4. Medium confidence: the source topology supports separate capture/streaming and review-transition ownership; a live end-to-end AX/typing experiment was not part of this gate.
5. High confidence: documentation local references and decision references are internally valid; the historical matches are explicitly marked superseded.

Unmeasured or intentionally skipped:

- No live external Feishu recognition or real user Accessibility/typing session was performed.
- The one live TCP test remains intentionally skipped to avoid an extra live socket and the known XCTest-host hang.
- The 51 retired direct-output streaming oracles remain skipped by design; canonical review-first coverage is represented by the passing review-first suites.
- The production-owner lint repair was supplied in the shared tree; this investigator made no source, test, or documentation edits.

## Handoff

Final result is PASS. The post-repair final rerun below is the authoritative gate evidence. One initial hash command in that rerun used a mistyped path and exited 1; the corrected Git-object hash comparison exited 0 and matched all protected baseline paths. This was an investigator command typo, not a product, test, environment, or docs failure.

## Final post-lint-repair rerun

Rerun window: 2026-08-23 16:50-16:55 Asia/Shanghai

The repaired production tree contains the extracted editableReviewState helper at MainViewModel.swift lines 1950-1973; finishReviewTransition now calls that helper. The source was inspected read-only. No source, test, or documentation file was changed by this investigator.

### Canonical lint

Exact command:

    swiftlint --strict --config .swiftlint.yml

Exit: 0. Output: Done linting! Found 0 violations, 0 serious in 35 files.

### Affected MainViewModel suite

Exact command:

    xcodebuild -scheme FeishuSpeech -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests test

Exit: 0. Result bundle:

    /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-50-13-+0800.xcresult

Result: 29 total, 29 passed, 0 skipped, 0 failed.

The xcresult summary command exited 0 and reported passedTests 29, skippedTests 0, failedTests 0, totalTestCount 29.

### Blueprint-focused selectors

Exact command:

    xcodebuild -scheme FeishuSpeech -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/AppSettingsCredentialStorageTests -only-testing:FeishuSpeechTests/StreamingMainViewModelTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests test

Exit: 0. Result bundle:

    /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-54-35-+0800.xcresult

Result: 232 total, 181 passed, 51 skipped, 0 failed.

| Suite | Passed | Skipped | Failed |
|---|---:|---:|---:|
| AppSettingsCredentialStorageTests | 16 | 0 | 0 |
| FinalTextOutputSecurityTests | 23 | 0 | 0 |
| ReviewDestinationDeliveryTests | 13 | 0 | 0 |
| ReviewFirstApplicationFallbackTests | 16 | 0 | 0 |
| ReviewFirstMainViewModelTests | 29 | 0 | 0 |
| ReviewPasteboardLifecycleTests | 7 | 0 | 0 |
| ReviewWindowControllerReadinessTests | 8 | 0 | 0 |
| StreamingMainViewModelTests | 52 | 51 | 0 |
| TranscriptionReviewViewKeyboardTests | 13 | 0 | 0 |
| TranscriptionReviewViewTests | 4 | 0 | 0 |
| Total | 181 | 51 | 0 |

The summary command exited 0 and reported passedTests 181, skippedTests 51, failedTests 0, totalTestCount 232.

### Complete serialized FeishuSpeech target

Exact command:

    xcodebuild -scheme FeishuSpeech -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test

Exit: 0. Result bundle:

    /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-50-36-+0800.xcresult

Result: 459 total, 407 passed, 52 skipped, 0 failed.

| Suite | Passed | Skipped | Failed |
|---|---:|---:|---:|
| AppSettingsCredentialStorageTests | 16 | 0 | 0 |
| AudioRecorderFailureTests | 4 | 0 | 0 |
| AudioRecorderStreamingIntegrationTests | 7 | 0 | 0 |
| BoundTLSSocketTests | 3 | 0 | 0 |
| CurrentFocusAppendSessionTests | 37 | 0 | 0 |
| CursorTextSessionTests | 15 | 0 | 0 |
| DirectFeishuKeepAliveSessionTests | 5 | 1 | 0 |
| EmptyResultFeedbackTests | 3 | 0 | 0 |
| FeishuAPIServiceTests | 36 | 0 | 0 |
| FeishuStreamingSessionTests | 24 | 0 | 0 |
| FinalTextOutputSecurityTests | 23 | 0 | 0 |
| HoldPacketJournalTests | 5 | 0 | 0 |
| HotKeyServiceTests | 29 | 0 | 0 |
| HotKeyStateTests | 4 | 0 | 0 |
| MainViewModelTests | 8 | 0 | 0 |
| MonitoringStateBindingTests | 4 | 0 | 0 |
| PermissionManagerTests | 7 | 0 | 0 |
| ReviewDestinationDeliveryTests | 13 | 0 | 0 |
| ReviewFirstApplicationFallbackTests | 16 | 0 | 0 |
| ReviewFirstMainViewModelTests | 29 | 0 | 0 |
| ReviewPasteboardLifecycleTests | 7 | 0 | 0 |
| ReviewWindowControllerReadinessTests | 8 | 0 | 0 |
| StreamingAudioIngressTests | 15 | 0 | 0 |
| StreamingCoordinatorStateTests | 6 | 0 | 0 |
| StreamingDrainPolicyTests | 3 | 0 | 0 |
| StreamingMainViewModelTests | 52 | 51 | 0 |
| TranscriptionReviewViewKeyboardTests | 13 | 0 | 0 |
| TranscriptionReviewViewTests | 4 | 0 | 0 |
| TransportAttemptContextTests | 11 | 0 | 0 |
| Total | 407 | 52 | 0 |

The summary command exited 0 and reported passedTests 407, skippedTests 52, failedTests 0, totalTestCount 459.

Final skip extraction command:

    xcrun xcresulttool get test-results tests --path '/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_16-50-36-+0800.xcresult' --format json | ruby -rjson -e 'root=JSON.parse(STDIN.read); walk=lambda{|n,&b| Array(n).each{|x| b.call(x); walk.call(x["children"],&b) if x.is_a?(Hash) && x["children"]}}; skips=[]; walk.call(root["testNodes"]){|n| skips << n["name"] if n["nodeType"]=="Test Case" && n["result"]=="Skipped"}; puts "count=#{skips.length}"; puts skips.join("\n")'

Exit: 0; count=52. The skip set is one intentional live TCP test, test_liveKeepAliveTCPIsNotOnVPNTunnelAddress(), plus 51 retired direct-output StreamingMainViewModelTests oracles. No failures were hidden by the skip set.

### Debug and Release builds

    xcodebuild -scheme FeishuSpeech -configuration Debug build

Exit: 0; BUILD SUCCEEDED.

    xcodebuild -scheme FeishuSpeech -configuration Release build

Exit: 0; BUILD SUCCEEDED.

The build logs warn that multiple destinations exist and select arm64 My Mac. Release also reports AppIntents metadata extraction skipped because AppIntents.framework is not a dependency. These are non-blocking and did not change the exit status.

### Diff and protected paths

    git diff --check

Exit: 0; no output.

    git diff --exit-code 60090c955fbd57d4b6e875acb8a9bdc42d61f032 -- FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/ByteBoundedAudioIngress.swift FeishuSpeech/Services/HoldPacketJournal.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Models/StreamingSpeechModels.swift FeishuSpeech/Models/StreamingSpeechProvider.swift FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift FeishuSpeech/Services/BoundTLSSocket.swift FeishuSpeech/Services/TransportAttemptContext.swift

Exit: 0; no protected path differences.

Git-object hash command:

    for f in FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/ByteBoundedAudioIngress.swift FeishuSpeech/Services/HoldPacketJournal.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Models/StreamingSpeechModels.swift FeishuSpeech/Models/StreamingSpeechProvider.swift FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift FeishuSpeech/Services/BoundTLSSocket.swift FeishuSpeech/Services/TransportAttemptContext.swift FeishuSpeech/Services/AccessibilityClient.swift FeishuSpeech/Services/ReviewDestinationDelivery.swift; do printf '%s\t' "$f"; git hash-object "$f"; git rev-parse "60090c955fbd57d4b6e875acb8a9bdc42d61f032:$f"; done

Exit: 0. Current and baseline Git-object hashes:

| Path | Current | Baseline |
|---|---|---|
| AudioRecorder.swift | 18232a39248ad6f252a98ca815674918a5526bef | 18232a39248ad6f252a98ca815674918a5526bef |
| ByteBoundedAudioIngress.swift | 4bc7bcfa403ea756a65d2c12753875e66945c24f | 4bc7bcfa403ea756a65d2c12753875e66945c24f |
| HoldPacketJournal.swift | 11dc1cf394da8cb51738444980f98b25789e6225 | 11dc1cf394da8cb51738444980f98b25789e6225 |
| FeishuStreamingSession.swift | fb4982923fc2a4e05a93221ab6ce172247799df3 | fb4982923fc2a4e05a93221ab6ce172247799df3 |
| StreamingSpeechModels.swift | 7ca8d9c312511efd9183326068d6665584eed608 | 7ca8d9c312511efd9183326068d6665584eed608 |
| StreamingSpeechProvider.swift | eaa50c5709c563a05088be3598ffdf5adb57aba9 | eaa50c5709c563a05088be3598ffdf5adb57aba9 |
| DirectFeishuKeepAliveSession.swift | 52f1475e505af628709ccdc15c74e5e6ac092f21 | 52f1475e505af628709ccdc15c74e5e6ac092f21 |
| BoundTLSSocket.swift | c49d3fd9ac9ebc3d52b784e360d51fb63e1abf7b | c49d3fd9ac9ebc3d52b784e360d51fb63e1abf7b |
| TransportAttemptContext.swift | 22416290c612973235b4d9c6dfd7e96067a08275 | 22416290c612973235b4d9c6dfd7e96067a08275 |
| AccessibilityClient.swift | 7d03f3771a85165b72c5c2ef453357be1faaa413 | b28d1c3986a16c4dca946829cbe60dab5fb771bb |
| ReviewDestinationDelivery.swift | 4db749feb5c7d67fe1f18457dc39a1d80a65006c | 275256e70ebf9c67b63ef1c634d01e01e5c66b72 |

An initial shasum command mistakenly named FeishuSpeech/AccessibilityClient.swift rather than FeishuSpeech/Services/AccessibilityClient.swift and exited 1 with a no-such-file message. It was immediately rerun with the corrected path and exited 0; this is classified as an investigator command typo.

### Forbidden routes and topology

    rg -n 'copyForManualRecovery|manualRecoveryCopied|recoverReviewSurfaceFailure|reviewCopyRecoveryIssued|copyToPasteboard' FeishuSpeech --glob '*.swift' | rg -v 'Models/(CursorTextModels|RecordingState)\.swift'

Exit: 1; no accepted-production matches.

    rg -n 'insertOnce|insertReviewAtCurrentFocusOnce|replaceSelectedText|simulateTextInput' FeishuSpeech/ViewModels/MainViewModel.swift

Exit: 1; no direct-output call-site matches in MainViewModel.

    rg -n 'InteractionOutputMode|activeInteractionOutputMode|sampledAutoInsert|isReviewFirstMode' FeishuSpeech

Exit: 1; no interaction-mode bypass matches.

    rg -n 'reviewBeforeInsert.*\?|if .*reviewBeforeInsert|switch .*reviewBeforeInsert|if .*autoInsert|switch .*autoInsert|prepareCursorTarget\(|compatibility\(' FeishuSpeech/ViewModels/MainViewModel.swift FeishuSpeech/Services FeishuSpeech/Controllers FeishuSpeech/Views --glob '*.swift'

Exit: 1; no legacy route-setting branch matches.

An unfiltered legacy-symbol search still finds only dormant model declarations in RecordingState.swift and CursorTextModels.swift; it finds no accepted production call site. The lower-level TextInputSimulator and ReviewDestinationDelivery insertion APIs remain the intentional confirmation-delivery implementation, but MainViewModel has no direct-output call-site match.

    rg -n 'captureDrainTask|consumerTask|holdPacketJournal|retrySleepTask|sessionCreationTask' FeishuSpeech/ViewModels/MainViewModel.swift; rg -n 'renderEditable|renderDraft|requestEditableReadiness|await .*reviewSurface|await .*present' FeishuSpeech/ViewModels/MainViewModel.swift

Exit: 0. Capture/consumer/journal tasks remain separate from review render/readiness calls; this is structural evidence, not a live AX/typing experiment.

### Final documentation checks

The changed Markdown set remains the same 12-file set listed earlier in this receipt. The final relative-link checker, decision-reference checker, and trailing-whitespace command were rerun after the repair:

    ruby -e 'require "pathname"; bad=[]; ARGV.each{|f| base=Pathname(f).dirname; File.read(f).scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each{|u| next if u.start_with?("http://","https://","mailto:","#"); target=u.split("#",2).first; next if target.empty?; path=(base+Pathname(target)).cleanpath; bad << "#{f}:#{u}" unless path.exist?}}; abort bad.join("\n") unless bad.empty?' CHANGELOG.md README.md docs/README.md docs/architecture.md docs/decisions/D-25-01.md docs/decisions/D-26-01.md docs/decisions/D-27-01.md docs/decisions/D-38-01.md docs/decisions/D-39-01.md docs/decisions/D-40-01.md docs/designs/capture-recognition-split-direct-connect.md docs/streaming-speech-design.md

Exit: 0; no broken local targets.

    ruby -e 'missing=[]; ARGV.each{|f| text=File.read(f); text.scan(/D-[0-9]+-[0-9]+/).uniq.each{|d| missing << "#{f}:#{d}" unless File.file?("docs/decisions/#{d}.md")}}; abort missing.join("\n") unless missing.empty?' CHANGELOG.md README.md docs/README.md docs/architecture.md docs/decisions/D-25-01.md docs/decisions/D-26-01.md docs/decisions/D-27-01.md docs/decisions/D-38-01.md docs/decisions/D-39-01.md docs/decisions/D-40-01.md docs/designs/capture-recognition-split-direct-connect.md docs/streaming-speech-design.md

Exit: 0; no missing decision references.

    rg -n '[[:blank:]]+$' CHANGELOG.md README.md docs/README.md docs/architecture.md docs/decisions/D-25-01.md docs/decisions/D-26-01.md docs/decisions/D-27-01.md docs/decisions/D-38-01.md docs/decisions/D-39-01.md docs/decisions/D-40-01.md docs/designs/capture-recognition-split-direct-connect.md docs/streaming-speech-design.md

Exit: 1; no matches, meaning no trailing whitespace. The final status and mtime inspection showed no documentation updates while these checks ran, so the docs were stable for this gate.

Stability command:

    stat -f '%m %N' CHANGELOG.md README.md docs/README.md docs/architecture.md docs/decisions/D-25-01.md docs/decisions/D-26-01.md docs/decisions/D-27-01.md docs/decisions/D-38-01.md docs/decisions/D-39-01.md docs/decisions/D-40-01.md docs/designs/capture-recognition-split-direct-connect.md docs/streaming-speech-design.md

Exit: 0; timestamps matched the pre-check values for all 12 files.

## Final handoff

All required final gates are green. Final verdict: PASS. The only non-green command observed during this rerun was the first mistyped hash path; the corrected protected hash and diff checks passed. No product defect, stale oracle, environment failure, or docs-in-flight blocker remains.

## Issue #40 v3 final rerun (authoritative)

Date: 2026-08-23 (Asia/Shanghai)
Candidate worktree: /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40
Candidate HEAD: aec7aad8ca29eab8cbde90b23be5dbe66ce454e2
Baseline for v3 scope: aec7aad8ca29eab8cbde90b23be5dbe66ce454e2
HEAD subject: fix: make preview the sole speech output (#40)

The v3 shared tree contains only the intended 12 uncommitted paths relative to the
aec7aad baseline: two production UI files, three test files, and seven documentation/changelog
files. No source, tests, or docs were edited by this investigator. The only write was this receipt.

### Environment

    sw_vers
    uname -m
    xcodebuild -version
    swift --version
    swiftlint version
    git rev-parse HEAD
    git status --short

Observed: macOS 26.6.2 build 25G83, arm64; Xcode 26.6 build 17F113; Swift 6.3.3 with
swift-driver 1.148.6; SwiftLint 0.65.0. The worktree status lists:

    M CHANGELOG.md
    M FeishuSpeech/Controllers/ReviewWindowController.swift
    M FeishuSpeech/Views/TranscriptionReviewView.swift
    M FeishuSpeechTests/ReviewFirstMainViewModelTests.swift
    M FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift
    M FeishuSpeechTests/TranscriptionReviewViewTests.swift
    M README.md
    M docs/README.md
    M docs/architecture.md
    M docs/decisions/D-38-01.md
    M docs/decisions/D-40-01.md
    M docs/streaming-speech-design.md

### v3 focused selectors

Exact serialized command:

    xcodebuild -scheme FeishuSpeech -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests test

Exit: 0. Result bundle:

    /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_18-03-38-+0800.xcresult

Structured summary exit: 0; 122 total, 122 passed, 0 skipped, 0 failed.

| Suite | Passed | Skipped | Failed |
|---|---:|---:|---:|
| FinalTextOutputSecurityTests | 23 | 0 | 0 |
| ReviewDestinationDeliveryTests | 13 | 0 | 0 |
| ReviewFirstApplicationFallbackTests | 16 | 0 | 0 |
| ReviewFirstMainViewModelTests | 30 | 0 | 0 |
| ReviewPasteboardLifecycleTests | 7 | 0 | 0 |
| ReviewWindowControllerReadinessTests | 10 | 0 | 0 |
| TranscriptionReviewViewKeyboardTests | 13 | 0 | 0 |
| TranscriptionReviewViewTests | 10 | 0 | 0 |
| Total | 122 | 0 | 0 |

This covers the v3 font, traffic-light/titlebar boundary, retained-panel identity/size, advisory
activation, typed readiness polling/timeout, no visible Retry Editing, explicit Send/Return,
delivery-uncertain duplicate warning, activation-failure copy, coordinator, fallback, pasteboard,
security, and keyboard oracles.

### Complete serialized FeishuSpeech target

Exact command:

    xcodebuild -scheme FeishuSpeech -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test

Exit: 0. Result bundle:

    /Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_18-03-57-+0800.xcresult

Structured summary exit: 0; 468 total, 416 passed, 52 skipped, 0 failed.

| Suite | Passed | Skipped | Failed |
|---|---:|---:|---:|
| AppSettingsCredentialStorageTests | 16 | 0 | 0 |
| AudioRecorderFailureTests | 4 | 0 | 0 |
| AudioRecorderStreamingIntegrationTests | 7 | 0 | 0 |
| BoundTLSSocketTests | 3 | 0 | 0 |
| CurrentFocusAppendSessionTests | 37 | 0 | 0 |
| CursorTextSessionTests | 15 | 0 | 0 |
| DirectFeishuKeepAliveSessionTests | 5 | 1 | 0 |
| EmptyResultFeedbackTests | 3 | 0 | 0 |
| FeishuAPIServiceTests | 36 | 0 | 0 |
| FeishuStreamingSessionTests | 24 | 0 | 0 |
| FinalTextOutputSecurityTests | 23 | 0 | 0 |
| HoldPacketJournalTests | 5 | 0 | 0 |
| HotKeyServiceTests | 29 | 0 | 0 |
| HotKeyStateTests | 4 | 0 | 0 |
| MainViewModelTests | 8 | 0 | 0 |
| MonitoringStateBindingTests | 4 | 0 | 0 |
| PermissionManagerTests | 7 | 0 | 0 |
| ReviewDestinationDeliveryTests | 13 | 0 | 0 |
| ReviewFirstApplicationFallbackTests | 16 | 0 | 0 |
| ReviewFirstMainViewModelTests | 30 | 0 | 0 |
| ReviewPasteboardLifecycleTests | 7 | 0 | 0 |
| ReviewWindowControllerReadinessTests | 10 | 0 | 0 |
| StreamingAudioIngressTests | 15 | 0 | 0 |
| StreamingCoordinatorStateTests | 6 | 0 | 0 |
| StreamingDrainPolicyTests | 3 | 0 | 0 |
| StreamingMainViewModelTests | 52 | 51 | 0 |
| TranscriptionReviewViewKeyboardTests | 13 | 0 | 0 |
| TranscriptionReviewViewTests | 10 | 0 | 0 |
| TransportAttemptContextTests | 11 | 0 | 0 |
| Total | 416 | 52 | 0 |

Final skip extraction command:

    xcrun xcresulttool get test-results tests --path '/Users/ylpromax5/Library/Developer/Xcode/DerivedData/FeishuSpeech-cgiyjqtocfbabebmiznsskomsotp/Logs/Test/Test-FeishuSpeech-2026.08.23_18-03-57-+0800.xcresult' --format json | ruby -rjson -e 'root=JSON.parse(STDIN.read); walk=lambda{|n,&b| Array(n).each{|x| b.call(x); walk.call(x["children"],&b) if x.is_a?(Hash) && x["children"]}}; skips=[]; walk.call(root["testNodes"]){|n| skips << n["name"] if n["nodeType"]=="Test Case" && n["result"]=="Skipped"}; puts "count=#{skips.length}"; puts skips.join("\n")'

Exit: 0; count=52. The skip set is one intentional live TCP test and 51 retired
direct-output StreamingMainViewModelTests oracles. No failed test is hidden by these skips.

Two initial attempts to read this xcresult concurrently with separate xcresulttool processes exited 1
because the xcresult database was being moved/read simultaneously. Serial summary, suite-count, and
skip extraction commands all exited 0. This is classified as an investigator tool-concurrency
condition, not a product, test, environment, or documentation failure.

### Lint and builds

    swiftlint --strict --config .swiftlint.yml

Exit: 0; Done linting! Found 0 violations, 0 serious in 35 files.

    xcodebuild -scheme FeishuSpeech -configuration Debug build

Exit: 0; BUILD SUCCEEDED.

    xcodebuild -scheme FeishuSpeech -configuration Release build

Exit: 0; BUILD SUCCEEDED.

Build warnings were non-blocking: xcodebuild selected arm64 My Mac from multiple destinations, and
Release metadata extraction reported no AppIntents.framework dependency. Test logs also show the
known host Accessibility/microphone denial and AppKit/NSCGS diagnostics; no test failed.

### Diff hygiene and protected asynchronous paths

    git diff --check

Exit: 0; no output.

    git diff --exit-code aec7aad8ca29eab8cbde90b23be5dbe66ce454e2 -- FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/ByteBoundedAudioIngress.swift FeishuSpeech/Services/HoldPacketJournal.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Models/StreamingSpeechModels.swift FeishuSpeech/Models/StreamingSpeechProvider.swift FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift FeishuSpeech/Services/BoundTLSSocket.swift FeishuSpeech/Services/TransportAttemptContext.swift FeishuSpeech/Services/AccessibilityClient.swift FeishuSpeech/Services/ReviewDestinationDelivery.swift FeishuSpeech/ViewModels/MainViewModel.swift FeishuSpeech/Services/TextInputSimulator.swift

Exit: 0; no protected async-path differences.

Git-object current/baseline hashes for those protected paths were identical:

| Path | Current = baseline |
|---|---|
| AudioRecorder.swift | 18232a39248ad6f252a98ca815674918a5526bef |
| ByteBoundedAudioIngress.swift | 4bc7bcfa403ea756a65d2c12753875e66945c24f |
| HoldPacketJournal.swift | 11dc1cf394da8cb51738444980f98b25789e6225 |
| FeishuStreamingSession.swift | fb4982923fc2a4e05a93221ab6ce172247799df3 |
| StreamingSpeechModels.swift | 7ca8d9c312511efd9183326068d6665584eed608 |
| StreamingSpeechProvider.swift | eaa50c5709c563a05088be3598ffdf5adb57aba9 |
| DirectFeishuKeepAliveSession.swift | 52f1475e505af628709ccdc15c74e5e6ac092f21 |
| BoundTLSSocket.swift | c49d3fd9ac9ebc3d52b784e360d51fb63e1abf7b |
| TransportAttemptContext.swift | 22416290c612973235b4d9c6dfd7e96067a08275 |
| AccessibilityClient.swift | 7d03f3771a85165b72c5c2ef453357be1faaa413 |
| ReviewDestinationDelivery.swift | 4db749feb5c7d67fe1f18457dc39a1d80a65006c |
| MainViewModel.swift | b149a767fa8d5a6e60429ce26f539ab0e5f21f30 |
| TextInputSimulator.swift | df1fb8f701a8d0cb3370a39bb874ae360ad602d2 |

### Exact v3 diff scope

Corrected scope assertion command:

    ruby -e 'expected=%w[CHANGELOG.md FeishuSpeech/Controllers/ReviewWindowController.swift FeishuSpeech/Views/TranscriptionReviewView.swift FeishuSpeechTests/ReviewFirstMainViewModelTests.swift FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift FeishuSpeechTests/TranscriptionReviewViewTests.swift README.md docs/README.md docs/architecture.md docs/decisions/D-38-01.md docs/decisions/D-40-01.md docs/streaming-speech-design.md].sort; actual=IO.popen(["git","diff","--name-only","aec7aad8ca29eab8cbde90b23be5dbe66ce454e2"], &:read).lines.map(&:strip).reject(&:empty?).sort; abort("unexpected diff:\n#{actual.join("\n")}") unless actual==expected; puts actual'

Exit: 0. Exact output was the 12 intended paths:

    CHANGELOG.md
    FeishuSpeech/Controllers/ReviewWindowController.swift
    FeishuSpeech/Views/TranscriptionReviewView.swift
    FeishuSpeechTests/ReviewFirstMainViewModelTests.swift
    FeishuSpeechTests/ReviewWindowControllerReadinessTests.swift
    FeishuSpeechTests/TranscriptionReviewViewTests.swift
    README.md
    docs/README.md
    docs/architecture.md
    docs/decisions/D-38-01.md
    docs/decisions/D-40-01.md
    docs/streaming-speech-design.md

Two preceding copies of this assertion had zsh unmatched-quote errors because the shell command
string omitted its closing quote. The corrected command above exited 0; those are investigator
command-construction errors, not candidate failures.

### Forbidden output-route searches

    rg -n 'copyForManualRecovery|manualRecoveryCopied|recoverReviewSurfaceFailure|reviewCopyRecoveryIssued|copyToPasteboard' FeishuSpeech --glob '*.swift' | rg -v 'Models/(CursorTextModels|RecordingState)\.swift'

Exit: 1; no accepted-production manual-recovery/copy matches.

    rg -n 'insertOnce|insertReviewAtCurrentFocusOnce|replaceSelectedText|simulateTextInput' FeishuSpeech/ViewModels/MainViewModel.swift

Exit: 1; no MainViewModel direct-output call-site matches.

    rg -n 'InteractionOutputMode|activeInteractionOutputMode|sampledAutoInsert|isReviewFirstMode' FeishuSpeech

Exit: 1; no interaction-mode bypass matches.

    rg -n 'reviewBeforeInsert.*\?|if .*reviewBeforeInsert|switch .*reviewBeforeInsert|if .*autoInsert|switch .*autoInsert|prepareCursorTarget\(|compatibility\(' FeishuSpeech/ViewModels/MainViewModel.swift FeishuSpeech/Services FeishuSpeech/Controllers FeishuSpeech/Views --glob '*.swift'

Exit: 1; no legacy route-setting branch matches.

    rg -n '重试编辑|请重试编辑|编辑器正在准备|activationRejected' FeishuSpeech/Views FeishuSpeech/Controllers

Exit: 1; no stale production UI copy/control matches.

Positive implementation search:

    rg -n 'Button\("发送"\)|keyboardShortcut\(\.return|transcriptFontSize|fullSizeContentView' FeishuSpeech/Views/TranscriptionReviewView.swift FeishuSpeech/Controllers/ReviewWindowController.swift

Exit: 0; current production contains the 18pt typography, explicit Send/Command-Return path, and
no fullSizeContentView match. Readiness search also shows activationAdvisoryRejected is logged only
as an advisory result, while actual firstUnmetReadinessPredicate polling remains authoritative.

The broad stale-claim search found only intentional current/history documentation statements:
the docs describe no Retry Editing/no automatic copy, retry, or retarget, and explicitly retain the
status that installed UAT v3 is failed/open. These are not stale active production routes; the
production-only stale UI search above returned no matches.

### Changed-document links and stale claims

The seven changed Markdown files were:

    CHANGELOG.md
    README.md
    docs/README.md
    docs/architecture.md
    docs/decisions/D-38-01.md
    docs/decisions/D-40-01.md
    docs/streaming-speech-design.md

Relative-link checker:

    ruby -e 'require "pathname"; bad=[]; ARGV.each{|f| base=Pathname(f).dirname; File.read(f).scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each{|u| next if u.start_with?("http://","https://","mailto:","#"); target=u.split("#",2).first; next if target.empty?; path=(base+Pathname(target)).cleanpath; bad << "#{f}:#{u}" unless path.exist?}}; abort bad.join("\n") unless bad.empty?' CHANGELOG.md README.md docs/README.md docs/architecture.md docs/decisions/D-38-01.md docs/decisions/D-40-01.md docs/streaming-speech-design.md

Exit: 0; no broken local targets.

Decision-reference checker:

    ruby -e 'missing=[]; ARGV.each{|f| text=File.read(f); text.scan(/D-[0-9]+-[0-9]+/).uniq.each{|d| missing << "#{f}:#{d}" unless File.file?("docs/decisions/#{d}.md")}}; abort missing.join("\n") unless missing.empty?' CHANGELOG.md README.md docs/README.md docs/architecture.md docs/decisions/D-38-01.md docs/decisions/D-40-01.md docs/streaming-speech-design.md

Exit: 0; no missing decision references.

Trailing-whitespace check:

    rg -n '[[:blank:]]+$' CHANGELOG.md README.md docs/README.md docs/architecture.md docs/decisions/D-38-01.md docs/decisions/D-40-01.md docs/streaming-speech-design.md

Exit: 1; no matches, expected no-match result.

Stability check:

    stat -f '%m %N' CHANGELOG.md README.md docs/README.md docs/architecture.md docs/decisions/D-38-01.md docs/decisions/D-40-01.md docs/streaming-speech-design.md

Exit: 0; timestamps were captured after the checks and docs were stable. Current docs intentionally
state that installed UAT v3 remains failed/open; this local receipt does not convert that external
UAT status into a pass.

## Final v3 verdict

PASS. The v3 focused selectors passed 122/122 with no skips; the complete serialized target passed
416/468 with exactly 52 classified intentional skips and zero failures; canonical strict lint,
Debug, Release, diff hygiene, protected async-path equality, exact aec7aad scope, forbidden
output-route searches, and changed-document link/reference checks all passed. The only nonzero
commands were expected no-match searches, trailing-whitespace no-match, and investigator/tool
command-construction/concurrency retries; none is a product defect, stale oracle, environment
failure, or docs-in-flight blocker.
