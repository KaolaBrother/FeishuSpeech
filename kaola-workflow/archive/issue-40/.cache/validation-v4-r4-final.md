# Issue #40 v4 R4 release-candidate validation receipt

Date: 2026-08-24 00:05:17 +0800
Role: read-only validation investigator
Scope: repaired Issue #40 v4 R4 in `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`.

No tracked repository, product, or test file was edited by this validation. The only write from
this run is this receipt in the workflow evidence directory. The app was not launched or
installed. No GUI/UAT claim is made.

## Setup and baseline

`CLAUDE.md` was reread in full before any validation action:

```text
wc -l CLAUDE.md; sed -n '1,999p' CLAUDE.md
=> 119 lines; full read completed.
```

Baseline commands and observations:

```text
git rev-parse HEAD
=> 4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a

git status --short --branch
=> workflow/issue-40...origin/workflow/issue-40; expected Issue #40 v4 production,
   test, CHANGELOG, README, and docs changes are dirty.

git diff --stat
=> 25 files changed, 4761 insertions(+), 2058 deletions(-).

sw_vers; xcodebuild -version; swiftlint version; uname -m
=> macOS 26.6.2 / 25G83; Xcode 26.6 / 17F113; SwiftLint 0.65.0; arm64.
```

The initial and final process checks used:

```text
ps -axo pid=,comm= | awk '$2 ~ /FeishuSpeech|Siji\.FeishuSpeech|FeishuSpeechTests/ {print}'
=> exit 0; empty output at both checks.
```

XCTest hosts existed transiently while tests ran and were absent after the final check. No
`/Applications` operation, application launch command, or install command was used.

## Observation table

All test/build legs used a fresh, distinct `/tmp` DerivedData directory. XCTest legs were
serialized with `-parallel-testing-enabled NO -maximum-parallel-testing-workers 1`.

| Leg | Exact command | Observed result | Exit |
|---|---|---:|---:|
| R4 selectors | `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-r4-final-validation-dd.4dbAlU -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_postReleaseDrainExpiryReportsFixedFailureWhenNoSafeOutputWasCommitted -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_postReleaseDrainExpiryNeverAuthorizesPartialBeforeAction2ThroughEitherUISeam -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_postReleaseDrainExpiryRetainsMultilineLFAsInertReadOnlyData test` | 3 passed, 0 failed, 0 skipped. xcresult: `passedTests=3 failedTests=0 skippedTests=0 totalTestCount=3 result=Passed`. | 0 |
| Streaming class | `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-r4-final-streaming-validation-dd.BtXlA3 -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test` | 105 passed, 0 failed, 0 skipped. xcresult: `passedTests=105 failedTests=0 skippedTests=0 totalTestCount=105 result=Passed`. | 0 |
| Full v4 focused matrix | `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-r4-final-focused-validation-dd.Y4Bt0l -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test` | 265 passed, 0 failed, 0 skipped. xcresult: `passedTests=265 failedTests=0 skippedTests=0 totalTestCount=265 result=Passed`. | 0 |
| Full macOS target | `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-r4-final-full-validation-dd.afLPgr -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test` | 484 total: 483 passed, 0 failed, 1 skipped; `TEST SUCCEEDED`. xcresult: `passedTests=483 failedTests=0 skippedTests=1 totalTestCount=484 result=Passed`. | 0 |
| Debug build | `xcodebuild -scheme FeishuSpeech -configuration Debug -derivedDataPath /tmp/issue40-v4-r4-final-debug-validation-dd.5Bd66w build` | `BUILD SUCCEEDED`; artifact remained under `/tmp`. Normal destination-selection and AppIntents metadata warnings; no error. | 0 |
| Release build | `xcodebuild -scheme FeishuSpeech -configuration Release -derivedDataPath /tmp/issue40-v4-r4-final-release-validation-dd.EWWiKD build` | `BUILD SUCCEEDED`; artifact remained under `/tmp`. Existing Swift 6 migration warnings for `NSLock.lock/unlock` from async contexts in `TransportAttemptContext.swift`, a no-op `await` in `MainViewModel.swift`, a `will never be executed` warning, and normal/AppIntents warnings; no error. | 0 |
| SwiftLint | `swiftlint --strict` | `Done linting! Found 0 violations, 0 serious in 35 files.` | 0 |
| Patch whitespace | `git diff --check` | No output; clean. | 0 |

Result bundles:

