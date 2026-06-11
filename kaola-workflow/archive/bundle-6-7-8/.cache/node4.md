RED: test_stateCancellable_isNil_afterStopHotKeyMonitoring -- compile errors: stateCancellable property did not exist; start/stopHotKeyMonitoring were private
GREEN: test_stateCancellable_isNil_afterStopHotKeyMonitoring passes; test_stateCancellable_replacedNotAccumulated_onRestart passes; 4/4 MainViewModelTests assertions green; all prior tests still green

Changes:
- MainViewModel.swift: added var stateCancellable: AnyCancellable?; startHotKeyMonitoring() now assigns stateCancellable = hotKeyService.$state.sink(...) instead of .store(in: &cancellables); stopHotKeyMonitoring() sets stateCancellable = nil before stopMonitoring()
- MainViewModelTests.swift (new): test_stateCancellable_isNil_afterStopHotKeyMonitoring and test_stateCancellable_replacedNotAccumulated_onRestart

Build clean. All tests green.
