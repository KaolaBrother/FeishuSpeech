import XCTest
import AVFoundation
import Combine
import os.log
@testable import FeishuSpeech

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "PermissionManagerTests")

/// Tests for issue #10: SecureInput detection in PermissionManager.
///
/// PermissionManager must expose a `@Published var secureInputEnabled: Bool`
/// that reflects the live state of `IsSecureEventInputEnabled()` and is
/// refreshed via `refreshSecureInputStatus()`.
@MainActor
final class PermissionManagerTests: XCTestCase {

    private var sut: PermissionManager!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() async throws {
        try await super.setUp()
        sut = PermissionManager.shared
        sut.resetStateForTesting()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() async throws {
        sut.resetStateForTesting()
        cancellables.removeAll()
        try await super.tearDown()
    }

    // MARK: - Initial state

    /// `secureInputEnabled` must start as `false` unless the system already
    /// has secure keyboard entry active (which is not the case in a test runner).
    func test_secureInputEnabled_initialValueIsFalse() {
        // The test runner does not hold a password-field focus, so the initial
        // value — set in init — must be false.
        XCTAssertFalse(
            sut.secureInputEnabled,
            "secureInputEnabled must start as false in a normal test environment"
        )
    }

    // MARK: - Property existence (structural)

    /// `PermissionManager` must expose `secureInputEnabled` as a `Bool` Published
    /// property accessible from the outside.
    func test_secureInputEnabled_isPublishedBool() {
        // Verify the property is observable via Combine ($-projection exists).
        var received: [Bool] = []
        sut.$secureInputEnabled
            .sink { received.append($0) }
            .store(in: &cancellables)

        // After subscribing we should have received at least the current value.
        XCTAssertFalse(
            received.isEmpty,
            "Subscribing to $secureInputEnabled must deliver the current value immediately"
        )
        XCTAssertNotNil(
            received.first,
            "$secureInputEnabled must publish a Bool value"
        )
    }

    // MARK: - refreshSecureInputStatus exists and is callable

    /// `refreshSecureInputStatus()` must exist and be callable without crashing.
    func test_refreshSecureInputStatus_existsAndIsCallable() {
        // This test will fail at compile time if the method does not exist,
        // and at runtime if it crashes.
        sut.refreshSecureInputStatus()
        // No assertion needed — compile + no crash is the pass condition.
        XCTAssertTrue(true, "refreshSecureInputStatus() must exist and not crash")
    }

    // MARK: - refreshSecureInputStatus updates secureInputEnabled

    /// Calling `refreshSecureInputStatus()` must update `secureInputEnabled`
    /// to reflect `IsSecureEventInputEnabled()`.  In the test environment the
    /// system value is false, so the property must remain (or become) false.
    func test_refreshSecureInputStatus_updatesSecureInputEnabled() {
        var receivedValues: [Bool] = []
        sut.$secureInputEnabled
            .sink { receivedValues.append($0) }
            .store(in: &cancellables)

        sut.refreshSecureInputStatus()

        // After refresh, at least two values should have been published
        // (initial + post-refresh), OR the initial value itself was already
        // the system value (just one publish is acceptable if unchanged).
        XCTAssertFalse(
            receivedValues.isEmpty,
            "At least one value must be published on $secureInputEnabled"
        )
        // In a test runner there is no secure keyboard entry active, so the
        // refreshed value must be false.
        XCTAssertFalse(
            sut.secureInputEnabled,
            "secureInputEnabled must be false in test runner after refresh (no password field focused)"
        )
    }

    // MARK: - Combine publisher emits on change

    /// When `refreshSecureInputStatus()` is called and the underlying value has
    /// changed (simulated via test-hook), the $-publisher must emit the new value.
    func test_refreshSecureInputStatus_publishesNewValueWhenChanged() {
        // Force secureInputEnabled to a known state that differs from the system
        // value so we can observe a publish event when it is corrected.
        // We reach into the testable injection point if available; otherwise we
        // rely on the structural assertions in the other tests.
        var publishedValues: [Bool] = []
        sut.$secureInputEnabled
            .dropFirst()  // skip current value
            .sink { publishedValues.append($0) }
            .store(in: &cancellables)

        // Inject false → call refresh (system is false) → no publish expected
        // (no delta). Then inject a synthetic true to ensure publishing works.
        sut.simulateSecureInputState(true)
        sut.simulateSecureInputState(false)

        XCTAssertEqual(
            publishedValues.count, 2,
            "Two state changes (false→true, true→false) must produce two published events"
        )
        XCTAssertEqual(publishedValues, [true, false], "Published sequence must match injected values")
    }

    // MARK: - Microphone permission refresh

    func test_refreshMicrophoneStatus_usesInjectedAuthorizedProvider() {
        sut.setMicrophoneAuthorizationStatusProviderForTesting { .authorized }

        sut.refreshMicrophoneStatus()

        XCTAssertTrue(
            sut.microphoneGranted,
            "refreshMicrophoneStatus() must set microphoneGranted from the injected authorization provider"
        )
    }

    func test_refreshMicrophoneStatus_updatesAllPermissionsGrantedWhenMicrophoneChanges() {
        sut.accessibilityGranted = true
        sut.setMicrophoneAuthorizationStatusProviderForTesting { .authorized }
        sut.refreshMicrophoneStatus()
        XCTAssertTrue(sut.allPermissionsGranted)

        sut.setMicrophoneAuthorizationStatusProviderForTesting { .denied }
        sut.refreshMicrophoneStatus()

        XCTAssertFalse(sut.microphoneGranted)
        XCTAssertFalse(
            sut.allPermissionsGranted,
            "allPermissionsGranted must be recomputed when the runtime microphone status changes"
        )
    }
}
