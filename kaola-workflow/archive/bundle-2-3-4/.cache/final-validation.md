# Final Validation

## Build
command: xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -configuration Debug build 2>&1
exit_code: 1
result: FAIL (ENVIRONMENT — NOT A CODE ERROR)

Error:
  xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory
  '/Library/Developer/CommandLineTools' is a command line tools instance.

Root cause: Xcode.app is not installed on this machine. Only Command Line Tools are present.
xcodebuild requires a full Xcode.app installation. This is an environment issue, not a
source-code issue.

Fallback swiftc typecheck (target arm64-apple-macosx26.2, matching project deployment target):
  Only error found:
    RecordingOverlayView.swift:29:1: error: external macro implementation type
    'PreviewsMacros.SwiftUIView' could not be found for macro 'Preview(_:body:)'
  This error is also an environment artifact: the #Preview macro plugin (PreviewsMacros)
  is bundled inside Xcode.app and is unavailable when running raw swiftc. When built with
  Xcode, this resolves automatically. All availability-guard errors (symbolEffect, pulse,
  repeating) disappeared once the correct deployment target (26.2) was used.

Conclusion: No source-code compilation errors were found. Build failure is environment-only.

## Test
command: xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test 2>&1
exit_code: 1
result: FAIL (ENVIRONMENT — NOT A CODE ERROR)

Error:
  xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory
  '/Library/Developer/CommandLineTools' is a command line tools instance.

Root cause: Same environment issue as Build — Xcode.app not installed.
Test files present and inspected:
  - FeishuSpeechTests/HotKeyServiceTests.swift
  - FeishuSpeechTests/MockURLProtocol.swift
No source-level issues identified in test files.

## Lint
command: swiftlint 2>&1
exit_code: 1
result: FAIL (ENVIRONMENT — NOT A CODE ERROR)

Error:
  /bin/bash: swiftlint: command not found

Root cause: swiftlint is not installed on this machine. Not available via Homebrew
(/opt/homebrew/bin/swiftlint missing), /usr/local/bin, or ~/.mint/bin.
This is an environment issue, not a source-code issue.

## Overall
result: FAIL (ENVIRONMENT ONLY — NO SOURCE-CODE ERRORS DETECTED)

All three commands failed due to missing toolchain components on this machine:
  - xcodebuild requires Xcode.app (not installed; only Command Line Tools present)
  - swiftlint is not installed

Source code analysis via raw swiftc (with correct deployment target macOS 26.2) found
zero real compilation errors. The only error reported (#Preview macro plugin) is itself
an environment artifact that resolves inside a proper Xcode.app build.

Action required: Install Xcode.app and swiftlint before re-running validation.
  - Install Xcode: https://developer.apple.com/xcode/
  - Install swiftlint: brew install swiftlint
