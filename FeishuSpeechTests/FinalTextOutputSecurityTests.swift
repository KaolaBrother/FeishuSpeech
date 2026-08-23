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
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster()
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: eventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [42])
        )
        let destination = makeDestination(processIdentifier: 42)
        var validationResults = [true, false]
        var validationCallCount = 0

        let result = output.insertOnce(
            "safe plain text",
            destination: destination,
            validateBeforeMutation: {
                validationCallCount += 1
                return validationResults.removeFirst()
            },
            validateAfterPosting: {
                validationCallCount += 1
                return validationResults.removeFirst()
            },
            postPairIfPreflightRemainsValid: { postPair in
                postPair()
                return true
            }
        )

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertEqual(validationCallCount, 2)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, ["safe plain text"])
        XCTAssertEqual(currentFocusEventPoster.destinationProcessIdentifiers, [42])
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
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster()
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: eventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [88])
        )
        var validationCallCount = 0

        let result = output.insertOnce(
            "safe plain text",
            destination: makeDestination(processIdentifier: 88),
            validateBeforeMutation: {
                validationCallCount += 1
                return true
            },
            validateAfterPosting: {
                validationCallCount += 1
                return true
            },
            postPairIfPreflightRemainsValid: { postPair in
                postPair()
                return true
            }
        )

        XCTAssertEqual(result, .submittedUnverified)
        XCTAssertEqual(validationCallCount, 2)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, ["safe plain text"])
        XCTAssertEqual(currentFocusEventPoster.destinationProcessIdentifiers, [88])
    }

    func test_keyEventPostingFailureIsReportedForManualRecovery() throws {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let eventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster(result: .deliveryFailed)
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: eventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [99])
        )

        let result = output.insertOnce(
            "safe plain text",
            destination: makeDestination(processIdentifier: 99),
            validateBeforeMutation: { true },
            validateAfterPosting: { true },
            postPairIfPreflightRemainsValid: { postPair in
                postPair()
                return true
            }
        )

        XCTAssertEqual(result, .deliveryFailed)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, ["safe plain text"])
        XCTAssertEqual(currentFocusEventPoster.destinationProcessIdentifiers, [99])
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

    func test_reviewApplicationBoundDraftUsesOneModifierFreeUnicodePairWithoutPasteboardOrCmdV() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let legacyEventPoster = FakeFinalTextKeyEventPoster()
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let unicodeEventPoster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: legacyEventPoster,
            currentFocusEventPoster: unicodeEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false, false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        )
        var beforeCalls = 0
        var afterCalls = 0
        let draft = "first line\nsecond line"

        let result = output.insertReviewAtCurrentFocusOnce(
            draft,
            processIdentifier: 42,
            validateBeforeMutation: {
                beforeCalls += 1
                return .valid
            },
            validateAfterPosting: {
                afterCalls += 1
                return .valid
            }
        )

        XCTAssertEqual(result, .submittedUnverified)
        XCTAssertEqual(beforeCalls, 1)
        XCTAssertEqual(afterCalls, 1)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(legacyEventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(backend.constructedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(backend.constructedEvents.map(\.virtualKey), [nil, nil])
        XCTAssertEqual(backend.constructedEvents.map(\.utf16), [Array(draft.utf16), Array(draft.utf16)])
        XCTAssertEqual(backend.constructedEvents.map(\.flags), [[], []])
        XCTAssertEqual(backend.postedEvents.map(\.processIdentifier), [42, 42])
        XCTAssertEqual(backend.taggedUserData, [FeishuSpeechSyntheticEventTag.value, FeishuSpeechSyntheticEventTag.value])
    }

    func test_reviewExactBindingUsesOneModifierFreeUnicodePairWithoutPasteboardOrCmdV() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let legacyEventPoster = FakeFinalTextKeyEventPoster()
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let unicodeEventPoster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: legacyEventPoster,
            currentFocusEventPoster: unicodeEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false, false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        )
        let draft = "first line\nsecond line"

        let result = output.insertOnce(
            draft,
            destination: makeDestination(processIdentifier: 42),
            validateBeforeMutation: { true },
            validateAfterPosting: { true }
        )

        XCTAssertEqual(result, .submittedUnverified)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(legacyEventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(backend.constructedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(backend.constructedEvents.map(\.virtualKey), [nil, nil])
        XCTAssertEqual(backend.constructedEvents.map(\.utf16), [Array(draft.utf16), Array(draft.utf16)])
        XCTAssertEqual(backend.constructedEvents.map(\.flags), [[], []])
        XCTAssertEqual(backend.postedEvents.map(\.processIdentifier), [42, 42])
        XCTAssertEqual(backend.taggedUserData, [FeishuSpeechSyntheticEventTag.value, FeishuSpeechSyntheticEventTag.value])
    }

    func test_reviewExactBindingPostflightUncertaintyPostsOneUnicodePairWithoutRetryOrPasteboard() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let legacyEventPoster = FakeFinalTextKeyEventPoster()
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let unicodeEventPoster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: legacyEventPoster,
            currentFocusEventPoster: unicodeEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false, false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        )
        let draft = "first line\nsecond line"

        let result = output.insertOnce(
            draft,
            destination: makeDestination(processIdentifier: 42),
            validateBeforeMutation: { true },
            validateAfterPosting: { false }
        )

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(legacyEventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(backend.constructedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(backend.constructedEvents.map(\.virtualKey), [nil, nil])
        XCTAssertEqual(backend.constructedEvents.map(\.utf16), [Array(draft.utf16), Array(draft.utf16)])
        XCTAssertEqual(backend.constructedEvents.map(\.flags), [[], []])
        XCTAssertEqual(backend.postedEvents.map(\.processIdentifier), [42, 42])
        XCTAssertEqual(backend.taggedUserData, [FeishuSpeechSyntheticEventTag.value, FeishuSpeechSyntheticEventTag.value])
    }

    func test_reviewApplicationBoundPostflightUncertaintyPostsOneUnicodePairWithoutRetryOrPasteboard() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let legacyEventPoster = FakeFinalTextKeyEventPoster()
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let unicodeEventPoster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: legacyEventPoster,
            currentFocusEventPoster: unicodeEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false, false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        )
        let draft = "first line\nsecond line"

        let result = output.insertReviewAtCurrentFocusOnce(
            draft,
            processIdentifier: 42,
            validateBeforeMutation: { .valid },
            validateAfterPosting: { .identityChanged }
        )

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(legacyEventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(backend.constructedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(backend.constructedEvents.map(\.virtualKey), [nil, nil])
        XCTAssertEqual(backend.constructedEvents.map(\.utf16), [Array(draft.utf16), Array(draft.utf16)])
        XCTAssertEqual(backend.constructedEvents.map(\.flags), [[], []])
        XCTAssertEqual(backend.postedEvents.map(\.processIdentifier), [42, 42])
        XCTAssertEqual(backend.taggedUserData, [FeishuSpeechSyntheticEventTag.value, FeishuSpeechSyntheticEventTag.value])
    }

    func test_reviewExactAndApplicationBoundPreflightFailurePostsNoUnicodePair() {
        let draft = "first line\nsecond line"
        for route in ["exact", "application"] {
            let pasteboard = FakeFinalTextPasteboardWriter()
            let legacyEventPoster = FakeFinalTextKeyEventPoster()
            let unicodeEventPoster = FakeCurrentFocusUnicodeEventPoster()
            let output = SystemFinalTextOutput(
                pasteboardWriter: pasteboard,
                keyEventPoster: legacyEventPoster,
                currentFocusEventPoster: unicodeEventPoster,
                secureInputStateProvider: FakeSecureInputStateProvider(states: [false, false]),
                frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
            )
            let result: FinalTextInsertionResult
            if route == "exact" {
                result = output.insertOnce(
                    draft,
                    destination: makeDestination(processIdentifier: 42),
                    validateBeforeMutation: { false },
                    validateAfterPosting: {
                        XCTFail("preflight rejection must not run postflight")
                        return false
                    }
                )
            } else {
                result = output.insertReviewAtCurrentFocusOnce(
                    draft,
                    processIdentifier: 42,
                    validateBeforeMutation: { .destinationInvalid },
                    validateAfterPosting: {
                        XCTFail("preflight rejection must not run postflight")
                        return .destinationInvalid
                    }
                )
            }
            XCTAssertEqual(result, .destinationInvalid, "route: \(route)")
            XCTAssertEqual(pasteboard.writtenTexts, [], "route: \(route)")
            XCTAssertEqual(legacyEventPoster.destinationProcessIdentifiers, [], "route: \(route)")
            XCTAssertEqual(unicodeEventPoster.requestedTexts, [], "route: \(route)")
        }
    }

    func test_reviewCurrentFocusUnsafeMultilineControlsRejectBeforeValidationOrMutation() {
        for draft in [
            "first\tline",
            "first\rline",
            "first\u{0000}line",
            "first\u{007F}line",
            "first\u{0085}line",
            "\n\n"
        ] {
            let pasteboard = FakeFinalTextPasteboardWriter()
            let eventPoster = FakeFinalTextKeyEventPoster()
            let output = SystemFinalTextOutput(
                pasteboardWriter: pasteboard,
                keyEventPoster: eventPoster
            )

            let result = output.insertReviewAtCurrentFocusOnce(
                draft,
                processIdentifier: 42,
                validateBeforeMutation: {
                    XCTFail("unsafe review text must be rejected before destination validation")
                    return .valid
                },
                validateAfterPosting: {
                    XCTFail("unsafe review text must not reach postflight")
                    return .valid
                }
            )

            XCTAssertEqual(result, .deliveryFailed, "draft: \(draft.debugDescription)")
            XCTAssertEqual(pasteboard.writtenTexts, [], "draft: \(draft.debugDescription)")
            XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [], "draft: \(draft.debugDescription)")
        }
    }

    func test_reviewCurrentFocusTypedValidationRejectsSecurityIdentityOrDestinationBeforeMutation() {
        let failures: [(ReviewCurrentFocusValidation, FinalTextInsertionResult)] = [
            (.securityRejected, .securityRejected),
            (.identityChanged, .identityChanged),
            (.destinationInvalid, .destinationInvalid)
        ]

        for (validation, expectedResult) in failures {
            let pasteboard = FakeFinalTextPasteboardWriter()
            let eventPoster = FakeFinalTextKeyEventPoster()
            let output = SystemFinalTextOutput(
                pasteboardWriter: pasteboard,
                keyEventPoster: eventPoster
            )

            let result = output.insertReviewAtCurrentFocusOnce(
                "PRIVATE_REVIEW_DRAFT",
                processIdentifier: 42,
                validateBeforeMutation: { validation },
                validateAfterPosting: {
                    XCTFail("a rejected preflight must not reach postflight")
                    return .valid
                }
            )

            XCTAssertEqual(result, expectedResult)
            XCTAssertEqual(pasteboard.writtenTexts, [])
            XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [])
        }
    }

    func test_reviewCurrentFocusPostflightIdentityChangeIsUncertainAndDoesNotRetry() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let eventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster()
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: eventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [42])
        )

        let result = output.insertReviewAtCurrentFocusOnce(
            "PRIVATE_POSTFLIGHT_IDENTITY_CHANGE",
            processIdentifier: 42,
            validateBeforeMutation: { .valid },
            validateAfterPosting: { .identityChanged },
            postPairIfPreflightRemainsValid: { postPair in
                postPair()
                return true
            }
        )

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, ["PRIVATE_POSTFLIGHT_IDENTITY_CHANGE"])
        XCTAssertEqual(currentFocusEventPoster.destinationProcessIdentifiers, [42])
    }

    func test_systemUnicodePosterConstructsCompletePrivatePairBeforePostingDownThenUpOnce() {
        let trace = FakePosterOperationTrace()
        let backend = FakeSystemUnicodeEventBackend(failure: nil, trace: trace)
        let secureInput = FakeTracingSecureInputStateProvider(isEnabled: false, trace: trace)
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: secureInput
        )
        let text = "first line\nFn held 中文"

        let result = poster.postUnicodeText(text, to: 4242)

        XCTAssertEqual(result, .posted)
        XCTAssertEqual(
            backend.operations,
            [
                "source",
                "construct-down",
                "construct-up",
                "tag-down",
                "target-down",
                "tag-up",
                "target-up",
                "readback-down",
                "readback-up",
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

    func test_v4ReviewUnicodePairAcceptsExactUTF16CapAndRejectsSurrogateOverflowBeforeConstruction() {
        let acceptedText = String(repeating: "a", count: 16_382) + "😀"
        XCTAssertEqual(
            acceptedText.utf16.count,
            16_384,
            "the boundary fixture must count the non-BMP character as its intact surrogate pair"
        )
        let acceptedBackend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let acceptedPoster = SystemFinalTextCurrentFocusEventPoster(
            backend: acceptedBackend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )

        XCTAssertEqual(acceptedPoster.postUnicodeText(acceptedText, to: 42), .posted)
        XCTAssertEqual(
            acceptedBackend.constructedEvents.map(\.utf16),
            [Array(acceptedText.utf16), Array(acceptedText.utf16)]
        )
        XCTAssertEqual(
            acceptedBackend.postedEvents.map(\.phase),
            [.keyDown, .keyUp],
            "exactly one complete pair is allowed at the 16,384 UTF-16-unit boundary"
        )
        XCTAssertEqual(
            acceptedBackend.constructedEvents.map(\.sourceProcessIdentifier),
            [getpid(), getpid()],
            "both prepared events must carry the producing process provenance"
        )
        XCTAssertEqual(
            acceptedBackend.constructedEvents.map(\.sourceIdentity),
            [acceptedBackend.sourceIdentity, acceptedBackend.sourceIdentity]
        )
        XCTAssertEqual(acceptedBackend.constructedEvents.map(\.flags), [[], []])
        XCTAssertEqual(
            acceptedBackend.constructedEvents.map(\.userData),
            [FeishuSpeechSyntheticEventTag.value, FeishuSpeechSyntheticEventTag.value]
        )
        XCTAssertEqual(acceptedBackend.postedEvents.map(\.processIdentifier), [42, 42])

        let rejectedText = String(repeating: "a", count: 16_383) + "😀"
        XCTAssertEqual(rejectedText.utf16.count, 16_385)
        let rejectedBackend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let rejectedPoster = SystemFinalTextCurrentFocusEventPoster(
            backend: rejectedBackend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )

        XCTAssertEqual(
            rejectedPoster.postUnicodeText(rejectedText, to: 42),
            .deliveryFailed,
            "one unit over the product cap must fail before event construction"
        )
        XCTAssertEqual(rejectedBackend.constructedEvents.count, 0)
        XCTAssertEqual(rejectedBackend.postedEvents, [])
    }

    func test_v4PreparedPairReadbackFaultsFailBeforeAnyPost() {
        for fault in FakeSystemUnicodeEventBackend.ReadbackFault.allCases {
            let backend = FakeSystemUnicodeEventBackend(
                failure: nil,
                trace: FakePosterOperationTrace()
            )
            backend.readbackFault = fault
            let poster = SystemFinalTextCurrentFocusEventPoster(
                backend: backend,
                secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
            )

            XCTAssertEqual(
                poster.postUnicodeText("PRIVATE_READBACK_FAULT", to: 4242),
                .deliveryFailed,
                "readback fault \(fault) must remain in the notStarted phase"
            )
            XCTAssertEqual(
                backend.postedEvents,
                [],
                "readback fault \(fault) must not submit even a down event"
            )
        }
    }

    func test_v4ReviewUnicodePairHooksAreExecutablePhaseAndPIDOracles() {
        let scenarios: [(
            name: String,
            hooks: ReviewUnicodePosterHooks,
            expected: ReviewUnicodeOutputResult,
            expectedPhases: [FinalTextUnicodeEventPhase]
        )] = [
            (
                "beforeDown",
                ReviewUnicodePosterHooks(beforeDown: { false }),
                .failedBeforeSubmission(.preflightRejected),
                []
            ),
            (
                "afterDown",
                ReviewUnicodePosterHooks(afterDown: { false }),
                .submittedUnverified(.uncertain),
                [.keyDown, .keyUp]
            ),
            (
                "beforeUp",
                ReviewUnicodePosterHooks(beforeUp: { false }),
                .submittedUnverified(.uncertain),
                [.keyDown, .keyUp]
            ),
            (
                "afterUp",
                ReviewUnicodePosterHooks(afterUp: { false }),
                .submittedUnverified(.uncertain),
                [.keyDown, .keyUp]
            ),
            (
                "postflight",
                ReviewUnicodePosterHooks(postflight: { false }),
                .submittedUnverified(.uncertain),
                [.keyDown, .keyUp]
            )
        ]

        for scenario in scenarios {
            let backend = FakeSystemUnicodeEventBackend(
                failure: nil,
                trace: FakePosterOperationTrace()
            )
            let poster = SystemFinalTextCurrentFocusEventPoster(
                backend: backend,
                secureInputStateProvider: FakeSecureInputStateProvider(states: [false]),
                hooks: scenario.hooks
            )
            var pairGateCalls = 0

            let result = poster.postReviewUnicodePair(
                "PRIVATE_\(scenario.name)",
                to: 4242,
                postPairIfPreflightRemainsValid: { postPair in
                    pairGateCalls += 1
                    postPair()
                    return true
                },
                validateAfterPosting: { .valid }
            )

            XCTAssertEqual(result, scenario.expected, scenario.name)
            XCTAssertEqual(pairGateCalls, 1, scenario.name)
            XCTAssertEqual(
                backend.postedEvents.map(\.phase),
                scenario.expectedPhases,
                "phase sequence for \(scenario.name)"
            )
            XCTAssertEqual(
                backend.postedEvents.map(\.processIdentifier),
                Array(repeating: 4242, count: scenario.expectedPhases.count),
                "captured PID for \(scenario.name)"
            )
        }
    }

    func test_v4ReviewUnicodePairCancellationBeforeAndAfterBoundaryIsPhaseAware() {
        let beforeBackend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let beforePoster = SystemFinalTextCurrentFocusEventPoster(
            backend: beforeBackend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false]),
            hooks: ReviewUnicodePosterHooks(cancellation: { true })
        )
        XCTAssertEqual(
            beforePoster.postReviewUnicodePair(
                "PRIVATE_CANCEL_BEFORE_DOWN",
                to: 4242,
                postPairIfPreflightRemainsValid: { postPair in
                    postPair()
                    return true
                },
                validateAfterPosting: { .valid }
            ),
            .cancelledBeforeSubmission
        )
        XCTAssertEqual(beforeBackend.postedEvents, [])

        var cancellationCalls = 0
        let afterBackend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let afterPoster = SystemFinalTextCurrentFocusEventPoster(
            backend: afterBackend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false]),
            hooks: ReviewUnicodePosterHooks(cancellation: {
                cancellationCalls += 1
                return cancellationCalls >= 3
            })
        )
        XCTAssertEqual(
            afterPoster.postReviewUnicodePair(
                "PRIVATE_CANCEL_AFTER_DOWN",
                to: 4242,
                postPairIfPreflightRemainsValid: { postPair in
                    postPair()
                    return true
                },
                validateAfterPosting: { .valid }
            ),
            .submittedUnverified(.uncertain)
        )
        XCTAssertEqual(
            afterBackend.postedEvents.map(\.phase),
            [.keyDown, .keyUp],
            "cancellation after the boundary must still attempt the complete pair"
        )
        XCTAssertEqual(afterBackend.postedEvents.map(\.processIdentifier), [4242, 4242])
    }

    func test_v4BindingSpecificFinalValidationModifierTransitionIsPreBoundaryForExactAndApplicationRoutes() async {
        for modifier in [
            CGEventFlags.maskCommand,
            .maskShift,
            .maskControl,
            .maskAlternate,
            .maskSecondaryFn
        ] {
            for route in ["exact", "application"] {
                let runtime = R1ReviewApplicationRuntime()
                let activation = R1ReviewApplicationActivator()
                let flags = R1MutableReviewModifierFlags()
                let access = R1ReviewDestinationAccess(
                    captureResult: route == "exact"
                        ? .exact(R1ReviewFixtures.cursorToken())
                        : .nonSecureCursorUnavailable
                )
                let secureInput = R1MutableReviewSecureInputProvider()
                let backend = FakeSystemUnicodeEventBackend(
                    failure: nil,
                    trace: FakePosterOperationTrace()
                )
                let poster = SystemFinalTextCurrentFocusEventPoster(
                    backend: backend,
                    secureInputStateProvider: secureInput
                )
                let output = SystemFinalTextOutput(
                    pasteboardWriter: FakeFinalTextPasteboardWriter(),
                    keyEventPoster: FakeFinalTextKeyEventPoster(),
                    currentFocusEventPoster: poster,
                    secureInputStateProvider: secureInput,
                    frontmostProcessProvider: R1ReviewFrontmostProcessProvider(
                        runtime: runtime
                    )
                )

                if route == "exact" {
                    access.onRestore = { flags.value = modifier }
                } else {
                    // The fourth secure-input read is the second composite
                    // sample inside application-bound final validation. It
                    // occurs after the monitor's empty modifier check and
                    // before the pair can be submitted.
                    secureInput.onQuery = { queryCount in
                        if queryCount == 4 {
                            flags.value = modifier
                        }
                    }
                }

                let delivery = SystemReviewDestinationDelivery(
                    applicationRuntime: runtime,
                    applicationActivator: activation,
                    accessibility: access,
                    finalTextOutput: output,
                    accessibilityTrustProvider: R1ReviewTrustProvider(),
                    secureInputStateProvider: secureInput,
                    frontmostProcessProvider: R1ReviewFrontmostProcessProvider(
                        runtime: runtime
                    ),
                    inputMonitor: R1ReviewInputMonitor(),
                    activationMonitor: R1ReviewActivationMonitor(),
                    modifierSampler: { flags.value },
                    modifierSleeper: { _ in true }
                )
                let destination = R1ReviewFixtures.destination(
                    binding: route == "exact"
                        ? .exactCursor(R1ReviewFixtures.cursorToken())
                        : .applicationCurrentFocus
                )

                let result = await delivery.deliver(
                    "PRIVATE_MODIFIER_\(route)_\(modifier.rawValue)",
                    to: destination
                )

                XCTAssertEqual(
                    result,
                    .deliveryFailed,
                    "\(route) route must fail before the Unicode submission boundary for \(modifier)"
                )
                XCTAssertEqual(
                    backend.postedEvents,
                    [],
                    "\(route) route must not post after \(modifier) changes in final validation"
                )
                XCTAssertEqual(
                    backend.constructedEvents.count,
                    2,
                    "\(route) route may prepare/read back, but must not post, for \(modifier)"
                )
            }
        }
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
            [
                "source",
                "construct-down",
                "construct-up",
                "tag-down",
                "target-down",
                "tag-up",
                "target-up",
                "readback-down",
                "readback-up",
                "secure"
            ]
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

    private func productionSource(relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
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
private enum R1ReviewFixtures {
    static let identity = ReviewApplicationIdentity(
        processIdentifier: 42,
        bundleIdentifier: "com.example.issue40.r1",
        executableURL: URL(fileURLWithPath: "/Applications/Issue40R1.app/Contents/MacOS/R1"),
        launchDate: Date(timeIntervalSince1970: 40)
    )

    static func cursorToken() -> CursorDestinationToken {
        CursorDestinationToken(
            generation: 40,
            processIdentifier: identity.processIdentifier,
            element: AXUIElementCreateApplication(identity.processIdentifier),
            originalSelection: CursorTextRange(location: 0, length: 0)
        )
    }

    static func destination(binding: ReviewDestinationBinding) -> ReviewDestinationToken {
        ReviewDestinationToken(
            generation: 40,
            application: identity,
            binding: binding,
            capturedSecurityState: .safe
        )
    }
}

@MainActor
private final class R1ReviewApplicationRuntime: ReviewApplicationRuntime {
    func identity(for processIdentifier: pid_t) -> ReviewApplicationIdentity? {
        processIdentifier == R1ReviewFixtures.identity.processIdentifier
            ? R1ReviewFixtures.identity
            : nil
    }

    func frontmostIdentity() -> ReviewApplicationIdentity? {
        R1ReviewFixtures.identity
    }

    func frontmostProcessIdentifier() -> pid_t? {
        R1ReviewFixtures.identity.processIdentifier
    }
}

@MainActor
private final class R1ReviewApplicationActivator: ReviewApplicationActivating {
    func activateAndWait(
        for _: ReviewApplicationIdentity,
        timeoutNanoseconds _: UInt64
    ) async -> ReviewActivationResult {
        .activated
    }
}

@MainActor
private final class R1ReviewDestinationAccess: ReviewDestinationAccessing {
    let captureResult: ReviewCursorCaptureResult
    var onRestore: (() -> Void)?

    init(captureResult: ReviewCursorCaptureResult) {
        self.captureResult = captureResult
    }

    func captureReviewCursorDestination(generation: UInt64) -> ReviewCursorCaptureResult {
        captureResult
    }

    func restoreAndValidateBeforeDelivery(_: CursorDestinationToken) throws -> Bool {
        onRestore?()
        return true
    }

    func validateAfterDelivery(_: CursorDestinationToken) throws -> Bool {
        true
    }
}

@MainActor
private final class R1ReviewTrustProvider: AccessibilityTrustProviding {
    var isAccessibilityTrusted = true
}

@MainActor
private final class R1MutableReviewModifierFlags {
    var value: CGEventFlags = []
}

@MainActor
private final class R1MutableReviewSecureInputProvider: SecureInputStateProviding {
    var onQuery: ((Int) -> Void)?
    private(set) var queryCount = 0

    func isSecureInputEnabled() -> Bool {
        queryCount += 1
        onQuery?(queryCount)
        return false
    }
}

@MainActor
private final class R1ReviewFrontmostProcessProvider: FrontmostProcessProviding {
    private let runtime: R1ReviewApplicationRuntime

    init(runtime: R1ReviewApplicationRuntime) {
        self.runtime = runtime
    }

    func frontmostProcessIdentifier() -> pid_t? {
        runtime.frontmostProcessIdentifier()
    }
}

@MainActor
private final class R1ReviewInputMonitor: CurrentFocusInputMonitoring {
    let supportsReviewDeliveryEpoch = true
    var interferenceEpoch: UInt64 = 0

    func startMonitoring(_: @escaping @MainActor () -> Void) {}

    func armMonitoringFailClosed(_: @escaping @MainActor () -> Void) -> Bool {
        true
    }

    func armMonitoringFailClosedWithEpoch(
        _: @escaping @MainActor () -> Void
    ) -> UInt64? {
        interferenceEpoch
    }

    func postCompleteSyntheticPairIfInterferenceEpochIsUnchanged(
        expectedEpoch: UInt64,
        _ postPair: () -> Void
    ) -> Bool {
        guard expectedEpoch == interferenceEpoch else { return false }
        postPair()
        return true
    }

    func stopMonitoring() {}
}

@MainActor
private final class R1ReviewActivationMonitor: CurrentFocusActivationMonitoring {
    let supportsReviewDeliveryEpoch = true
    var activationEpoch: UInt64 = 0

    func startMonitoring(_: @escaping @MainActor (pid_t) -> Void) {}

    func armMonitoringFailClosedWithEpoch(
        _: @escaping @MainActor (pid_t) -> Void
    ) -> UInt64? {
        activationEpoch
    }

    func stopMonitoring() {}
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

    enum ReadbackFault: String, CaseIterable {
        case tag
        case sourcePID
        case sourceIdentity
        case flags
        case phase
        case payload
        case targetPID
    }

    private let failure: Failure?
    private let keyboardFailurePhase: FinalTextUnicodeEventPhase?
    private let source = FakeUnicodeEventSourceHandle()
    private let trace: FakePosterOperationTrace
    private(set) var sourceStateIDs: [CGEventSourceStateID] = []
    private(set) var constructedEvents: [FakeUnicodeEventHandle] = []
    private(set) var postedEvents: [FakePostedUnicodeEvent] = []
    private(set) var taggedUserData: [Int64] = []
    var readbackFault: ReadbackFault?
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
            phase: readbackFault == .phase
                ? (phase == .keyDown ? .keyUp : .keyDown)
                : phase,
            sourceIdentity: readbackFault == .sourceIdentity
                ? ObjectIdentifier(FakeUnicodeEventSourceHandle())
                : ObjectIdentifier(source),
            sourceProcessIdentifier: readbackFault == .sourcePID ? nil : getpid(),
            utf16: readbackFault == .payload ? Array(utf16.dropLast()) : utf16,
            flags: readbackFault == .flags ? .maskCommand : flags,
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
            sourceProcessIdentifier: getpid(),
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
        let actualUserData = readbackFault == .tag ? 0 : userData
        event.userData = actualUserData
        taggedUserData.append(actualUserData)
    }

    func setTargetProcessIdentifier(
        _ processIdentifier: pid_t,
        for event: any FinalTextUnicodeEventHandle
    ) {
        guard let event = event as? FakeUnicodeEventHandle else {
            XCTFail("poster targeted an event outside the injected backend")
            return
        }
        trace.record(event.phase == .keyDown ? "target-down" : "target-up")
        event.targetProcessIdentifier = readbackFault == .targetPID
            ? processIdentifier + 1
            : processIdentifier
    }

    func readbackEvent(_ expectation: FinalTextUnicodeReadback) -> Bool {
        guard let event = expectation.event as? FakeUnicodeEventHandle,
              let source = expectation.source as? FakeUnicodeEventSourceHandle else {
            return false
        }
        trace.record(event.phase == .keyDown ? "readback-down" : "readback-up")
        return event.phase == expectation.expectedPhase
            && event.sourceIdentity == ObjectIdentifier(source)
            && event.sourceProcessIdentifier == expectation.expectedSourceProcessIdentifier
            && event.targetProcessIdentifier == expectation.expectedTargetProcessIdentifier
            && event.utf16 == expectation.expectedUTF16
            && event.flags == expectation.expectedFlags
            && event.userData == expectation.expectedUserData
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
            processIdentifier: readbackFault == .targetPID ? processIdentifier + 1 : processIdentifier,
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
    let sourceProcessIdentifier: pid_t?
    let utf16: [UInt16]
    let flags: CGEventFlags
    let virtualKey: CGKeyCode?
    var userData: Int64 = 0
    var targetProcessIdentifier: pid_t?

    init(
        phase: FinalTextUnicodeEventPhase,
        sourceIdentity: ObjectIdentifier,
        sourceProcessIdentifier: pid_t?,
        utf16: [UInt16],
        flags: CGEventFlags,
        virtualKey: CGKeyCode?
    ) {
        self.phase = phase
        self.sourceIdentity = sourceIdentity
        self.sourceProcessIdentifier = sourceProcessIdentifier
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
