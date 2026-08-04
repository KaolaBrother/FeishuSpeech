import AppKit
@testable import FeishuSpeech
import Foundation
import os.log
import XCTest

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "CurrentFocusAppendSessionTests"
)

@MainActor
final class CurrentFocusAppendSessionTests: XCTestCase {
    private let generation: UInt64 = 41
    private let boundProcessIdentifier: pid_t = 4242

    func test_firstValuePostsWholePayloadAndExactDuplicateIsNoOp() {
        let context = makeContext()

        let first = context.session.applyOpaqueHypothesis(
            "first visible value",
            generation: generation,
            source: .livePacket
        )
        let duplicate = context.session.applyOpaqueHypothesis(
            "first visible value",
            generation: generation,
            source: .replayCatchUp
        )

        XCTAssertEqual(first, .insertedFirst)
        XCTAssertEqual(duplicate, .duplicate)
        assertPosted(["first visible value"], by: context.poster)
        XCTAssertEqual(context.poster.destinationProcessIdentifiers, [boundProcessIdentifier])
        XCTAssertEqual(context.poster.callCount, 1)
    }

    func test_snapshotReplacementUsesExactGraphemeBackspacesAndReplacementSuffix() {
        let family = "👨‍👩‍👧‍👦"
        let cases = [
            SnapshotReplacementCase(
                previous: "hello",
                next: "hello world",
                expectedDeleteCharacterCount: 0,
                expectedInsertText: " world"
            ),
            SnapshotReplacementCase(
                previous: "abcd",
                next: "ab",
                expectedDeleteCharacterCount: 2,
                expectedInsertText: ""
            ),
            SnapshotReplacementCase(
                previous: "hello cat",
                next: "hello car",
                expectedDeleteCharacterCount: 1,
                expectedInsertText: "r"
            ),
            SnapshotReplacementCase(
                previous: "one",
                next: "two",
                expectedDeleteCharacterCount: 3,
                expectedInsertText: "two"
            ),
            SnapshotReplacementCase(
                previous: family + "x",
                next: family + "y",
                expectedDeleteCharacterCount: 1,
                expectedInsertText: "y"
            ),
            SnapshotReplacementCase(
                previous: "🇨🇳x",
                next: "🇨🇳y",
                expectedDeleteCharacterCount: 1,
                expectedInsertText: "y"
            ),
            SnapshotReplacementCase(
                previous: "你好猫",
                next: "你好狗",
                expectedDeleteCharacterCount: 1,
                expectedInsertText: "狗"
            ),
            SnapshotReplacementCase(
                previous: "שלוםא",
                next: "שלוםב",
                expectedDeleteCharacterCount: 1,
                expectedInsertText: "ב"
            ),
            SnapshotReplacementCase(
                previous: "line1\nold",
                next: "line1\nnew",
                expectedDeleteCharacterCount: 3,
                expectedInsertText: "new"
            )
        ]

        for testCase in cases {
            let context = makeContext()
            _ = context.session.applyOpaqueHypothesis(
                testCase.previous,
                generation: generation,
                source: .livePacket
            )
            _ = context.session.applyOpaqueHypothesis(
                testCase.next,
                generation: generation,
                source: .livePacket
            )

            XCTAssertEqual(
                context.poster.replacementRequests,
                [
                    ReplacementRequest(
                        deleteCharacterCount: 0,
                        insertText: testCase.previous,
                        processIdentifier: boundProcessIdentifier
                    ),
                    ReplacementRequest(
                        deleteCharacterCount: testCase.expectedDeleteCharacterCount,
                        insertText: testCase.expectedInsertText,
                        processIdentifier: boundProcessIdentifier
                    )
                ],
                "replacement must reconcile Swift Character boundaries for \(testCase.previous.debugDescription)"
            )
        }
    }

    func test_completeExtensionSnapshotsPostOnlyUnseenSuffixAcrossEmojiZWJCJKAndRTL() {
        let context = makeContext()
        let first = "A"
        let family = "👨‍👩‍👧‍👦"
        let cjk = "中文"
        let rtl = "שלום"

        _ = context.session.applyOpaqueHypothesis(first, generation: generation, source: .livePacket)
        _ = context.session.applyOpaqueHypothesis(
            first + family,
            generation: generation,
            source: .livePacket
        )
        _ = context.session.applyOpaqueHypothesis(
            first + family + cjk + rtl,
            generation: generation,
            source: .livePacket
        )

        XCTAssertEqual(
            context.poster.replacementRequests,
            [
                ReplacementRequest(
                    deleteCharacterCount: 0,
                    insertText: first,
                    processIdentifier: boundProcessIdentifier
                ),
                ReplacementRequest(
                    deleteCharacterCount: 0,
                    insertText: family,
                    processIdentifier: boundProcessIdentifier
                ),
                ReplacementRequest(
                    deleteCharacterCount: 0,
                    insertText: cjk + rtl,
                    processIdentifier: boundProcessIdentifier
                )
            ]
        )
    }

    func test_completeGrowingSnapshotsRemainBoundToOnePID() {
        let context = makeContext()
        let firstScalar = "one"
        let secondScalar = "👩🏽‍💻"
        let thirdScalar = "שלום"
        let snapshots = [
            firstScalar,
            firstScalar + secondScalar,
            firstScalar + secondScalar + thirdScalar
        ]

        snapshots.forEach { snapshot in
            _ = context.session.applyOpaqueHypothesis(
                snapshot,
                generation: generation,
                source: .livePacket
            )
        }

        XCTAssertEqual(context.poster.requestedTexts, [firstScalar, secondScalar, thirdScalar])
        XCTAssertEqual(
            context.poster.destinationProcessIdentifiers,
            Array(repeating: boundProcessIdentifier, count: 3),
            "reconciling complete snapshots must not weaken the fixed-PID boundary"
        )
    }

