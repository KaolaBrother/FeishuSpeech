RED: test_fnReleasedDuringTranscribing_stateRemainsTranscribing — compile error before impl (forceState/handleFnReleased not public)
GREEN: test_fnReleasedDuringTranscribing_stateRemainsTranscribing passes; state remains .transcribing after handleFnReleased() call; 10/10 HotKeyServiceTests assertions green

Changes:
- HotKeyService.swift: handleFnReleased() made internal; default:state=.idle replaced with explicit .transcribing/.error/.cancelled/.idle no-op; added internal forceState() test helper
- MainViewModel.swift: stale-error gate in transcribeAudio catch -- if hotKeyService.state.isActive { return } before setting status/.error
- HotKeyServiceTests.swift: added test_fnReleasedDuringTranscribing_stateRemainsTranscribing

Build clean. All tests green.
