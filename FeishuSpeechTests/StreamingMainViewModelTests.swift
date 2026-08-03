import Foundation
import ApplicationServices
import Combine
import XCTest
import os.log
@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "StreamingMainViewModelTests"
)

@MainActor
final class StreamingMainViewModelTests: XCTestCase {
    override func tearDown() async throws {
        HotKeyService.shared.resetToIdle()
        PermissionManager.shared.resetStateForTesting()
        try await super.tearDown()
    }

    func test_secureTargetIsRejectedBeforeAudioOrStreamingProviderStarts() async {
        let context = makeContext(capability: .secureRejected)
        let identity = StreamingSessionIdentity(generation: 101)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await settle()

        XCTAssertEqual(context.accessibility.captureCount, 1)
        XCTAssertEqual(context.recorder.startStreamingCallCount, 0)
        let makeSessionCallCount = await context.provider.makeSessionCallCount
        XCTAssertEqual(makeSessionCallCount, 0)
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertFalse(containsTranscript(context.viewModel, transcript: "PRIVATE_TRANSCRIPT"))
    }

    func test_liveModeReplacesPartialAndFinalOnCapturedElementOnly() async throws {
        let context = makeContext(
            capability: .live,
            packetEvents: [.partial("PRIVATE_PARTIAL")],
            finishEvent: .final("PRIVATE_FINAL")
        )
        context.accessibility.returnedWriteLengths = [31, 47]
        let identity = StreamingSessionIdentity(generation: 102)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x11, count: 6_400))
        await waitUntil { await context.session.sendCallCount == 1 }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { await context.session.finishCallCount == 1 }

        XCTAssertEqual(context.accessibility.setSelectedTextCalls, ["PRIVATE_PARTIAL", "PRIVATE_FINAL"])
        XCTAssertEqual(context.accessibility.captureCount, 1)
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertFalse(containsTranscript(context.viewModel, transcript: "PRIVATE_PARTIAL"))
        XCTAssertFalse(containsTranscript(context.viewModel, transcript: "PRIVATE_FINAL"))
    }

    func test_releaseWhileFirstPacketHTTPIsInFlightFlushesTailFromIngressEmissionState() async {
        let context = makeContext(
            capability: .finalOnly,
            packetEvents: [.partial("first accepted response")],
            finishEvent: .final("safe final"),
            holdFirstPacketResponse: true
        )
        let identity = StreamingSessionIdentity(generation: 121)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x21, count: 6_400))
        await waitUntil { await context.session.sendCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x22, count: 4_001))

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { context.recorder.stopStreamingCallCount == 1 }
        await context.session.releaseFirstPacketResponse()
        await waitUntil { await context.session.finishCallCount == 1 }

        let packetByteCounts = await context.session.packetByteCounts
        XCTAssertEqual(
            packetByteCounts,
            [6_400, 4_001],
            "normal release must retain the queued tail once ingress emitted the first full packet"
        )
    }

    func test_finalOnlyCurrentDestinationInsertsFinalExactlyOnce() async {
        let context = makeContext(
            capability: .finalOnly,
            packetEvents: [.partial("PRIVATE_PARTIAL")],
            finishEvent: .final("PRIVATE_FINAL")
        )
        let identity = StreamingSessionIdentity(generation: 103)

        await runOnePacketInteraction(context, identity: identity)
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { await context.session.finishCallCount == 1 }

        XCTAssertEqual(context.output.insertedTexts, ["PRIVATE_FINAL"])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
        XCTAssertEqual(context.recorder.stopStreamingCallCount, 1)
    }

    func test_finalOnlyStaleDestinationCopiesForRecoveryWithoutSyntheticInsertion() async {
        let context = makeContext(
            capability: .finalOnly,
            packetEvents: [.partial("PRIVATE_PARTIAL")],
            finishEvent: .final("PRIVATE_FINAL")
        )
        let identity = StreamingSessionIdentity(generation: 104)

        await runOnePacketInteraction(context, identity: identity)
        context.accessibility.currentProcessIdentifier = 99
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { await context.session.finishCallCount == 1 }

        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, ["PRIVATE_FINAL"])
        XCTAssertEqual(context.output.syntheticInputCallCount, 0)
        XCTAssertFalse(containsTranscript(context.viewModel, transcript: "PRIVATE_FINAL"))
    }

    func test_finalOnlyActionCapableControlCharactersDowngradeToCopyOnly() async {
        let unsafeFinals = [
            "safe text\r",
            "safe text\n",
            "safe text\t",
            "safe text\u{001B}",
            "safe text\u{0000}"
        ]

        for (offset, unsafeFinal) in unsafeFinals.enumerated() {
            let context = makeContext(
                capability: .finalOnly,
                packetEvents: [.partial("safe partial")],
                finishEvent: .final(unsafeFinal)
            )
            let identity = StreamingSessionIdentity(generation: UInt64(130 + offset))

            await runOnePacketInteraction(context, identity: identity)
            context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
            await waitUntil { context.viewModel.status == .idle }

            XCTAssertEqual(context.output.insertedTexts, [])
            XCTAssertEqual(context.output.syntheticInputCallCount, 0)
            XCTAssertEqual(
                context.output.copiedTexts,
                [unsafeFinal],
                "action-capable control characters must require manual recovery"
            )
        }
    }

    func test_finalOnlyDeliveryRechecksCapturedDestinationAfterSafePlainTextInsertion() async {
        let context = makeContext(
            capability: .finalOnly,
            packetEvents: [.partial("safe partial")],
            finishEvent: .final("safe plain final")
        )
        let identity = StreamingSessionIdentity(generation: 140)
        context.output.onInsertOnce = {
            context.accessibility.currentFocusedElement = AXUIElementCreateApplication(99)
        }

        await runOnePacketInteraction(context, identity: identity)
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { context.viewModel.status == .idle }

        XCTAssertEqual(
            context.output.insertedTexts,
            ["safe plain final"],
            "D-25-01 retains automatic fallback for safe plain text"
        )
        XCTAssertEqual(context.output.destinationProcessIdentifiers, [42])
        XCTAssertEqual(
            context.output.copiedTexts,
            ["safe plain final"],
            "an uncertain post-delivery destination must retain manual recovery"
        )
        XCTAssertGreaterThanOrEqual(
            context.accessibility.frontmostProcessQueryCount,
            2,
            "the destination must be rechecked after the delivery attempt"
        )
        XCTAssertGreaterThanOrEqual(context.accessibility.focusedElementQueryCount, 2)
    }

    func test_finalOnlySecurityRecheckFailsClosedBeforeAnyOutput() async {
        enum SecurityChange {
            case secure
            case unverifiable
            case queryFailure
        }

        for (offset, change) in [
            SecurityChange.secure,
            .unverifiable,
            .queryFailure
        ].enumerated() {
            let context = makeContext(
                capability: .finalOnly,
                packetEvents: [.partial("PRIVATE_PARTIAL")],
                finishEvent: .final("PRIVATE_FINAL")
            )
            let identity = StreamingSessionIdentity(generation: UInt64(160 + offset))
            await runOnePacketInteraction(context, identity: identity)

            switch change {
            case .secure:
                context.accessibility.currentSecurityState = .secure
            case .unverifiable:
                context.accessibility.currentSecurityState = .unverifiable
            case .queryFailure:
                context.accessibility.securityStateError = .cannotComplete
            }

            context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
            await waitUntil { context.viewModel.status == .idle }

            XCTAssertEqual(context.output.insertedTexts, [])
            XCTAssertEqual(context.output.copiedTexts, [])
            XCTAssertEqual(context.output.syntheticInputCallCount, 0)
            XCTAssertFalse(containsTranscript(context.viewModel, transcript: "PRIVATE_FINAL"))
        }
    }

    func test_autoInsertFalseStillRejectsSecureTargetAndOtherwisePerformsNoTargetOrFinalOutput() async {
        let secure = makeContext(capability: .secureRejected, autoInsert: false)
        secure.viewModel.handleHotKeyStateForTesting(
            .streaming(sessionID: StreamingSessionIdentity(generation: 105))
        )
        await settle()
        XCTAssertEqual(secure.recorder.startStreamingCallCount, 0)
        let secureProviderCallCount = await secure.provider.makeSessionCallCount
        XCTAssertEqual(secureProviderCallCount, 0)

        let ordinary = makeContext(
            capability: .live,
            autoInsert: false,
            packetEvents: [.partial("PRIVATE_PARTIAL")],
            finishEvent: .final("PRIVATE_FINAL")
        )
        let identity = StreamingSessionIdentity(generation: 106)
        await runOnePacketInteraction(ordinary, identity: identity)
        ordinary.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { await ordinary.session.finishCallCount == 1 }

        XCTAssertEqual(ordinary.accessibility.setSelectedTextCalls, [])
        XCTAssertEqual(ordinary.output.insertedTexts, [])
        XCTAssertEqual(ordinary.output.copiedTexts, [])
    }

    func test_releaseAndDurationCapRaceStopsAndFinishesExactlyOnce() async {
        let context = makeContext(
            capability: .finalOnly,
            packetEvents: [.partial("partial")],
            finishEvent: .final("final")
        )
        let identity = StreamingSessionIdentity(generation: 107)
        await runOnePacketInteraction(context, identity: identity)
        HotKeyService.shared.forceState(.streaming(sessionID: identity))

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        context.viewModel.handleMaxDurationReachedForTesting()
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { await context.session.finishCallCount == 1 }

        XCTAssertEqual(context.recorder.stopStreamingCallCount, 1)
        let finishCallCount = await context.session.finishCallCount
        XCTAssertEqual(finishCallCount, 1)
        XCTAssertEqual(context.output.insertedTexts, ["final"])
    }

    func test_emptyFinalAndStreamFailurePreserveVerifiedPartial() async {
        for terminalEvent in [
            StreamingRecognitionEvent.final(""),
            StreamingRecognitionEvent.final("  \n  "),
            StreamingRecognitionEvent.failed(.network)
        ] {
            let context = makeContext(
                capability: .live,
                packetEvents: [.partial("PRIVATE_VISIBLE_PARTIAL")],
                finishEvent: terminalEvent
            )
            context.accessibility.returnedWriteLengths = [29]
            let identity = StreamingSessionIdentity(
                generation: terminalEvent == .final("") ? 108 : 109
            )

            await runOnePacketInteraction(context, identity: identity)
            context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
            await waitUntil { await context.session.finishCallCount == 1 }

            XCTAssertEqual(context.accessibility.rangeText, "PRIVATE_VISIBLE_PARTIAL")
            XCTAssertEqual(context.accessibility.setSelectedTextCalls, ["PRIVATE_VISIBLE_PARTIAL"])
            XCTAssertEqual(context.output.insertedTexts, [])
            XCTAssertEqual(context.output.copiedTexts, [])
            XCTAssertFalse(containsTranscript(context.viewModel, transcript: "PRIVATE_VISIBLE_PARTIAL"))
        }
    }

    func test_staleCopyAndEmptyFinalPublishTranscriptFreeFeedbackOnRenderedStatusSurface() async {
        let stale = makeContext(
            capability: .finalOnly,
            packetEvents: [.partial("PRIVATE_STALE_PARTIAL")],
            finishEvent: .final("PRIVATE_STALE_FINAL")
        )
        let staleIdentity = StreamingSessionIdentity(generation: 145)
        await runOnePacketInteraction(stale, identity: staleIdentity)
        stale.accessibility.currentProcessIdentifier = 99
        let staleSurface = RenderedStatusSurface(viewModel: stale.viewModel)
        stale.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: staleIdentity))
        await waitUntil { stale.viewModel.status == .idle }

        XCTAssertEqual(stale.output.copiedTexts, ["PRIVATE_STALE_FINAL"])
        assertContainsFixedFeedback(
            staleSurface,
            excludingTranscript: "PRIVATE_STALE_FINAL"
        )

        let empty = makeContext(
            capability: .live,
            packetEvents: [.partial("PRIVATE_VISIBLE_PARTIAL")],
            finishEvent: .final("")
        )
        empty.accessibility.returnedWriteLengths = [23]
        let emptyIdentity = StreamingSessionIdentity(generation: 146)
        await runOnePacketInteraction(empty, identity: emptyIdentity)
        let emptySurface = RenderedStatusSurface(viewModel: empty.viewModel)
        empty.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: emptyIdentity))
        await waitUntil { empty.viewModel.status == .idle }

        XCTAssertEqual(empty.accessibility.rangeText, "PRIVATE_VISIBLE_PARTIAL")
        assertContainsFixedFeedback(
            emptySurface,
            excludingTranscript: "PRIVATE_VISIBLE_PARTIAL"
        )
    }

    func test_completionFeedbackRemainsActuallyPresentedForBoundedReadableIntervalWhileStateReturnsIdle() async throws {
        let stale = makeContext(
            capability: .finalOnly,
            packetEvents: [.partial("PRIVATE_STALE_PARTIAL")],
            finishEvent: .final("PRIVATE_STALE_FINAL")
        )
        let staleIdentity = StreamingSessionIdentity(generation: 170)
        await runOnePacketInteraction(stale, identity: staleIdentity)
        stale.accessibility.currentProcessIdentifier = 99
        stale.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: staleIdentity))
        await waitUntil { stale.viewModel.status == .idle }

        try assertActuallyPresentedCompletionFeedback(
            stale.overlayPresenter,
            expected: .manualRecoveryCopied,
            excludingTranscript: "PRIVATE_STALE_FINAL"
        )

        let empty = makeContext(
            capability: .live,
            packetEvents: [.partial("PRIVATE_VISIBLE_PARTIAL")],
            finishEvent: .final("")
        )
        empty.accessibility.returnedWriteLengths = [23]
        let emptyIdentity = StreamingSessionIdentity(generation: 171)
        await runOnePacketInteraction(empty, identity: emptyIdentity)
        empty.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: emptyIdentity))
        await waitUntil { empty.viewModel.status == .idle }

        try assertActuallyPresentedCompletionFeedback(
            empty.overlayPresenter,
            expected: .emptyFinalPreservedPartial,
            excludingTranscript: "PRIVATE_VISIBLE_PARTIAL"
        )
    }

    func test_resetSleepAndWakeInvalidateGenerationBeforeRecorderAndTransportCleanup() async {
        enum LifecycleAction: CaseIterable {
            case reset
            case sleep
            case wake
        }

        for (offset, action) in LifecycleAction.allCases.enumerated() {
            let context = makeContext(capability: .finalOnly)
            let identity = StreamingSessionIdentity(generation: UInt64(110 + offset))
            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            await waitUntil { await context.provider.makeSessionCallCount == 1 }
            context.recorder.resetTracking()
            context.recorder.onForceCleanup = {
                XCTAssertNil(
                    context.viewModel.activeSessionIdentityForTesting,
                    "generation must be invalid before recorder cleanup for \(action)"
                )
            }

            switch action {
            case .reset:
                await context.viewModel.resetService()
            case .sleep:
                await context.viewModel.handleSystemWillSleep()
            case .wake:
                await context.viewModel.handleSystemDidWake()
            }

            XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
            XCTAssertEqual(context.recorder.forceCleanupCallCount, 1)
            let cancelCallCount = await context.session.cancelCallCount
            XCTAssertEqual(cancelCallCount, 1)
            XCTAssertEqual(context.viewModel.status, .idle)
        }
    }

    func test_secureEventInputActivationInvalidatesAndCancelsBeforeFurtherLiveOrFinalOnlyOutput() async {
        for (offset, capability) in [
            CoordinatorAccessibilityClient.Capability.live,
            CoordinatorAccessibilityClient.Capability.finalOnly
        ].enumerated() {
            PermissionManager.shared.simulateSecureInputState(false)
            let context = makeContext(capability: capability)
            let identity = StreamingSessionIdentity(generation: UInt64(150 + offset))
            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            await waitUntil { await context.provider.makeSessionCallCount == 1 }
            context.recorder.onForceCleanup = {
                XCTAssertNil(
                    context.viewModel.activeSessionIdentityForTesting,
                    "secure-input cleanup must invalidate the generation first"
                )
            }

            PermissionManager.shared.simulateSecureInputState(true)
            await settle(iterations: 50)

            XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
            let cancelCallCount = await context.session.cancelCallCount
            XCTAssertEqual(cancelCallCount, 1)
            XCTAssertEqual(context.recorder.forceCleanupCallCount, 1)

            let lateText = "PRIVATE_AFTER_SECURE_INPUT"
            context.viewModel.handleStreamingEventForTesting(
                capability == .live ? .partial(lateText) : .final(lateText),
                identity: identity
            )
            XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
            XCTAssertEqual(context.output.insertedTexts, [])
            XCTAssertEqual(context.output.copiedTexts, [])

            PermissionManager.shared.simulateSecureInputState(false)
            await context.viewModel.resetService()
        }
    }

    func test_latePartialFinalAndFailureFromInvalidatedGenerationAreNoOps() async {
        let context = makeContext(capability: .live)
        let staleIdentity = StreamingSessionIdentity(generation: 120)
        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: staleIdentity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        await context.viewModel.resetService()

        context.viewModel.handleStreamingEventForTesting(
            .partial("PRIVATE_LATE_PARTIAL"),
            identity: staleIdentity
        )
        context.viewModel.handleStreamingEventForTesting(
            .final("PRIVATE_LATE_FINAL"),
            identity: staleIdentity
        )
        context.viewModel.handleStreamingEventForTesting(
            .failed(.network),
            identity: staleIdentity
        )

        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.viewModel.status, .idle)
        XCTAssertFalse(containsTranscript(context.viewModel, transcript: "PRIVATE_LATE_PARTIAL"))
        XCTAssertFalse(containsTranscript(context.viewModel, transcript: "PRIVATE_LATE_FINAL"))
    }

    private func makeContext(
        capability: CoordinatorAccessibilityClient.Capability,
        autoInsert: Bool = true,
        packetEvents: [StreamingRecognitionEvent] = [],
        finishEvent: StreamingRecognitionEvent = .cancelled,
        holdFirstPacketResponse: Bool = false
    ) -> StreamingCoordinatorContext {
        let recorder = CoordinatorAudioRecorder()
        let session = CoordinatorStreamingSession(
            packetEvents: packetEvents,
            finishEvent: finishEvent,
            holdFirstPacketResponse: holdFirstPacketResponse
        )
        let provider = CoordinatorStreamingProvider(session: session)
        let accessibility = CoordinatorAccessibilityClient(capability: capability)
        let output = CoordinatorFinalTextOutput()
        let overlayPresenter = CoordinatorOverlayPresenter()
        let viewModel = MainViewModel(
            audioRecorder: recorder,
            settings: AppSettings(
                appId: "configured-app",
                appSecret: "configured-secret",
                autoInsert: autoInsert,
                playSound: false
            ),
            hotKeyWakeRecovering: TrackingHotKeyWakeRecoverer(),
            streamingProvider: provider,
            accessibilityClient: accessibility,
            finalTextOutput: output,
            overlayPresenter: overlayPresenter
        )
        recorder.resetTracking()
        return StreamingCoordinatorContext(
            viewModel: viewModel,
            recorder: recorder,
            session: session,
            provider: provider,
            accessibility: accessibility,
            output: output,
            overlayPresenter: overlayPresenter
        )
    }

    private func runOnePacketInteraction(
        _ context: StreamingCoordinatorContext,
        identity: StreamingSessionIdentity
    ) async {
        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x55, count: 6_400))
        await waitUntil { await context.session.sendCallCount == 1 }
    }

    private func containsTranscript(_ viewModel: MainViewModel, transcript: String) -> Bool {
        let surface = String(describing: viewModel.status) + (viewModel.overlayMessage ?? "")
        return surface.contains(transcript)
    }

    private func assertContainsFixedFeedback(
        _ surface: RenderedStatusSurface,
        excludingTranscript transcript: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let lifecycleStates: [RecordingState] = [
            .idle,
            .streaming,
            .finalOnly,
            .sealing,
            .recording,
            .transcribing
        ]
        let feedbackStates = surface.states.filter { state in
            if case .error = state {
                return false
            }
            return !lifecycleStates.contains(state)
        }

        XCTAssertFalse(
            feedbackStates.isEmpty,
            "normal completion must publish a dedicated visible feedback state",
            file: file,
            line: line
        )
        XCTAssertTrue(
            feedbackStates.allSatisfy { !$0.text.contains(transcript) },
            "visible feedback must remain fixed-content and transcript-free",
            file: file,
            line: line
        )
    }

    private func assertActuallyPresentedCompletionFeedback(
        _ presenter: CoordinatorOverlayPresenter,
        expected: RecordingState,
        excludingTranscript transcript: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(presenter.visibleStatus, expected, file: file, line: line)
        XCTAssertEqual(presenter.lastCompletionFeedback, expected, file: file, line: line)
        XCTAssertFalse(expected.text.contains(transcript), file: file, line: line)

        let duration = try XCTUnwrap(
            presenter.lastMinimumVisibleDuration,
            "completion feedback must request a deliberate presentation interval",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            duration,
            1.0,
            "the interval must be long enough for a human to read",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            duration,
            5.0,
            "completion feedback must remain bounded",
            file: file,
            line: line
        )

        presenter.advance(by: max(0, duration - 0.01))
        XCTAssertEqual(presenter.visibleStatus, expected, file: file, line: line)
        presenter.advance(by: 0.02)
        XCTAssertNil(presenter.visibleStatus, file: file, line: line)
    }

    private func waitUntil(_ predicate: @escaping () async -> Bool) async {
        for _ in 0..<200 {
            if await predicate() {
                return
            }
            await Task.yield()
        }
        XCTFail("timed out waiting for streaming coordinator state")
    }

    private func settle(iterations: Int = 10) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }
}

