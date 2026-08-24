# Issue #40 final validation — post-R1

Validated 2026-08-23 on the current dirty `workflow/issue-40` candidate after
the R1 production and strengthened-test repair landed. This receipt supersedes
the earlier pre-R1 validation.

## Verdict

**PASS for the requested automated validation gates.** The focused R1 suites,
the full serialized macOS suite, Debug and Release builds, strict SwiftLint,
diff hygiene, protected-path guard, byte-for-byte async-topology checks, and the
available Markdown-link check all passed.

This is not a live-UAT or release-install verdict. No application was installed
or launched for user interaction, no permissions were granted, and no real
third-party target or Feishu network request was exercised.

## Setup

- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
- Workflow evidence root: `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40`
- Candidate branch: `workflow/issue-40`
- `HEAD`: `98e1eb53b6aaee369f6481303a289ca60b843262`
- `HEAD` subject: `chore: archive issue-39 [sink]`
- Worktree was already dirty with the R1 source/test changes and concurrent
  documentation changes; the validator did not edit source, tests, docs, or
  project files.
- macOS: `26.6.2 (25G83)`; Darwin `25.6.0`, arm64
- Xcode: `26.6 (17F113)`; SDK observed by `xcodebuild`: `MacOSX26.5`
- Swift driver: Apple Swift `6.3.3`; SwiftLint `0.65.0`
- Dedicated DerivedData: `/tmp/feishuspeech-issue40-r1-validation.mCTwim`
- No install, commit, push, or workflow-state mutation was performed.

## Commands and observations

### Focused serialized R1 suites

Exact command (exit `0`):

```bash
set -o pipefail
xcodebuild -derivedDataPath /tmp/feishuspeech-issue40-r1-validation.mCTwim -scheme FeishuSpeech -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests test 2>&1 | tee /tmp/feishuspeech-issue40-r1-validation.mCTwim-focused.log
```

| Suite | Executed | Failures | Result |
| --- | ---: | ---: | --- |
| `FinalTextOutputSecurityTests` | 23 | 0 | passed |
| `ReviewDestinationDeliveryTests` | 13 | 0 | passed |
| `ReviewFirstApplicationFallbackTests` | 12 | 0 | passed |
| `ReviewFirstMainViewModelTests` | 24 | 0 | passed |
| `ReviewPasteboardLifecycleTests` | 7 | 0 | passed |
| **Selected aggregate** | **79** | **0** | **TEST SUCCEEDED** |

Result bundle:
`/tmp/feishuspeech-issue40-r1-validation.mCTwim/Logs/Test/Test-FeishuSpeech-2026.08.23_11-54-44-+0800.xcresult`

### Full serialized macOS test suite

Exact command (exit `0`):

```bash
set -o pipefail
xcodebuild -derivedDataPath /tmp/feishuspeech-issue40-r1-validation.mCTwim -scheme FeishuSpeech -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test 2>&1 | tee /tmp/feishuspeech-issue40-r1-validation.mCTwim-full.log
```

Observed result: `All tests` passed; **442 tests executed, 1 test skipped, 0
failures** in `29.880` seconds (XCTest reported `30.074` seconds including
session timing). The sole skip was
`DirectFeishuKeepAliveSessionTests.test_liveKeepAliveTCPIsNotOnVPNTunnelAddress`,
explicitly skipped because a live TCP test previously hung the XCTest host and
issue #34 forbids additional live sockets. The command emitted
`** TEST SUCCEEDED **`.

Result bundle:
`/tmp/feishuspeech-issue40-r1-validation.mCTwim/Logs/Test/Test-FeishuSpeech-2026.08.23_11-56-53-+0800.xcresult`

### Debug build

Exact command (exit `0`):

```bash
set -o pipefail
xcodebuild -derivedDataPath /tmp/feishuspeech-issue40-r1-validation.mCTwim -scheme FeishuSpeech -configuration Debug build 2>&1 | tee /tmp/feishuspeech-issue40-r1-validation.mCTwim-debug-build.log
```

Observed result: `** BUILD SUCCEEDED **`. Xcode emitted one uppercase
destination-selection warning because no destination was specified and multiple
macOS destinations matched; there were no compiler `warning:` diagnostics in
this incremental build log.

### Release build

Exact command (exit `0`):

```bash
set -o pipefail
xcodebuild -derivedDataPath /tmp/feishuspeech-issue40-r1-validation.mCTwim -scheme FeishuSpeech -configuration Release build 2>&1 | tee /tmp/feishuspeech-issue40-r1-validation.mCTwim-release-build.log
```

Observed result: `** BUILD SUCCEEDED **`. The log contained one uppercase
destination-selection warning, 25 Swift compiler `warning:` diagnostic lines,
and one AppIntents metadata warning (`No AppIntents.framework dependency
found`). No build failure marker occurred.

### SwiftLint

Exact command (exit `0`):

```bash
set -o pipefail
swiftlint --strict 2>&1 | tee /tmp/feishuspeech-issue40-r1-validation.mCTwim-swiftlint-strict.log
```

Observed result: **0 violations, 0 serious, 35 files**.

### Diff hygiene and protected paths

`git diff --check` (exit `0`) produced no output.

Exact protected-path command (exit `0`, empty output):

```bash
git diff --name-only -- \
  FeishuSpeech/Services/AudioRecorder.swift \
  FeishuSpeech/Services/ByteBoundedAudioIngress.swift \
  FeishuSpeech/Services/HoldPacketJournal.swift \
  FeishuSpeech/Services/FeishuStreamingSession.swift \
  FeishuSpeech/Services/TransportAttemptContext.swift \
  FeishuSpeech/Services/CurrentFocusAppendSession.swift \
  FeishuSpeech/Controllers/ReviewWindowController.swift \
  FeishuSpeech/Views/TranscriptionReviewView.swift \
  FeishuSpeech/Controllers/OverlayWindowController.swift \
  FeishuSpeech/Views/RecordingOverlayView.swift
```

