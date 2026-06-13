# Documentation Docking - issue-18

verdict: DOCKED

## Docking Checks

- `CHANGELOG.md`: includes issue #18 under Unreleased / Fixed.
- `docs/decisions/D-18-01.md`: records the Keychain credential-storage decision, migration policy, and failure-preservation behavior.
- `docs/api.md`: documents the credential-storage contract, Keychain service/account names, non-sensitive `FeishuSpeechSettings` payload, and legacy migration behavior.
- `docs/architecture.md`: documents `AppSettings`, `CredentialStoring`, `KeychainCredentialStore`, guarded legacy migration, and transient `SettingsView` credential fields.
- `kaola-workflow/ROADMAP.md`: regenerated/validated against current open GitHub issue state; #18 correctly remains open before sink closure.
- `.env.example`: not present and not relevant to this macOS app credential-storage change.
- `README.md`: no stale UserDefaults credential-storage statement found by `rg`.

## Residual Risk

`CLAUDE.md` still says `appSecret` is stored in plaintext UserDefaults and that Keychain migration is tracked in issue #18. That file is outside the frozen documentation write set for issue #18 and outside the finalization write set. It is a stale project-guide note, not a product/API/user workflow doc, so docking is not blocked for this issue.
