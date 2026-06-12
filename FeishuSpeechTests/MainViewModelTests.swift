import XCTest
import Combine
import os.log
@testable import FeishuSpeech

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "MainViewModelTests")

// MARK: - MainViewModelTests

/// Tests for the $state subscription leak fix (issue #8).
///
/// Bug: `startHotKeyMonitoring()` stored the `$state` sink into
/// `Set<AnyCancellable>` which is never cleared.  Repeated start/stop
/// cycles (permission flicker) accumulate subscribers; every live sink
/// fires `handleHotKeyState` on each state change, causing duplicate
/// processing.
///
/// Fix: introduce a dedicated `stateCancellable: AnyCancellable?`
/// property.  `startHotKeyMonitoring()` assigns the fresh sink to it
/// (implicitly cancelling any prior value); `stopHotKeyMonitoring()`
/// nils it out before calling `hotKeyService.stopMonitoring()`.
@MainActor
final class MainViewModelTests: XCTestCase {

    // MARK: - test_stateCancellable_isNil_afterStopHotKeyMonitoring

    /// After `startHotKeyMonitoring()` + `stopHotKeyMonitoring()`, the
    /// dedicated `stateCancellable` property MUST be nil.
    ///
    /// This is the core invariant of the fix: stopping monitoring fully
    /// releases the $state subscriber so no stale handler fires during
    /// a subsequent start/stop cycle.
    func test_stateCancellable_isNil_afterStopHotKeyMonitoring() async {
        // Arrange: a fresh view model — PermissionManager starts with
        // allPermissionsGranted == false, so monitoring is not yet started.
        let sut = MonitoringTestableMainViewModel(recorder: AudioRecorder())

        // Reach into the monitored state: manually call the internal methods
        // rather than relying on the permission observer to avoid
        // AVCaptureSession / CGEventTap side-effects in a test context.
        sut.testStartHotKeyMonitoring()

        // Precondition: the cancellable should be set (non-nil).
        XCTAssertNotNil(
            sut.stateCancellable,
            "stateCancellable must be non-nil after startHotKeyMonitoring()"
        )

        // Act: stop monitoring.
        sut.testStopHotKeyMonitoring()

        // Assert: the cancellable must have been released.
        XCTAssertNil(
            sut.stateCancellable,
            "stateCancellable must be nil after stopHotKeyMonitoring() — " +
            "a non-nil value means the $state subscriber is still alive and " +
            "will fire handleHotKeyState for the next session (subscription leak)"
        )
    }

    // MARK: - test_stateCancellable_replacedNotAccumulated_onRestart

    /// Calling `startHotKeyMonitoring()` twice (simulating permission flicker)
    /// MUST NOT create two live $state subscribers.
    ///
    /// The second `start` assigns a new `AnyCancellable` to `stateCancellable`,
    /// which implicitly cancels the first one.  We verify this by checking that
    /// `stateCancellable` is still exactly one object — the property holds a
    /// single optional, not a growing set.
    func test_stateCancellable_replacedNotAccumulated_onRestart() async {
        let sut = MonitoringTestableMainViewModel(recorder: AudioRecorder())

        // Start → stop → start  (simulates permission flicker sequence)
        sut.testStartHotKeyMonitoring()
        let firstCancellable = sut.stateCancellable

        sut.testStopHotKeyMonitoring()
        sut.testStartHotKeyMonitoring()
        let secondCancellable = sut.stateCancellable

        // The two references must differ (the second is a fresh subscription)
        // but there is only ever one live subscriber.  Both conditions hold if
        // `stateCancellable` is a plain `AnyCancellable?` that gets reassigned.
        XCTAssertNotNil(secondCancellable, "stateCancellable must be non-nil after re-starting")
        // Identity check: a new AnyCancellable is a different object
        if let first = firstCancellable, let second = secondCancellable {
            // AnyCancellable is a reference type; distinct allocations indicate
            // a fresh subscription was created (the old one was replaced).
            XCTAssertFalse(
                first === second,
                "A fresh subscription object must replace the old one on restart; " +
                "same object indicates the old cancellable was reused, which means " +
                "stop/start produced no new subscription"
            )
        }

        // Cleanup
        sut.testStopHotKeyMonitoring()
    }
}

