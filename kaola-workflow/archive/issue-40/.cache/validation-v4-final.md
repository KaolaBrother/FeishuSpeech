# Issue #40 v4 independent final validation receipt

Date: 2026-08-23 23:25 +0800
Role: read-only validation investigator
Scope: repaired Issue #40 v4 in `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`.

No tracked repository, product, or test file was edited by this validation. The only write from
this run is this receipt in the workflow evidence directory. The app was not launched or
installed, and no GUI/UAT claim is made.

## Setup and baseline

Commands and observed baseline:

```text
wc -l CLAUDE.md; sed -n '1,999p' CLAUDE.md
=> 119 lines; CLAUDE.md reread in full before validation.

git rev-parse HEAD
=> 4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a

git status --short --branch
=> workflow/issue-40...origin/workflow/issue-40, with the expected Issue #40 v4 production,
   test, CHANGELOG, README, and docs changes dirty; no validation-file change in the worktree.

sw_vers -productVersion; sw_vers -buildVersion; xcodebuild -version; swiftlint version
=> macOS 26.6.2 / 25G83; Xcode 26.6 / 17F113; SwiftLint 0.65.0; arm64 MacBook Pro.
```

The initial process check found no FeishuSpeech app/test process. The final process check was:

```text
ps -axo pid=,comm= | awk '$2 ~ /FeishuSpeech|Siji\.FeishuSpeech|FeishuSpeechTests/ {print}'
=> exit 0; empty output (no matching app or test process).
```

The test host necessarily existed transiently while XCTest ran; it was absent after the final
check. No `/Applications` operation and no application launch command was used.

## Observation table

All XCTest/build commands below used a fresh, distinct `/tmp` DerivedData directory and
`-parallel-testing-enabled NO`; validation legs were run serially.

| Leg | Exact command | Observed result | Exit |
|---|---|---:|---:|
| R1/R3 security | `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-final-r13-dd.GBbQ2q -parallel-testing-enabled NO test -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests` | 32 passed, 0 failed, 0 skipped; `TEST SUCCEEDED`. xcresult summary: `passedTests=32 failedTests=0 skippedTests=0 totalTestCount=32 result=Passed`. | 0 |
| Streaming class | `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-final-streaming-dd.5bKb8W -parallel-testing-enabled NO test -only-testing:FeishuSpeechTests/StreamingMainViewModelTests` | 103 passed, 0 failed, 0 skipped; `TEST SUCCEEDED`. xcresult summary: `passedTests=103 failedTests=0 skippedTests=0 totalTestCount=103 result=Passed`. | 0 |
| Focused v4 matrix excluding the separately measured streaming class | `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-final-focused-dd.WKMlbr -parallel-testing-enabled NO test -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests` | 160 passed, 0 failed, 0 skipped; `TEST SUCCEEDED`. xcresult summary: `passedTests=160 failedTests=0 skippedTests=0 totalTestCount=160 result=Passed`. The nested `TranscriptionReviewViewKeyboardTests` ran through `TranscriptionReviewViewTests.swift`. | 0 |
| Full macOS target | `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-final-full-dd.woAHgh -parallel-testing-enabled NO test` | 482 total: 481 passed, 0 failed, 1 skipped; `TEST SUCCEEDED`. xcresult summary: `passedTests=481 failedTests=0 skippedTests=1 totalTestCount=482 result=Passed`. | 0 |
| Debug build | `xcodebuild -scheme FeishuSpeech -configuration Debug -derivedDataPath /tmp/issue40-v4-final-debug-dd.zEkKPT build` | `BUILD SUCCEEDED`; local Debug app artifact only under `/tmp`. Xcode emitted the normal destination-selection warning and AppIntents metadata warning. | 0 |
| Release build | `xcodebuild -scheme FeishuSpeech -configuration Release -derivedDataPath /tmp/issue40-v4-final-release-dd.74z2nE build` | `BUILD SUCCEEDED`; local Release artifact only under `/tmp`. The compiler emitted existing Swift 6 migration warnings for `NSLock` from async contexts in `TransportAttemptContext.swift`, a no-op `await` warning in `MainViewModel.swift`, and a `will never be executed` warning; no error. | 0 |
| SwiftLint | `swiftlint --strict` | 35 Swift files linted; 0 violations, 0 serious. | 0 |
| Patch whitespace | `git diff --check` | No output; clean. | 0 |

Full-target result bundle:
`/tmp/issue40-v4-final-full-dd.woAHgh/Logs/Test/Test-FeishuSpeech-2026.08.23_23-20-14-+0800.xcresult`

