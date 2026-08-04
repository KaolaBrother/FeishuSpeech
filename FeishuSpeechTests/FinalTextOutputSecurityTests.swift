import ApplicationServices
import Carbon
@testable import FeishuSpeech
import Foundation
import os.log
import XCTest

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
        XCTAssertEqual(currentFocusEventPoster.destinationProcessIdentifiers, [42])
        XCTAssertEqual(secureInput.queryCount, 2)
        XCTAssertEqual(frontmostProcess.queryCount, 2)
    }

    func test_systemUnicodePosterConstructsCompletePrivatePairBeforePostingDownThenUpOnce() {
        let trace = FakePosterOperationTrace()
        let backend = FakeSystemUnicodeEventBackend(failure: nil, trace: trace)
        let secureInput = FakeTracingSecureInputStateProvider(isEnabled: false, trace: trace)
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: secureInput
        )
        let text = "Fn held 中文"

        let result = poster.postUnicodeText(text, to: 4242)

        XCTAssertEqual(result, .posted)
        XCTAssertEqual(
            backend.operations,
            [
                "source",
                "construct-down",
                "construct-up",
                "tag-down",
                "tag-up",
                "secure",
                "post-down-4242",
                "post-up-4242"
            ]
        )
        XCTAssertEqual(backend.sourceStateIDs, [.privateState])
        XCTAssertEqual(backend.constructedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(
            backend.constructedEvents.map(\.sourceIdentity),
            [backend.sourceIdentity, backend.sourceIdentity]
        )
        XCTAssertEqual(backend.constructedEvents.map(\.utf16), [Array(text.utf16), Array(text.utf16)])
        XCTAssertEqual(backend.constructedEvents.map(\.flags), [[], []])
        XCTAssertEqual(backend.postedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(backend.postedEvents.map(\.processIdentifier), [4242, 4242])
        XCTAssertEqual(
            backend.taggedUserData,
            Array(repeating: FeishuSpeechSyntheticEventTag.value, count: 2)
        )
        XCTAssertEqual(secureInput.queryCount, 1)
    }

    func test_systemReplacementPosterConstructsAndTagsEveryEventBeforeOrderedPosting() {
        let trace = FakePosterOperationTrace()
        let backend = FakeSystemUnicodeEventBackend(failure: nil, trace: trace)
        let secureInput = FakeTracingSecureInputStateProvider(isEnabled: false, trace: trace)
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: secureInput
        )

        let result = poster.postReplacement(
            deleteCharacterCount: 2,
            insertText: "r",
            to: 4242
        )

        XCTAssertEqual(result, .posted)
        XCTAssertEqual(backend.sourceStateIDs, [.privateState])
        XCTAssertEqual(
            backend.constructedEvents.map(\.phase),
            [.keyDown, .keyUp, .keyDown, .keyUp, .keyDown, .keyUp]
        )
        XCTAssertEqual(
            backend.constructedEvents.map(\.virtualKey),
            [
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                nil,
                nil
            ]
        )
        XCTAssertEqual(
            backend.constructedEvents.map(\.utf16),
            [[], [], [], [], Array("r".utf16), Array("r".utf16)]
        )
        XCTAssertEqual(
            backend.constructedEvents.map(\.sourceIdentity),
            Array(repeating: backend.sourceIdentity, count: 6)
        )
        XCTAssertEqual(backend.constructedEvents.map(\.flags), Array(repeating: [], count: 6))
        XCTAssertEqual(
            backend.taggedUserData,
            Array(repeating: FeishuSpeechSyntheticEventTag.value, count: 6)
        )
        XCTAssertEqual(
            backend.postedEvents.map(\.virtualKey),
            [
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                nil,
                nil
            ]
        )
        XCTAssertEqual(backend.postedEvents.map(\.processIdentifier), Array(repeating: 4242, count: 6))
        let lastConstruction = backend.operations.lastIndex { $0.hasPrefix("construct-") }
        let lastTag = backend.operations.lastIndex { $0.hasPrefix("tag-") }
        let firstPost = backend.operations.firstIndex { $0.hasPrefix("post-") }
        XCTAssertNotNil(lastConstruction)
        XCTAssertNotNil(lastTag)
        XCTAssertNotNil(firstPost)
        if let lastConstruction, let lastTag, let firstPost {
            XCTAssertLessThan(lastConstruction, firstPost)
            XCTAssertLessThan(lastTag, firstPost)
        }
        XCTAssertEqual(secureInput.queryCount, 1)
    }

    func test_productionGuardedReplacementEpochDriftBeforeFirstPairPostsNothing() {
        let gate = CurrentFocusInputInterferenceEpoch()
        let expectedEpoch = gate.value
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )
        gate.observePreDispatch(type: .keyDown, event: makePhysicalKeyEvent())

        let result = poster.postReplacement(
            deleteCharacterCount: 2,
            insertText: "replacement",
            to: 4242,
            postCompleteSyntheticPairIfInterferenceEpochIsUnchanged: { postPair in
                gate.performIfUnchanged(expectedEpoch: expectedEpoch, postPair)
            }
        )

        XCTAssertEqual(result, .deliveryFailed)
        XCTAssertEqual(backend.postedEvents, [])
    }

    func test_productionGuardedReplacementUnchangedEpochPostsEveryCompletePair() {
        let gate = CurrentFocusInputInterferenceEpoch()
        let expectedEpoch = gate.value
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )

        let result = poster.postReplacement(
            deleteCharacterCount: 2,
            insertText: "r",
            to: 4242,
            postCompleteSyntheticPairIfInterferenceEpochIsUnchanged: { postPair in
                gate.performIfUnchanged(expectedEpoch: expectedEpoch, postPair)
            }
        )

        XCTAssertEqual(result, .posted)
        XCTAssertEqual(
            backend.postedEvents.map(\.phase),
            [.keyDown, .keyUp, .keyDown, .keyUp, .keyDown, .keyUp]
        )
        XCTAssertEqual(
            backend.postedEvents.map(\.virtualKey),
            [
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                nil,
                nil
            ]
        )
    }

    func test_productionSharedGateFinishesFirstPairThenBlocksLaterPairsAndInsertion() {
        let gate = CurrentFocusInputInterferenceEpoch()
        let expectedEpoch = gate.value
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )
        let trace = ThreadSafeProductionGateTrace()
        let physicalEvent = makePhysicalKeyEvent()
        let attemptedAdvance = DispatchSemaphore(value: 0)
        let completedAdvance = DispatchSemaphore(value: 0)
        var advanceStarted = false

        backend.onPostedEvent = { event in
            let isDelete = event.virtualKey == CGKeyCode(kVK_Delete)
            trace.append(isDelete ? "delete-\(event.phase)" : "insert-\(event.phase)")
            guard isDelete, event.phase == .keyDown, !advanceStarted else { return }
            advanceStarted = true
            DispatchQueue.global(qos: .userInitiated).async {
                attemptedAdvance.signal()
                gate.observePreDispatch(type: .keyDown, event: physicalEvent)
                trace.append("physical-epoch-advance")
                completedAdvance.signal()
            }
            attemptedAdvance.wait()
        }

        let result = poster.postReplacement(
            deleteCharacterCount: 3,
            insertText: "r",
            to: 4242,
            postCompleteSyntheticPairIfInterferenceEpochIsUnchanged: { postPair in
                let posted = gate.performIfUnchanged(
                    expectedEpoch: expectedEpoch,
                    postPair
                )
                if advanceStarted {
                    completedAdvance.wait()
                    advanceStarted = false
                }
                return posted
            }
        )

        XCTAssertEqual(result, .deliveryFailed)
        XCTAssertEqual(
            trace.values,
            ["delete-keyDown", "delete-keyUp", "physical-epoch-advance"]
        )
        XCTAssertEqual(backend.postedEvents.count, 2)
        XCTAssertEqual(backend.postedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(
            backend.postedEvents.map(\.virtualKey),
            [CGKeyCode(kVK_Delete), CGKeyCode(kVK_Delete)]
        )
    }

    func test_productionGuardedInsertionOnlyRejectsEpochDriftWithoutPosting() {
        let gate = CurrentFocusInputInterferenceEpoch()
        let expectedEpoch = gate.value
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )
        gate.observePreDispatch(type: .leftMouseDown, event: makePhysicalMouseEvent())

        let result = poster.postReplacement(
            deleteCharacterCount: 0,
            insertText: "insertion",
            to: 4242,
            postCompleteSyntheticPairIfInterferenceEpochIsUnchanged: { postPair in
                gate.performIfUnchanged(expectedEpoch: expectedEpoch, postPair)
            }
        )

        XCTAssertEqual(result, .deliveryFailed)
        XCTAssertEqual(backend.postedEvents, [])
    }

    func test_systemReplacementPosterDeleteOnlyPostsExactBackspacePairs() {
        let backend = FakeSystemUnicodeEventBackend(failure: nil, trace: FakePosterOperationTrace())
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )

        let result = poster.postReplacement(
            deleteCharacterCount: 2,
            insertText: "",
            to: 5150
        )

        XCTAssertEqual(result, .posted)
        XCTAssertEqual(
            backend.postedEvents.map(\.phase),
            [.keyDown, .keyUp, .keyDown, .keyUp]
        )
        XCTAssertEqual(
            backend.postedEvents.map(\.virtualKey),
            Array(repeating: CGKeyCode(kVK_Delete), count: 4)
        )
        XCTAssertEqual(backend.postedEvents.map(\.processIdentifier), Array(repeating: 5150, count: 4))
    }

    func test_systemReplacementPosterAnyConstructionFailurePostsNothing() {
        for phase in [FinalTextUnicodeEventPhase.keyDown, .keyUp] {
            let backend = FakeSystemUnicodeEventBackend(
                failure: nil,
                trace: FakePosterOperationTrace(),
                keyboardFailurePhase: phase
            )
            let poster = SystemFinalTextCurrentFocusEventPoster(
                backend: backend,
                secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
            )

            let result = poster.postReplacement(
                deleteCharacterCount: 1,
                insertText: "r",
                to: 5150
            )

            XCTAssertEqual(result, .deliveryFailed, "phase: \(phase)")
            XCTAssertEqual(backend.postedEvents, [], "phase: \(phase)")
        }

        let unicodeFailure = FakeSystemUnicodeEventBackend(
            failure: .keyDown,
            trace: FakePosterOperationTrace()
        )
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: unicodeFailure,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )

        XCTAssertEqual(
            poster.postReplacement(deleteCharacterCount: 1, insertText: "r", to: 5150),
            .deliveryFailed
        )
        XCTAssertEqual(unicodeFailure.postedEvents, [])
    }

    func test_systemUnicodePosterConstructionFailuresPostNothing() {
        for failure in FakeSystemUnicodeEventBackend.Failure.allCases {
            let backend = FakeSystemUnicodeEventBackend(
                failure: failure,
                trace: FakePosterOperationTrace()
            )
            let secureInput = FakeSecureInputStateProvider(states: [false])
            let poster = SystemFinalTextCurrentFocusEventPoster(
                backend: backend,
                secureInputStateProvider: secureInput
            )

            let result = poster.postUnicodeText("all or nothing", to: 5150)

            XCTAssertEqual(result, .deliveryFailed, "failure: \(failure)")
            XCTAssertEqual(backend.postedEvents, [], "failure: \(failure)")
            let expectedOperations: [String]
            switch failure {
            case .source:
                expectedOperations = ["source"]
            case .keyDown:
                expectedOperations = ["source", "construct-down"]
            case .keyUp:
                expectedOperations = ["source", "construct-down", "construct-up"]
            }
            XCTAssertEqual(backend.operations, expectedOperations, "failure: \(failure)")
            XCTAssertFalse(
                backend.operations.contains(where: { $0.hasPrefix("post-") }),
                "failure: \(failure)"
            )
        }
    }

    func test_systemUnicodePosterConstructionHookCanEnableSecureInputBeforeFinalSampleAndZeroPosts() {
        let trace = FakePosterOperationTrace()
        let secureInput = FakeTracingSecureInputStateProvider(isEnabled: false, trace: trace)
        let backend = FakeSystemUnicodeEventBackend(failure: nil, trace: trace)
        backend.onConstructedEvent = { phase in
            if phase == .keyUp {
                secureInput.enable()
            }
        }
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: secureInput
        )

        let result = poster.postUnicodeText("PRIVATE_SECURE_TEXT", to: 4242)

        XCTAssertEqual(result, .securityRejected)
        XCTAssertEqual(secureInput.queryCount, 1)
        XCTAssertEqual(
            backend.operations,
            ["source", "construct-down", "construct-up", "tag-down", "tag-up", "secure"]
        )
        XCTAssertEqual(backend.constructedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(backend.postedEvents, [])
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

    private func makePhysicalKeyEvent() -> CGEvent {
        CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        )!
    }

    private func makePhysicalMouseEvent() -> CGEvent {
        CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: .zero,
            mouseButton: .left
        )!
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
    private(set) var destinationProcessIdentifiers: [pid_t] = []

    init(result: FinalTextCurrentFocusPostResult = .posted) {
        self.result = result
    }

    func postUnicodeText(
        _ text: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult {
        requestedTexts.append(text)
        destinationProcessIdentifiers.append(processIdentifier)
        return result
    }
}

