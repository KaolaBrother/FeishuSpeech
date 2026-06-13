evidence-binding: n1-current-secret-storage-survey efcb264fc162
Current credential storage survey completed.
Findings:
- AppSettings.swift currently defines Codable appId/appSecret with autoInsert/playSound/launchAtLogin and stores the full JSON payload as UserDefaults data under `FeishuSpeechSettings`; because appId/appSecret are Codable fields, credentials are plaintext in that payload.
- SettingsView currently has independent `@AppStorage("appId")` and `@AppStorage("appSecret")`; onAppear copies viewModel settings into those bindings, and edits persist immediately to standalone UserDefaults keys before onDisappear save.
- MainViewModel initializes settings via AppSettings.load(), gates recording on settings.isConfigured, passes settings.appId/appSecret to FeishuAPIService.recognizeSpeech, and saveSettings preserves LoginItemService behavior by comparing old launchAtLogin.
- FeishuAPIService consumes credentials as recognizeSpeech parameters and auth JSON body; no direct credential-value logging found. Transcript text logging exists but is outside this credential issue.
Plaintext defaults before fix:
- Bundle id `Siji.FeishuSpeech`; sandbox disabled; expected defaults file `~/Library/Preferences/Siji.FeishuSpeech.plist`.
- `FeishuSpeechSettings` Data JSON contains appId/appSecret.
- Standalone `appId` and `appSecret` UserDefaults strings are written by SettingsView @AppStorage.
Migration/UI constraints:
- n3 must migrate valid legacy FeishuSpeechSettings JSON credentials into Keychain, rewrite payload without credentials, remove standalone appId/appSecret keys, preserve launchAtLogin/autoInsert/playSound, ensure save stores only non-sensitive preferences, and clearing credentials deletes/clears Keychain items.
- n4 must remove credential @AppStorage bindings, use non-persistent local state for credential text fields initialized from viewModel.settings, and route persistence only through AppSettings.save() while preserving non-sensitive settings behavior and LoginItemService sync.
Xcode/test membership:
- Project uses PBXFileSystemSynchronizedRootGroup for FeishuSpeech and FeishuSpeechTests; new files `FeishuSpeech/Services/KeychainCredentialStore.swift` and `FeishuSpeechTests/AppSettingsCredentialStorageTests.swift` should not require pbxproj edits unless adding exceptions.
