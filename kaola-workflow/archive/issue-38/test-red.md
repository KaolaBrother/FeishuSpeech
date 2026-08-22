# Issue #38 RED evidence

- Baseline commit: `ec3e4bda902715714f27753e2289a8170f1a45fe`
- Test custody: `tdd-guide`; production files were not modified.
- Command:

  ```bash
  xcodebuild -scheme FeishuSpeech \
    -destination 'platform=macOS' \
    -parallel-testing-enabled NO \
    -maximum-parallel-testing-workers 1 \
    -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests \
    build-for-testing
  ```

- Result: `** TEST BUILD FAILED **`, as required on the baseline.
- Representative missing-production failures:
  - `ReviewApplicationIdentity` not found.
  - `MacAccessibilityClient.captureReviewCursorDestination` not found.
  - The two-phase `FinalTextOutput.insertOnce` overload is absent.
  - `FinalTextInsertionResult.deliveryUncertain` is absent.
  - `SystemReviewDestinationDelivery` is absent.
- Full log: `/tmp/feishuspeech-issue38-red-revised-final.log`
- Test static checks: `swiftc -parse` passed, strict SwiftLint reported zero violations, and `git diff --check` passed.
- The revised tests encode the owner-confirmed third review axis: visible read-only streaming/sealing preview, editable action-2 transition on the same review panel, and no review UI dependency in either the capture/journal or recognition/retry/replay asynchronous line.