@MainActor
private final class FakeSystemUnicodeEventBackend: FinalTextUnicodeEventBackend {
    enum Failure: String, CaseIterable {
        case source
        case keyDown
        case keyUp
    }

    private let failure: Failure?
    private let keyboardFailurePhase: FinalTextUnicodeEventPhase?
    private let source = FakeUnicodeEventSourceHandle()
    private let trace: FakePosterOperationTrace
    private(set) var sourceStateIDs: [CGEventSourceStateID] = []
    private(set) var constructedEvents: [FakeUnicodeEventHandle] = []
    private(set) var postedEvents: [FakePostedUnicodeEvent] = []
    private(set) var taggedUserData: [Int64] = []
    var onConstructedEvent: ((FinalTextUnicodeEventPhase) -> Void)?
    var onPostedEvent: ((FakePostedUnicodeEvent) -> Void)?

    var sourceIdentity: ObjectIdentifier { ObjectIdentifier(source) }
    var operations: [String] { trace.operations }

    init(
        failure: Failure?,
        trace: FakePosterOperationTrace,
        keyboardFailurePhase: FinalTextUnicodeEventPhase? = nil
    ) {
        self.failure = failure
        self.trace = trace
        self.keyboardFailurePhase = keyboardFailurePhase
    }

    func makeEventSource(
        stateID: CGEventSourceStateID
    ) -> (any FinalTextUnicodeEventSourceHandle)? {
        trace.record("source")
        sourceStateIDs.append(stateID)
        return failure == .source ? nil : source
    }

