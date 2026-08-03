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