    func test_shorterDivergentAndCombiningMarkSnapshotsReplaceOwnedTailThenExtend() {
        let context = makeContext()
        let decomposed = "cafe\u{301}x"

        _ = context.session.applyOpaqueHypothesis(decomposed, generation: generation, source: .livePacket)
        _ = context.session.applyOpaqueHypothesis("cafe\u{301}", generation: generation, source: .livePacket)
        _ = context.session.applyOpaqueHypothesis("cafe\u{301}y", generation: generation, source: .livePacket)
        _ = context.session.applyOpaqueHypothesis("revised", generation: generation, source: .livePacket)
        _ = context.session.applyOpaqueHypothesis("revised!", generation: generation, source: .replayCatchUp)

        XCTAssertEqual(
            context.poster.replacementRequests,
            [
                ReplacementRequest(
                    deleteCharacterCount: 0,
                    insertText: decomposed,
                    processIdentifier: boundProcessIdentifier
                ),
                ReplacementRequest(
                    deleteCharacterCount: 1,
                    insertText: "",
                    processIdentifier: boundProcessIdentifier
                ),
                ReplacementRequest(
                    deleteCharacterCount: 0,
                    insertText: "y",
                    processIdentifier: boundProcessIdentifier
                ),
                ReplacementRequest(
                    deleteCharacterCount: 5,
                    insertText: "revised",
                    processIdentifier: boundProcessIdentifier
                ),
                ReplacementRequest(
                    deleteCharacterCount: 0,
                    insertText: "!",
                    processIdentifier: boundProcessIdentifier
                )
            ]
        )
    }

    func test_shorterAndDivergentReplacementOutcomesUsedByReceiptsNeverSayAppendedSuffix() {
        let shorter = makeContext()
        _ = shorter.session.applyOpaqueHypothesis(
            "hello world",
            generation: generation,
            source: .livePacket
        )
        let shorterOutcome = shorter.session.applyOpaqueHypothesis(
            "hello",
            generation: generation,
            source: .livePacket
        )

        let divergent = makeContext()
        _ = divergent.session.applyOpaqueHypothesis(
            "hello cat",
            generation: generation,
            source: .livePacket
        )
        let divergentOutcome = divergent.session.applyOpaqueHypothesis(
            "hello dog",
            generation: generation,
            source: .replayCatchUp
        )

        XCTAssertNotEqual(shorterOutcome, .appendedSuffix)
        XCTAssertNotEqual(divergentOutcome, .appendedSuffix)
        XCTAssertNotEqual(String(describing: shorterOutcome), "appendedSuffix")
        XCTAssertNotEqual(String(describing: divergentOutcome), "appendedSuffix")
    }

