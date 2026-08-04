# Finalization — Summary: issue-27

## Delivered

- Fn release now stops capture without closing current-generation recognition or output admission.
- Queued and tail audio, journal replay, recoverable retry, and Feishu action 2 drain before output ownership closes.
- The authoritative terminal snapshot reconciles the existing AX range or fixed-PID keyboard owner exactly once.
- Repeated backend code 10024 remains recoverable and every packet acknowledgement resets the consecutive retry backoff.
- Factory, packet, and finish operations have 30-second watchdogs; post-recorder-barrier drain has a bounded 60-second budget.
- Expiry distinguishes committed, uncertain, rejected, and absent output; it preserves visible text conservatively and suppresses late completions.
- Release 1.0 build 8 is installed as the sole Applications copy and remains unlaunched for owner UAT.

## Files Changed

- Production: `StreamingSpeechModels.swift`, `CurrentFocusAppendSession.swift`, `MainViewModel.swift`.
- Tests: `CurrentFocusAppendSessionTests.swift`, `StreamingMainViewModelTests.swift`.
- Configuration: `FeishuSpeech.xcodeproj/project.pbxproj`.
- Documentation: README, changelog, documentation index, API, architecture, streaming design, and D-27-01.

## Test Coverage

- Release tail packet and authoritative action-2 final for AX and keyboard routes.
- Release during factory, retry, replay, recorder barrier, and in-flight packet work.
- Repeated backend 10024 recovery, retry-streak reset, operation watchdogs, and post-release drain expiry.
- AX terminal acknowledgement failure, typed output preservation, deadline admission races, and late noncooperative factory cancellation.
- Fixed PID, Secure Input, physical-interference epoch, exact grapheme replacement, unsafe controls, stale generation/attempt, and late-result suppression.
- Final authored XCTest bundle: 316/316 passed.

## Validation

- Consumer validation receipt: PASS, candidate hash `5a63394083edf321e626429e3f2a74dd1423ed154d4fbcfb057c0dab9ca24fa4`.
- Strict SwiftLint: 27 files, 0 violations.
- Debug and Release builds: passed.
- Release metadata: version 1.0, build 8.
- Strict deep code-sign verification: passed with the local ad-hoc signature; no Developer ID or notarization claim.
- Independent correctness and security re-reviews: PASS; findings R1-R4 resolved.
- Documentation commit `b78e68a` landed after the binary validation and changed documentation only.

## Changed Paths

- `CHANGELOG.md`
- `FeishuSpeech.xcodeproj/project.pbxproj`
- `FeishuSpeech/Models/StreamingSpeechModels.swift`
- `FeishuSpeech/Services/CurrentFocusAppendSession.swift`
- `FeishuSpeech/ViewModels/MainViewModel.swift`
- `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift`
- `FeishuSpeechTests/StreamingMainViewModelTests.swift`
- `README.md`
- `docs/README.md`
- `docs/api.md`
- `docs/architecture.md`
- `docs/decisions/D-27-01.md`
- `docs/streaming-speech-design.md`

## Documentation Docking

- `.cache/doc-updater.md`: verdict PASS.
- `.cache/doc-docking.md`: verdict DOCKED.
- No real-credential or cross-application UAT success is claimed.

## Run gaps

None swept. All diagnostic and review findings were reproduced, fixed, and closed inside issue #27.

## Follow-Up Items

- Owner UAT of Release 1.0 build 8 remains pending for real Feishu credentials, tail completion after Fn release, repeated 10024 recovery, and real target applications.
- GitHub issue #27 remains open in `comment_keep_open` mode until that UAT result is recorded.
- Developer ID signing and notarization are outside this local Release.

## Status: ARCHIVED AFTER FINAL GIT GATE
