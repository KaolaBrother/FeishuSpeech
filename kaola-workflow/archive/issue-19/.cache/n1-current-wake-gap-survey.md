evidence-binding: n1-current-wake-gap-survey 38b2e00ef0d9

read_only: yes
findings: AppDelegate has launch/terminate cleanup but no NSWorkspace sleep/wake observers; observer teardown does not exist.
findings: HotKeyService owns private eventTap/runLoopSource/previousFlags/tap thread and has timeout/user-input recovery, but no CGEvent.tapIsEnabled health check or wake recovery method.
findings: startMonitoring() no-ops when eventTap != nil, so a stored disabled/dead tap needs an explicit health/recreate path.
findings: MainViewModel resetService() cleans audio/API/hotkey state; cleanup() stops monitoring/timer; transcription Task is currently untracked.
findings: FeishuAPIService resetState() clears token/expiry/lastNetworkError but does not refresh NWPathMonitor or isNetworkAvailable.
existing_tests: HotKeyServiceTests cover previousFlags reset and timeout resync; MainViewModelTests cover cleanup subscription release; FeishuAPIServiceTests cover retry/cancellation but not resetState cache assertions.
success_criteria: register sleep/wake observers on launch and remove on termination; abort active recording/transcription on sleep/wake without stale audio submission; wake verifies/recreates tap, cancels pending transitions, resets previousFlags; API token/network stale state clears without logging secrets.
smallest_surface: n3 HotKeyService.swift and HotKeyServiceTests.swift; n4 AppDelegate.swift, MainViewModel.swift, FeishuAPIService.swift, MainViewModelTests.swift, FeishuAPIServiceTests.swift.
