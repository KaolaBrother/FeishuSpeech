import Foundation
import ApplicationServices
import XCTest
import os.log
@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "FinalTextOutputSecurityTests"
)

@MainActor
final class FinalTextOutputSecurityTests: XCTestCase {
    func test_safePlainTextTargetsCapturedPIDAndChecksSameDestinationBeforeAndAfterPosting() throws {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let eventPoster = FakeFinalTextKeyEventPoster()
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: eventPoster
        )
        let destination = makeDestination(processIdentifier: 42)
        var validationResults = [true, false]
        var validationCallCount = 0

        let result = output.insertOnce(
            "safe plain text",
            destination: destination,
            validateDestination: {
                validationCallCount += 1
                return validationResults.removeFirst()
            }
        )

        XCTAssertEqual(result, .destinationInvalid)
        XCTAssertEqual(validationCallCount, 2)
        XCTAssertEqual(pasteboard.writtenTexts, ["safe plain text"])
        XCTAssertEqual(
            eventPoster.destinationProcessIdentifiers,
            [42],
            "Cmd+V must be posted to the PID captured before recognition, never to a global event tap"
        )
    }

    func test_failedPreflightValidationDoesNotTouchPasteboardOrPostSyntheticInput() throws {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let eventPoster = FakeFinalTextKeyEventPoster()
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: eventPoster
        )

        let result = output.insertOnce(
            "safe plain text",
            destination: makeDestination(processIdentifier: 77),
            validateDestination: { false }
        )

        XCTAssertEqual(result, .destinationInvalid)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [])
    }

    func test_safePlainTextRetainsAutomaticFallbackWhenDeliveryIsStable() throws {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let eventPoster = FakeFinalTextKeyEventPoster()
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: eventPoster
        )
        var validationCallCount = 0

        let result = output.insertOnce(
            "safe plain text",
            destination: makeDestination(processIdentifier: 88),
            validateDestination: {
                validationCallCount += 1
                return true
            }
        )

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(validationCallCount, 2)
        XCTAssertEqual(pasteboard.writtenTexts, ["safe plain text"])
        XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [88])
    }

    func test_keyEventPostingFailureIsReportedForManualRecovery() throws {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let eventPoster = FakeFinalTextKeyEventPoster()
        eventPoster.shouldSucceed = false
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: eventPoster
        )

        let result = output.insertOnce(
            "safe plain text",
            destination: makeDestination(processIdentifier: 99),
            validateDestination: { true }
        )

        XCTAssertEqual(result, .deliveryFailed)
        XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [99])
    }

    func test_currentFocusStableSafePIDPostsUnicodeOnceWithoutTouchingPasteboard() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let boundEventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster()
        let secureInput = FakeSecureInputStateProvider(states: [false, false])
        let frontmostProcess = FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: boundEventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )

        let result = output.insertAtCurrentFocusOnce("直接输入中文")

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(boundEventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, ["直接输入中文"])
        XCTAssertEqual(secureInput.queryCount, 2)
        XCTAssertEqual(frontmostProcess.queryCount, 2)
    }

    func test_currentFocusLiveSecureInputTransitionRejectsBeforeUnicodePost() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let boundEventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster()
        let secureInput = FakeSecureInputStateProvider(states: [false, true])
        let frontmostProcess = FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: boundEventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )

        let result = output.insertAtCurrentFocusOnce("PRIVATE_SECURE_TEXT")

        XCTAssertEqual(result, .securityRejected)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(boundEventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, [])
        XCTAssertEqual(secureInput.queryCount, 2)
    }

    func test_currentFocusFrontmostPIDChangeFailsClosedBeforeUnicodePost() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let boundEventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster()
        let secureInput = FakeSecureInputStateProvider(states: [false, false])
        let frontmostProcess = FakeFrontmostProcessProvider(processIdentifiers: [42, 99])
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: boundEventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )

        let result = output.insertAtCurrentFocusOnce("PRIVATE_STALE_TEXT")

        XCTAssertEqual(result, .destinationInvalid)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(boundEventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, [])
        XCTAssertEqual(frontmostProcess.queryCount, 2)
    }

    func test_currentFocusPosterSecurityRejectionIsPreservedWithoutAmbientResample() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let boundEventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster(
            result: .securityRejected
        )
        let secureInput = FakeSecureInputStateProvider(states: [false, false])
        let frontmostProcess = FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: boundEventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )

        let result = output.insertAtCurrentFocusOnce("PRIVATE_POSTER_SECURE_TEXT")

        XCTAssertEqual(result, .securityRejected)
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, ["PRIVATE_POSTER_SECURE_TEXT"])
        XCTAssertEqual(
            secureInput.queryCount,
            2,
            "the typed poster result must be preserved without an ambiguous third security sample"
        )
        XCTAssertEqual(frontmostProcess.queryCount, 2)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(boundEventPoster.destinationProcessIdentifiers, [])
    }

    func test_currentFocusPosterOrdinaryFailureMapsToDeliveryFailedWithoutResample() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let boundEventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster(
            result: .deliveryFailed
        )
        let secureInput = FakeSecureInputStateProvider(states: [false, false])
        let frontmostProcess = FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: boundEventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )

        let result = output.insertAtCurrentFocusOnce("PRIVATE_POSTER_FAILURE_TEXT")

        XCTAssertEqual(result, .deliveryFailed)
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, ["PRIVATE_POSTER_FAILURE_TEXT"])
        XCTAssertEqual(secureInput.queryCount, 2)
        XCTAssertEqual(frontmostProcess.queryCount, 2)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(boundEventPoster.destinationProcessIdentifiers, [])
    }

    private func makeDestination(processIdentifier: pid_t) -> CursorDestinationToken {
        CursorDestinationToken(
            generation: 7,
            processIdentifier: processIdentifier,
            element: AXUIElementCreateApplication(processIdentifier),
            originalSelection: CursorTextRange(location: 2, length: 0)
        )
    }
}