@MainActor
private struct StreamingCoordinatorContext {
    let viewModel: MainViewModel
    let recorder: CoordinatorAudioRecorder
    let session: CoordinatorStreamingSession
    let provider: CoordinatorStreamingProvider
    let accessibility: CoordinatorAccessibilityClient
    let output: CoordinatorFinalTextOutput
    let overlayPresenter: CoordinatorOverlayPresenter
}

@MainActor
private final class RenderedStatusSurface {
    private(set) var states: [RecordingState] = []
    private var cancellable: AnyCancellable?

    init(viewModel: MainViewModel) {
        cancellable = viewModel.$status.sink { [weak self] status in
            self?.states.append(status)
        }
    }
}

@MainActor
private final class CoordinatorOverlayPresenter: RecordingOverlayPresenting {
    private(set) var visibleStatus: RecordingState?
    private(set) var lastCompletionFeedback: RecordingState?
    private(set) var lastMinimumVisibleDuration: TimeInterval?
    private var remainingVisibleDuration: TimeInterval?

    func show(status: RecordingState) {
        visibleStatus = status
        remainingVisibleDuration = nil
    }

    func update(status: RecordingState) {
        visibleStatus = status
    }

    func hide() {
        visibleStatus = nil
        remainingVisibleDuration = nil
    }