    func test_contentlessAndUnsafeC0C1DELValuesNeverPostAndSafeExtensionCanRecover() {
        for unsafe in ["safe\u{0000}", "safe\u{001F}", "safe\u{007F}", "safe\u{0085}", "safe\u{009F}"] {
            let context = makeContext()
            XCTAssertEqual(
                context.session.applyOpaqueHypothesis(unsafe, generation: generation, source: .livePacket),
                .unsafeTextSuppressed
            )
            XCTAssertEqual(context.poster.callCount, 0)
        }

        let context = makeContext()
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis("   ", generation: generation, source: .livePacket),
            .contentless
        )
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis("safe", generation: generation, source: .livePacket),
            .insertedFirst
        )
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis("safe\u{007F}", generation: generation, source: .livePacket),
            .unsafeTextSuppressed
        )
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis("safe suffix", generation: generation, source: .livePacket),
            .appendedSuffix
        )
        assertPosted(["safe", " suffix"], by: context.poster)
    }

    func test_PIDMismatchAtEitherPreflightOrPostflightPermanentlySuspendsOutput() {
        let samples: [[pid_t?]] = [
            [9999],
            [boundProcessIdentifier, 9999],
            [boundProcessIdentifier, boundProcessIdentifier, 9999]
        ]

        for processIdentifiers in samples {
            let context = makeContext(processIdentifiers: processIdentifiers)
            let first = context.session.applyOpaqueHypothesis(
                "candidate",
                generation: generation,
                source: .livePacket
            )
            let late = context.session.applyOpaqueHypothesis(
                "candidate extension",
                generation: generation,
                source: .livePacket
            )

            XCTAssertEqual(first, .destinationChanged)
            XCTAssertEqual(late, .destinationChanged)
            XCTAssertLessThanOrEqual(context.poster.callCount, 1)
        }
    }

    func test_secureInputAtEitherPreflightPosterOrPostflightPermanentlySuspendsOutput() {
        let firstSample = makeContext(secureInputStates: [true])
        assertSecuritySuspension(firstSample)

        let secondSample = makeContext(secureInputStates: [false, true])
        assertSecuritySuspension(secondSample)

        let posterSample = makeContext(
            secureInputStates: [false, false],
            posterResults: [.securityRejected]
        )
        assertSecuritySuspension(posterSample)

        let postflightSample = makeContext(secureInputStates: [false, false, true])
        assertSecuritySuspension(postflightSample)
    }

    func test_activationAwayPermanentlySuspendsEvenAfterActivationReturns() {
        let context = makeContext()

        context.activationMonitor.activate(processIdentifier: 9999)
        context.activationMonitor.activate(processIdentifier: boundProcessIdentifier)

        XCTAssertEqual(
            context.session.applyOpaqueHypothesis("late", generation: generation, source: .livePacket),
            .destinationChanged
        )
        XCTAssertEqual(context.poster.callCount, 0)
        XCTAssertEqual(context.activationMonitor.startCallCount, 1)
    }

    func test_externalCaretAffectingInputPermanentlySuspendsReplacement() {
        let context = makeContext()
        _ = context.session.applyOpaqueHypothesis(
            "owned text",
            generation: generation,
            source: .livePacket
        )

        context.inputMonitor.receiveExternalInput()
        let later = context.session.applyOpaqueHypothesis(
            "owned replacement",
            generation: generation,
            source: .livePacket
        )

        XCTAssertEqual(later, .deliveryUncertain)
        XCTAssertEqual(context.poster.replacementRequests.count, 1)
        XCTAssertEqual(context.inputMonitor.startCallCount, 1)
        XCTAssertEqual(context.inputMonitor.stopCallCount, 1)
    }

    func test_inputMonitorFailureAtEitherRegistrationArmFailsClosedBeforeTransaction() {
        for failure in [TestInputMonitorArmFailure.local, .global] {
            let context = makeContext(inputMonitorArmFailure: failure)

            let outcome = context.session.applyOpaqueHypothesis(
                "must not post",
                generation: generation,
                source: .livePacket
            )

            XCTAssertFalse(context.inputMonitor.isCompletelyArmed)
            XCTAssertEqual(
                context.inputMonitor.failClosedArmCallCount,
                1,
                "the session must consume an explicit complete-arm result"
            )
            XCTAssertEqual(
                context.poster.callCount,
                0,
                "\(failure) registration failure must prevent the transaction"
            )
            XCTAssertNotEqual(outcome, .insertedFirst)
            XCTAssertNotEqual(outcome, .appendedSuffix)
        }
    }

    func test_armedInputMonitorCapturesBaselineEpochAndExemptsTaggedSyntheticAndFnEvents() {
        let context = makeContext(inputMonitorInitialEpoch: 17)

        XCTAssertEqual(
            context.inputMonitor.interferenceEpochReadCount,
            1,
            "arming must capture the pre-dispatch interference baseline"
        )
        context.inputMonitor.receivePreDispatchCGEventTap(.taggedSyntheticKeyDown)
        context.inputMonitor.receivePreDispatchCGEventTap(.fnFlagsChanged)

        let outcome = context.session.applyOpaqueHypothesis(
            "safe snapshot",
            generation: generation,
            source: .livePacket
        )

        XCTAssertEqual(context.inputMonitor.rawInterferenceEpoch, 17)
        XCTAssertGreaterThanOrEqual(
            context.inputMonitor.interferenceEpochReadCount,
            2,
            "the epoch must be sampled again immediately before output"
        )
        XCTAssertEqual(outcome, .insertedFirst)
        XCTAssertEqual(context.poster.callCount, 1)
    }

    func test_armReturnsBaselineEpochAtomicallyWithoutAbsorbingBoundaryInput() {
        let context = makeContext(
            inputMonitorInitialEpoch: 41,
            injectPhysicalInputAtArmBoundary: true
        )

        XCTAssertEqual(
            context.inputMonitor.failClosedArmWithEpochCallCount,
            1,
            "the arm operation must return the baseline captured inside the installation gate"
        )
        XCTAssertEqual(context.inputMonitor.rawInterferenceEpoch, 42)

        let outcome = context.session.applyOpaqueHypothesis(
            "must remain queued",
            generation: generation,
            source: .livePacket
        )

        XCTAssertEqual(outcome, .deliveryUncertain)
        XCTAssertEqual(
            context.poster.callCount,
            0,
            "input after arm completion must not be absorbed by a later baseline read"
        )
    }

    func test_preDispatchPhysicalKeyOrMouseEpochDriftSuppressesTransactionWithoutMainActorCallback() {
        for input in [TestPreDispatchInputKind.physicalKeyDown, .physicalLeftMouseDown] {
            let context = makeContext(inputMonitorInitialEpoch: 23)
            context.inputMonitor.receivePreDispatchCGEventTap(
                input,
                deliverAppKitGlobalMonitorCallback: false
            )

            let outcome = context.session.applyOpaqueHypothesis(
                "queued snapshot",
                generation: generation,
                source: .livePacket
            )

            XCTAssertEqual(
                outcome,
                .deliveryUncertain,
                "\(input) epoch drift must fail closed before destructive output"
            )
            XCTAssertEqual(
                context.poster.callCount,
                0,
                "\(input) must suppress the queued transaction before AppKit callback delivery"
            )
            XCTAssertGreaterThanOrEqual(context.inputMonitor.interferenceEpochReadCount, 2)
            XCTAssertEqual(context.inputMonitor.rawInterferenceEpoch, 24)
        }
    }

    func test_epochDriftDuringMultiBackspaceReplacementStopsLaterDestructiveEvents() {
        let context = makeContext(inputMonitorInitialEpoch: 31)
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis(
                "abcdef",
                generation: generation,
                source: .livePacket
            ),
            .insertedFirst
        )
        context.poster.resetTransactionTracking()
        context.poster.afterFirstGuardedBackspace = {
            context.inputMonitor.receivePreDispatchCGEventTap(
                .physicalKeyDown,
                deliverAppKitGlobalMonitorCallback: false
            )
        }

        let outcome = context.session.applyOpaqueHypothesis(
            "uvwxyz",
            generation: generation,
            source: .livePacket
        )

        XCTAssertEqual(context.poster.guardedReplacementCallCount, 1)
        XCTAssertEqual(
            context.poster.destructiveBackspaceCount,
            1,
            "epoch drift after the first pair must prevent every later Backspace pair"
        )
        XCTAssertEqual(context.poster.replacementRequests, [])
        XCTAssertEqual(outcome, .deliveryUncertain)
    }

    func test_sharedInterferenceGateHoldsPhysicalAdvanceAcrossCompleteSyntheticPair() {
        let context = makeContext(inputMonitorInitialEpoch: 51)
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis(
                "abcdef",
                generation: generation,
                source: .livePacket
            ),
            .insertedFirst
        )
        context.poster.resetTransactionTracking()
        let trace = ThreadSafeRaceTrace()
        context.poster.raceTrace = trace
        context.poster.afterEpochValidationBeforeFirstSyntheticPost = {
            context.inputMonitor.beginPhysicalAdvanceDuringPosting(trace: trace)
        }

        let outcome = context.session.applyOpaqueHypothesis(
            "uvwxyz",
            generation: generation,
            source: .livePacket
        )
        context.inputMonitor.waitForPendingPhysicalAdvance()

        XCTAssertEqual(context.poster.atomicGuardedReplacementCallCount, 1)
        XCTAssertEqual(context.poster.guardedReplacementCallCount, 0)
        XCTAssertEqual(
            trace.values,
            ["synthetic-down", "synthetic-up", "physical-epoch-advance"],
            "physical HID delivery must wait until the complete synthetic down/up pair leaves the gate"
        )
        XCTAssertEqual(context.poster.destructiveBackspaceCount, 1)
        XCTAssertEqual(context.poster.insertionPairCount, 0)
        XCTAssertEqual(outcome, .deliveryUncertain)
    }

    func test_tapDisabledEventsSynchronouslyAdvanceLossOfObservabilityEpochWithExemptions() {
        let epoch = CurrentFocusInputInterferenceEpoch()
        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        )!
        let taggedEvent = event.copy()!
        taggedEvent.setIntegerValueField(
            .eventSourceUserData,
            value: FeishuSpeechSyntheticEventTag.value
        )
        let fnEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 63,
            keyDown: true
        )!

        epoch.observePreDispatch(type: .keyDown, event: taggedEvent)
        epoch.observePreDispatch(type: .flagsChanged, event: fnEvent)
        XCTAssertEqual(epoch.value, 0)

        epoch.observePreDispatch(type: .tapDisabledByTimeout, event: event)
        XCTAssertEqual(
            epoch.value,
            1,
            "tap timeout must synchronously mark loss of observability"
        )
        epoch.observePreDispatch(type: .tapDisabledByUserInput, event: event)
        XCTAssertEqual(
            epoch.value,
            2,
            "tap user-input disable must synchronously mark loss of observability"
        )
    }

    func test_tapDisabledEpochDriftSuppressesActiveSessionBeforeRecoveryCallbacks() {
        for input in [
            TestPreDispatchInputKind.tapDisabledByTimeout,
            .tapDisabledByUserInput
        ] {
            let context = makeContext(inputMonitorInitialEpoch: 61)
            context.inputMonitor.receivePreDispatchCGEventTap(
                input,
                deliverAppKitGlobalMonitorCallback: false
            )

            XCTAssertEqual(
                context.session.applyOpaqueHypothesis(
                    "late replacement",
                    generation: generation,
                    source: .livePacket
                ),
                .deliveryUncertain
            )
            XCTAssertEqual(context.poster.callCount, 0)
        }
    }

    func test_workspaceInputMonitorObservesSameAppPhysicalKeyboardSynchronously() {
        let monitor = WorkspaceCurrentFocusInputMonitor()
        var suspensionCount = 0
        monitor.startMonitoring {
            suspensionCount += 1
        }
        defer { monitor.stopMonitoring() }

        NSApplication.shared.sendEvent(makeKeyEvent(type: .keyDown, characters: "a", keyCode: 0))

        XCTAssertEqual(
            suspensionCount,
            1,
            "same-app keyboard input must synchronously cross the suspension barrier"
        )
    }

    func test_workspaceInputMonitorObservesSameAppPhysicalMouseSynchronously() {
        let monitor = WorkspaceCurrentFocusInputMonitor()
        var suspensionCount = 0
        monitor.startMonitoring {
            suspensionCount += 1
        }
        defer { monitor.stopMonitoring() }

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
        NSApplication.shared.sendEvent(event)

        XCTAssertEqual(
            suspensionCount,
            1,
            "same-app mouse input must synchronously cross the suspension barrier"
        )
    }

    func test_workspaceInputMonitorExemptsTaggedSyntheticEventsAndFnTransitions() {
        let monitor = WorkspaceCurrentFocusInputMonitor()
        var suspensionCount = 0
        monitor.startMonitoring {
            suspensionCount += 1
        }
        defer { monitor.stopMonitoring() }

        let taggedCGEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        )!
        taggedCGEvent.setIntegerValueField(
            .eventSourceUserData,
            value: FeishuSpeechSyntheticEventTag.value
        )
        NSApplication.shared.sendEvent(NSEvent(cgEvent: taggedCGEvent)!)
        NSApplication.shared.sendEvent(
            makeKeyEvent(
                type: .flagsChanged,
                characters: "",
                modifierFlags: .function,
                keyCode: 63
            )
        )

        XCTAssertEqual(suspensionCount, 0)
    }

    func test_sameAppPhysicalInputSuspendsBeforeQueuedReplacementTransaction() {
        let processProvider = FakeAppendFrontmostProcessProvider(
            processIdentifiers: Array(repeating: boundProcessIdentifier, count: 10)
        )
        let secureInputProvider = FakeAppendSecureInputStateProvider(
            states: Array(repeating: false, count: 10)
        )
        let poster = FakeUnicodeEventPoster(results: [])
        let monitor = WorkspaceCurrentFocusInputMonitor()
        let session = CurrentFocusAppendSession(
            generation: generation,
            boundProcessIdentifier: boundProcessIdentifier,
            eventPoster: poster,
            secureInputStateProvider: secureInputProvider,
            frontmostProcessProvider: processProvider,
            activationMonitor: FakeActivationMonitor(),
            inputMonitor: monitor
        )
        defer { session.invalidate() }

        NSApplication.shared.sendEvent(makeKeyEvent(type: .keyDown, characters: "a", keyCode: 0))
        let outcome = session.applyOpaqueHypothesis(
            "queued replacement",
            generation: generation,
            source: .livePacket
        )

        XCTAssertEqual(outcome, .deliveryUncertain)
        XCTAssertEqual(
            poster.callCount,
            0,
            "suspension must become visible atomically before the queued transaction can post"
        )
    }

    func test_stableSamePIDAllowsOutputAndDocumentsUnobservableSameProcessCaretRisk() {
        let context = makeContext()

        XCTAssertEqual(
            context.session.applyOpaqueHypothesis("same process", generation: generation, source: .livePacket),
            .insertedFirst
        )

        XCTAssertEqual(context.poster.callCount, 1)
        XCTAssertEqual(context.processProvider.queryCount, 3)
        XCTAssertEqual(context.secureInputProvider.queryCount, 3)
    }

    func test_systemFactoryCapturedSessionUsesSuppliedPIDAndValidatesTwiceBeforeOnceAfterPost() {
        let poster = FakeUnicodeEventPoster(results: [])
        let secureInput = FakeAppendSecureInputStateProvider(states: [false, false, false])
        let processProvider = FakeAppendFrontmostProcessProvider(
            processIdentifiers: [boundProcessIdentifier, boundProcessIdentifier, boundProcessIdentifier]
        )
        let activationMonitor = FakeActivationMonitor()
        let factory = SystemCurrentFocusProvisionalOutputSessionFactory(
            eventPoster: poster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: processProvider,
            activationMonitorFactory: { activationMonitor }
        )
        var validationCallCount = 0

        let session = factory.makeSession(
            generation: generation,
            boundProcessIdentifier: boundProcessIdentifier,
            validateBoundDestination: {
                validationCallCount += 1
                return .valid
            }
        )
        let outcome = session?.applyOpaqueHypothesis(
            "captured target",
            generation: generation,
            source: .livePacket
        )

        XCTAssertEqual(outcome, .insertedFirst)
        XCTAssertEqual(validationCallCount, 3, "captured validation must run twice before and once after posting")
        XCTAssertEqual(poster.requestedTexts, ["captured target"])
        XCTAssertEqual(poster.destinationProcessIdentifiers, [boundProcessIdentifier])
        XCTAssertEqual(processProvider.queryCount, 3)
        XCTAssertEqual(secureInput.queryCount, 3)
    }

    func test_capturedPostflightElementDriftPermanentlySuspendsWithoutLaterFinalPost() {
        let poster = FakeUnicodeEventPoster(results: [])
        let secureInput = FakeAppendSecureInputStateProvider(
            states: Array(repeating: false, count: 10)
        )
        let processProvider = FakeAppendFrontmostProcessProvider(
            processIdentifiers: Array(repeating: boundProcessIdentifier, count: 10)
        )
        let activationMonitor = FakeActivationMonitor()
        let factory = SystemCurrentFocusProvisionalOutputSessionFactory(
            eventPoster: poster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: processProvider,
            activationMonitorFactory: { activationMonitor }
        )
        var validations: [CurrentFocusBoundDestinationValidation] = [
            .valid,
            .valid,
            .destinationChanged
        ]
        let session = factory.makeSession(
            generation: generation,
            boundProcessIdentifier: boundProcessIdentifier,
            validateBoundDestination: {
                guard !validations.isEmpty else { return .valid }
                return validations.removeFirst()
            }
        )

        let first = session?.applyOpaqueHypothesis(
            "visible",
            generation: generation,
            source: .livePacket
        )
        let late = session?.applyOpaqueHypothesis(
            "visible extension",
            generation: generation,
            source: .livePacket
        )
        let final = session?.finalize(
            finalText: "visible final",
            lastAcceptedText: "visible extension",
            generation: generation
        )

        XCTAssertEqual(first, .destinationChanged)
        XCTAssertEqual(late, .destinationChanged)
        XCTAssertEqual(final, .preservedDestinationLoss)
        XCTAssertEqual(poster.requestedTexts, ["visible"])
        XCTAssertEqual(poster.destinationProcessIdentifiers, [boundProcessIdentifier])
    }

    func test_capturedPostflightSecureInputPermanentlySuspendsWithoutLaterFinalPost() {
        let poster = FakeUnicodeEventPoster(results: [])
        let secureInput = FakeAppendSecureInputStateProvider(states: [false, false, true])
        let processProvider = FakeAppendFrontmostProcessProvider(
            processIdentifiers: Array(repeating: boundProcessIdentifier, count: 10)
        )
        let activationMonitor = FakeActivationMonitor()
        let factory = SystemCurrentFocusProvisionalOutputSessionFactory(
            eventPoster: poster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: processProvider,
            activationMonitorFactory: { activationMonitor }
        )
        var validationCallCount = 0
        let session = factory.makeSession(
            generation: generation,
            boundProcessIdentifier: boundProcessIdentifier,
            validateBoundDestination: {
                validationCallCount += 1
                return .valid
            }
        )

        let first = session?.applyOpaqueHypothesis(
            "visible",
            generation: generation,
            source: .livePacket
        )
        let late = session?.applyOpaqueHypothesis(
            "visible extension",
            generation: generation,
            source: .livePacket
        )
        let final = session?.finalize(
            finalText: "visible final",
            lastAcceptedText: "visible extension",
            generation: generation
        )

        XCTAssertEqual(first, .securityRejected)
        XCTAssertEqual(late, .securityRejected)
        XCTAssertEqual(final, .preservedSecurityRejection)
        XCTAssertEqual(validationCallCount, 2)
        XCTAssertEqual(poster.requestedTexts, ["visible"])
        XCTAssertEqual(poster.destinationProcessIdentifiers, [boundProcessIdentifier])
    }

    func test_posterFailureOrSecurityUncertaintyNeverResendsPayload() {
        for posterResult in [FinalTextCurrentFocusPostResult.deliveryFailed, .securityRejected] {
            let context = makeContext(posterResults: [posterResult, .posted])

            let first = context.session.applyOpaqueHypothesis(
                "uncertain",
                generation: generation,
                source: .livePacket
            )
            let retry = context.session.applyOpaqueHypothesis(
                "uncertain",
                generation: generation,
                source: .replayCatchUp
            )

            XCTAssertEqual(
                first,
                posterResult == .securityRejected ? .securityRejected : .deliveryUncertain
            )
            XCTAssertEqual(
                retry,
                posterResult == .securityRejected ? .securityRejected : .deliveryUncertain
            )
            XCTAssertEqual(context.poster.callCount, 1)
        }
    }

    func test_staleGenerationInvalidateAndLateValuesAreNoOps() {
        let stale = makeContext()
        XCTAssertEqual(
            stale.session.applyOpaqueHypothesis("stale", generation: generation + 1, source: .livePacket),
            .staleGeneration
        )
        XCTAssertEqual(
            stale.session.finalize(
                finalText: "stale final",
                lastAcceptedText: nil,
                generation: generation + 1
            ),
            .staleGeneration
        )
        XCTAssertEqual(stale.poster.callCount, 0)

        let invalidated = makeContext()
        invalidated.session.invalidate()
        XCTAssertEqual(
            invalidated.session.applyOpaqueHypothesis("late", generation: generation, source: .livePacket),
            .staleGeneration
        )
        XCTAssertEqual(
            invalidated.session.finalize(
                finalText: "late final",
                lastAcceptedText: "late accepted",
                generation: generation
            ),
            .staleGeneration
        )
        XCTAssertEqual(invalidated.poster.callCount, 0)
        XCTAssertEqual(invalidated.activationMonitor.stopCallCount, 1)
    }

    func test_finalizeExactIsNoOpAndRepeatedFinalizeAndLateHypothesisCannotWrite() {
        let context = makeContext()
        _ = context.session.applyOpaqueHypothesis("visible", generation: generation, source: .livePacket)

        let first = context.session.finalize(
            finalText: "visible",
            lastAcceptedText: "visible",
            generation: generation
        )
        let repeated = context.session.finalize(
            finalText: "visible extension",
            lastAcceptedText: "visible extension",
            generation: generation
        )
        let late = context.session.applyOpaqueHypothesis(
            "visible extension",
            generation: generation,
            source: .livePacket
        )

        XCTAssertEqual(first, .exactCommitted)
        XCTAssertEqual(repeated, .staleGeneration)
        XCTAssertEqual(late, .staleGeneration)
        assertPosted(["visible"], by: context.poster)
        XCTAssertEqual(context.activationMonitor.stopCallCount, 1)
    }

    func test_finalizeNeverPostsAReleaseTimeExtension() {
        let context = makeContext()
        _ = context.session.applyOpaqueHypothesis("base", generation: generation, source: .livePacket)

        _ = context.session.finalize(
            finalText: "base final",
            lastAcceptedText: "base final",
            generation: generation
        )
        assertPosted(["base"], by: context.poster)
    }

    func test_finalizeRevisionOrShorteningPreservesEmittedTextWithoutRecoveryOutput() {
        for finalText in ["revise", "vis"] {
            let context = makeContext()
            _ = context.session.applyOpaqueHypothesis("visible", generation: generation, source: .livePacket)

            XCTAssertEqual(
                context.session.finalize(
                    finalText: finalText,
                    lastAcceptedText: "visible",
                    generation: generation
                ),
                .preservedDivergence
            )
            assertPosted(["visible"], by: context.poster)
        }
    }

    func test_finalizeEmptyPreservesEmittedAndNeverCreatesFirstOutput() {
        let emitted = makeContext()
        _ = emitted.session.applyOpaqueHypothesis("visible", generation: generation, source: .livePacket)
        XCTAssertEqual(
            emitted.session.finalize(
                finalText: nil,
                lastAcceptedText: "visible",
                generation: generation
            ),
            .exactCommitted
        )
        assertPosted(["visible"], by: emitted.poster)

        let fallback = makeContext()
        _ = fallback.session.finalize(
            finalText: "",
            lastAcceptedText: "accepted",
            generation: generation
        )
        XCTAssertEqual(fallback.poster.callCount, 0)

        let empty = makeContext()
        XCTAssertEqual(
            empty.session.finalize(finalText: nil, lastAcceptedText: nil, generation: generation),
            .noUsableText
        )
        XCTAssertEqual(empty.poster.callCount, 0)
    }

    func test_finalizePreservesTypedDestinationSecurityAndDeliveryUncertainty() {
        let destination = makeContext(processIdentifiers: [9999])
        _ = destination.session.applyOpaqueHypothesis("candidate", generation: generation, source: .livePacket)
        XCTAssertEqual(
            destination.session.finalize(
                finalText: "candidate",
                lastAcceptedText: "candidate",
                generation: generation
            ),
            .preservedDestinationLoss
        )

        let security = makeContext(secureInputStates: [true])
        _ = security.session.applyOpaqueHypothesis("candidate", generation: generation, source: .livePacket)
        XCTAssertEqual(
            security.session.finalize(
                finalText: "candidate",
                lastAcceptedText: "candidate",
                generation: generation
            ),
            .preservedSecurityRejection
        )

        let delivery = makeContext(posterResults: [.deliveryFailed])
        _ = delivery.session.applyOpaqueHypothesis("candidate", generation: generation, source: .livePacket)
        XCTAssertEqual(
            delivery.session.finalize(
                finalText: "candidate",
                lastAcceptedText: "candidate",
                generation: generation
            ),
            .deliveryUncertain
        )
    }

    func test_outcomeDescriptionsAreTypedAndTranscriptFree() {
        let marker = "PRIVATE_TRANSCRIPT_MARKER"
        let context = makeContext()
        let apply = context.session.applyOpaqueHypothesis(marker, generation: generation, source: .livePacket)
        let final = context.session.finalize(
            finalText: marker,
            lastAcceptedText: marker,
            generation: generation
        )

        XCTAssertFalse(String(describing: apply).contains(marker))
        XCTAssertFalse(String(describing: final).contains(marker))
    }

    private func assertSecuritySuspension(_ context: TestContext) {
        let first = context.session.applyOpaqueHypothesis(
            "candidate",
            generation: generation,
            source: .livePacket
        )
        let late = context.session.applyOpaqueHypothesis(
            "candidate extension",
            generation: generation,
            source: .livePacket
        )

        XCTAssertEqual(first, .securityRejected)
        XCTAssertEqual(late, .securityRejected)
        XCTAssertLessThanOrEqual(context.poster.callCount, 1)
    }

    private func assertPosted(
        _ expected: [String],
        by poster: FakeUnicodeEventPoster,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            poster.requestedTexts == expected,
            "direct Unicode payload sequence differed from the opaque contract",
            file: file,
            line: line
        )
    }

    private func makeContext(
        processIdentifiers: [pid_t?]? = nil,
        secureInputStates: [Bool]? = nil,
        posterResults: [FinalTextCurrentFocusPostResult] = [],
        inputMonitorArmFailure: TestInputMonitorArmFailure? = nil,
        inputMonitorInitialEpoch: UInt64 = 0,
        injectPhysicalInputAtArmBoundary: Bool = false
    ) -> TestContext {
        let processProvider = FakeAppendFrontmostProcessProvider(
            processIdentifiers: processIdentifiers ?? Array(repeating: boundProcessIdentifier, count: 30)
        )
        let secureInputProvider = FakeAppendSecureInputStateProvider(
            states: secureInputStates ?? Array(repeating: false, count: 30)
        )
        let poster = FakeUnicodeEventPoster(results: posterResults)
        let activationMonitor = FakeActivationMonitor()
        let inputMonitor = FakeInputMonitor(
            armFailure: inputMonitorArmFailure,
            initialInterferenceEpoch: inputMonitorInitialEpoch,
            injectPhysicalInputAtArmBoundary: injectPhysicalInputAtArmBoundary
        )
        let session = CurrentFocusAppendSession(
            generation: generation,
            boundProcessIdentifier: boundProcessIdentifier,
            eventPoster: poster,
            secureInputStateProvider: secureInputProvider,
            frontmostProcessProvider: processProvider,
            activationMonitor: activationMonitor,
            inputMonitor: inputMonitor
        )
        return TestContext(
            session: session,
            poster: poster,
            secureInputProvider: secureInputProvider,
            processProvider: processProvider,
            activationMonitor: activationMonitor,
            inputMonitor: inputMonitor
        )
    }

    private func makeKeyEvent(
        type: NSEvent.EventType,
        characters: String,
        modifierFlags: NSEvent.ModifierFlags = [],
        keyCode: UInt16
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}