Focused result bundles:

- `/tmp/issue40-v4-final-r13-dd.GBbQ2q/Logs/Test/Test-FeishuSpeech-2026.08.23_23-18-55-+0800.xcresult`
- `/tmp/issue40-v4-final-streaming-dd.5bKb8W/Logs/Test/Test-FeishuSpeech-2026.08.23_23-19-16-+0800.xcresult`
- `/tmp/issue40-v4-final-focused-dd.WKMlbr/Logs/Test/Test-FeishuSpeech-2026.08.23_23-19-52-+0800.xcresult`

## Skip audit and retirement accounting

The full target's only skipped test was enumerated directly from the xcresult:

```text
xcrun xcresulttool get test-results tests --path "/tmp/issue40-v4-final-full-dd.woAHgh/Logs/Test/Test-FeishuSpeech-2026.08.23_23-20-14-+0800.xcresult"
=> DirectFeishuKeepAliveSessionTests/test_liveKeepAliveTCPIsNotOnVPNTunnelAddress()
```

The source gives the reason at `FeishuSpeechTests/DirectFeishuKeepAliveSessionTests.swift:99-102`:
`live TCP previously hung the XCTest host; issue #34 forbids additional live sockets`. This is
the expected environmental skip, not a v4 review/streaming skip.

The streaming audit commands were:

```text
rg -c '^    func test_' FeishuSpeechTests/StreamingMainViewModelTests.swift
=> 103
rg -n 'XCTSkip|throw XCTSkip|retiredCompatibility|legacy.*skip|skip.*legacy' FeishuSpeechTests/StreamingMainViewModelTests.swift
=> no output
```

The prior 51-name `retiredCompatibilityOutputTests` blanket skip was removed from the test
class. The workflow evidence receipt
`kaola-workflow/issue-40/test-red-v4-r1-r3.md:99-151` explicitly maps all 51 former skipped
method names to active replacement oracles; `test-green-v4-final.md:95-98` records that the
103-test class has no blanket skip and all 51 methods execute. The current run independently
reproduced that state: 103/103 streaming tests passed with zero skips. Thus the 51 legacy cases
are documented retirement/migration history, not hidden runtime skips.

## Forbidden output and confirmation-boundary checks

Production-only searches were run against `FeishuSpeech/**/*.swift`:

```text
printf '%s\\n' 'PASTEBOARD_SEARCH'; rg -n -i 'NSPasteboard|generalPasteboard|changeCount|clearContents|setString\\(|setData\\(|writeObjects|readObjects|pasteboardItems|public\\.png|Apple PNG' FeishuSpeech --glob '*.swift' || true
=> no matches

printf '%s\\n' 'KEYBOARD_PASTE_SEARCH'; rg -n -i 'Cmd.?V|command.?V|CGEventPost\\(|CGEventPostToPid|CGEventCreateKeyboardEvent' FeishuSpeech --glob '*.swift' || true
=> no matches
```

The pre-confirmation call-graph search was:

```text
rg -n -i 'finalTextOutput\\.insert|insertAtCurrentFocusOnce|applyOpaqueHypothesis|makeSession\\(|CurrentFocusProvisionalOutputSession|ReviewOutputCompatibilityWriter|ReviewOutputCompatibilityPoster|deliver\\(' FeishuSpeech --glob '*.swift'
```

It found only dormant protocol/service definitions and the single review delivery authority:
`MainViewModel.swift:2010` calls `reviewDestinationDelivery.deliver(...)`; the destination
delivery implementation calls the final text output only inside the confirmed delivery path.
No pasteboard or keyboard-post symbol matched anywhere in production. The dormant
`CurrentFocusAppendSession` and compatibility writer definitions are not evidence of a live
accepted-interaction caller; the 103 streaming tests assert they are inert.

## Documentation/link checks

The stale/current-claim search was:

```text
rg -n -i 'clipboard|pasteboard|Cmd.?V|command.?V|自动插入|auto.?insert|copy.*manual|manual recovery|direct.*output|provisional.*output|output.*before|release.*insert|Fn.*insert|recognition.*insert|重试编辑' README.md CHANGELOG.md docs --glob '*.md'
```

The matches are explicitly labelled historical, superseded, dormant, or non-review in the
current docs. In particular, `docs/architecture.md:662-676` labels the old issue #13 mechanics
as a historical/non-review API surface, while `docs/decisions/D-40-01.md` and the v4 streaming
design state that the current route has no pasteboard/Cmd+V transaction and requires real
Send/qualified Return confirmation. No contradictory unqualified current-authority claim was
found.

