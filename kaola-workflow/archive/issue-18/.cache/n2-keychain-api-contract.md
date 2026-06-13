evidence-binding: n2-keychain-api-contract c8c67c89832e
Keychain API contract confirmed from Apple Developer documentation and local Security.framework headers.
Implementation contract for n3:
- Use Security.framework `kSecClassGenericPassword` items keyed by stable service + fixed account names `appId` and `appSecret`.
- Store secret strings only as UTF-8 `kSecValueData`; never place credential values in service/account/label/logs/UserDefaults.
- Read via `SecItemCopyMatching` with class/service/account, `kSecReturnData: true`, `kSecMatchLimitOne`; treat `errSecItemNotFound` as absent and other statuses as failures.
- Save uses update-or-add: empty value deletes; non-empty value encodes to UTF-8 Data, attempts `SecItemUpdate`, adds on `errSecItemNotFound`, and retries update once on `errSecDuplicateItem` from add.
- Delete is idempotent: `errSecSuccess` and `errSecItemNotFound` are both success for clearing credentials.
- Do not set `kSecAttrAccessGroup` or `kSecAttrSynchronizable` for the single-app credential store.
Migration contract:
- `AppSettings.load()` decodes legacy `FeishuSpeechSettings`, migrates non-empty legacy appId/appSecret to Keychain, rewrites UserDefaults without plaintext credentials, and returns non-sensitive preferences plus Keychain-backed credentials.
- `AppSettings.save()` persists only non-sensitive preferences to UserDefaults and writes/deletes credentials in Keychain.
Test isolation:
- Use injectable/test-only service names such as `Siji.FeishuSpeech.tests.<UUID>`.
- Delete both appId/appSecret test items in setup and teardown.
- Use fake values only.
Primary sources checked:
- https://developer.apple.com/documentation/Security/kSecClassGenericPassword
- https://developer.apple.com/documentation/security/searching-for-keychain-items
- https://developer.apple.com/documentation/security/updating-and-deleting-keychain-items
- https://developer.apple.com/documentation/security/secitemcopymatching%28_%3A_%3A%29
- https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps
- https://developer.apple.com/documentation/security/errsecmissingentitlement