- R4 selectors: `/tmp/issue40-v4-r4-final-validation-dd.4dbAlU/Logs/Test/Test-FeishuSpeech-2026.08.24_00-00-09-+0800.xcresult`
- Streaming: `/tmp/issue40-v4-r4-final-streaming-validation-dd.BtXlA3/Logs/Test/Test-FeishuSpeech-2026.08.24_00-00-29-+0800.xcresult`
- Focused: `/tmp/issue40-v4-r4-final-focused-validation-dd.Y4Bt0l/Logs/Test/Test-FeishuSpeech-2026.08.24_00-00-57-+0800.xcresult`
- Full target: `/tmp/issue40-v4-r4-final-full-validation-dd.afLPgr/Logs/Test/Test-FeishuSpeech-2026.08.24_00-01-24-+0800.xcresult`

## Skip audit and 51-test retirement accounting

The full-target summary and direct skip enumeration were:

```text
xcrun xcresulttool get test-results summary --path "/tmp/issue40-v4-r4-final-full-validation-dd.afLPgr/Logs/Test/Test-FeishuSpeech-2026.08.24_00-01-24-+0800.xcresult"
=> passedTests=483 failedTests=0 skippedTests=1 totalTestCount=484 result=Passed

xcrun xcresulttool get test-results tests --path "/tmp/issue40-v4-r4-final-full-validation-dd.afLPgr/Logs/Test/Test-FeishuSpeech-2026.08.24_00-01-24-+0800.xcresult" | jq -r '.. | objects | select(.result? == "Skipped") | [.nodeIdentifier, .name, .testStatus] | @tsv'
=> DirectFeishuKeepAliveSessionTests/test_liveKeepAliveTCPIsNotOnVPNTunnelAddress()
```

The source reason at `FeishuSpeechTests/DirectFeishuKeepAliveSessionTests.swift:99-102` is:
`live TCP previously hung the XCTest host; issue #34 forbids additional live sockets`.
This is the sole expected environmental skip and is unrelated to the review/streaming route.

The current Streaming class audit was:

```text
rg -c '^    func test_' FeishuSpeechTests/StreamingMainViewModelTests.swift
=> 105

rg -n 'XCTSkip|throw XCTSkip|retiredCompatibility|legacy.*skip|skip.*legacy' FeishuSpeechTests/StreamingMainViewModelTests.swift
=> no output
```

The prior 51-name retirement evidence remains documented at
`kaola-workflow/issue-40/test-red-v4-r1-r3.md:99-151`, mapping every former compatibility
skip name to an active replacement oracle. The current class has no blanket `XCTSkip`,
`retiredCompatibilityOutputTests`, or setup skip. The independent 105/105 run therefore
rules out accidental hiding of those 51 tests.

## Forbidden output and confirmation-boundary checks

The production-only scan was:

```text
printf '%s\n' 'PASTEBOARD_SEARCH'; rg -n -i 'NSPasteboard|generalPasteboard|changeCount|clearContents|setString\(|setData\(|writeObjects|readObjects|pasteboardItems|public\.png|Apple PNG' FeishuSpeech --glob '*.swift' || true
=> no matches

printf '%s\n' 'KEYBOARD_PASTE_SEARCH'; rg -n -i 'Cmd.?V|command.?V|CGEventPost\(|CGEventPostToPid|CGEventCreateKeyboardEvent' FeishuSpeech --glob '*.swift' || true
=> no matches

printf '%s\n' 'PRECONFIRM_OUTPUT_SEARCH'; rg -n -i 'finalTextOutput\.insert|insertAtCurrentFocusOnce|applyOpaqueHypothesis|makeSession\(|CurrentFocusProvisionalOutputSession|ReviewOutputCompatibilityWriter|ReviewOutputCompatibilityPoster|deliver\(' FeishuSpeech --glob '*.swift' || true
=> only dormant protocol/compatibility definitions and the review delivery authority;
   MainViewModel.swift:2010 is the production delivery call, and ReviewDestinationDelivery
   invokes final text output only inside the explicit confirmation delivery path.
```

No production `NSPasteboard`, `generalPasteboard`, change-count, Cmd+V, `CGEventPost`, or
keyboard-event-construction symbol matched. The dormant append/compatibility definitions are
not evidence of an accepted-interaction caller; the focused and Streaming tests exercise their
inert boundary.

## Documentation and link checks

The local Markdown link checker was:

```text
ruby -e 'require "pathname"; files = [Pathname("README.md"), Pathname("CHANGELOG.md")] + Dir["docs/**/*.md"].map { |p| Pathname(p) }; missing = []; total = 0; files.each do |file| text = File.read(file); text.scan(/\]\(([^)]+)\)/).each do |m| target = m.first.strip; next if target.empty? || target.start_with?("http://", "https://", "mailto:", "#"); target = target.split("#", 2).first.split("?", 2).first; next if target.empty?; total += 1; resolved = (file.dirname + target).cleanpath; missing << "#{file}: #{target} -> #{resolved}" unless resolved.exist?; end; end; puts "LOCAL_MARKDOWN_LINKS=#{total}"; if missing.empty?; puts "MISSING_LOCAL_MARKDOWN_LINKS=0"; else; puts "MISSING_LOCAL_MARKDOWN_LINKS=#{missing.length}"; puts missing; exit 1; end'
=> LOCAL_MARKDOWN_LINKS=54; MISSING_LOCAL_MARKDOWN_LINKS=0; exit 0
```

Current status anchors were inspected at `docs/streaming-speech-design.md:3-11`, `:909-912`,
and `:1014-1020`; they state the measured R4 values of 265 focused, 105 Streaming, 3/3
selectors, and 483 passed plus one live-TCP skip. A repository-wide old-number scan found no
stale Issue #40 test-count claim (`263`, `482`, or the former 103-test count); the only `103`
match was an unrelated Issue #103 reference in `docs/designs/capture-recognition-split-direct-connect.md`.

Historical pasteboard/Cmd+V and direct-output wording remains in decision-history/API sections,
but the inspected matches are labelled historical, superseded, dormant, or otherwise describe
the removed route. Current README, CHANGELOG, architecture, D-40-01, and streaming-design
authority text explicitly states one-route review-first behavior, no pre-confirm output, and
real Send/qualified Return confirmation.

## Protected asynchronous topology

The protected capture/recognition file check was:

```text
git diff --name-only -- FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/HotKeyService.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Services/FeishuAPIService.swift FeishuSpeech/Services/HoldPacketJournal.swift FeishuSpeech/Services/ByteBoundedAudioIngress.swift FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift
=> no output
```

The marker scan over the protected and review/coordinator files was run exactly as follows:

```text
for file in FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/HotKeyService.swift FeishuSpeech/Services/CurrentFocusAppendSession.swift FeishuSpeech/Services/ReviewDestinationDelivery.swift FeishuSpeech/Services/TextInputSimulator.swift FeishuSpeech/ViewModels/MainViewModel.swift; do printf 'FILE=%s\n' "$file"; git diff --unified=0 -- "$file" | rg -n '^[+-].*(Task|DispatchQueue|MainActor|audioQueue|bufferQueue|CGEventTap|startRunning|stopRunning|await|NSLock|actor|NSEvent|addGlobalMonitor|addLocalMonitor|withChecked|continuation)' || true; done
```

Observed narrowing result:

- `AudioRecorder.swift` and `HotKeyService.swift` produced no changed protected-topology lines.
- `FeishuStreamingSession.swift`, `FeishuAPIService.swift`, `HoldPacketJournal.swift`,
  `ByteBoundedAudioIngress.swift`, and `DirectFeishuKeepAliveSession.swift` had no diff.
- Review changes add/cancel `@MainActor` presentation/delivery tasks and review-gate awaits;
  they do not add detached work, alter the audio queues, move `AVCaptureSession` work off its
  existing queue, or alter the `FeishuStreamingSession` actor.
- Existing `audioQueue`, `bufferQueue`, and `sessionQueue` remain in `AudioRecorder.swift`;
  `FeishuStreamingSession` remains an actor.

This is source topology evidence, not a claim about unmeasured live WindowServer behavior.

## Reproduction status, inferences, and limits

Reproduced in this environment:

- R4 selectors: 3/3 passed, zero skipped.
- All 105 Streaming tests: 105/105 passed, zero skipped.
- Full v4 focused matrix: 265/265 passed, zero skipped.
- Full macOS target: 483 passed, one documented live-TCP skip, zero failures.
- Debug and Release builds, strict lint, whitespace, local Markdown links, and forbidden-output
  scans all passed.
- Final matching-process check is empty; the app remained stopped and was not installed.

Inference, with high confidence and subject to the checked-in source/test assumptions: the
measured v4 coordinator has one explicit-confirmation delivery gate, with no production
pasteboard/Cmd+V fallback and no changed capture/recognition asynchronous root. The tests and
static searches rule out the checked-in paths; they cannot prove that a third-party target
consumes a posted Unicode pair.

Not measured by this receipt:

- GUI/UAT, live microphone capture, live Feishu credentials, third-party target focus,
  Accessibility permission behavior, or visible target text consumption.
- Application launch/install or sole-copy audit.
- An OS-level receipt for `CGEventPostToPid`; the product's `submitted-unverified` result remains
  the correct boundary.

Validation conclusion: automated R4 validation is green for all measured axes, with exactly one
documented live-TCP environmental skip. Installation and owner UAT remain outside this
read-only receipt and are not claimed complete.