@MainActor
private struct TestContext {
    let session: CurrentFocusAppendSession
    let poster: FakeUnicodeEventPoster
    let secureInputProvider: FakeAppendSecureInputStateProvider
    let processProvider: FakeAppendFrontmostProcessProvider
    let activationMonitor: FakeActivationMonitor
    let inputMonitor: FakeInputMonitor
}

private struct SnapshotReplacementCase {
    let previous: String
    let next: String
    let expectedDeleteCharacterCount: Int
    let expectedInsertText: String
}

private enum TestInputMonitorArmFailure: String {
    case local
    case global
}

private enum TestPreDispatchInputKind: String {
    case physicalKeyDown
    case physicalLeftMouseDown
    case taggedSyntheticKeyDown
    case fnFlagsChanged
    case tapDisabledByTimeout
    case tapDisabledByUserInput
}

private struct ReplacementRequest: Equatable {
    let deleteCharacterCount: Int
    let insertText: String
    let processIdentifier: pid_t
}

private final class ThreadSafeRaceTrace: @unchecked Sendable {
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

private final class TestAtomicInterferenceGate: @unchecked Sendable {
    private let gateLock = NSLock()
    private let stateLock = NSLock()
    private var rawEpoch: UInt64
    private var isHeld = false
    private var pendingCompletion: DispatchSemaphore?