### Byte-for-byte async topology guard

Current symbol locations were:

- task launch: current lines `635-645`, `HEAD` lines `635-645`
- `drainCapturedAudio`: current lines `893-936`, `HEAD` lines `865-908`
- `consumeAudio`: current lines `938-957`, `HEAD` lines `910-929`

Exact comparison/scan command:

```bash
set +e
file=FeishuSpeech/ViewModels/MainViewModel.swift
git diff --unified=0 -- "$file" | rg '^@@'
diff -u <(git show HEAD:"$file" | sed -n '635,645p') <(sed -n '635,645p' "$file")
diff -u <(git show HEAD:"$file" | sed -n '865,908p') <(sed -n '893,936p' "$file")
diff -u <(git show HEAD:"$file" | sed -n '910,929p') <(sed -n '938,957p' "$file")
sed -n '893,936p' "$file" | rg -n -i 'review|present|render|backpressure'
sed -n '938,957p' "$file" | rg -n -i 'review|present|render|backpressure'
```

`diff -u` comparisons of each current slice against its exact `HEAD` slice all
returned exit `0` with no output. The only `MainViewModel.swift` diff hunks were
the review-destination preflight changes around the earlier
`prepareReviewDestination` function; there were no task-launch, capture-drain,
or consumer-loop hunks. Scanning the current drain and consumer bodies for
`review|present|render|backpressure` returned no matches (expected `rg` exit
`1` for each scan). Thus this run found no review awaits, presentation work, or
backpressure logic introduced into those asynchronous loops.

### Documentation/link check

No repository-provided Markdown-link checker script or configured checker
reference was found by the read-only candidate scan. The available local
relative-link check was run over the changed documentation surfaces with this
exact command (exit `0`, no broken links):

```bash
ruby -e 'files=ARGV; bad=[]; files.each{|f| s=File.read(f); s.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each{|p| next if p =~ %r{^(https?://|#)}; target=p.split("#",2).first; path=File.expand_path(target,File.dirname(f)); bad << "#{f}: #{p}" unless File.exist?(path)}}; puts bad; exit(bad.empty? ? 0 : 1)' README.md CHANGELOG.md docs/README.md docs/architecture.md docs/streaming-speech-design.md docs/decisions/D-38-01.md docs/decisions/D-39-01.md docs/decisions/D-40-01.md
```

A trailing-whitespace scan over the same surfaces returned exit `1` with no
matches (the expected no-match result).

## Warning versus failure accounting

- Focused test log: 46 lower-case `warning:` lines, consisting of 44 Swift
  compiler diagnostics and 2 AppIntents metadata warnings; exit `0`, 79/79
  selected tests passed.
- Full test log: no compiler or AppIntents `warning:` lines; exit `0`,
  442 passed with 1 intentional skip and 0 failures.
- Debug build log: one uppercase Xcode destination-selection warning; exit
  `0` and `BUILD SUCCEEDED`.
- Release build log: 25 Swift compiler diagnostics, one AppIntents metadata
  warning, one uppercase destination-selection warning; exit `0` and `BUILD
  SUCCEEDED`.
- SwiftLint strict: 0 violations; exit `0`.
- The test host also logged environment-limited messages such as failure to
  register with `com.apple.linkd.autoShortcut`, login-item unregister not
  permitted, and Accessibility/microphone remaining false. These did not
  produce XCTest failures or nonzero exits; they are recorded as host/UAT
  limitations, not silently treated as proof of live permission behavior.

## Reproduction status

The post-R1 candidate reproduced green on the first run of every requested
automated gate. No flaky rerun was needed or performed. The requested focused
count is exactly 79, and the newly exercised
`ReviewFirstApplicationFallbackTests` contributed 12 passing tests.

## Narrowing legs and inferences

1. The focused 79-test leg rules in the R1 review-destination, current-focus
   security, pasteboard lifecycle, and review-first ViewModel contracts as
   exercised by XCTest.
2. The full serialized leg rules in regressions detectable by the remaining
   363 tests under one worker; it passed with only the pre-declared live-TCP
   skip.
3. Debug and Release builds rule in successful compilation, linking, signing,
   app validation, and product generation in the isolated DerivedData tree.
4. Strict lint, diff hygiene, protected-path, and async byte comparisons rule
   in the requested static cleanliness and preserve the capture-drain/consumer
   topology relative to `HEAD`.

Inference (high confidence, limited to these measurements): the current dirty
candidate satisfies the requested automated Issue #40/R1 validation gates, and
the measured R1 fallback/security behavior is covered by passing tests. This
does not establish correctness under a real WindowServer, target application,
TCC state, or network.

## Remaining unmeasured / live-UAT boundary

Not measured in this read-only validation:

- installing or launching the built app from `/tmp`;
- real Accessibility and microphone authorization flows;
- real Secure Input transitions and frontmost-process races;
- actual AX cursor capture or a third-party app's multiline editor;
- real synthetic Unicode/Cmd-V delivery and pasteboard restoration in a user
  session;
- Feishu authentication/recognition over the live network;
- release distribution signing/notarization and installed-app behavior.

Logs retained under the dedicated `/tmp/feishuspeech-issue40-r1-validation.mCTwim`
tree are the raw command evidence for this receipt.

verdict: pass
validation_command: xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /private/tmp/issue40-v9-full-20260824 test -quiet
validated_candidate_hash: 9959180ece24d9a531003c1196c0a79d6c55327a7398438dad5902e1bbd4f460
