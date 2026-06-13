evidence-binding: n3-keychain-storage-migration 9e991aa45c7f

# n3-keychain-storage-migration Evidence

## Scope

- Updated `FeishuSpeech/Models/AppSettings.swift`.
- Added `FeishuSpeech/Services/KeychainCredentialStore.swift`.
- Added and expanded `FeishuSpeechTests/AppSettingsCredentialStorageTests.swift`.

## Initial RED

- `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -only-testing:FeishuSpeechTests/AppSettingsCredentialStorageTests test`
- Initial failure: test target could not compile before the new credential storage contracts existed (`CredentialStoring` / `CredentialAccount` unresolved).

## Initial GREEN

- `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -only-testing:FeishuSpeechTests/AppSettingsCredentialStorageTests test`
- Result: passed, 5 `AppSettingsCredentialStorageTests` tests.

## Review-Fix RED

Code review found two in-scope high findings:

- R1: standalone plaintext credentials from prior `@AppStorage("appId")` / `@AppStorage("appSecret")` could be removed without migration.
- R2: Keychain read/write failures could collapse to empty credentials, delete valid Keychain items, or scrub legacy plaintext after a failed migration write.

Added failing tests before the first review fix:

- `test_load_migratesStandaloneCredentialsWhenEncodedSettingsHasNoCredentials`
- `test_load_prefersStandaloneCredentialsWhenTheyDifferFromEncodedLegacyValues`
- `test_load_keepsLegacyDefaultsWhenCredentialMigrationSaveFails`
- `test_saveAfterCredentialReadFailureDoesNotDeleteExistingCredential`

RED command:

- `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test -only-testing:FeishuSpeechTests/AppSettingsCredentialStorageTests`
- Result: failed, with the four new review-fix tests failing after compile was corrected.

## Review-Fix GREEN

- `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test -only-testing:FeishuSpeechTests/AppSettingsCredentialStorageTests`
- Result: passed, 9 `AppSettingsCredentialStorageTests` tests.
- `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test`
  - Result: passed before the second R2 edge-case follow-up.

## Second R2 RED

Second code review found R1 resolved and R2 still open for this edge case:

- if encoded legacy credential migration fails, a later `settings.save()` could rewrite `FeishuSpeechSettings` without credentials and erase the only encoded plaintext fallback while Keychain writes still fail.

Added failing test:

- `test_saveAfterFailedEncodedMigrationKeepsLegacySettingsPayload`

RED command attempted:

- `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' -parallel-testing-enabled NO test -only-testing:FeishuSpeechTests/AppSettingsCredentialStorageTests/test_saveAfterFailedEncodedMigrationKeepsLegacySettingsPayload`
- Result: Xcode app-host test runner hung after launching the test host. The installed FeishuSpeech app was quit and DerivedData test-host processes were cleaned, but xcodebuild still hung in the runner layer.

## Second R2 GREEN

To bypass the xcodebuild host-connection hang, the already built test bundle was run directly with `xcrun xctest` after symlinking the app debug dylib into the generated test bundle's `Contents/Frameworks`.

- `xcrun xctest -XCTest FeishuSpeechTests.AppSettingsCredentialStorageTests/test_saveAfterFailedEncodedMigrationKeepsLegacySettingsPayload .../FeishuSpeechTests.xctest`
  - Result: passed, 1 test.
- `xcrun xctest -XCTest FeishuSpeechTests.AppSettingsCredentialStorageTests .../FeishuSpeechTests.xctest`
  - Result: passed, 10 `AppSettingsCredentialStorageTests` tests.

## Validation

- `xcodebuild -scheme FeishuSpeech -configuration Debug build`
  - Result: passed after the final R2 fix.
- `git diff --check -- FeishuSpeech/Models/AppSettings.swift FeishuSpeech/Services/KeychainCredentialStore.swift FeishuSpeechTests/AppSettingsCredentialStorageTests.swift`
  - Result: passed after the final R2 fix.
- `swiftlint`
  - Result: unavailable in this environment (`command not found`).

## Behavior

- `AppSettings.save()` routes `appId` and `appSecret` through `CredentialStoring` and encodes only non-sensitive preferences when credential writes are complete.
- `AppSettings.load()` migrates credentials from both legacy plaintext paths: encoded `FeishuSpeechSettings` JSON and standalone `UserDefaults` keys. Standalone credential keys win when both sources are present because they could be newer than the last encoded settings payload.
- Legacy plaintext credentials are scrubbed only after all required Keychain migration writes and reads succeed.
- If legacy credential fallback is still needed, `save()` skips the no-credential preferences rewrite when any credential save fails, preserving the old plaintext fallback instead of losing credentials.
- Keychain read failures are tracked per credential account; a later save skips delete for an empty credential that came from a failed read, avoiding accidental removal of a valid existing Keychain item.
- Empty credential values still delete the corresponding Keychain item when there was no prior read failure.
- The new Keychain store uses generic password items keyed by app service and credential account, with an isolated-service contract test.
