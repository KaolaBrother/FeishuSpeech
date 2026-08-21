# Issue #35 data-protection keychain / launch-at-login — implementer evidence

Date: 2026-08-21

## task

Make the existing RED keychain / launch-at-login tests in
`FeishuSpeechTests/AppSettingsCredentialStorageTests` green without editing them.

Production-only changes (allowed files):

- `FeishuSpeech/Services/KeychainCredentialStore.swift`
- `FeishuSpeech/Models/AppSettings.swift`
- `FeishuSpeech/App/AppDelegate.swift`

Did not edit `FeishuSpeechTests/`, docs, or any Transport / BoundTLS /
DirectFeishuKeepAliveSession files.

## verification tier

`build-green` (intended `tests-green` is blocked by the issue #34
`BoundPhysicalDNS` compile seam on the whole test target).

## files changed

- `FeishuSpeech/Services/KeychainCredentialStore.swift`
  - `baseQuery` sets `kSecUseDataProtectionKeychain = true` for modern items.
  - `add` sets `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
  - `read` copies with the DP flag first; on `errSecItemNotFound` copies the
    legacy login item (no DP flag), `SecItemAdd`s it into DP, then
    `SecItemDelete`s the login item. Default service name remains
    `Siji.FeishuSpeech.credentials`.
  - Still throws `StoreError.unexpectedStatus` for
    `errSecMissingEntitlement` / `errSecInteractionNotAllowed`.
- `FeishuSpeech/Models/AppSettings.swift`
  - Added `static func launchAtLoginPreference(from defaults: UserDefaults) -> Bool`.
  - Decodes the `FeishuSpeechSettings` / `StoredSettings` payload from the
    given defaults. Missing payload → `false`. Does not touch
    `AppSettings.credentialStore`.
- `FeishuSpeech/App/AppDelegate.swift`
  - `applicationDidFinishLaunching` no longer calls `AppSettings.load()`.
  - Applies launch-at-login with
    `LoginItemService.setEnabled(AppSettings.launchAtLoginPreference(from: .standard))`.

## verification commands

### Official assigned command (whole test target)

```bash
cd /Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/bundle-34-35
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/feishuspeech-bundle-34-35-impl-35 \
  -only-testing:FeishuSpeechTests/AppSettingsCredentialStorageTests \
  test
```

- before (baseline derived data `/tmp/feishuspeech-bundle-34-35-impl-35-baseline`):
  **TEST FAILED**. Errors:
  - `BoundTLSSocketTests.swift:54/66: cannot find 'BoundPhysicalDNS' in scope`
    (issue #34 seam; production `FeishuSpeech/` still has no `BoundPhysicalDNS`).
  - `AppSettings.launchAtLoginPreference(from:)` was also absent on this
    baseline (issue #35 compile oracle from `test-red-35.md`). The truncated
    xcodebuild log surfaced the #34 error first and cancelled the test target
    compile.
- after: **TEST FAILED**, exit from xcodebuild **TEST FAILED**. The only
  remaining compile errors are:

```
FeishuSpeechTests/BoundTLSSocketTests.swift:54:25: error: cannot find 'BoundPhysicalDNS' in scope
FeishuSpeechTests/BoundTLSSocketTests.swift:66:25: error: cannot find 'BoundPhysicalDNS' in scope
```

  No `AppSettings.launchAtLoginPreference` compile error remains. Production
  objects `AppDelegate.o`, `AppSettings.o`, `KeychainCredentialStore.o` built.
  The #35 test file started compiling; the target did not link because #34
  tests are in the same test target.

### Production build (this issue's files)

```bash
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/feishuspeech-bundle-34-35-impl-35-appbuild \
  build
```

**BUILD SUCCEEDED**.

### Lint

```bash
swiftlint lint FeishuSpeech/Services/KeychainCredentialStore.swift \
  FeishuSpeech/Models/AppSettings.swift \
  FeishuSpeech/App/AppDelegate.swift