    func makeUnicodeEvent(
        source: any FinalTextUnicodeEventSourceHandle,
        phase: FinalTextUnicodeEventPhase,
        utf16: [UInt16],
        flags: CGEventFlags
    ) -> (any FinalTextUnicodeEventHandle)? {
        trace.record(phase == .keyDown ? "construct-down" : "construct-up")
        if failure == .keyDown, phase == .keyDown { return nil }
        if failure == .keyUp, phase == .keyUp { return nil }
        let event = FakeUnicodeEventHandle(
            phase: phase,
            sourceIdentity: ObjectIdentifier(source),
            utf16: utf16,
            flags: flags,
            virtualKey: nil
        )
        constructedEvents.append(event)
        onConstructedEvent?(phase)
        return event
    }

    func makeKeyboardEvent(
        source: any FinalTextUnicodeEventSourceHandle,
        phase: FinalTextUnicodeEventPhase,
        virtualKey: CGKeyCode,
        flags: CGEventFlags
    ) -> (any FinalTextUnicodeEventHandle)? {
        trace.record(phase == .keyDown ? "construct-delete-down" : "construct-delete-up")
        if keyboardFailurePhase == phase { return nil }
        let event = FakeUnicodeEventHandle(
            phase: phase,
            sourceIdentity: ObjectIdentifier(source),
            utf16: [],
            flags: flags,
            virtualKey: virtualKey
        )
        constructedEvents.append(event)
        return event
    }

