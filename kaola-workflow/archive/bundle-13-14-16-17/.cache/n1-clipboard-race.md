evidence-binding: n1-clipboard-race 2196f8714a4e
non_tdd_reason: Glue / wiring — TextInputSimulator is a static-method enum doing live NSPasteboard mutation and CGEvent keyboard posting via .cghidEventTap with no dependency-injection seam. No meaningful failing unit test for the clipboard race without a live frontmost-app paste loop.
build-green: yes
regression-green: yes
Wrote FeishuSpeech/Services/TextInputSimulator.swift: added PasteboardSnapshot deep-copy, changeCount-based polling before restore, empty-text guard, UNUserNotificationCenter fallback on paste failure.
