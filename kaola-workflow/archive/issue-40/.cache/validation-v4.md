# Issue #40 v4 independent validation receipt

## Setup

- Validation timestamp: `2026-08-23T22:25:35+08:00`
- Repository: `/Users/ylpromax5/Workspace/feishuspeech`
- Validation worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-40`
- Branch: `workflow/issue-40`
- Baseline commit reported by `git rev-parse HEAD`: `4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a`
- The v4 production/test/doc changes were uncommitted in the worktree during validation. Validation did not edit tracked files. A concurrent documentation update added `README.md` to the final dirty set; all validation commands below ran against the observed worktree contents.
- Host: macOS `26.6.2` build `25G83`, arm64 MacBook Pro
- Xcode: `26.6`, build `17F113`
- SwiftLint: `0.65.0`
- Scheme/target: `FeishuSpeech` / `FeishuSpeechTests`
- App state before and after validation: no `FeishuSpeech`, `Siji.FeishuSpeech`, or `FeishuSpeechTests` process was present. The app was not launched or installed by this validation.

## Observation table

| Measurement | Exact command | Result | Exit |
|---|---|---:|---:|
| Worktree/commit baseline | `git rev-parse HEAD; git status --short --branch` | `HEAD=4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a`; branch `workflow/issue-40`; v4 files dirty as expected | 0 |
| Focused v4/output/security/review suites, clean DerivedData | `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-focused-dd.bNWtoi -parallel-testing-enabled NO test -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewKeyboardTests` | 174 passed, 0 skipped, 0 failed; xcresult: `/tmp/issue40-v4-focused-dd.bNWtoi/Logs/Test/Test-FeishuSpeech-2026.08.23_22-21-48-+0800.xcresult` | 0 |
| Full macOS test target, clean DerivedData | `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-full-dd.RU9I9z -parallel-testing-enabled NO test` | 483 total; 431 passed, 52 skipped, 0 failed; xcresult summary result `Passed`; xcresult: `/tmp/issue40-v4-full-dd.RU9I9z/Logs/Test/Test-FeishuSpeech-2026.08.23_22-22-13-+0800.xcresult` | 0 |
| Debug build, clean DerivedData | `xcodebuild -scheme FeishuSpeech -configuration Debug -derivedDataPath /tmp/issue40-v4-debug-dd.5uicfU build` | `** BUILD SUCCEEDED **` | 0 |
| Release build, clean DerivedData | `xcodebuild -scheme FeishuSpeech -configuration Release -derivedDataPath /tmp/issue40-v4-release-dd.rlIYC6 build` | `** BUILD SUCCEEDED **`; compiler emitted warnings but no errors | 0 |
| Strict lint | `swiftlint --strict` | `Done linting! Found 0 violations, 0 serious in 35 files.` | 0 |
| Diff whitespace integrity | `git diff --check` | No output; no whitespace errors | 0 |
| App remains stopped | `pgrep -alf 'FeishuSpeech|Siji.FeishuSpeech|FeishuSpeechTests' || true` | Only the invoking `pgrep` shell line matched; no app/test process remained | 0 |

## Test-skip audit

The full run's 52 skipped tests were not an accidental broad skip:

- `StreamingMainViewModelTests.swift:16-68` contains exactly 51 named entries (`rg -c '^        "'` returned `51`).
- `StreamingMainViewModelTests.swift:70-75` skips only those names and records the reason: `Retired obsolete direct-output MainViewModel oracle; canonical preview route is covered by ReviewFirstMainViewModelTests`.
- `xcresulttool get test-results tests` returned exactly those 51 `StreamingMainViewModelTests/...` identifiers plus `DirectFeishuKeepAliveSessionTests/test_liveKeepAliveTCPIsNotOnVPNTunnelAddress()`.
- The remaining skip is explicitly documented at `DirectFeishuKeepAliveSessionTests.swift:99-102` because the live TCP test previously hung the XCTest host and issue #34 forbids additional live sockets.
- The Keychain skip branch exists in source but was not part of this run's skipped set; the full test run had 52 skips, accounted for above.

## Forbidden output/search measurements

Commands were run over `FeishuSpeech/**/*.swift` in the validated worktree.

1. Pasteboard search:

   `rg -n "NSPasteboard|generalPasteboard|changeCount|clearContents|setString\\(|setData\\(|writeObjects|readObjects|pasteboardItems|public\\.png|Apple PNG" FeishuSpeech --glob '*.swift'`

   Result: **0 production matches**. No `NSPasteboard`, general-pasteboard snapshot, write, restore, change-count polling, or image-paste symbol remains in production source.

2. Cmd+V/keyboard-post search:

   `rg -n -i "Cmd.?V|command.?V|CGEventPost\\(|CGEventPostToPid|CGEventCreateKeyboardEvent" FeishuSpeech --glob '*.swift'`

   Result: **0 production matches**. The search found no Cmd+V or CoreGraphics keyboard-post API. The final-confirmation implementation uses the injected Unicode event backend, not a pasteboard or virtual-key command path.

3. AX mutation search:

   `rg -n "AXUIElementSetAttributeValue|setSelectedText\\(|setSelectedTextRange\\(" FeishuSpeech --glob '*.swift'`

   Result: 16 textual matches, all in the legacy `AccessibilityClient.swift`/`CursorTextSession.swift` implementation and declarations. This is not a claim that AX mutation symbols were deleted. The production call-site search found no `CursorTextSession` construction/use, no `setSelectedText` call from `MainViewModel`, and no `setSelectedText` call from `ReviewDestinationDelivery`; those APIs are not on the accepted v4 preview route.

4. Direct-output/provisional call-site search:

   `rg -n "currentFocusAppendSessionFactory|CurrentFocusProvisionalOutputSession|makeSession\\(|applyOpaqueHypothesis|insertAtCurrentFocusOnce|finalTextOutput\\.insert|setSelectedText|CGEvent" FeishuSpeech --glob '*.swift'`

   Result: the only `MainViewModel` hits for `finalTextOutput` and `currentFocusAppendSessionFactory` are legacy initializer labels followed by `_ =` at `MainViewModel.swift:327-359`; no accepted interaction constructs or selects those direct-output owners. No production caller of `makeSession` or `applyOpaqueHypothesis` exists outside `CurrentFocusAppendSession.swift` itself.

5. Confirmation call-chain inspection:

   - `MainViewModel.swift:1799-1830` transitions to `.editable` and installs the draft-change/opaque-confirmation callbacks.
   - `MainViewModel.swift:1950-2020` requires the current review ID, matching surface revision, `.editable` state, non-contentless safe draft, and no in-flight confirmation before it calls `reviewDestinationDelivery.deliver` at line 2010.
   - `ReviewDestinationDelivery.swift:570-604` arms monitoring and activates the captured app before `deliverAfterActivation`.
   - `ReviewDestinationDelivery.swift:607-633` checks current destination, stabilizes modifiers, captures baselines, and only then enters `insertReviewText`.
   - `ReviewDestinationDelivery.swift:636-681` calls the strict pair-gated review output overloads. The default `SystemFinalTextOutput` is constructed only by `SystemReviewDestinationDelivery` at `ReviewDestinationDelivery.swift:512-521`.
   - `TextInputSimulator.swift:770-905` constructs/tag-targets/readbacks the complete Unicode pair before the first post, then marks the down post as the irreversible submission boundary and attempts the mandatory up post.

## Reproduction status

- Reproduced and validated: the focused v4 test matrix is green, including zero-side-effect preview/edit ledger coverage, no-pasteboard lifecycle assertions, opaque confirmation-intent fencing, exact Send/Return behavior, destination binding, modifier/epoch/provenance checks, Unicode cap/readback, and post-down uncertainty handling.
- Reproduced and validated: the complete macOS unit-test target is green at 483 total tests with zero failures.
- Reproduced and validated: Debug and Release production builds compile/link/package successfully.
- Reproduced and validated: strict lint and diff checks are clean.
- Reproduced and validated: the app remains stopped after validation.
- Not reproduced by this read-only validation: a real external target application receiving physical Fn/typing/clipboard interaction. The computer-use skill's required `node_repl` capability was unavailable in this environment, so no GUI owner UAT was attempted and no runtime claim is made for that unmeasured leg.

## Narrowing legs

1. **Test behavior axis:** focused v4 suites passed with 174/174. This rules out the known preview/output/security regressions in the supplied deterministic test doubles and test ledger.
2. **Whole-target axis:** full target passed 431 passed + 52 accounted skips. This rules out a compile/test integration failure outside the focused suites.
3. **Build axis:** clean Debug and Release builds passed. This rules out a configuration-specific compile/link/package failure.
4. **Static side-effect axis:** zero pasteboard/Cmd+V/CGEventPost production matches; no pre-confirm production caller for the retained provisional/legacy output owners. This rules out the prior clipboard/Cmd+V implementation being present on the source path, while not proving the absence of every possible runtime event from unmeasured external GUI interaction.
5. **Process-liveness axis:** no FeishuSpeech process remained. This rules out an app process continuing to emit events after this validation; it does not diagnose pending events already queued in another target application's event queue.

## Labeled inferences

- **High confidence:** the v4 accepted application flow has one output authority after explicit Send/qualified Return: `handleReviewConfirmation` → `ReviewDestinationDelivering.deliver` → strict pair-gated Unicode output. Streaming snapshots, recorder sealing, editable draft changes, and focus telemetry do not call a target-output API in `MainViewModel`.
- **High confidence:** the prior image-paste mechanism is absent from the current production source: no pasteboard API and no Cmd+V/CoreGraphics keyboard-post symbol matched. The retained compatibility writer/poster are empty marker types.
- **Medium-to-high confidence:** legacy AX/provisional-output implementations remain in the source tree for compatibility/tests, but are unreachable from accepted production interactions because `MainViewModel` ignores those injected owners and no production call sites construct/use the provisional session. A code-owner decision is still required if the desired contract is source-level deletion rather than runtime-path exclusion.
- **High confidence:** once the final Unicode key-down is posted, the implementation reports submitted-unverified/uncertain rather than cancellation and attempts key-up; this is covered by the focused security tests and the source order at `TextInputSimulator.swift:875-905`.
- **No claim:** this validation does not prove the receiving application consumed the event, because `CGEventPostToPid`/the injected posting backend provides no consumption receipt. It only validates the local preflight/posting/uncertainty contract.

## Remaining unmeasured or non-blocking observations

- Owner GUI UAT against a real editable target, including checking an untouched image clipboard before/after Fn, recognition, each draft edit, Send, and Return, remains unmeasured here. The app was deliberately not launched or installed.
- The Release build emitted existing Swift 6 migration warnings for `NSLock` use from async contexts in `TransportAttemptContext.swift`, a no-op `await` in `MainViewModel.swift`, and a statically unreachable reset line. They did not fail the build or strict lint; they remain observations for the owning implementation/review lanes.
- Xcode's test harness emitted AppKit/transaction warnings during some UI tests, but the affected tests passed and the xcresult reported zero failures.

## Validator verdict

Deterministic v4 validation is **PASS** for the measured test/build/lint/static/process axes, with **GUI owner UAT still required** before installation or final issue closure. The app remains stopped; no install or external output was performed by this validation.