    func setUserData(
        _ userData: Int64,
        for event: any FinalTextUnicodeEventHandle
    ) {
        guard let event = event as? FakeUnicodeEventHandle else {
            XCTFail("poster tagged an event outside the injected backend")
            return
        }
        trace.record(event.phase == .keyDown ? "tag-down" : "tag-up")
        taggedUserData.append(userData)
    }

    func postUnicodeEvent(
        _ event: any FinalTextUnicodeEventHandle,
        to processIdentifier: pid_t
    ) {
        guard let event = event as? FakeUnicodeEventHandle else {
            XCTFail("poster returned an event outside the injected backend")
            return
        }
        let phaseName = event.phase == .keyDown ? "down" : "up"
        let eventName = event.virtualKey == CGKeyCode(kVK_Delete) ? "delete-\(phaseName)" : phaseName
        trace.record("post-\(eventName)-\(processIdentifier)")
        let postedEvent = FakePostedUnicodeEvent(
            phase: event.phase,
            processIdentifier: processIdentifier,
            virtualKey: event.virtualKey,
            utf16: event.utf16
        )
        postedEvents.append(postedEvent)
        onPostedEvent?(postedEvent)
    }
}

@MainActor
private final class FakeUnicodeEventSourceHandle: FinalTextUnicodeEventSourceHandle {}

