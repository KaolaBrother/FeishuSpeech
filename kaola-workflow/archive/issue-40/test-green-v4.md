# Issue #40 v4 TDD GREEN receipt

Baseline RED: `4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a`.
The v4 amendment RED receipt is [test-red-v4.md](/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/test-red-v4.md); it records 145 tests, 181 failures, exit 65, including the representative failures for obsolete `editablePending`, pasteboard/Cmd+V output, missing Unicode pair construction, UTF-16 cap/provenance/phase checks, and monitor PID/tag epoch filters.

## Final serialized matrix

Command:

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/issue40-v4-final-matrix -parallel-testing-enabled NO -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests -only-testing:FeishuSpeechTests/FinalTextOutputSecurityTests -only-testing:FeishuSpeechTests/ReviewDestinationDeliveryTests -only-testing:FeishuSpeechTests/ReviewFirstApplicationFallbackTests -only-testing:FeishuSpeechTests/ReviewFirstMainViewModelTests -only-testing:FeishuSpeechTests/ReviewPasteboardLifecycleTests -only-testing:FeishuSpeechTests/ReviewWindowControllerReadinessTests -only-testing:FeishuSpeechTests/StreamingMainViewModelTests -only-testing:FeishuSpeechTests/TranscriptionReviewViewTests test 2>&1 | tee /tmp/issue40-v4-final-matrix.log
```

Result: exit `0`; 264 tests executed, 51 explicitly skipped as retired obsolete direct-output MainViewModel oracles, and 0 failures. Result bundle: `/tmp/issue40-v4-final-matrix/Logs/Test/Test-FeishuSpeech-2026.08.23_22-18-04-+0800.xcresult`. `git diff --check` passed.

| Suite | Executed | Skipped | Failures |
|---|---:|---:|---:|
| `CurrentFocusAppendSessionTests` | 38 | 0 | 0 |
| `FinalTextOutputSecurityTests` | 33 | 0 | 0 |
| `ReviewDestinationDeliveryTests` | 13 | 0 | 0 |
| `ReviewFirstApplicationFallbackTests` | 16 | 0 | 0 |
| `ReviewFirstMainViewModelTests` | 31 | 0 | 0 |
| `ReviewPasteboardLifecycleTests` | 7 | 0 | 0 |
| `ReviewWindowControllerReadinessTests` | 11 | 0 | 0 |
| `StreamingMainViewModelTests` | 103 | 51 | 0 |
| `TranscriptionReviewViewTests` | 12 | 0 | 0 |
| **total** | **264** | **51** | **0** |

## Migration and oracle status

- Migrated output doubles to `FinalTextCurrentFocusEventPosting`, `ReviewUnicodeOutputResult`, captured PID, readback/provenance, and phase-aware outcomes. Exact and application-bound security suites retain one modifier-free tagged Unicode pair, full multiline UTF-16 draft, zero-pair preflight failure, and one-pair postflight uncertainty assertions.
- Added deterministic application-bound trust transition coverage: trust revoked after capture is rejected before any output; trust transition during preflight fails closed; trust transition during postflight preserves the one submitted pair as uncertain. All assert zero pasteboard snapshot/read/write/restore/change-count, Cmd+V, retarget, retry, and copy collaborators.
- Migrated fallback and MainViewModel confirmation fixtures to a real materialized editor and qualified native Return event. No coordinator zero-argument or optional-revision bypass is used. The fallback suite additionally verifies exact draft/authority retention after trust failure.
- Retired only obsolete selectable-direct-output StreamingMainViewModel cases; the canonical preview-only route remains covered by `ReviewFirstMainViewModelTests` for both legacy configuration values.
- Retained lower-level exact/application-bound, multiline/keyboard, stale-callback, exact-once, modifier/PID/tag epoch, UTF-16 cap, and provenance/fault boundary oracles without weakening them.

## Test custody

Test-only changes are confined to:

`CurrentFocusAppendSessionTests.swift`, `FinalTextOutputSecurityTests.swift`, `ReviewDestinationDeliveryTests.swift`, `ReviewFirstApplicationFallbackTests.swift`, `ReviewFirstMainViewModelTests.swift`, `ReviewPasteboardLifecycleTests.swift`, `ReviewWindowControllerReadinessTests.swift`, `StreamingMainViewModelTests.swift`, and `TranscriptionReviewViewTests.swift`.

No production source was authored or changed by this test-author lane. The receipt records the exact v4 RED baseline and current GREEN evidence for issue review.
