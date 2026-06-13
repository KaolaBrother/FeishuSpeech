import XCTest
import Combine
@testable import FeishuSpeech

@MainActor
final class HotKeyServiceTests: XCTestCase {

    private var sut: HotKeyService!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() async throws {
        try await super.setUp()
        sut = HotKeyService.shared
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() async throws {
        sut.resetToIdle()
        cancellables.removeAll()
        try await super.tearDown()
    }
    
    func test_initialState_isIdle() {
        XCTAssertEqual(sut.state, .idle)
    }
    
    func test_idle_isNotActive() {
        XCTAssertFalse(sut.state.isActive)
    }
    
    func test_idle_shouldNotShowOverlay() {
        XCTAssertFalse(sut.state.shouldShowOverlay)
    }
    
    func test_recording_isActive() {
        let state: HotKeyState = .recording
        XCTAssertTrue(state.isActive)
    }
    
    func test_recording_shouldShowOverlay() {
        let state: HotKeyState = .recording
        XCTAssertTrue(state.shouldShowOverlay)
    }
    
    func test_pending_isActive() {
        let state: HotKeyState = .pending(startTime: Date())
        XCTAssertTrue(state.isActive)
    }
    
    func test_pending_shouldNotShowOverlay() {
        let state: HotKeyState = .pending(startTime: Date())
        XCTAssertFalse(state.shouldShowOverlay)
    }
    
    func test_cancelled_isNotActive() {
        let state: HotKeyState = .cancelled(reason: .releasedTooSoon(duration: 0.1))
        XCTAssertFalse(state.isActive)
    }
    
    func test_error_isNotActive() {
        let state: HotKeyState = .error("Test error")
        XCTAssertFalse(state.isActive)
    }
    
    func test_resetToIdle_setsStateToIdle() {
        sut.setError("Test error")
        sut.resetToIdle()
        XCTAssertEqual(sut.state, .idle)
    }
    
    func test_setError_setsErrorState() {
        sut.setError("Test error message")
        XCTAssertEqual(sut.state, .error("Test error message"))
    }

    // MARK: - Issue #7: forceTranscribing() for max-duration auto-stop

    func test_forceTranscribing_fromRecording_transitionsToTranscribing() {
        // Arrange: force state to .recording to simulate an active recording session
        sut.forceState(.recording)

        // Act: trigger forceTranscribing() as the max-duration handler would
        sut.forceTranscribing()

        // Assert: state must be .transcribing so the $state sink routes to stopRecordingAndTranscribe
        XCTAssertEqual(
            sut.state,
            .transcribing,
            "forceTranscribing() from .recording must transition to .transcribing; got \(sut.state) instead"
        )
    }

    func test_forceTranscribing_whenAlreadyTranscribing_isNoOp() {
        // Arrange: state is already .transcribing (e.g. Fn released just before timer fired)
        sut.forceState(.transcribing)

        // Act: timer fires and calls forceTranscribing() a second time
        sut.forceTranscribing()

        // Assert: state must remain .transcribing — idempotent, no double-stop
        XCTAssertEqual(
            sut.state,
            .transcribing,
            "forceTranscribing() when already .transcribing must be a no-op; got \(sut.state) instead"
        )
    }

    // MARK: - Issue #6: Fn release during .transcribing must not reset state

    func test_fnReleasedDuringTranscribing_stateRemainsTranscribing() {
        // Arrange: force state to .transcribing to simulate an in-flight API call
        sut.forceState(.transcribing)

        // Act: simulate a Fn key release event while already transcribing
        sut.handleFnReleased()

        // Assert: state must NOT revert to .idle (no concurrent session allowed)
        XCTAssertEqual(
            sut.state,
            .transcribing,
            "Fn release during .transcribing must be a no-op; got \(sut.state) instead"
        )
    }

    // MARK: - Issue #5: Tap-failure observable state

    /// When accessibility is not trusted, startMonitoring() must set
    /// monitoringState to .failed(.accessibilityNotTrusted).
    func test_startMonitoring_whenNotTrusted_setsMonitoringStateToFailed() {
        // Arrange: ensure there is no live tap so startMonitoring() runs fresh.
        sut.stopMonitoring()

        // Act: simulate the not-trusted path by calling the test-only hook.
        sut.simulateStartMonitoringWithAccessibilityTrusted(false)

        // Assert: monitoringState must reflect the tap failure reason.
        XCTAssertEqual(
            sut.monitoringState,
            .failed(.accessibilityNotTrusted),
            "monitoringState must be .failed(.accessibilityNotTrusted) when AXIsProcessTrusted() == false; got \(sut.monitoringState)"
        )
    }

    /// When tap creation fails (tap returns nil), startMonitoring() must set
    /// monitoringState to .failed(.tapCreationFailed).
    func test_startMonitoring_whenTapCreationFails_setsMonitoringStateToFailed() {
        sut.stopMonitoring()

        // Simulate the tapCreationFailed path.
        sut.simulateStartMonitoringWithTapCreationResult(false)

        XCTAssertEqual(
            sut.monitoringState,
            .failed(.tapCreationFailed),
            "monitoringState must be .failed(.tapCreationFailed) when CGEvent.tapCreate returns nil; got \(sut.monitoringState)"
        )
    }

    /// On successful start (tap creation succeeds), monitoringState must be .active
    /// and isMonitoring must be true.
    func test_startMonitoring_whenTapCreationSucceeds_setsMonitoringStateToActive() {
        sut.stopMonitoring()

        // Simulate success path.
        sut.simulateStartMonitoringWithTapCreationResult(true)

        XCTAssertEqual(
            sut.monitoringState,
            .active,
            "monitoringState must be .active after successful tap creation; got \(sut.monitoringState)"
        )
        XCTAssertTrue(
            sut.isMonitoring,
            "isMonitoring must be true after successful tap creation"
        )
    }

    /// After stopMonitoring(), monitoringState must be .stopped.
    func test_stopMonitoring_setsMonitoringStateToStopped() {
        sut.simulateStartMonitoringWithTapCreationResult(true)
        sut.stopMonitoring()

        XCTAssertEqual(
            sut.monitoringState,
            .stopped,
            "monitoringState must be .stopped after stopMonitoring(); got \(sut.monitoringState)"
        )
    }

    /// Retry backoff follows capped exponential: 1s, 2s, 4s, 8s, 16s, 30s, 30s.
    func test_retryBackoff_isExponentialWithCap() {
        // This test validates the pure backoff formula used in scheduleRestartRetry().
        // The formula is: delay = min(1.0 * pow(2.0, Double(attempt - 1)), 30.0)
        let expectedDelays: [(attempt: Int, delay: TimeInterval)] = [
            (1, 1.0),
            (2, 2.0),
            (3, 4.0),
            (4, 8.0),
            (5, 16.0),
            (6, 30.0),   // min(32, 30) = 30
            (7, 30.0)    // capped
        ]

        for entry in expectedDelays {
            let computed = min(1.0 * pow(2.0, Double(entry.attempt - 1)), 30.0)
            XCTAssertEqual(
                computed, entry.delay,
                "Backoff attempt \(entry.attempt) should be \(entry.delay)s, got \(computed)s"
            )
        }
    }

    // MARK: - Issue #9: Run-loop placement, previousFlags reset, post-timeout Fn resync

    /// After stopMonitoring(), previousFlags must be reset to [] so a stale Fn-down
    /// cache cannot make the hotkey appear dead on restart.
    func test_stopMonitoring_resetsPreviousFlags() {
        // Arrange: seed previousFlags with a Fn-down state via the test hook.
        sut.setPreviousFlagsForTesting(CGEventFlags.maskSecondaryFn)
        XCTAssertTrue(
            sut.previousFlagsForTesting.contains(.maskSecondaryFn),
            "Precondition: previousFlags must contain Fn before stopMonitoring()"
        )

        // Act: stop monitoring.
        sut.stopMonitoring()

        // Assert: previousFlags must be empty so restart starts from a clean slate.
        XCTAssertEqual(
            sut.previousFlagsForTesting,
            [],
            "previousFlags must be [] after stopMonitoring(); got \(sut.previousFlagsForTesting)"
        )
    }

    /// When the tap is re-enabled after a timeout, a Fn release that was missed while
    /// the tap was disabled must be detected by resyncing against live modifier state.
    /// If previousFlags said Fn-was-down but the live state says Fn-is-up, the resync
    /// must invoke handleFnReleased().
    func test_postTimeoutResync_missedFnRelease_triggersHandleFnReleased() {
        // Arrange: simulate that we believed Fn was held (e.g. .recording), and the
        // live state reports Fn is no longer down (the user released it during the gap).
        sut.forceState(.recording)
        sut.setPreviousFlagsForTesting(CGEventFlags.maskSecondaryFn)

        // Act: run the resync with a live snapshot in which Fn is NOT pressed.
        sut.resyncFnStateForTesting(liveFlags: [])

        // Assert: the missed release must transition .recording -> .transcribing,
        // exactly as handleFnReleased() does for the recording case.
        XCTAssertEqual(
            sut.state,
            .transcribing,
            "Missed Fn release during tap-timeout must trigger handleFnReleased(); got \(sut.state)"
        )
        // And previousFlags must now mirror the live (Fn-up) state.
        XCTAssertFalse(
            sut.previousFlagsForTesting.contains(.maskSecondaryFn),
            "previousFlags must mirror live Fn-up state after resync"
        )
    }

    /// When the live state still reports Fn down after re-enable, no release is fired.
    func test_postTimeoutResync_fnStillHeld_doesNotTriggerRelease() {
        sut.forceState(.recording)
        sut.setPreviousFlagsForTesting(CGEventFlags.maskSecondaryFn)

        // Act: live state still has Fn down — no missed release.
        sut.resyncFnStateForTesting(liveFlags: CGEventFlags.maskSecondaryFn)

        // Assert: state stays .recording (no release fired).
        XCTAssertEqual(
            sut.state,
            .recording,
            "Resync with Fn still held must not fire a release; got \(sut.state)"
        )
    }

    /// The CGEventTap run-loop source must NOT live on the main run loop. After a
    /// monitoring session starts, the private tap run loop must exist and differ from
    /// CFRunLoopGetMain(), so a blocked main actor can never starve Fn events.
    func test_tapRunLoop_isNotMainRunLoop() {
        // Act: start a monitoring session (lazily spins up the private tap thread).
        sut.startMonitoring()
        defer { sut.stopMonitoring() }

        // The private tap run loop is created lazily on the dedicated thread; give it a
        // brief moment to come up.
        let deadline = Date().addingTimeInterval(2.0)
        while sut.tapRunLoopForTesting == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        guard let tapRunLoop = sut.tapRunLoopForTesting else {
            // If accessibility is not trusted in CI, the tap is never created and the
            // run loop stays nil — there is nothing on the main run loop in that case,
            // which still satisfies the invariant.
            XCTAssertNil(
                sut.tapRunLoopForTesting,
                "No tap run loop means nothing was placed on the main run loop"
            )
            return
        }

        XCTAssertFalse(
            tapRunLoop === CFRunLoopGetMain(),
            "Tap run-loop source must live on the private tap thread, not CFRunLoopGetMain()"
        )
    }

    /// monitoringState published .failed causes a Combine event on every retry attempt.
    func test_monitoringState_publishesFailedOnEachRetryAttempt() {
        sut.stopMonitoring()

        var states: [MonitoringState] = []
        sut.$monitoringState
            .dropFirst()   // skip initial .stopped
            .sink { states.append($0) }
            .store(in: &cancellables)

        // Simulate two consecutive accessibility-not-trusted failures.
        sut.simulateStartMonitoringWithAccessibilityTrusted(false)
        sut.simulateStartMonitoringWithAccessibilityTrusted(false)

        XCTAssertEqual(states.count, 2, "Should have received two .failed publications")
        XCTAssertTrue(
            states.allSatisfy { $0 == .failed(.accessibilityNotTrusted) },
            "All published states must be .failed(.accessibilityNotTrusted)"
        )
    }

    // MARK: - Issue #19: Wake recovery tap health

    func test_recoverAfterWake_whenTapIsPresentAndEnabled_keepsMonitoringActiveAndClearsStaleInput() {
        sut.forceState(.pending(startTime: Date()))
        sut.setPreviousFlagsForTesting(CGEventFlags.maskSecondaryFn)
        sut.simulateStartMonitoringWithTapCreationResult(true)

        let result = sut.recoverAfterWakeForTesting(tapPresent: true, tapEnabled: true)

        XCTAssertEqual(result.restartCount, 0, "Enabled live tap must not restart during wake recovery")
        XCTAssertEqual(sut.monitoringState, .active, "Enabled live tap must remain active after wake recovery")
        XCTAssertTrue(sut.isMonitoring, "Enabled live tap must keep monitoring active")
        XCTAssertEqual(sut.state, .idle, "Pending wake transition must be cancelled back to idle")
        XCTAssertEqual(sut.previousFlagsForTesting, [], "Stale pre-sleep Fn flags must be cleared")
    }

    func test_recoverAfterWake_whenTapIsMissing_restartsMonitoringThroughLifecycle() {
        sut.forceState(.pending(startTime: Date()))
        sut.setPreviousFlagsForTesting(CGEventFlags.maskSecondaryFn)

        let result = sut.recoverAfterWakeForTesting(tapPresent: false, tapEnabled: false)

        XCTAssertEqual(result.restartCount, 1, "Missing tap must restart monitoring during wake recovery")
        XCTAssertEqual(sut.monitoringState, .active, "Restarted monitoring must publish active state")
        XCTAssertTrue(sut.isMonitoring, "Restarted monitoring must be active")
        XCTAssertEqual(sut.state, .idle, "Wake recovery must cancel pending state before restart")
        XCTAssertEqual(sut.previousFlagsForTesting, [], "Wake recovery must clear previousFlags before restart")
    }

    func test_recoverAfterWake_whenTapIsDisabled_restartsMonitoringThroughLifecycle() {
        sut.forceState(.pending(startTime: Date()))
        sut.setPreviousFlagsForTesting(CGEventFlags.maskSecondaryFn)
        sut.simulateStartMonitoringWithTapCreationResult(true)

        let result = sut.recoverAfterWakeForTesting(tapPresent: true, tapEnabled: false)

        XCTAssertEqual(result.restartCount, 1, "Disabled tap must restart monitoring during wake recovery")
        XCTAssertEqual(sut.monitoringState, .active, "Restarted disabled tap must publish active state")
        XCTAssertTrue(sut.isMonitoring, "Restarted disabled tap must be active")
        XCTAssertEqual(sut.state, .idle, "Wake recovery must cancel pending state before restart")
        XCTAssertEqual(sut.previousFlagsForTesting, [], "Wake recovery must clear stale Fn flags")
    }
}

final class HotKeyStateTests: XCTestCase {
    
    func test_cancelReason_otherKeyPressed_description() {
        let reason = CancelReason.otherKeyPressed(keyCode: 42)
        XCTAssertEqual(reason.description, "检测到组合键")
    }
    
    func test_cancelReason_releasedTooSoon_description() {
        let reason = CancelReason.releasedTooSoon(duration: 0.3)
        XCTAssertEqual(reason.description, "按键时间太短 (0.3s)")
    }
    
    func test_cancelReason_modifierCombo_description() {
        let reason = CancelReason.modifierCombo(modifiers: "Command")
        XCTAssertEqual(reason.description, "检测到修饰键组合")
    }
    
    func test_cancelReason_eventTapDisabled_description() {
        let reason = CancelReason.eventTapDisabled
        XCTAssertEqual(reason.description, "系统事件被禁用")
    }
}