    init(initialEpoch: UInt64) {
        rawEpoch = initialEpoch
    }

    var value: UInt64 {
        gateLock.lock()
        defer { gateLock.unlock() }
        return rawEpoch
    }

    func advance() {
        gateLock.lock()
        rawEpoch &+= 1
        gateLock.unlock()
    }

    func performIfUnchanged(expectedEpoch: UInt64, _ operation: () -> Void) -> Bool {
        gateLock.lock()
        guard rawEpoch == expectedEpoch else {
            gateLock.unlock()
            return false
        }
        setHeld(true)
        operation()
        setHeld(false)
        gateLock.unlock()
        waitForPendingAdvance()
        return true
    }

    func beginPhysicalAdvance(trace: ThreadSafeRaceTrace) {
        let attempted = DispatchSemaphore(value: 0)
        let completed = DispatchSemaphore(value: 0)
        stateLock.lock()
        pendingCompletion = completed
        let held = isHeld
        stateLock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            attempted.signal()
            gateLock.lock()
            rawEpoch &+= 1
            trace.append("physical-epoch-advance")
            gateLock.unlock()
            completed.signal()
        }
        attempted.wait()
        if !held {
            completed.wait()
            stateLock.lock()
            pendingCompletion = nil
            stateLock.unlock()
        }
    }