    func presentCompletionFeedback(
        _ feedback: RecordingState,
        minimumVisibleDuration: TimeInterval
    ) {
        visibleStatus = feedback
        lastCompletionFeedback = feedback
        lastMinimumVisibleDuration = minimumVisibleDuration
        remainingVisibleDuration = minimumVisibleDuration
    }

    func advance(by elapsed: TimeInterval) {
        guard let remainingVisibleDuration else { return }
        let remaining = remainingVisibleDuration - elapsed
        if remaining <= 0 {
            visibleStatus = nil
            self.remainingVisibleDuration = nil
        } else {
            self.remainingVisibleDuration = remaining
        }
    }
}

private actor CoordinatorStreamingSession: SpeechStreamingSession {
    private var packetEvents: [StreamingRecognitionEvent]
    private let finishEvent: StreamingRecognitionEvent
    private(set) var sendCallCount = 0
    private(set) var finishCallCount = 0
    private(set) var cancelCallCount = 0
    private(set) var packetByteCounts: [Int] = []
    private var holdFirstPacketResponse: Bool
    private var firstPacketContinuation: CheckedContinuation<Void, Never>?

    init(
        packetEvents: [StreamingRecognitionEvent],
        finishEvent: StreamingRecognitionEvent,
        holdFirstPacketResponse: Bool = false
    ) {
        self.packetEvents = packetEvents
        self.finishEvent = finishEvent
        self.holdFirstPacketResponse = holdFirstPacketResponse
    }

    func sendAudioPacket(_ pcm16: Data) async throws -> StreamingRecognitionEvent {
        sendCallCount += 1
        packetByteCounts.append(pcm16.count)
        if holdFirstPacketResponse, sendCallCount == 1 {
            await withCheckedContinuation { continuation in
                firstPacketContinuation = continuation
            }
        }
        guard !packetEvents.isEmpty else { return .partial("") }
        return packetEvents.removeFirst()
    }

    func releaseFirstPacketResponse() {
        holdFirstPacketResponse = false
        firstPacketContinuation?.resume()
        firstPacketContinuation = nil
    }

    func finish() async throws -> StreamingRecognitionEvent {
        finishCallCount += 1
        return finishEvent
    }

    func cancel() async {
        cancelCallCount += 1
    }
}

