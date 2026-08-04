# Issue 27 test-contract migration

## Scope

This migration replaces release-time expectations that contradicted the authoritative-final and resilient-drain contract. It changes tests only; the production edit already present in the issue worktree was neither staged nor committed.

Starting baseline: `eb9f0b340bb2013374800492d7eaf5d04f1b19ab`

Test-only migration commit: `c522afb` (`test: migrate release final contract`)

## Authoritative-final contract

The `CurrentFocusAppendSessionTests` oracle now requires `finalize` to reconcile a usable authoritative final value through the owner captured before Fn-up:

- an extension commits only the unseen suffix before the owner closes;
- a revision or shortening emits the exact keyboard replacement transaction;
- an equal final remains a no-op;
- an empty final preserves already emitted text and cannot create first output;
- fixed PID, Secure Input, destination-change, physical-interference, delivery-uncertainty, and stale-generation fail-closed cases remain intact.

Concrete replacement examples are pinned as keyboard operations:

- `base` to `base final`: zero backspaces, insert ` final`;
- `visible` to `revise`: seven backspaces, insert `revise`;
- `visible` to `vis`: four backspaces, insert nothing.

## Coordinator contract

The directly contradictory coordinator expectations now require:

- Fn-up opens a bounded terminal drain instead of cancelling admitted work;
- an in-flight packet, retry sleep, session creation, replay attempt, and recoverable finish remain admitted for the same generation;
- captured packets are replayed to the successor before terminal settlement;
- the authoritative final is offered once to the already armed append owner;
- the recorder stop barrier controls cleanup but does not cancel retry/replay authority;
- callbacks after cleanup remain suppressed;
- automatic insertion disabled, missing owner/factory, unsafe text, changed destination, Secure Input, interference, and uncertain delivery continue to fail closed without clipboard fallback.

## Baseline falsification record

The migrated append tests were applied to a disposable detached worktree at the exact baseline SHA. The focused target compiled after excluding the unrelated coordinator file, but the macOS app test host launched without starting XCTest; it was terminated without requesting permissions.

The baseline source nevertheless exposes the exact deterministic mismatches exercised by these named tests:

- `test_finalizeCommitsAuthoritativeExtensionAsSuffixBeforeClosingOwner`: expected `.suffixCommitted` plus `{ delete: 0, insert: " final", pid: fixedPID }`; baseline `finalize` returns `.preservedDivergence` and posts no replacement whenever the candidate differs from `previousSnapshot`.
- `test_finalizeRevisionOrShorteningReconcilesOwnedTailExactly`: expected `.exactCommitted` plus exact backspace/insert transactions; baseline `finalize` returns `.preservedDivergence` and posts no replacement for both revision and shortening.

The full focused migration command remains RED before test execution because the earlier issue-27 drain tests refer to production API that is not yet implemented:

`StreamingMainViewModelTests.test_postReleaseDrainExpiryPreservesOutputAndSuppressesLatePacketCompletion` and its companion drain-policy test cannot compile because `StreamingDrainPolicy` is absent and `MainViewModel` does not accept `streamingDrainPolicy`.

Failure signature: `StreamingMainViewModelTests.swift:1638:35: error: cannot find 'StreamingDrainPolicy' in scope` (repeated at line 1689), followed by `extra argument 'streamingDrainPolicy' in call`.

## Commands and evidence

- `git diff --check`
- focused current-worktree command: `xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue27-contract-migration -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test`
- focused RED log: `/tmp/feishuspeech-issue27-contract-migration-rerun.log`
- focused RED result bundle: `/tmp/feishuspeech-issue27-contract-migration/Logs/Test/Test-FeishuSpeech-2026.08.04_15-37-43-+0800.xcresult`
- detached-baseline build log: `/tmp/feishuspeech-contract-baseline.log`

No green-suite verdict is claimed by test custody.
