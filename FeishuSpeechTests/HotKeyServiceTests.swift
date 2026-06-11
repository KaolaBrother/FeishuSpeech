import XCTest
@testable import FeishuSpeech

@MainActor
final class HotKeyServiceTests: XCTestCase {
    
    private var sut: HotKeyService!
    
    override func setUp() async throws {
        try await super.setUp()
        sut = HotKeyService.shared
    }
    
    override func tearDown() async throws {
        sut.resetToIdle()
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
