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

    func test_retryPolicyUsesCappedExponentialBackoffWithDeterministicJitter() {
        let policy = StreamingRetryPolicy(jitterFactor: { 1.0 })

        XCTAssertEqual(policy.delayNanoseconds(forRetryOrdinal: 1), 250_000_000)
        XCTAssertEqual(policy.delayNanoseconds(forRetryOrdinal: 2), 500_000_000)
        XCTAssertEqual(policy.delayNanoseconds(forRetryOrdinal: 3), 1_000_000_000)
        XCTAssertEqual(policy.delayNanoseconds(forRetryOrdinal: 4), 2_000_000_000)
        XCTAssertEqual(policy.delayNanoseconds(forRetryOrdinal: 5), 4_000_000_000)
        XCTAssertEqual(policy.delayNanoseconds(forRetryOrdinal: 40), 4_000_000_000)
    }

    func test_retryPolicyClampsJitterAndFinalDelayBounds() {
        let low = StreamingRetryPolicy(jitterFactor: { 0.01 })
        let high = StreamingRetryPolicy(jitterFactor: { 99.0 })

        XCTAssertEqual(low.delayNanoseconds(forRetryOrdinal: 1), 200_000_000)
        XCTAssertEqual(high.delayNanoseconds(forRetryOrdinal: 1), 300_000_000)
        XCTAssertEqual(high.delayNanoseconds(forRetryOrdinal: 40), 4_000_000_000)
    }
}
