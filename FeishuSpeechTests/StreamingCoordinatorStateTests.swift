import Foundation
import XCTest
import os.log
@testable import FeishuSpeech

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "StreamingCoordinatorStateTests")

@MainActor
final class StreamingCoordinatorStateTests: XCTestCase {
    override func tearDown() async throws {
        HotKeyService.shared.resetToIdle()
        try await super.tearDown()
    }

    func test_streamingReleaseAndDurationCapRace_preserveIdentityAndEnterSealingOnce() {
        let service = HotKeyService.shared
        let identity = StreamingSessionIdentity(generation: 41)
        service.forceState(.streaming(sessionID: identity))

        service.handleFnReleased()
        service.forceSealing()
        service.handleFnReleased()

        XCTAssertEqual(service.state, .sealing(sessionID: identity))
        XCTAssertFalse(service.state.isActive, "sealing must reject a successor hold")
        XCTAssertTrue(service.state.shouldShowOverlay, "the finalizing status remains visible while sealing")
    }

    func test_newFnPressDuringSealing_isIgnoredAndCannotReplaceSessionIdentity() {
        let service = HotKeyService.shared
        let identity = StreamingSessionIdentity(generation: 42)
        service.forceState(.sealing(sessionID: identity))

        service.handleFnPressedForTesting(flags: [])

        XCTAssertEqual(service.state, .sealing(sessionID: identity))
    }

    func test_resetInvalidatesActiveIdentityBeforeReturningIdle() {
        let service = HotKeyService.shared
        let identity = StreamingSessionIdentity(generation: 43)
        service.forceState(.streaming(sessionID: identity))

        service.resetToIdle()

        XCTAssertEqual(service.state, .idle)
        XCTAssertFalse(service.acceptsCallbacksForTesting(identity))
    }

    func test_recordingPresentationUsesStreamingAndSealingWithoutTranscriptSurface() {
        XCTAssertFalse(RecordingState.streaming.text.isEmpty)
        XCTAssertFalse(RecordingState.finalOnly.text.isEmpty)
        XCTAssertFalse(RecordingState.sealing.text.isEmpty)
        XCTAssertNotEqual(RecordingState.streaming, RecordingState.sealing)
        XCTAssertNotEqual(RecordingState.streaming, RecordingState.finalOnly)
        XCTAssertEqual(
            Set([
                RecordingState.streaming.text,
                RecordingState.finalOnly.text,
                RecordingState.sealing.text
            ]).count,
            3,
            "listening, final-only, and sealing must remain distinguishable fixed statuses"
        )
    }
}
