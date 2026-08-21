# Issue #35 data-protection keychain / launch-at-login — RED receipt

Date: 2026-08-21

## Assignment

Pin failing tests for: data-protection keychain (no login-keychain ACL dialogs), AppDelegate
launch-at-login from UserDefaults without reading credentials, and migration from the two existing
login-keychain generic-password items.

## Test artifact

- `FeishuSpeechTests/AppSettingsCredentialStorageTests.swift`
- Production files changed: none

## Baseline

- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/bundle-34-35`
- Branch: `workflow/bundle-34-35`
- HEAD SHA from `.git/refs/heads/workflow/bundle-34-35`: `276c470d86e64634f70ebf2252e7a62ea94c884c`
- Production `FeishuSpeech/` was not modified

## xcodebuild run

Orchestrator ran the same worktree command as `test-red-34.md`. Build failed first on
`BoundPhysicalDNS` (issue #34 seam). `AppSettings.launchAtLoginPreference(from:)` is still
absent in `AppSettings.swift` on this baseline, so the #35 tests cannot link until that
API exists; that remains the #35 compile-fail oracle.

Command to execute on this worktree:

```bash
cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/bundle-34-35
git rev-parse HEAD
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/feishuspeech-issue-35-test-red \
  -only-testing:FeishuSpeechTests/AppSettingsCredentialStorageTests test
```

## Expected RED on this baseline (source inspection, not a run)

```
RED: test_launchAtLoginPreference_readsEncodedPayloadWithoutTouchingCredentialStore
     type 'AppSettings' has no member 'launchAtLoginPreference'
baseline: 276c470d86e64634f70ebf2252e7a62ea94c884c
```

That compile-fail is the oracle for claim 3. Until `AppSettings.launchAtLoginPreference(from:)`
exists, the test target does not link and the assertion tests below do not execute. After a stub
lands, those assertions are still false on this baseline:

| Test | Why it fails on `276c470` |
|---|---|
| `test_keychainCredentialStoreSource_usesDataProtectionKeychainAndAfterFirstUnlockAccessibility` | `KeychainCredentialStore.baseQuery` has no `kSecUseDataProtectionKeychain` and no after-first-unlock `kSecAttrAccessible` |
| `test_appDelegateDidFinishLaunching_doesNotLoadAppSettingsCredentials` | `applicationDidFinishLaunching` still contains `AppSettings.load()` and does not call `launchAtLoginPreference` |
| `test_appSettingsSource_declaresLaunchAtLoginPreferenceReader` | `AppSettings.swift` has no `func launchAtLoginPreference(from` |
| `test_keychainCredentialStore_saveReadPersistsInDataProtectionKeychain` | saves go to the login keychain; a `kSecUseDataProtectionKeychain=true` query does not see them |
| `test_keychainCredentialStore_migratesLegacyLoginKeychainItemsIntoDataProtectionKeychain` | isolated login-keychain fixtures are readable today, but they are not copied into the data-protection keychain |
| `test_launchAtLoginPreference_readsEncodedPayloadWithoutTouchingCredentialStore` | API missing (compile-fail). After a stub: must decode `launchAtLogin` from the injected `UserDefaults` while a throwing credential store is installed, with zero read/save/delete |

Existing D-18-01 tests in the same file are unchanged.

## Tests encoded (behaviors, not names, are the contract)

1. Production `KeychainCredentialStore` queries set `kSecUseDataProtectionKeychain` and after-first-unlock accessibility.
2. `AppDelegate.applicationDidFinishLaunching` must not call `AppSettings.load()`; it must still apply launch-at-login via `launchAtLoginPreference` + `LoginItemService.setEnabled`.
3. `AppSettings.launchAtLoginPreference(from: UserDefaults)` returns the encoded `FeishuSpeechSettings.launchAtLogin` value (true / false / missing→false) without touching `AppSettings.credentialStore`.
4. Two isolated login-keychain generic-password items (`appId` / `appSecret`) remain readable and become visible to a data-protection query after `KeychainCredentialStore.read`. Two items are fine; collapsing to one is not required.
5. Isolated-service save/read still works and persists in the data-protection keychain. Skip on `errSecMissingEntitlement` / `errSecInteractionNotAllowed`. Never touch `Siji.FeishuSpeech.credentials`.

## Assumed production seam (not implemented on this baseline)

```swift
extension AppSettings {
    static func launchAtLoginPreference(from defaults: UserDefaults) -> Bool
}
```

`AppDelegate.applicationDidFinishLaunching` should call that API instead of `AppSettings.load()`
when applying `LoginItemService.setEnabled`.
