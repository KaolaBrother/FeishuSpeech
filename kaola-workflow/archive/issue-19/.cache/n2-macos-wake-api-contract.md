evidence-binding: n2-macos-wake-api-contract 38b2e00ef0d9

read_only: yes
sources: local SDK NSWorkspace.h, CGEvent.h, CGEventTypes.h; Apple docs for NSWorkspace.willSleepNotification, didWakeNotification, notificationCenter, CGEvent.tapEnable.
api_contract: use NSWorkspace.shared.notificationCenter for workspace sleep/wake notifications, not NotificationCenter.default.
api_contract: Swift names are NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, NSWorkspace.shared.notificationCenter.
api_contract: willSleepNotification is posted before sleep; didWakeNotification is posted after wake; notification object is shared NSWorkspace.
api_contract: CGEvent.tapIsEnabled(tap:) returns Bool for CFMachPortRef; CGEvent.tapEnable(tap:enable:) re-enables existing tap.
api_contract: CoreGraphics uses tapDisabledByTimeout and tapDisabledByUserInput event types for disabled taps.
testing_caveat: do not depend on real system sleep/wake in unit tests; inject/post synthetic notifications or expose deterministic test hooks for wake recovery and tap health.
