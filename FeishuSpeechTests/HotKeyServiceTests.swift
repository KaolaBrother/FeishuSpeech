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
    
    func test_armed_isActive() {
        let state: HotKeyState = .armed
        XCTAssertTrue(state.isActive)
    }
    
    func test_armed_shouldShowOverlay() {
        let state: HotKeyState = .armed
        XCTAssertTrue(state.shouldShowOverlay)
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
