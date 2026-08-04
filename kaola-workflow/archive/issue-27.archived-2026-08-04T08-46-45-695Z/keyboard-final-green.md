# Issue #27 keyboard terminal reconciliation GREEN receipt

Date: 2026-08-04

## Assigned task

Implement the fixed-PID keyboard owner's authoritative terminal reconciliation in
`FeishuSpeech/Services/CurrentFocusAppendSession.swift` only. A differing safe
action-2 final reuses the existing Swift-`Character` replacement transaction while
activation, Secure Input, captured-destination, and physical-interference gates
remain armed. An equal final closes without another synthetic event. Contentless,
unsafe, stale, suspended, and delivery-uncertain outcomes remain fail closed.

## Result

- Verification tier: `tests-green`
- Production commit: `6066a72d94aee5ec6382027037cb3cabbb638d15`
- Production files changed: `FeishuSpeech/Services/CurrentFocusAppendSession.swift`
- Test files changed by implementer: none

The held-snapshot and terminal-final paths now share one private
`postReplacement(with:)` primitive. `finalize` defers owner closure until after the
terminal transaction. It maps exact/revision/extension results to typed final
outcomes and preserves the existing rule that a contentless final cannot create
first output from a fallback accepted snapshot.

## Before verification

Command:

```text
xcrun xctest -XCTest FeishuSpeechTests.CurrentFocusAppendSessionTests/test_authoritativeFinalReconcilesExactGraphemeTailBeforeClosingSafetyMonitors /tmp/feishuspeech-issue27-release-drain-red/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

Result: exit `1`; 1 test executed with 6 expected failures. Production returned
`preservedDivergence`, emitted zero replacement requests, and closed the safety
monitors before any terminal replacement.

Companion baseline:

```text
xcrun xctest -XCTest FeishuSpeechTests.CurrentFocusAppendSessionTests/test_equalAuthoritativeFinalClosesArmedOwnerWithoutDuplicateKeyboardEvents /tmp/feishuspeech-issue27-release-drain-red/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

Result: exit `0`; 1/1 passed.

## After verification

The CurrentFocus bundle was rebuilt from test-custody commit `c522afb` with the
still-RED unrelated `StreamingMainViewModelTests.swift` excluded from this
production unit's focused build:

```text
xcodebuild -quiet -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue27-keyboard-focused EXCLUDED_SOURCE_FILE_NAMES=StreamingMainViewModelTests.swift build-for-testing
```

Result: exit `0`.

Focused authoritative-final test:

```text
LLVM_PROFILE_FILE=/tmp/issue27-keyboard-authoritative-2.profraw xcrun xctest -XCTest FeishuSpeechTests.CurrentFocusAppendSessionTests/test_authoritativeFinalReconcilesExactGraphemeTailBeforeClosingSafetyMonitors /tmp/feishuspeech-issue27-keyboard-focused/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

Result: exit `0`; 1/1 passed.

Focused equal-final test:

```text
LLVM_PROFILE_FILE=/tmp/issue27-keyboard-equal-2.profraw xcrun xctest -XCTest FeishuSpeechTests.CurrentFocusAppendSessionTests/test_equalAuthoritativeFinalClosesArmedOwnerWithoutDuplicateKeyboardEvents /tmp/feishuspeech-issue27-keyboard-focused/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

Result: exit `0`; 1/1 passed.

Full CurrentFocus suite:

```text
LLVM_PROFILE_FILE=/tmp/issue27-keyboard-full-2.profraw xcrun xctest -XCTest FeishuSpeechTests.CurrentFocusAppendSessionTests /tmp/feishuspeech-issue27-keyboard-focused/Build/Products/Debug/FeishuSpeech.app/Contents/PlugIns/FeishuSpeechTests.xctest
```

Result: exit `0`; 37/37 passed.

Strict production-file lint:

```text
swiftlint lint --strict FeishuSpeech/Services/CurrentFocusAppendSession.swift
```

Result: exit `0`; 0 violations.

Debug production build:

```text
xcodebuild -quiet -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -configuration Debug -derivedDataPath /tmp/feishuspeech-issue27-keyboard-final-dd build
```

Result: exit `0`; only pre-existing warnings outside the changed file.

`git diff --check` also exited `0` before commit.