@MainActor
private final class FakeFinalTextPasteboardWriter: FinalTextPasteboardWriting {
    private(set) var writtenTexts: [String] = []

    func replaceContents(with text: String) -> Bool {
        writtenTexts.append(text)
        return true
    }
}

@MainActor
private final class FakeFinalTextKeyEventPoster: FinalTextKeyEventPosting {
    var shouldSucceed = true
    private(set) var destinationProcessIdentifiers: [pid_t] = []

    func postCommandV(to processIdentifier: pid_t) -> Bool {
        destinationProcessIdentifiers.append(processIdentifier)
        return shouldSucceed
    }
}

@MainActor
private final class FakeCurrentFocusUnicodeEventPoster: FinalTextCurrentFocusEventPosting {
    private let result: FinalTextCurrentFocusPostResult
    private(set) var requestedTexts: [String] = []

    init(result: FinalTextCurrentFocusPostResult = .posted) {
        self.result = result
    }

    func postUnicodeText(_ text: String) -> FinalTextCurrentFocusPostResult {
        requestedTexts.append(text)
        return result
    }
}

@MainActor
private final class FakeSecureInputStateProvider: SecureInputStateProviding {
    private var states: [Bool]
    private(set) var queryCount = 0

    init(states: [Bool]) {
        self.states = states
    }

    func isSecureInputEnabled() -> Bool {
        queryCount += 1
        guard !states.isEmpty else { return true }
        return states.removeFirst()
    }
}

@MainActor
private final class FakeFrontmostProcessProvider: FrontmostProcessProviding {
    private var processIdentifiers: [pid_t?]
    private(set) var queryCount = 0

    init(processIdentifiers: [pid_t?]) {
        self.processIdentifiers = processIdentifiers
    }

    func frontmostProcessIdentifier() -> pid_t? {
        queryCount += 1
        guard !processIdentifiers.isEmpty else { return nil }
        return processIdentifiers.removeFirst()
    }
}
