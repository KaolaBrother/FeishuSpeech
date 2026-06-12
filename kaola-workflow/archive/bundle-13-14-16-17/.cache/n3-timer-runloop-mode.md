evidence-binding: n3-timer-runloop-mode 1be7132f5d89
non_tdd_reason: Config/glue — run-loop-mode firing behavior during event-tracking mode is not exercisable by any unit test without a live macOS event-tracking run loop.
build-green: yes
regression-green: yes
Changed startMaxDurationTimer() in MainViewModel.swift: replaced Timer.scheduledTimer (implicitly .default mode) with explicit Timer + RunLoop.main.add(timer, forMode: .common) so the 60s limit fires even while the menu-bar menu is open, matching the AppDelegate permission-poll pattern.