private actor CoordinatorStreamingProvider: SpeechStreamingSessionProviding {
    private let session: CoordinatorStreamingSession
    private(set) var makeSessionCallCount = 0

    init(session: CoordinatorStreamingSession) {
        self.session = session
    }

    func makeStreamingSession(
        appId: String,
        appSecret: String
    ) async throws -> any SpeechStreamingSession {
        makeSessionCallCount += 1
        return session
    }
}

@MainActor
private final class CoordinatorAudioRecorder: AudioRecorder {
    private var ingress: ByteBoundedAudioIngress?
    private(set) var startStreamingCallCount = 0
    private(set) var stopStreamingCallCount = 0
    private(set) var forceCleanupCallCount = 0
    var onForceCleanup: (() -> Void)?

    override func startStreamingRecording(
        ingress: ByteBoundedAudioIngress,
        completion: @escaping (_ started: Bool) -> Void
    ) -> Bool {
        startStreamingCallCount += 1
        self.ingress = ingress
        isRecording = true
        completion(true)
        return true
    }

    override func stopStreamingRecording(streamEstablished: Bool) async {
        stopStreamingCallCount += 1
        isRecording = false
        ingress?.finish(streamEstablished: streamEstablished)
        ingress = nil
    }

    override func forceCleanup() {
        forceCleanupCallCount += 1
        onForceCleanup?()
        ingress?.fail(.cancelled)
        ingress = nil
        isRecording = false
    }