// MARK: - MonitoringTestableMainViewModel (test-visible subclass)

/// Subclass of `MainViewModel` that exposes `startHotKeyMonitoring()` and
/// `stopHotKeyMonitoring()` for unit-testing the `stateCancellable` invariant
/// without triggering real system permissions or CGEventTap.
///
/// Named distinctly from `TestableMainViewModel` (AudioRecorderRecoveryTests)
/// to avoid a duplicate-type compilation error in the test target.
@MainActor
final class MonitoringTestableMainViewModel: MainViewModel {
    init(recorder: AudioRecorder) {
        super.init(audioRecorder: recorder)
    }

    func testStartHotKeyMonitoring() {
        startHotKeyMonitoring()
    }

    func testStopHotKeyMonitoring() {
        stopHotKeyMonitoring()
    }
}

// MARK: - EmptyResultFeedbackTests

/// Tests for issue #14: empty recognition result must produce observable
/// feedback (overlayMessage) instead of a silent no-op.
@MainActor
final class EmptyResultFeedbackTests: XCTestCase {

    // MARK: - test_emptyRecognitionResult_setsOverlayMessage

    /// When `handleRecognitionResult` is called with an empty string, the view
    /// model MUST set `overlayMessage` to a non-nil, non-empty string so that
    /// the UI can display transient feedback to the user.
    ///
    /// Pre-fix behaviour: the `if settings.autoInsert && !text.isEmpty` branch
    /// is silently skipped; `overlayMessage` stays nil and the user sees nothing.
    ///
    /// Post-fix behaviour: `overlayMessage` is set to "未识别到内容" (or
    /// equivalent non-empty string) before returning to idle.
    func test_emptyRecognitionResult_setsOverlayMessage() {
        let sut = MainViewModel(audioRecorder: AudioRecorder())

        // Pre-condition: overlayMessage starts nil
        XCTAssertNil(
            sut.overlayMessage,
            "overlayMessage must be nil before any recognition result"
        )

        // Act: simulate API returning an empty recognition result
        sut.handleRecognitionResult("")

        // Assert: feedback must be visible
        XCTAssertNotNil(
            sut.overlayMessage,
            "overlayMessage must be non-nil when recognition returns empty text"
        )
        XCTAssertFalse(
            sut.overlayMessage?.isEmpty ?? true,
            "overlayMessage must be non-empty when recognition returns empty text"
        )
    }

    // MARK: - test_whitespaceOnlyRecognitionResult_setsOverlayMessage

    /// Whitespace-only results (e.g. "  \n  ") must also trigger feedback,
    /// because after trimming they are effectively empty.
    func test_whitespaceOnlyRecognitionResult_setsOverlayMessage() {
        let sut = MainViewModel(audioRecorder: AudioRecorder())

        sut.handleRecognitionResult("   \n   ")

        XCTAssertNotNil(
            sut.overlayMessage,
            "overlayMessage must be non-nil for whitespace-only recognition result"
        )
    }

    // MARK: - test_nonEmptyRecognitionResult_doesNotSetOverlayMessage

    /// A non-empty result is the happy path — `overlayMessage` MUST remain nil
    /// so no spurious feedback panel appears over normally recognised text.
    func test_nonEmptyRecognitionResult_doesNotSetOverlayMessage() {
        let sut = MainViewModel(audioRecorder: AudioRecorder())

        sut.handleRecognitionResult("你好世界")

        XCTAssertNil(
            sut.overlayMessage,
            "overlayMessage must remain nil for a non-empty recognition result"
        )
    }
}
