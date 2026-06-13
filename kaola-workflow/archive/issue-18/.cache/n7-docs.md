evidence-binding: n7-docs b3611f1642b7

non_tdd_reason: docs update
changed_files: docs/decisions/D-18-01.md, docs/api.md, docs/architecture.md, CHANGELOG.md
sources_inspected: CLAUDE.md, FeishuSpeech/Models/AppSettings.swift, FeishuSpeech/Services/KeychainCredentialStore.swift, FeishuSpeech/Views/SettingsView.swift, FeishuSpeech/ViewModels/MainViewModel.swift, FeishuSpeechTests/AppSettingsCredentialStorageTests.swift
validation: git diff --check -- docs/decisions/D-18-01.md docs/api.md docs/architecture.md CHANGELOG.md passed
declared_write_set_check: changed docs are limited to n7 declared write set
residual_doc_risk: CLAUDE.md still contains stale plaintext/UserDefaults note, but CLAUDE.md is outside the frozen n7 and n8 declared write sets