    func emit(_ data: Data) {
        ingress?.append(data)
    }

    func resetTracking() {
        startStreamingCallCount = 0
        stopStreamingCallCount = 0
        forceCleanupCallCount = 0
        onForceCleanup = nil
    }
}

@MainActor
private final class CoordinatorAccessibilityClient: AccessibilityClient {
    enum Capability: Equatable {
        case live
        case finalOnly
        case secureRejected
    }

    private let capability: Capability
    private let token: CursorDestinationToken
    private(set) var captureCount = 0
    private(set) var frontmostProcessQueryCount = 0
    private(set) var focusedElementQueryCount = 0
    var currentProcessIdentifier: pid_t = 42
    var currentFocusedElement: AXUIElement
    var selectedRange = CursorTextRange(location: 2, length: 0)
    var rangeText = ""
    var returnedWriteLengths: [Int] = []
    var currentSecurityState: DestinationSecurityState = .safe
    var securityStateError: AccessibilityClientError?
    private(set) var setSelectedTextCalls: [String] = []

    init(capability: Capability) {
        self.capability = capability
        let element = AXUIElementCreateApplication(42)
        currentFocusedElement = element
        token = CursorDestinationToken(
            generation: 0,
            processIdentifier: 42,
            element: element,
            originalSelection: selectedRange
        )
    }