```

0 violations, 0 serious.

### Lifecycle-free extra run of the #35 class (not the assigned command)

Hosted `xcodebuild test` stalls at `RegisterWithLaunchServices` / testmanagerd
on this machine (also seen in prior issue-26 notes). After excluding
`BoundTLSSocketTests.swift` so the test bundle could link, `xcrun xctest`
against the built `FeishuSpeechTests.xctest` (with the host debug dylib
symlinked) executed `AppSettingsCredentialStorageTests`:

```
Executed 16 tests, with 2 tests skipped and 4 failures (2 unexpected)
```

Passed (source pins, launch-at-login reader, D-18-01 credential/UserDefaults
tests):

- `test_keychainCredentialStoreSource_usesDataProtectionKeychainAndAfterFirstUnlockAccessibility`
- `test_appDelegateDidFinishLaunching_doesNotLoadAppSettingsCredentials`
- `test_appSettingsSource_declaresLaunchAtLoginPreferenceReader`
- `test_launchAtLoginPreference_readsEncodedPayloadWithoutTouchingCredentialStore`
- all existing D-18-01 `load` / `save` / Codable tests in this class

Skipped (`errSecMissingEntitlement` / `-34018`, as the tests already do on a
bare `try`):

- `test_keychainCredentialStore_saveReadAndDeleteUseIsolatedService`
- `test_keychainCredentialStore_saveReadPersistsInDataProtectionKeychain`

Failed (not a production-code miss on this host):

- `test_keychainCredentialStore_migratesLegacyLoginKeychainItemsIntoDataProtectionKeychain`
  plants login-keychain items (no DP flag, succeeds), then
  `XCTAssertEqual(try store.read, …)` records `unexpectedStatus(-34018)`
  instead of propagating into the test's `catch`/`XCTSkip`. That skip path is
  test-side; production still throws `StoreError.unexpectedStatus` as specified.
  Debug test host is adhoc (`Sign to Run Locally`, no
  `com.apple.application-identifier`), so
  `kSecUseDataProtectionKeychain` returns `-34018`.

## leftover red that is not this issue

1. **Issue #34 seam (blocks the assigned `xcodebuild test` command):**
   `cannot find 'BoundPhysicalDNS' in scope` in
   `FeishuSpeechTests/BoundTLSSocketTests.swift`. Re-run the assigned command
   after #34 lands.
2. **Adhoc test-host DP entitlement:** Debug/`Sign to Run Locally` has no
   application-identifier, so live DP keychain ops return `-34018` and the
   two save/read tests skip. The later mission “Release signed with Apple
   Development, not adhoc” is what injects that entitlement. Production now
   uses DP as specified; adhoc credential save/read will throw
   `unexpectedStatus(-34018)` until that signing lands. Not changed here
   (entitlements / CODE_SIGN_IDENTITY are out of scope).
3. **Migration-test skip path:**
   `XCTAssertEqual(try store.read)` swallows `-34018` so the authored skip
   does not fire. Tests are read-only for this role; do not edit.

## before

- Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/bundle-34-35`
- `KeychainCredentialStore.baseQuery` had no `kSecUseDataProtectionKeychain`
  and no after-first-unlock `kSecAttrAccessible`.
- `AppDelegate.applicationDidFinishLaunching` called `AppSettings.load()`
  then `LoginItemService.setEnabled(settings.launchAtLogin)`.
- `AppSettings` had no `launchAtLoginPreference(from:)`.
- Official test command: **TEST FAILED** (`BoundPhysicalDNS` + missing #35 API).

## after

- DP queries + AfterFirstUnlockThisDeviceOnly on add; login-keychain read
  migrates into DP (two accounts stay two items).
- Launch-at-login is read from UserDefaults only; `AppSettings.load()` is
  gone from `applicationDidFinishLaunching`.
- Production Debug **BUILD SUCCEEDED**; swiftlint clean on the three files.
- Official `xcodebuild test` still **TEST FAILED** only on `BoundPhysicalDNS`
  (#34). Re-run after that seam lands.