@MainActor
private final class FakeUnicodeEventHandle: FinalTextUnicodeEventHandle {
    let phase: FinalTextUnicodeEventPhase
    let sourceIdentity: ObjectIdentifier
    let utf16: [UInt16]
    let flags: CGEventFlags
    let virtualKey: CGKeyCode?

    init(
        phase: FinalTextUnicodeEventPhase,
        sourceIdentity: ObjectIdentifier,
        utf16: [UInt16],
        flags: CGEventFlags,
        virtualKey: CGKeyCode?
    ) {
        self.phase = phase
        self.sourceIdentity = sourceIdentity
        self.utf16 = utf16
        self.flags = flags
        self.virtualKey = virtualKey
    }
}

private struct FakePostedUnicodeEvent: Equatable {
    let phase: FinalTextUnicodeEventPhase
    let processIdentifier: pid_t
    let virtualKey: CGKeyCode?
    let utf16: [UInt16]
}

private final class ThreadSafeProductionGateTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

@MainActor
private final class FakePosterOperationTrace {
    private(set) var operations: [String] = []

    func record(_ operation: String) {
        operations.append(operation)
    }
}

@MainActor
private final class FakeTracingSecureInputStateProvider: SecureInputStateProviding {
    private var isEnabled: Bool
    private let trace: FakePosterOperationTrace
    private(set) var queryCount = 0

    init(isEnabled: Bool, trace: FakePosterOperationTrace) {
        self.isEnabled = isEnabled
        self.trace = trace
    }

    func enable() {
        isEnabled = true
    }

    func isSecureInputEnabled() -> Bool {
        queryCount += 1
        trace.record("secure")
        return isEnabled
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