    func captureDestination(generation: UInt64) throws -> CursorCapabilityResult {
        captureCount += 1
        let captured = CursorDestinationToken(
            generation: generation,
            processIdentifier: token.processIdentifier,
            element: token.element,
            originalSelection: token.originalSelection
        )
        switch capability {
        case .live:
            return .live(captured)
        case .finalOnly:
            return .finalOnly(captured)
        case .secureRejected:
            return .rejected(.secureTarget)
        }
    }

    func frontmostProcessIdentifier() -> pid_t? {
        frontmostProcessQueryCount += 1
        return currentProcessIdentifier
    }

    func focusedElement() throws -> AXUIElement {
        focusedElementQueryCount += 1
        return currentFocusedElement
    }

    func currentSecurityState(for token: CursorDestinationToken) throws -> DestinationSecurityState {
        if let securityStateError {
            throw securityStateError
        }
        return currentSecurityState
    }

    func selectedTextRange(for token: CursorDestinationToken) throws -> CursorTextRange {
        selectedRange
    }

    func string(for range: CursorTextRange, in token: CursorDestinationToken) throws -> String {
        rangeText
    }

    func setSelectedTextRange(_ range: CursorTextRange, for token: CursorDestinationToken) throws {
        selectedRange = range
    }

    func setSelectedText(_ text: String, for token: CursorDestinationToken) throws {
        setSelectedTextCalls.append(text)
        let replacementStart = selectedRange.location
        let returnedLength = returnedWriteLengths.isEmpty ? text.utf16.count : returnedWriteLengths.removeFirst()
        rangeText = text
        selectedRange = CursorTextRange(location: replacementStart + returnedLength, length: 0)
    }
}

@MainActor
private final class CoordinatorFinalTextOutput: FinalTextOutput {
    private(set) var insertedTexts: [String] = []
    private(set) var copiedTexts: [String] = []
    private(set) var syntheticInputCallCount = 0
    private(set) var destinationProcessIdentifiers: [pid_t] = []
    var onInsertOnce: (() -> Void)?

    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateDestination: () throws -> Bool
    ) -> FinalTextInsertionResult {
        do {
            guard try validateDestination() else {
                return .destinationInvalid
            }
        } catch {
            return .destinationInvalid
        }

        onInsertOnce?()
        insertedTexts.append(text)
        destinationProcessIdentifiers.append(destination.processIdentifier)
        syntheticInputCallCount += 1

        do {
            guard try validateDestination() else {
                return .destinationInvalid
            }
        } catch {
            return .destinationInvalid
        }
        return .inserted
    }

    func copyForManualRecovery(_ text: String) {
        copiedTexts.append(text)
    }
}
