import XCTest
import os.log
@testable import FeishuSpeech

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "AudioRecorderRecoveryTests")

// MARK: - AudioRecorderRecoveryTests

/// Tests for the stale-session lifecycle bug fix (issue #1).
///
/// Scenario A: `startRecording()` self-heals a stale `isRecording == true` flag.
/// Scenario B: cancel / error paths leave `isRecording == false`.
/// Scenario C: `MainViewModel.resetService()` leaves the recorder quiescent.
final class AudioRecorderRecoveryTests: XCTestCase {

    // MARK: - Scenario A

    /// Scenario A (core): When `isRecording` is `true` but no live `AVCaptureSession` is
    /// running, `startRecording()` MUST call `forceCleanup()` before doing anything else, so
    /// the stale flag is cleared and a fresh session can be attempted.
    ///
    /// Pre-fix behaviour: `guard !isRecording` fires at the top of `startRecording()`,
    /// returns `false` immediately, and the recorder is permanently stuck.
    ///
    /// Post-fix behaviour: `forceCleanup()` runs first, which sets `isRecording = false`,
    /// then the method proceeds.  In a sandbox without a physical microphone the session
    /// setup will still fail — but `isRecording` will be `false`, not stale-`true`.
    func test_scenarioA_staleRecordingFlag_isResetBeforeStartAttempt() {
        let recorder = AudioRecorder()

        // Inject stale state: isRecording = true with no live session underneath.
        recorder.forceSetRecordingForTesting(true)
        XCTAssertTrue(recorder.isRecording, "Pre-condition: isRecording must be true")

        // Act — call startRecording() while the stale flag is set.
        _ = recorder.startRecording()

        // Key invariant: isRecording is never left stuck at true from the stale state.
        // (Either cleanup reset it to false, or a new session was started and then the
        // mic was unavailable so forceCleanup() inside startRecording() reset it again.)
        XCTAssertFalse(
            recorder.isRecording,
            "isRecording must be false after startRecording() on a stale recorder; " +
            "forceCleanup() must run before the isRecording guard"
        )
    }

    /// Scenario A (via TrackedAudioRecorder): `startRecording()` must call `forceCleanup()`
    /// unconditionally, even when `isRecording` is already `false`.
    func test_scenarioA_startRecording_alwaysCallsForceCleanup() {
        let recorder = TrackedAudioRecorder()
        XCTAssertFalse(recorder.isRecording, "Pre-condition: isRecording is false")

        _ = recorder.startRecording()

        XCTAssertTrue(
            recorder.forceCleanupCalled,
            "startRecording() must call forceCleanup() unconditionally"
        )
    }

    // MARK: - Scenario B

    /// Scenario B (forceCleanup): After `forceCleanup()` (the cancel / error recovery path),
    /// `isRecording` must be `false`.
    func test_scenarioB_forceCleanup_setsIsRecordingFalse() {
        let recorder = AudioRecorder()

        recorder.forceSetRecordingForTesting(true)
        XCTAssertTrue(recorder.isRecording, "Pre-condition: isRecording must be true")

        recorder.forceCleanup()

        XCTAssertFalse(recorder.isRecording, "isRecording must be false after forceCleanup()")
    }

    /// Scenario B (stopRecording): `stopRecording()` also resets `isRecording` to `false`.
    func test_scenarioB_stopRecording_setsIsRecordingFalse() {
        let recorder = AudioRecorder()

        recorder.forceSetRecordingForTesting(true)
        _ = recorder.stopRecording()

        XCTAssertFalse(recorder.isRecording, "isRecording must be false after stopRecording()")
    }

    // MARK: - Scenario C

    /// Scenario C: `MainViewModel.resetService()` must call `forceCleanup()` on the recorder,
    /// leaving the recorder quiescent (`isRecording == false`).
    func test_scenarioC_resetService_leavesRecorderQuiescent() async {
        let trackedRecorder = TrackedAudioRecorder()

        // Build a testable view model with the injected tracked recorder.
        let viewModel = await MainActor.run { TestableMainViewModel(recorder: trackedRecorder) }

        // Inject stale state after construction (init already calls forceCleanup once).
        trackedRecorder.forceSetRecordingForTesting(true)
        trackedRecorder.resetForceCleanupTracking()
        XCTAssertTrue(trackedRecorder.isRecording, "Pre-condition: recorder must look stuck")

        await viewModel.resetService()

        XCTAssertFalse(
            trackedRecorder.isRecording,
            "resetService() must leave the recorder quiescent (isRecording == false)"
        )
        XCTAssertTrue(
            trackedRecorder.forceCleanupCalled,
            "resetService() must call forceCleanup() on the recorder"
        )
    }
}

// MARK: - Test helpers

extension AudioRecorder {
    /// Injects a stale `isRecording` value without starting a real session.
    /// Simulates the condition where `isRecording` is `true` but the underlying
    /// `AVCaptureSession` is gone (an error path forgot to reset the flag).
    func forceSetRecordingForTesting(_ value: Bool) {
        isRecording = value
    }
}

/// An `AudioRecorder` subclass that tracks whether `forceCleanup()` has been called.
final class TrackedAudioRecorder: AudioRecorder {
    private(set) var forceCleanupCalled = false

    override func forceCleanup() {
        forceCleanupCalled = true
        super.forceCleanup()
    }

    /// Resets the tracking flag so a test can observe a fresh `forceCleanup()` invocation.
    func resetForceCleanupTracking() {
        forceCleanupCalled = false
    }
}

/// A `MainViewModel` subclass that accepts an injected `AudioRecorder` for unit testing.
@MainActor
final class TestableMainViewModel: MainViewModel {
    init(recorder: AudioRecorder) {
        super.init(audioRecorder: recorder)
    }
}
