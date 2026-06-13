evidence-binding: n4-settings-ui-credential-wiring e17f1dcefcf1

# n4-settings-ui-credential-wiring Evidence

## Scope

- Updated `FeishuSpeech/Views/SettingsView.swift`.
- Updated `FeishuSpeech/ViewModels/MainViewModel.swift`.

## non_tdd_reason

- This node is UI wiring over the TDD-backed credential storage contract from n3; no new domain branch or storage behavior was introduced.

## Implementation

- Replaced credential and preference `@AppStorage` bindings in `SettingsView` with transient `@State` values initialized from `viewModel.settings`.
- Persisted Settings window changes through `viewModel.updateSettings(...)`, which updates `viewModel.settings` and calls the existing `saveSettings()` path.
- Preserved `saveSettings()` launch-at-login synchronization through `LoginItemService.setEnabled(...)` when `launchAtLogin` changes.
- Verified no remaining credential `@AppStorage("appId")` or `@AppStorage("appSecret")` references.

## regression-green

- `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test`
  - Result: passed.
- `xcodebuild -scheme FeishuSpeech -configuration Debug build`
  - Result: passed.
- `git diff --check -- FeishuSpeech/Views/SettingsView.swift FeishuSpeech/ViewModels/MainViewModel.swift`
  - Result: passed.
- `swiftlint`
  - Result: unavailable in this environment (`command not found`).