    func waitForPendingAdvance() {
        stateLock.lock()
        let completion = pendingCompletion
        pendingCompletion = nil
        stateLock.unlock()
        completion?.wait()
    }

    private func setHeld(_ held: Bool) {
        stateLock.lock()
        isHeld = held
        stateLock.unlock()
    }
}

@MainActor
private final class FakeUnicodeEventPoster: FinalTextCurrentFocusEventPosting {
    private var results: [FinalTextCurrentFocusPostResult]
    private(set) var requestedTexts: [String] = []
    private(set) var destinationProcessIdentifiers: [pid_t] = []
    private(set) var replacementRequests: [ReplacementRequest] = []
    private(set) var guardedReplacementCallCount = 0
    private(set) var atomicGuardedReplacementCallCount = 0
    private(set) var destructiveBackspaceCount = 0
    private(set) var insertionPairCount = 0
    var afterFirstGuardedBackspace: (() -> Void)?
    var afterEpochValidationBeforeFirstSyntheticPost: (() -> Void)?
    var raceTrace: ThreadSafeRaceTrace?

    var callCount: Int { requestedTexts.count }

    init(results: [FinalTextCurrentFocusPostResult]) {
        self.results = results
    }

    func postUnicodeText(
        _ text: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult {
        requestedTexts.append(text)
        destinationProcessIdentifiers.append(processIdentifier)
        replacementRequests.append(
            ReplacementRequest(
                deleteCharacterCount: 0,
                insertText: text,
                processIdentifier: processIdentifier
            )
        )
        guard !results.isEmpty else { return .posted }
        return results.removeFirst()
    }

    func postReplacement(
        deleteCharacterCount: Int,
        insertText: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult {
        requestedTexts.append(insertText)
        destinationProcessIdentifiers.append(processIdentifier)
        replacementRequests.append(
            ReplacementRequest(
                deleteCharacterCount: deleteCharacterCount,
                insertText: insertText,
                processIdentifier: processIdentifier
            )
        )
        guard !results.isEmpty else { return .posted }
        return results.removeFirst()
    }

    func postReplacement(
        deleteCharacterCount: Int,
        insertText: String,
        to processIdentifier: pid_t,
        whileInterferenceEpochIsUnchanged: () -> Bool
    ) -> FinalTextCurrentFocusPostResult {
        guardedReplacementCallCount += 1
        for _ in 0..<deleteCharacterCount {
            guard whileInterferenceEpochIsUnchanged() else { return .deliveryFailed }
            if destructiveBackspaceCount == 0 {
                afterEpochValidationBeforeFirstSyntheticPost?()
            }
            raceTrace?.append("synthetic-down")
            raceTrace?.append("synthetic-up")
            destructiveBackspaceCount += 1
            if destructiveBackspaceCount == 1 {
                afterFirstGuardedBackspace?()
            }
        }
        guard whileInterferenceEpochIsUnchanged() else { return .deliveryFailed }
        if !insertText.isEmpty {
            insertionPairCount += 1
        }
        requestedTexts.append(insertText)
        destinationProcessIdentifiers.append(processIdentifier)
        replacementRequests.append(
            ReplacementRequest(
                deleteCharacterCount: deleteCharacterCount,
                insertText: insertText,
                processIdentifier: processIdentifier
            )
        )
        guard !results.isEmpty else { return .posted }
        return results.removeFirst()
    }

    func postReplacement(
        deleteCharacterCount: Int,
        insertText: String,
        to processIdentifier: pid_t,
        postCompleteSyntheticPairIfInterferenceEpochIsUnchanged: ((_ postPair: () -> Void) -> Bool)
    ) -> FinalTextCurrentFocusPostResult {
        atomicGuardedReplacementCallCount += 1
        for _ in 0..<deleteCharacterCount {
            let posted = postCompleteSyntheticPairIfInterferenceEpochIsUnchanged {
                if destructiveBackspaceCount == 0 {
                    afterEpochValidationBeforeFirstSyntheticPost?()
                }
                raceTrace?.append("synthetic-down")
                raceTrace?.append("synthetic-up")
                destructiveBackspaceCount += 1
            }
            guard posted else { return .deliveryFailed }
        }
        if !insertText.isEmpty {
            let posted = postCompleteSyntheticPairIfInterferenceEpochIsUnchanged {
                raceTrace?.append("synthetic-down")
                raceTrace?.append("synthetic-up")
                insertionPairCount += 1
            }
            guard posted else { return .deliveryFailed }
        }
        requestedTexts.append(insertText)
        destinationProcessIdentifiers.append(processIdentifier)
        replacementRequests.append(
            ReplacementRequest(
                deleteCharacterCount: deleteCharacterCount,
                insertText: insertText,
                processIdentifier: processIdentifier
            )
        )
        guard !results.isEmpty else { return .posted }
        return results.removeFirst()
    }

    func resetTransactionTracking() {
        requestedTexts = []
        destinationProcessIdentifiers = []
        replacementRequests = []
        guardedReplacementCallCount = 0
        atomicGuardedReplacementCallCount = 0
        destructiveBackspaceCount = 0
        insertionPairCount = 0
    }
}

@MainActor
private final class FakeAppendSecureInputStateProvider: SecureInputStateProviding {
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
private final class FakeAppendFrontmostProcessProvider: FrontmostProcessProviding {
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

@MainActor
private final class FakeActivationMonitor: CurrentFocusActivationMonitoring {
    private var handler: (@MainActor (pid_t) -> Void)?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func startMonitoring(_ handler: @escaping @MainActor (pid_t) -> Void) {
        startCallCount += 1
        self.handler = handler
    }

    func stopMonitoring() {
        stopCallCount += 1
        handler = nil
    }

    func activate(processIdentifier: pid_t) {
        handler?(processIdentifier)
    }
}

@MainActor
private final class FakeInputMonitor: CurrentFocusInputMonitoring {
    private let armFailure: TestInputMonitorArmFailure?
    private let atomicGate: TestAtomicInterferenceGate
    private let injectPhysicalInputAtArmBoundary: Bool
    private var handler: (@MainActor () -> Void)?
    private var advanceEpochOnNextSeparateRead = false
    private(set) var startCallCount = 0
    private(set) var failClosedArmCallCount = 0
    private(set) var failClosedArmWithEpochCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var isCompletelyArmed = false
    private(set) var interferenceEpochReadCount = 0

    init(
        armFailure: TestInputMonitorArmFailure? = nil,
        initialInterferenceEpoch: UInt64 = 0,
        injectPhysicalInputAtArmBoundary: Bool = false
    ) {
        self.armFailure = armFailure
        atomicGate = TestAtomicInterferenceGate(initialEpoch: initialInterferenceEpoch)
        self.injectPhysicalInputAtArmBoundary = injectPhysicalInputAtArmBoundary
    }

    var rawInterferenceEpoch: UInt64 { atomicGate.value }

    var interferenceEpoch: UInt64 {
        interferenceEpochReadCount += 1
        if advanceEpochOnNextSeparateRead {
            advanceEpochOnNextSeparateRead = false
            atomicGate.advance()
        }
        return atomicGate.value
    }

    func startMonitoring(_ handler: @escaping @MainActor () -> Void) {
        startCallCount += 1
        isCompletelyArmed = armFailure == nil
        if isCompletelyArmed {
            self.handler = handler
        }
    }

    func armMonitoringFailClosed(_ handler: @escaping @MainActor () -> Void) -> Bool {
        failClosedArmCallCount += 1
        isCompletelyArmed = armFailure == nil
        if isCompletelyArmed {
            self.handler = handler
            advanceEpochOnNextSeparateRead = injectPhysicalInputAtArmBoundary
        }
        return isCompletelyArmed
    }

    func armMonitoringFailClosedWithEpoch(
        _ handler: @escaping @MainActor () -> Void
    ) -> UInt64? {
        failClosedArmWithEpochCallCount += 1
        guard armFailure == nil else { return nil }
        isCompletelyArmed = true
        self.handler = handler
        let armedEpoch = atomicGate.value
        if injectPhysicalInputAtArmBoundary {
            atomicGate.advance()
        }
        return armedEpoch
    }

    func postCompleteSyntheticPairIfInterferenceEpochIsUnchanged(
        expectedEpoch: UInt64,
        _ postPair: () -> Void
    ) -> Bool {
        atomicGate.performIfUnchanged(expectedEpoch: expectedEpoch, postPair)
    }

    func stopMonitoring() {
        stopCallCount += 1
        handler = nil
        isCompletelyArmed = false
    }

    func receiveExternalInput() {
        handler?()
    }

    func receivePreDispatchCGEventTap(
        _ input: TestPreDispatchInputKind,
        deliverAppKitGlobalMonitorCallback: Bool = true
    ) {
        switch input {
        case .physicalKeyDown, .physicalLeftMouseDown,
             .tapDisabledByTimeout, .tapDisabledByUserInput:
            atomicGate.advance()
            if deliverAppKitGlobalMonitorCallback {
                handler?()
            }
        case .taggedSyntheticKeyDown, .fnFlagsChanged:
            break
        }
    }

    func beginPhysicalAdvanceDuringPosting(trace: ThreadSafeRaceTrace) {
        atomicGate.beginPhysicalAdvance(trace: trace)
    }

    func waitForPendingPhysicalAdvance() {
        atomicGate.waitForPendingAdvance()
    }
}