The local-link checker was:

```text
ruby -e 'require "pathname"; files = [Pathname("README.md"), Pathname("CHANGELOG.md")] + Dir["docs/**/*.md"].map { |p| Pathname(p) }; missing = []; total = 0; files.each do |file| text = File.read(file); text.scan(/\\]\\(([^)]+)\\)/).each do |m| target = m.first.strip; next if target.empty? || target.start_with?("http://", "https://", "mailto:", "#"); target = target.split("#", 2).first.split("?", 2).first; next if target.empty?; total += 1; resolved = (file.dirname + target).cleanpath; missing << "#{file}: #{target} -> #{resolved}" unless resolved.exist?; end; end; puts "LOCAL_MARKDOWN_LINKS=#{total}"; if missing.empty?; puts "MISSING_LOCAL_MARKDOWN_LINKS=0"; else; puts "MISSING_LOCAL_MARKDOWN_LINKS=#{missing.length}"; puts missing; exit 1; end'
=> LOCAL_MARKDOWN_LINKS=53; MISSING_LOCAL_MARKDOWN_LINKS=0; exit 0
```

## Protected asynchronous topology

The capture/recognition protected-file diff check was:

```text
git diff --name-only -- FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/HotKeyService.swift FeishuSpeech/Services/FeishuStreamingSession.swift FeishuSpeech/Services/FeishuAPIService.swift FeishuSpeech/Services/HoldPacketJournal.swift FeishuSpeech/Services/ByteBoundedAudioIngress.swift FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift
=> no output
```

The protected marker scan over the changed review/coordinator files was:

```text
for file in FeishuSpeech/Services/AudioRecorder.swift FeishuSpeech/Services/HotKeyService.swift FeishuSpeech/Services/CurrentFocusAppendSession.swift FeishuSpeech/Services/ReviewDestinationDelivery.swift FeishuSpeech/Services/TextInputSimulator.swift FeishuSpeech/ViewModels/MainViewModel.swift; do printf 'FILE=%s\\n' "$file"; git diff --unified=0 -- "$file" | rg -n '^[+-].*(Task|DispatchQueue|MainActor|audioQueue|bufferQueue|CGEventTap|startRunning|stopRunning|await|NSLock|actor|NSEvent|addGlobalMonitor|addLocalMonitor|withChecked|continuation)' || true; done
```

Observed narrowing result:

- `AudioRecorder.swift` and `HotKeyService.swift` produced no changed protected-topology lines.
- `FeishuStreamingSession.swift`, `FeishuAPIService.swift`, `HoldPacketJournal.swift`,
  `ByteBoundedAudioIngress.swift`, and `DirectFeishuKeepAliveSession.swift` had no diff.
- Review-only changes add/cancel `@MainActor` presentation/delivery tasks and review-gate awaits;
  they do not add `Task.detached`, alter the audio queues, move `AVCaptureSession` work off its
  existing `sessionQueue`, or alter the `FeishuStreamingSession` actor.
- Current source still shows the existing `audioQueue`, `bufferQueue`, and `sessionQueue` in
  `AudioRecorder.swift`, and `FeishuStreamingSession` remains an actor. This is source topology
  evidence, not a claim about unmeasured live WindowServer behavior.

## Reproduction status, inference, and limits

Reproduced in this environment:

- The isolated security contract, all 103 streaming tests, the v4 focused matrix, and the full
  macOS target are green under clean DerivedData.
- Exactly one full-target skip remains, the documented live-TCP environmental test.
- Debug and Release builds, strict lint, whitespace, local markdown links, and production
  forbidden-output searches are green.
- The final process check is empty; the app remained stopped and was not installed.

Inference, with high confidence and subject to source/test assumptions: the measured v4
coordinator has one explicit-confirmation delivery gate, with no production pasteboard/Cmd+V
fallback and no changed capture/recognition async root. The tests and static searches rule out
the checked-in paths; they cannot prove that a third-party target consumes a posted Unicode pair.

Not measured by this receipt:

- No GUI/UAT, live microphone, live Feishu credentials, third-party target focus, Accessibility
  permission behavior, or visible text consumption.
- No application launch/install or sole-copy audit.
- No OS-level receipt exists for `CGEventPostToPid`; the product's `submitted-unverified` result
  remains the correct boundary.

Validation conclusion: automated v4 validation is green for the measured axes, with the one
expected live-TCP skip. Replacement installation and owner UAT remain outside this read-only
receipt and are not claimed complete.
