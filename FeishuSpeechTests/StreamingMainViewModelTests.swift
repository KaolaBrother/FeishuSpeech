import ApplicationServices
import Combine
@testable import FeishuSpeech
import Foundation
import os.log
import XCTest

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
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertFalse(containsTranscript(context.viewModel, transcript: "PRIVATE_TRANSCRIPT"))
    }

    func test_axCaptureFailureFallsBackWithoutBlockingCaptureOrStreamingStartup() async {
        for (offset, error) in [
            AccessibilityClientError.noFocusedElement,
            .cannotComplete
        ].enumerated() {
            let context = makeContext(capability: .captureThrows(error))
            let identity = StreamingSessionIdentity(generation: UInt64(180 + offset))

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            await settle(iterations: 50)

            XCTAssertEqual(
                context.recorder.startStreamingCallCount,
                1,
                "\(error) must not block audio capture startup"
            )
            let makeSessionCallCount = await context.provider.makeSessionCallCount
            XCTAssertEqual(
                makeSessionCallCount,
                1,
                "\(error) must not block streaming provider startup"
            )
            XCTAssertFalse(
                visibleFeedback(context.viewModel).contains("无法确认输入位置"),
                "an unavailable AX destination is an unbound fallback, not a startup error"
            )
        }
    }

    func test_accessibilityUnavailableResultFallsBackWithoutBlockingStartup() async {
        let context = makeContext(capability: .accessibilityUnavailable)
        let identity = StreamingSessionIdentity(generation: 182)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await settle(iterations: 50)

        XCTAssertEqual(context.recorder.startStreamingCallCount, 1)
        let makeSessionCallCount = await context.provider.makeSessionCallCount
        XCTAssertEqual(makeSessionCallCount, 1)
        XCTAssertFalse(visibleFeedback(context.viewModel).contains("无法确认输入位置"))
    }

    func test_nonRecoverableProviderTerminalFailureDismissesOverlayAndTearsDownGenerationOnce() async {
        let transcript = "PRIVATE_LATE_AFTER_PROVIDER_FAILURE"
        let context = makeContext(
            capability: .accessibilityUnavailable,
            packetEvents: [.failed(.authentication)]
        )
        let identity = StreamingSessionIdentity(generation: 186)
        context.recorder.onForceCleanup = {
            XCTAssertNil(
                context.viewModel.activeSessionIdentityForTesting,
                "the failed generation must be invalid before recorder teardown"
            )
            XCTAssertNil(
                context.overlayPresenter.visibleStatus,
                "the recording overlay must be dismissed before recorder teardown"
            )
        }

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        XCTAssertEqual(context.overlayPresenter.visibleStatus, .streaming)

        context.recorder.emit(Data(repeating: 0x57, count: 6_400))
        await waitUntil { context.recorder.forceCleanupCallCount >= 1 }
        await settle(iterations: 50)

        XCTAssertNil(context.overlayPresenter.visibleStatus)
        XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
        XCTAssertEqual(
            context.recorder.forceCleanupCallCount,
            1,
            "one terminal provider event must trigger exactly one teardown"
        )
        let cancelCallCount = await context.session.cancelCallCount
        XCTAssertEqual(cancelCallCount, 1)

        context.viewModel.handleStreamingEventForTesting(.partial(transcript), identity: identity)
        context.viewModel.handleStreamingEventForTesting(.final(transcript), identity: identity)
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertFalse(containsTranscript(context.viewModel, transcript: transcript))
    }

    func test_providerAuthFailureUsesFixedPrivateFeedbackAndTearsDownOnce() async {
        let secret = "PRIVATE_AUTH_SECRET PRIVATE_TRANSCRIPT"
        let context = makeContext(
            capability: .accessibilityUnavailable,
            providerError: .authFailed(secret)
        )
        let identity = StreamingSessionIdentity(generation: 187)
        context.recorder.onForceCleanup = {
            XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
            XCTAssertNil(context.overlayPresenter.visibleStatus)
        }

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { context.recorder.forceCleanupCallCount >= 1 }
        await settle(iterations: 50)

        XCTAssertEqual(context.viewModel.status, .error("认证失败，请检查应用凭据"))
        XCTAssertNil(context.overlayPresenter.visibleStatus)
        XCTAssertEqual(context.overlayPresenter.hideCallCount, 1)
        XCTAssertEqual(context.recorder.forceCleanupCallCount, 1)
        let cancelCallCount = await context.session.cancelCallCount
        XCTAssertEqual(cancelCallCount, 0)
        XCTAssertFalse(visibleFeedback(context.viewModel).contains(secret))
        XCTAssertFalse(visibleFeedback(context.viewModel).contains("PRIVATE_TRANSCRIPT"))
    }

    func test_unboundFallbackWithoutContinuousOwnerNeverUsesReleaseTimeFinalOutput() async {
        let context = makeContext(
            capability: .accessibilityUnavailable,
            packetEvents: [.partial("PRIVATE_PARTIAL")],
            finishEvent: .final("PRIVATE_FINAL")
        )
        let identity = StreamingSessionIdentity(generation: 183)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await settle(iterations: 50)
        XCTAssertEqual(
            context.recorder.startStreamingCallCount,
            1,
            "unbound fallback must reach capture startup before final delivery can be exercised"
        )
        guard context.recorder.startStreamingCallCount == 1 else { return }

        context.recorder.emit(Data(repeating: 0x56, count: 6_400))
        await waitUntil { await context.session.sendCallCount == 1 }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { await context.session.finishCallCount == 1 }

        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.recorder.stopStreamingCallCount, 1)
    }

    func test_unboundCurrentFocusReleaseNeverAttemptsDeliveryOrCopies() async {
        let transcript = "PRIVATE_UNBOUND_FINAL"
        let context = makeContext(
            capability: .accessibilityUnavailable,
            packetEvents: [.partial("PRIVATE_PARTIAL")],
            finishEvent: .final(transcript)
        )
        context.output.currentFocusInsertionResult = .deliveryFailed
        let identity = StreamingSessionIdentity(generation: 184)

        await runOnePacketInteraction(context, identity: identity)
        context.viewModel.handleStreamingEventForTesting(
            .final(transcript),
            identity: identity
        )
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { context.viewModel.status == .idle }

        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.output.syntheticInputCallCount, 0)
        XCTAssertNil(context.overlayPresenter.lastCompletionFeedback)
        XCTAssertFalse(
            context.overlayPresenter.visibleStatus?.text.contains(transcript) == true,
            "recovery feedback must remain fixed and transcript-free"
        )
    }

    func test_unboundReleaseDoesNotReachSecurityRejectedOneShotOrCopy() async {
        let transcript = "PRIVATE_SECURE_FINAL"
        let context = makeContext(
            capability: .accessibilityUnavailable,
            packetEvents: [.partial("PRIVATE_PARTIAL")],
            finishEvent: .final(transcript)
        )
        context.output.currentFocusInsertionResult = .securityRejected
        let identity = StreamingSessionIdentity(generation: 185)

        await runOnePacketInteraction(context, identity: identity)
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { context.viewModel.status == .idle }

        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.output.syntheticInputCallCount, 0)
        XCTAssertNotEqual(context.overlayPresenter.lastCompletionFeedback, .manualRecoveryCopied)
    }

    func test_liveModeOffersHeldSnapshotOnCapturedElementAndReleaseOnlyCloses() async throws {
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

        XCTAssertEqual(context.accessibility.setSelectedTextCalls, ["PRIVATE_PARTIAL"])
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

    func test_initialFinalOnlyArmsAppendAndAppliesPartialBeforeReleaseThenOnlyFinalizes() async {
        let context = makeAppendContext(
            capability: .finalOnly,
            autoInsert: true,
            rebindCapability: nil,
            packetEvents: [.partial("PRIVATE_PARTIAL")],
            finishEvent: .final("PRIVATE_PARTIAL"),
            appendFinalOutcomes: [.exactCommitted]
        )
        let identity = StreamingSessionIdentity(generation: 103)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        XCTAssertEqual(context.appendFactory.makeSessionCallCount, 1)

        context.recorder.emit(Data(repeating: 0x11, count: 6_400))
        await waitUntil { await context.transport.sendCallCount == 1 }

        XCTAssertEqual(context.appendSession.appliedTexts, ["PRIVATE_PARTIAL"])
        XCTAssertEqual(context.appendSession.appliedSources, ["live"])
        XCTAssertEqual(context.appendSession.finalizeCallCount, 0)
        XCTAssertEqual(context.recorder.stopStreamingCallCount, 0, "release must not be the first insertion")
        XCTAssertEqual(context.output.syntheticInputCallCount, 0)
        XCTAssertEqual(context.output.copiedTexts, [])

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { await context.transport.finishCallCount == 1 }

        XCTAssertEqual(context.appendSession.finalizeCallCount, 1)
        XCTAssertEqual(context.appendSession.finalTexts, [nil])
        XCTAssertEqual(context.appendSession.lastAcceptedTexts, ["PRIVATE_PARTIAL"])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
        XCTAssertEqual(context.recorder.stopStreamingCallCount, 1)
        XCTAssertEqual(context.output.syntheticInputCallCount, 0, "release must not duplicate provisional output")
    }

    func test_initialFinalOnlyFocusedElementDriftFailsClosedWithoutAppendOrRecoveryOutput() async {
        let context = makeAppendContext(
            capability: .finalOnly,
            autoInsert: true,
            rebindCapability: nil,
            packetEvents: [.partial("PRIVATE_PARTIAL")],
            finishEvent: .final("PRIVATE_FINAL")
        )
        let identity = StreamingSessionIdentity(generation: 104)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        XCTAssertEqual(context.appendFactory.makeSessionCallCount, 1)

        context.accessibility.currentFocusedElement = AXUIElementCreateApplication(99)
        context.recorder.emit(Data(repeating: 0x12, count: 6_400))
        await waitUntil { await context.transport.sendCallCount == 1 }

        XCTAssertEqual(context.appendSession.appliedTexts, [])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.output.syntheticInputCallCount, 0)
        await context.viewModel.resetService()
    }

    func test_finalOnlyActionCapableControlCharactersNeverOutputOrCopyAtRelease() async {
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
            XCTAssertEqual(context.output.copiedTexts, [])
            XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        }
    }

    func test_finalOnlyReleaseDoesNotAttemptInsertionOrDestinationRecheck() async {
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

        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.destinationProcessIdentifiers, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.output.syntheticInputCallCount, 0)
        XCTAssertEqual(context.accessibility.frontmostProcessQueryCount, 0)
        XCTAssertEqual(context.accessibility.focusedElementQueryCount, 0)
    }

    func test_finalOnlySecurityChangesDoNotReopenReleaseOutput() async {
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

    func test_autoInsertFalseUsableHeldResponseThenNonemptyActionTwoCompletesWithoutOutputOrFeedback() async {
        let context = makeContext(
            capability: .live,
            autoInsert: false,
            packetEvents: [.partial("USABLE_HELD_RESPONSE")],
            finishEvent: .final("NONEMPTY_ACTION_TWO")
        )
        let surface = RenderedStatusSurface(viewModel: context.viewModel)
        let identity = StreamingSessionIdentity(generation: 408)

        await runOnePacketInteraction(context, identity: identity)
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { context.viewModel.activeSessionIdentityForTesting == nil }

        let providerCallCount = await context.provider.makeSessionCallCount
        let sendCallCount = await context.session.sendCallCount
        let finishCallCount = await context.session.finishCallCount
        let cancelCallCount = await context.session.cancelCallCount
        XCTAssertEqual(providerCallCount, 1)
        XCTAssertEqual(sendCallCount, 1)
        XCTAssertEqual(finishCallCount, 1)
        XCTAssertEqual(cancelCallCount, 0)
        XCTAssertEqual(context.recorder.startStreamingCallCount, 1)
        XCTAssertEqual(context.recorder.stopStreamingCallCount, 1)
        XCTAssertEqual(context.viewModel.status, .idle)

        context.viewModel.handleStreamingEventForTesting(.partial("LATE_PARTIAL"), identity: identity)
        context.viewModel.handleStreamingEventForTesting(.final("LATE_FINAL"), identity: identity)
        await settle()

        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
        XCTAssertEqual(context.accessibility.rangeText, "")
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.output.syntheticInputCallCount, 0)
        XCTAssertEqual(context.overlayPresenter.completionFeedbacks, [])
        XCTAssertNil(context.overlayPresenter.lastCompletionFeedback)
        XCTAssertNil(context.viewModel.overlayMessage)
        XCTAssertFalse(surface.states.contains(where: isError))
        XCTAssertFalse(surface.states.contains(.emptyFinalPreservedPartial))
        XCTAssertFalse(surface.states.contains(.provisionalOutputPreserved))
        XCTAssertFalse(surface.states.contains(.manualRecoveryCopied))
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
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.syntheticInputCallCount, 0)
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

    func test_staleReleaseAndEmptyFinalNeverCopyAndKeepFeedbackTranscriptFree() async {
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

        XCTAssertEqual(stale.output.copiedTexts, [])
        XCTAssertEqual(stale.overlayPresenter.completionFeedbacks, [])
        XCTAssertFalse(staleSurface.states.contains(where: isError))

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
        XCTAssertFalse(
            emptySurface.states.contains { $0.text.contains("PRIVATE_VISIBLE_PARTIAL") },
            "release-only finalization must not expose the held frontier in feedback"
        )
        XCTAssertNil(empty.overlayPresenter.lastCompletionFeedback)
    }

    func test_noOwnerCompletionFeedbackIsBoundedWhileHeldOwnerNeedsNoReleaseFeedback() async throws {
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

        XCTAssertEqual(stale.overlayPresenter.completionFeedbacks, [])
        XCTAssertNil(stale.overlayPresenter.lastCompletionFeedback)
        XCTAssertNil(stale.overlayPresenter.visibleStatus)

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

        XCTAssertNil(empty.overlayPresenter.lastCompletionFeedback)
        XCTAssertNil(empty.overlayPresenter.visibleStatus)
        XCTAssertFalse(visibleFeedback(empty.viewModel).contains("PRIVATE_VISIBLE_PARTIAL"))
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

    func test_resetDuringHeldSealingRevokesLiveWriterAndCancelsTransportBeforeRecorderBarrier() async {
        let initialText = "PRIVATE_R11_LIVE_INITIAL"
        let latePartial = "PRIVATE_R11_LIVE_LATE_PARTIAL"
        let recorder = CoordinatorAudioRecorder(holdNextStopBarrier: true)
        let session = ReviewControllableStreamingSession(
            packetOutcomes: [
                .event(.partial(initialText)),
                .event(.partial(latePartial))
            ],
            holdSendCallNumber: 2,
            cancelHeldSendOutcome: .event(.partial(latePartial))
        )
        let forbiddenSuccessor = RetryCoordinatorStreamingSession(
            packetEvents: [.partial("PRIVATE_R11_FORBIDDEN_SUCCESSOR")]
        )
        let provider = RetryCoordinatorStreamingProvider(
            factoryErrors: [],
            sessions: [session, forbiddenSuccessor]
        )
        let context = makeReviewContext(
            capability: .live,
            provider: provider,
            recorder: recorder,
            retrySleeper: { _ in }
        )
        let resetCompletion = ReviewAsyncCompletionProbe()
        let oldIdentity = StreamingSessionIdentity(generation: 172)
        let successorIdentity = StreamingSessionIdentity(generation: 173)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: oldIdentity))
        context.recorder.emit(Data(repeating: 0xB1, count: 12_800))
        await waitUntil {
            await session.isHoldingSend &&
                context.accessibility.setSelectedTextCalls == [initialText]
        }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: oldIdentity))
        await waitUntil { recorder.isHoldingStopBarrier }

        let resetTask = Task { @MainActor in
            await context.viewModel.resetService()
            resetCompletion.markCompleted()
        }
        await settle(iterations: 50)
        await session.releaseHeldIfNeeded()
        await settle(iterations: 50)
        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: successorIdentity))
        await settle(iterations: 50)

        let cancelCallCountBeforeBarrier = await session.cancelCallCount
        let providerCallCountBeforeBarrier = await provider.makeSessionCallCount
        XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
        XCTAssertEqual(cancelCallCountBeforeBarrier, 1, "transport abort must not wait for recorder stop")
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [initialText])
        XCTAssertEqual(context.accessibility.rangeText, initialText)
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(providerCallCountBeforeBarrier, 1, "recorder latch must reject a successor")
        XCTAssertEqual(recorder.startStreamingCallCount, 1)
        XCTAssertTrue(recorder.isHoldingStopBarrier)
        XCTAssertEqual(recorder.finishedIngressIdentifiers, [])
        XCTAssertFalse(resetCompletion.completed)
        XCTAssertEqual(context.viewModel.status, .sealing)
        XCTAssertFalse(visibleFeedback(context.viewModel).contains(latePartial))

        recorder.releaseStopBarrier()
        await resetTask.value

        let finalCancelCallCount = await session.cancelCallCount
        XCTAssertTrue(resetCompletion.completed)
        XCTAssertEqual(finalCancelCallCount, 1)
        XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
        XCTAssertEqual(context.viewModel.status, .idle)
        XCTAssertEqual(recorder.finishedIngressIdentifiers, [recorder.startedIngressIdentifiers[0]])

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: successorIdentity))
        await waitUntil { await provider.makeSessionCallCount == 2 }
        await waitUntil { recorder.startStreamingCallCount == 2 }
        XCTAssertEqual(context.viewModel.activeSessionIdentityForTesting, successorIdentity)
        await context.viewModel.resetService()
    }

    func test_hotKeyFailureDuringHeldSealingRevokesAppendWriterAndCancelsTransportBeforeBarrier() async {
        let initialText = "PRIVATE_R11_APPEND_INITIAL"
        let lateFinal = "PRIVATE_R11_APPEND_LATE_FINAL"
        let fixedError = "流式传输失败"
        let recorder = CoordinatorAudioRecorder(holdNextStopBarrier: true)
        let session = ReviewControllableStreamingSession(
            packetOutcomes: [
                .event(.partial(initialText)),
                .event(.final(lateFinal))
            ],
            holdSendCallNumber: 2,
            cancelHeldSendOutcome: .event(.final(lateFinal))
        )
        let forbiddenSuccessor = RetryCoordinatorStreamingSession(
            packetEvents: [.partial("PRIVATE_R11_FORBIDDEN_SUCCESSOR")]
        )
        let provider = RetryCoordinatorStreamingProvider(
            factoryErrors: [],
            sessions: [session, forbiddenSuccessor]
        )
        let appendSession = CoordinatorCurrentFocusAppendSession()
        let appendFactory = CoordinatorCurrentFocusAppendSessionFactory(session: appendSession)
        let context = makeReviewContext(
            capability: .accessibilityUnavailable,
            rebindCapability: .accessibilityUnavailable,
            provider: provider,
            recorder: recorder,
            appendFactory: appendFactory,
            retrySleeper: { _ in }
        )
        let oldIdentity = StreamingSessionIdentity(generation: 174)
        let successorIdentity = StreamingSessionIdentity(generation: 175)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: oldIdentity))
        context.recorder.emit(Data(repeating: 0xB2, count: 12_800))
        await waitUntil {
            await session.isHoldingSend && appendSession.appliedTexts == [initialText]
        }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: oldIdentity))
        await waitUntil { recorder.isHoldingStopBarrier }

        context.viewModel.handleHotKeyStateForTesting(.error(fixedError))
        await settle(iterations: 50)
        await session.releaseHeldIfNeeded()
        await settle(iterations: 50)
        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: successorIdentity))
        await settle(iterations: 50)

        let cancelCallCountBeforeBarrier = await session.cancelCallCount
        let providerCallCountBeforeBarrier = await provider.makeSessionCallCount
        XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
        XCTAssertEqual(appendSession.invalidateCallCount, 1)
        XCTAssertEqual(cancelCallCountBeforeBarrier, 1, "transport abort must not wait for recorder stop")
        XCTAssertEqual(appendSession.appliedTexts, [initialText])
        XCTAssertEqual(appendSession.finalizeCallCount, 0)
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(providerCallCountBeforeBarrier, 1, "recorder latch must reject a successor")
        XCTAssertEqual(recorder.startStreamingCallCount, 1)
        XCTAssertTrue(recorder.isHoldingStopBarrier)
        XCTAssertEqual(recorder.finishedIngressIdentifiers, [])
        XCTAssertEqual(context.viewModel.status, .sealing)
        XCTAssertFalse(visibleFeedback(context.viewModel).contains(lateFinal))

        recorder.releaseStopBarrier()
        await waitUntil { context.viewModel.status == .error(fixedError) }
        await waitUntil { await session.cancelCallCount == 1 }

        let finalCancelCallCount = await session.cancelCallCount
        XCTAssertEqual(finalCancelCallCount, 1)
        XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
        XCTAssertEqual(appendSession.invalidateCallCount, 1)
        XCTAssertFalse(visibleFeedback(context.viewModel).contains(lateFinal))
        XCTAssertEqual(recorder.finishedIngressIdentifiers, [recorder.startedIngressIdentifiers[0]])
        await context.viewModel.resetService()
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

    func test_recoverableMidStreamFailureReplaysJournalThenResumesSameGeneration() async {
        let first = RetryCoordinatorStreamingSession(
            packetEvents: [
                .partial("first frontier"),
                .failed(.backend(code: 10024))
            ]
        )
        let replacement = RetryCoordinatorStreamingSession(
            packetEvents: [
                .partial("historical duplicate"),
                .partial("catch-up frontier"),
                .partial("live frontier")
            ]
        )
        let sleeper = ControlledCoordinatorRetrySleeper()
        let context = makeRetryContext(
            capability: .live,
            sessions: [first, replacement],
            sleeper: sleeper
        )
        let identity = StreamingSessionIdentity(generation: 201)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x11, count: 6_400))
        await waitUntil { await first.sendCallCount == 1 }
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, ["first frontier"])

        context.recorder.emit(Data(repeating: 0x22, count: 6_400))
        await waitUntil { await sleeper.callCount == 1 }

        XCTAssertEqual(context.viewModel.activeSessionIdentityForTesting, identity)
        XCTAssertEqual(context.recorder.startStreamingCallCount, 1)
        XCTAssertEqual(context.recorder.forceCleanupCallCount, 0)
        XCTAssertEqual(context.overlayPresenter.hideCallCount, 0)
        let firstCancelCallCount = await first.cancelCallCount
        let providerCallCountBeforeRetry = await context.provider.makeSessionCallCount
        XCTAssertEqual(firstCancelCallCount, 1)
        XCTAssertEqual(providerCallCountBeforeRetry, 1)

        context.recorder.emit(Data(repeating: 0x33, count: 6_400))
        await sleeper.releaseNext()
        await waitUntil { await replacement.sendCallCount == 3 }

        let providerCallCountAfterRetry = await context.provider.makeSessionCallCount
        let replacementPacketFirstBytes = await replacement.packetFirstBytes
        XCTAssertEqual(providerCallCountAfterRetry, 2)
        XCTAssertEqual(replacementPacketFirstBytes, [0x11, 0x22, 0x33])
        XCTAssertEqual(
            context.accessibility.setSelectedTextCalls,
            [
                "first frontier",
                "catch-up frontier",
                "live frontier"
            ],
            "replay must suppress historical indices and offer each newly owned complete snapshot"
        )
        XCTAssertEqual(context.viewModel.activeSessionIdentityForTesting, identity)
        XCTAssertEqual(context.recorder.startStreamingCallCount, 1)
    }

    func test_repeatedRecoverableSessionFactoryFailuresBackOffWithoutEarlyError() async {
        let session = RetryCoordinatorStreamingSession(packetEvents: [.partial("connected")])
        let sleeper = ControlledCoordinatorRetrySleeper()
        let context = makeRetryContext(
            capability: .live,
            factoryErrors: [.networkError("PRIVATE_NETWORK"), .timeout],
            sessions: [session],
            sleeper: sleeper
        )
        let identity = StreamingSessionIdentity(generation: 202)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await sleeper.callCount == 1 }
        XCTAssertFalse(isError(context.viewModel.status))
        XCTAssertEqual(context.recorder.forceCleanupCallCount, 0)
        XCTAssertEqual(context.overlayPresenter.hideCallCount, 0)

        await sleeper.releaseNext()
        await waitUntil { await sleeper.callCount == 2 }
        XCTAssertFalse(isError(context.viewModel.status))
        let retryDelays = await sleeper.delays
        XCTAssertEqual(retryDelays, [250_000_000, 500_000_000])

        await sleeper.releaseNext()
        await waitUntil { await context.provider.makeSessionCallCount == 3 }
        context.recorder.emit(Data(repeating: 0x44, count: 6_400))
        await waitUntil { await session.sendCallCount == 1 }

        XCTAssertEqual(context.accessibility.setSelectedTextCalls, ["connected"])
        XCTAssertEqual(context.recorder.startStreamingCallCount, 1)
        XCTAssertEqual(context.viewModel.activeSessionIdentityForTesting, identity)
    }

    func test_authenticationAndInvalidRequestFailuresAreNotRetried() async {
        for (offset, failure) in [StreamFailure.authentication, .invalidRequest].enumerated() {
            let session = RetryCoordinatorStreamingSession(packetEvents: [.failed(failure)])
            let sleeper = ControlledCoordinatorRetrySleeper()
            let context = makeRetryContext(
                capability: .live,
                sessions: [session],
                sleeper: sleeper
            )
            let identity = StreamingSessionIdentity(generation: UInt64(203 + offset))

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            await waitUntil { await context.provider.makeSessionCallCount == 1 }
            context.recorder.emit(Data(repeating: 0x45, count: 6_400))
            await waitUntil { context.recorder.forceCleanupCallCount == 1 }

            let providerCallCount = await context.provider.makeSessionCallCount
            let sleeperCallCount = await sleeper.callCount
            XCTAssertEqual(providerCallCount, 1)
            XCTAssertEqual(sleeperCallCount, 0)
            XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
            XCTAssertTrue(isError(context.viewModel.status))
        }
    }

    func test_releaseDuringRetryBackoffAdmitsNoSuccessorAndPreservesLatestPartial() async {
        let first = RetryCoordinatorStreamingSession(
            packetEvents: [.partial("preserved frontier"), .failed(.network)]
        )
        let forbiddenSuccessor = RetryCoordinatorStreamingSession(packetEvents: [.partial("LATE")])
        let sleeper = ControlledCoordinatorRetrySleeper()
        let context = makeRetryContext(
            capability: .live,
            sessions: [first, forbiddenSuccessor],
            sleeper: sleeper
        )
        let surface = RenderedStatusSurface(viewModel: context.viewModel)
        let identity = StreamingSessionIdentity(generation: 205)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x51, count: 6_400))
        await waitUntil { await first.sendCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x52, count: 6_400))
        await waitUntil { await sleeper.callCount == 1 }

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await sleeper.releaseNext()
        await settle(iterations: 100)

        let providerCallCount = await context.provider.makeSessionCallCount
        let forbiddenSendCallCount = await forbiddenSuccessor.sendCallCount
        XCTAssertEqual(providerCallCount, 1)
        XCTAssertEqual(forbiddenSendCallCount, 0)
        XCTAssertEqual(context.accessibility.rangeText, "preserved frontier")
        XCTAssertFalse(surface.states.contains(where: isError))
        XCTAssertLessThanOrEqual(context.overlayPresenter.completionFeedbacks.count, 1)
    }

    func test_autoInsertFalseUsableHeldResponseThenRecoverableFailureReleasedDuringBackoffCompletesNormally() async {
        let first = RetryCoordinatorStreamingSession(
            packetEvents: [.partial("USABLE_HELD_RESPONSE"), .failed(.network)]
        )
        let forbiddenSuccessor = RetryCoordinatorStreamingSession(packetEvents: [.partial("LATE")])
        let sleeper = ControlledCoordinatorRetrySleeper()
        let context = makeRetryContext(
            capability: .live,
            autoInsert: false,
            sessions: [first, forbiddenSuccessor],
            sleeper: sleeper
        )
        let surface = RenderedStatusSurface(viewModel: context.viewModel)
        let identity = StreamingSessionIdentity(generation: 409)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xB1, count: 6_400))
        await waitUntil { await first.sendCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xB2, count: 6_400))
        await waitUntil { await sleeper.callCount == 1 }

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await sleeper.releaseNext()
        await waitUntil { context.viewModel.activeSessionIdentityForTesting == nil }

        context.viewModel.handleStreamingEventForTesting(.partial("LATE_PARTIAL"), identity: identity)
        context.viewModel.handleStreamingEventForTesting(.final("LATE_FINAL"), identity: identity)
        await settle()

        let providerCallCount = await context.provider.makeSessionCallCount
        let firstSendCallCount = await first.sendCallCount
        let firstFinishCallCount = await first.finishCallCount
        let firstCancelCallCount = await first.cancelCallCount
        let forbiddenSendCallCount = await forbiddenSuccessor.sendCallCount
        let retryCallCount = await sleeper.callCount
        let retryDelays = await sleeper.delays
        XCTAssertEqual(providerCallCount, 1)
        XCTAssertEqual(firstSendCallCount, 2)
        XCTAssertEqual(firstFinishCallCount, 0)
        XCTAssertEqual(firstCancelCallCount, 1)
        XCTAssertEqual(forbiddenSendCallCount, 0)
        XCTAssertEqual(retryCallCount, 1)
        XCTAssertEqual(retryDelays, [250_000_000])
        XCTAssertEqual(context.recorder.startStreamingCallCount, 1)
        XCTAssertEqual(context.recorder.stopStreamingCallCount, 1)
        XCTAssertEqual(context.viewModel.status, .idle)
        XCTAssertFalse(surface.states.contains(where: isError))

        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
        XCTAssertEqual(context.accessibility.rangeText, "")
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.output.syntheticInputCallCount, 0)
        XCTAssertEqual(context.overlayPresenter.completionFeedbacks, [])
        XCTAssertNil(context.overlayPresenter.lastCompletionFeedback)
        XCTAssertNil(context.viewModel.overlayMessage)
    }

    func test_retryAdmissionIsCancelledByResetSecurityAndLifecycleInvalidation() async {
        enum Invalidation: CaseIterable {
            case reset
            case security
            case sleep
            case wake
        }

        for (offset, invalidation) in Invalidation.allCases.enumerated() {
            PermissionManager.shared.simulateSecureInputState(false)
            let first = RetryCoordinatorStreamingSession(packetEvents: [.failed(.network)])
            let forbiddenSuccessor = RetryCoordinatorStreamingSession(packetEvents: [.partial("LATE")])
            let sleeper = ControlledCoordinatorRetrySleeper()
            let context = makeRetryContext(
                capability: .live,
                sessions: [first, forbiddenSuccessor],
                sleeper: sleeper
            )
            let identity = StreamingSessionIdentity(generation: UInt64(210 + offset))

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            await waitUntil { await context.provider.makeSessionCallCount == 1 }
            context.recorder.emit(Data(repeating: 0x61, count: 6_400))
            await waitUntil { await sleeper.callCount == 1 }

            switch invalidation {
            case .reset:
                await context.viewModel.resetService()
            case .security:
                PermissionManager.shared.simulateSecureInputState(true)
                await waitUntil { context.viewModel.activeSessionIdentityForTesting == nil }
            case .sleep:
                await context.viewModel.handleSystemWillSleep()
            case .wake:
                await context.viewModel.handleSystemDidWake()
            }

            await sleeper.releaseNext()
            await settle(iterations: 100)

            let providerCallCount = await context.provider.makeSessionCallCount
            let forbiddenSendCallCount = await forbiddenSuccessor.sendCallCount
            XCTAssertEqual(providerCallCount, 1, "late retry for \(invalidation)")
            XCTAssertEqual(forbiddenSendCallCount, 0)
            XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
            XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
            PermissionManager.shared.simulateSecureInputState(false)
        }
    }

    func test_unboundFirstPartialRebindsOnceAndReplacesOwnedRangeWithEachSnapshot() async {
        let context = makeContext(
            capability: .accessibilityUnavailable,
            rebindCapability: .live,
            packetEvents: [
                .partial("a longer provisional value"),
                .partial("short"),
                .partial("revised frontier")
            ],
            finishEvent: .final("final frontier")
        )
        let identity = StreamingSessionIdentity(generation: 220)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        for marker in UInt8(0x71)...UInt8(0x73) {
            context.recorder.emit(Data(repeating: marker, count: 6_400))
        }
        await waitUntil { await context.session.sendCallCount == 3 }

        XCTAssertEqual(context.accessibility.captureCount, 2)
        XCTAssertEqual(
            context.accessibility.setSelectedTextCalls,
            [
                "a longer provisional value",
                "short",
                "revised frontier"
            ]
        )
        XCTAssertEqual(context.accessibility.rangeText, "revised frontier")

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { await context.session.finishCallCount == 1 }

        XCTAssertEqual(
            context.accessibility.setSelectedTextCalls.last,
            "revised frontier"
        )
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
    }

    func test_failedUnboundRebindIsAttemptedOnceAndAutoInsertFalseDoesNotRebind() async {
        let failed = makeContext(
            capability: .accessibilityUnavailable,
            rebindCapability: .accessibilityUnavailable,
            packetEvents: [.partial("first"), .partial("second")]
        )
        let failedIdentity = StreamingSessionIdentity(generation: 221)
        failed.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: failedIdentity))
        await waitUntil { await failed.provider.makeSessionCallCount == 1 }
        failed.recorder.emit(Data(repeating: 0x74, count: 12_800))
        await waitUntil { await failed.session.sendCallCount == 2 }
        XCTAssertEqual(failed.accessibility.captureCount, 2)

        let disabled = makeContext(
            capability: .accessibilityUnavailable,
            rebindCapability: .live,
            autoInsert: false,
            packetEvents: [.partial("must not bind")]
        )
        let disabledIdentity = StreamingSessionIdentity(generation: 222)
        disabled.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: disabledIdentity))
        await waitUntil { await disabled.provider.makeSessionCallCount == 1 }
        disabled.recorder.emit(Data(repeating: 0x75, count: 6_400))
        await waitUntil { await disabled.session.sendCallCount == 1 }

        XCTAssertEqual(disabled.accessibility.captureCount, 1)
        XCTAssertEqual(disabled.accessibility.setSelectedTextCalls, [])
        XCTAssertEqual(disabled.output.currentFocusAttemptedTexts, [])
    }

    func test_trulyUnboundModeOffersChangedCompleteSnapshotsBeforeRelease() async {
        let context = makeAppendContext(
            autoInsert: true,
            packetEvents: [
                .partial("first"),
                .partial("first extension"),
                .partial("first extension")
            ],
            finishEvent: .final("first extension final")
        )
        let identity = StreamingSessionIdentity(generation: 230)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x81, count: 19_200))
        await waitUntil { await context.transport.sendCallCount == 3 }

        XCTAssertEqual(
            context.appendSession.appliedTexts,
            ["first", "first extension"]
        )
        XCTAssertEqual(context.appendSession.appliedSources, ["live", "live"])
        XCTAssertEqual(context.appendFactory.makeSessionCallCount, 1)
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.recorder.stopStreamingCallCount, 0, "release must not be first output")

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { await context.transport.finishCallCount == 1 }

        XCTAssertEqual(context.appendSession.finalizeCallCount, 1)
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
    }

    func test_disjointLivePacketResponsesOfferCompleteSnapshotsWhileFnRemainsHeld() async {
        let context = makeProductionCapturedAppendContext(
            route: CoordinatorFinalOnlyRoute(
                capability: .finalOnly,
                rebindCapability: nil,
                generation: 401
            ),
            packetEvents: [
                .partial("one"),
                .partial("two"),
                .partial("three")
            ],
            finishEvent: .cancelled
        )
        let identity = StreamingSessionIdentity(generation: 401)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xB1, count: 19_200))
        await waitUntil { await context.transport.sendCallCount == 3 }

        XCTAssertEqual(
            context.unicodePoster.replacementRequests,
            [
                CoordinatorReplacementRequest(deleteCharacterCount: 0, insertText: "one"),
                CoordinatorReplacementRequest(deleteCharacterCount: 3, insertText: "two"),
                CoordinatorReplacementRequest(deleteCharacterCount: 2, insertText: "hree")
            ],
            "three complete live snapshots must reconcile in response order"
        )
        XCTAssertEqual(
            context.unicodePoster.destinationProcessIdentifiers,
            [42, 42, 42],
            "response assembly must retain the captured PID for every suffix"
        )
        XCTAssertEqual(context.recorder.stopStreamingCallCount, 0, "all advances must occur during the hold")
        XCTAssertEqual(context.output.syntheticInputCallCount, 0)
        XCTAssertEqual(context.output.copiedTexts, [])

        await context.viewModel.resetService()
    }

    func test_equalTextOnDistinctLivePacketIndicesIsOwnedButOfferedOnce() async {
        let context = makeAppendContext(
            autoInsert: true,
            packetEvents: [.partial("same"), .partial("same")],
            finishEvent: .cancelled
        )
        let identity = StreamingSessionIdentity(generation: 402)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xB2, count: 12_800))
        await waitUntil { await context.transport.sendCallCount == 2 }

        XCTAssertEqual(
            context.appendSession.appliedTexts,
            ["same"],
            "packet ownership is independent, but equal complete snapshots must not retype"
        )
        XCTAssertEqual(context.appendSession.appliedSources, ["live"])

        await context.viewModel.resetService()
    }

    func test_distinctLivePacketIndicesOfferOnlyChangedCompleteSnapshots() async {
        let context = makeAppendContext(
            autoInsert: true,
            packetEvents: [
                .partial("hello"),
                .partial("hello"),
                .partial("hello world"),
                .partial("hello"),
                .partial("yellow")
            ],
            finishEvent: .cancelled
        )
        let identity = StreamingSessionIdentity(generation: 4_027)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xC1, count: 32_000))
        await waitUntil { await context.transport.sendCallCount == 5 }

        XCTAssertEqual(
            context.appendSession.appliedTexts,
            ["hello", "hello world", "hello", "yellow"],
            "new packet ownership must not turn equal or changed complete snapshots into concatenated fragments"
        )
        XCTAssertEqual(context.appendSession.appliedSources, ["live", "live", "live", "live"])

        await context.viewModel.resetService()
    }

    func test_retryReplaySuppressesHistoricalPacketsAndReconcilesFirstNewSnapshotOnce() async {
        let first = RetryCoordinatorStreamingSession(
            packetEvents: [.partial("stable"), .failed(.network)]
        )
        let replacement = RetryCoordinatorStreamingSession(
            packetEvents: [
                .partial("changed historical replay"),
                .partial("stable"),
                .partial("revised")
            ]
        )
        let sleeper = ControlledCoordinatorRetrySleeper()
        let context = makeAppendRetryContext(
            sessions: [first, replacement],
            sleeper: sleeper
        )
        let identity = StreamingSessionIdentity(generation: 4_028)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xC2, count: 12_800))
        await waitUntil { await sleeper.callCount == 1 }
        context.recorder.emit(Data(repeating: 0xC3, count: 6_400))

        await sleeper.releaseNext()
        await waitUntil { await replacement.sendCallCount == 3 }

        XCTAssertEqual(
            context.appendSession.appliedTexts,
            ["stable", "revised"],
            "historical replay is packet-suppressed, duplicate recovery snapshots are text-suppressed, and the first changed new index advances once"
        )
        XCTAssertEqual(context.appendSession.appliedSources, ["live", "live"])

        await context.viewModel.resetService()
    }

    func test_releaseSealsSnapshotAdmissionBeforeLatePartialAndFinalCallbacks() async {
        let context = makeAppendContext(
            autoInsert: true,
            packetEvents: [.partial("visible before release")],
            finishEvent: .final("terminal after release")
        )
        let identity = StreamingSessionIdentity(generation: 4_029)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xC4, count: 6_400))
        await waitUntil { await context.transport.sendCallCount == 1 }

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        context.viewModel.handleStreamingEventForTesting(
            .partial("late partial replacement"),
            identity: identity
        )
        context.viewModel.handleStreamingEventForTesting(
            .final("late final replacement"),
            identity: identity
        )
        await waitUntil { context.viewModel.status == .idle }

        XCTAssertEqual(context.appendSession.appliedTexts, ["visible before release"])
        XCTAssertEqual(context.appendSession.finalizeCallCount, 1)
        XCTAssertEqual(context.output.syntheticInputCallCount, 0)
        XCTAssertEqual(context.output.copiedTexts, [])
    }

    func test_releaseDrainsInFlightPacketThenAppliesAuthoritativeFinalOnAXRoute() async {
        let session = ReviewControllableStreamingSession(
            packetOutcomes: [
                .event(.partial("held snapshot")),
                .event(.partial("tail snapshot"))
            ],
            holdSendCallNumber: 2,
            finishOutcome: .event(.final("authoritative final"))
        )
        let provider = RetryCoordinatorStreamingProvider(
            factoryErrors: [],
            sessions: [session]
        )
        let context = makeReviewContext(
            capability: .live,
            provider: provider,
            retrySleeper: { _ in }
        )
        let identity = StreamingSessionIdentity(generation: 4_030)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        context.recorder.emit(Data(repeating: 0xD0, count: 12_800))
        await waitUntil {
            await session.isHoldingSend &&
                context.accessibility.setSelectedTextCalls == ["held snapshot"]
        }

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await session.releaseHeldIfNeeded()
        await waitUntil { context.viewModel.status == .idle }

        XCTAssertEqual(
            context.accessibility.setSelectedTextCalls,
            ["held snapshot", "tail snapshot", "authoritative final"],
            "Fn-up closes capture, but its in-flight packet and action-2 final remain output-eligible"
        )
        let finishCallCount = await session.finishCallCount
        XCTAssertEqual(finishCallCount, 1)

        context.viewModel.handleStreamingEventForTesting(
            .partial("stale after cleanup"),
            identity: identity
        )
        context.viewModel.handleStreamingEventForTesting(
            .final("old-generation final"),
            identity: StreamingSessionIdentity(generation: identity.generation - 1)
        )
        XCTAssertEqual(
            context.accessibility.setSelectedTextCalls,
            ["held snapshot", "tail snapshot", "authoritative final"],
            "true terminal cleanup must still suppress stale and old-generation callbacks"
        )
    }

    func test_releaseFinalizesKeyboardReplacementWithAuthoritativeActionTwoTextExactlyOnce() async {
        let context = makeAppendContext(
            capability: .finalOnly,
            autoInsert: true,
            rebindCapability: nil,
            packetEvents: [.partial("held snapshot")],
            finishEvent: .final("authoritative final"),
            appendFinalOutcomes: [.exactCommitted]
        )
        let identity = StreamingSessionIdentity(generation: 4_031)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xD1, count: 6_400))
        await waitUntil { context.appendSession.appliedTexts == ["held snapshot"] }

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { context.viewModel.status == .idle }

        XCTAssertEqual(context.appendSession.appliedTexts, ["held snapshot"])
        XCTAssertEqual(context.appendSession.finalizeCallCount, 1)
        XCTAssertEqual(
            context.appendSession.finalTexts,
            ["authoritative final"],
            "action 2 must replace the owned held snapshot instead of being discarded"
        )
        XCTAssertEqual(context.appendSession.lastAcceptedTexts, ["held snapshot"])
    }

    func test_releaseDuringRecoverableBackoffReplaysCapturedPacketAndFinishesSuccessor() async {
        let failed = RetryCoordinatorStreamingSession(
            packetEvents: [.failed(.backend(code: 10024))]
        )
        let successor = RetryCoordinatorStreamingSession(
            packetEvents: [.partial("recovered snapshot")],
            finishEvent: .final("recovered final")
        )
        let sleeper = ControlledCoordinatorRetrySleeper()
        let context = makeRetryContext(
            capability: .live,
            sessions: [failed, successor],
            sleeper: sleeper
        )
        let identity = StreamingSessionIdentity(generation: 4_032)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        context.recorder.emit(Data(repeating: 0xD2, count: 6_400))
        await waitUntil { await sleeper.callCount == 1 }

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await sleeper.releaseNext()
        await waitUntil { await context.provider.makeSessionCallCount == 2 }
        let providerCallCount = await context.provider.makeSessionCallCount
        XCTAssertEqual(
            providerCallCount,
            2,
            "release during a recoverable retry must retain authority to recognize captured audio"
        )
        guard providerCallCount == 2 else { return }

        await waitUntil { await successor.finishCallCount == 1 }
        XCTAssertEqual(
            context.accessibility.setSelectedTextCalls,
            ["recovered snapshot", "recovered final"]
        )
        let successorSendCallCount = await successor.sendCallCount
        XCTAssertEqual(successorSendCallCount, 1, "the captured journal packet must be replayed")
        XCTAssertEqual(context.viewModel.status, .idle)
    }

    func test_successfulPacketAfterRepeatedBackend10024ResetsRetryBackoffStreak() async {
        let firstFailure = RetryCoordinatorStreamingSession(
            packetEvents: [.failed(.backend(code: 10024))]
        )
        let secondFailure = RetryCoordinatorStreamingSession(
            packetEvents: [.failed(.backend(code: 10024))]
        )
        let recoveredThenFailed = RetryCoordinatorStreamingSession(
            packetEvents: [
                .partial("recovered snapshot"),
                .failed(.backend(code: 10024))
            ]
        )
        let resumed = RetryCoordinatorStreamingSession(
            packetEvents: [
                .partial("historical replay"),
                .partial("resumed snapshot")
            ]
        )
        let sleeper = ControlledCoordinatorRetrySleeper()
        let context = makeRetryContext(
            capability: .live,
            sessions: [firstFailure, secondFailure, recoveredThenFailed, resumed],
            sleeper: sleeper
        )
        let identity = StreamingSessionIdentity(generation: 4_033)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        context.recorder.emit(Data(repeating: 0xD3, count: 6_400))
        await waitUntil { await sleeper.callCount == 1 }
        await sleeper.releaseNext()
        await waitUntil { await sleeper.callCount == 2 }
        await sleeper.releaseNext()
        await waitUntil {
            await recoveredThenFailed.sendCallCount == 1 &&
                context.accessibility.setSelectedTextCalls == ["recovered snapshot"]
        }

        context.recorder.emit(Data(repeating: 0xD4, count: 6_400))
        await waitUntil { await sleeper.callCount == 3 }
        let retryDelays = await sleeper.delays
        XCTAssertEqual(
            retryDelays,
            [250_000_000, 500_000_000, 250_000_000],
            "a successful packet ACK must reset the retry/backoff streak"
        )

        await sleeper.releaseNext()
        await waitUntil { await resumed.sendCallCount == 2 }
        XCTAssertEqual(
            context.accessibility.setSelectedTextCalls,
            ["recovered snapshot", "resumed snapshot"],
            "recovery must resume output after repeated backend 10024 responses"
        )
        await context.viewModel.resetService()
    }

    func test_retryOwnsOnlyThePreviouslyFailedJournalIndexAndNeverReownsHistory() async {
        let first = RetryCoordinatorStreamingSession(
            packetEvents: [.partial("same"), .failed(.network)]
        )
        let replacement = RetryCoordinatorStreamingSession(
            packetEvents: [
                .partial("changed historical replay"),
                .partial("same"),
                .failed(.network)
            ]
        )
        let secondReplacement = RetryCoordinatorStreamingSession(
            packetEvents: [
                .partial("second historical replay"),
                .partial("changed already-owned replay frontier"),
                .partial("tail")
            ]
        )
        let sleeper = ControlledCoordinatorRetrySleeper()
        let context = makeAppendRetryContext(
            sessions: [first, replacement, secondReplacement],
            sleeper: sleeper
        )
        let identity = StreamingSessionIdentity(generation: 403)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xB3, count: 12_800))
        await waitUntil { await sleeper.callCount == 1 }

        XCTAssertEqual(context.appendSession.appliedTexts, ["same"])

        await sleeper.releaseNext()
        await waitUntil { await replacement.sendCallCount == 2 }

        XCTAssertEqual(
            context.appendSession.appliedTexts,
            ["same"],
            "historical index 0 remains owned while an equal snapshot on newly owned index 1 is a no-op"
        )
        XCTAssertEqual(context.appendSession.appliedSources, ["live"])

        context.recorder.emit(Data(repeating: 0xB4, count: 6_400))
        await waitUntil { await sleeper.callCount == 2 }
        await sleeper.releaseNext()
        await waitUntil { await secondReplacement.sendCallCount == 3 }
        XCTAssertEqual(context.appendSession.appliedTexts, ["same", "tail"])
        XCTAssertEqual(
            context.appendSession.appliedSources,
            ["live", "replay"],
            "an index first owned during replay must become historical on every later replay"
        )

        await context.viewModel.resetService()
    }

    func test_liveAXOwnerReceivesEachCompleteSnapshotForDisjointPacketResponses() async {
        let context = makeContext(
            capability: .live,
            packetEvents: [.partial("one"), .partial("two"), .partial("three")],
            finishEvent: .cancelled
        )
        let identity = StreamingSessionIdentity(generation: 404)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xB5, count: 19_200))
        await waitUntil { await context.session.sendCallCount == 3 }

        XCTAssertEqual(
            context.accessibility.setSelectedTextCalls,
            ["one", "two", "three"],
            "the exact captured AX range must receive each raw complete snapshot"
        )
        XCTAssertEqual(context.output.syntheticInputCallCount, 0)
        XCTAssertEqual(context.output.copiedTexts, [])

        await context.viewModel.resetService()
    }

    func test_ineligibleEventsNeverAdvanceTheLatestSnapshot() async {
        let unsafe = "unsafe\u{001B}"
        let context = makeProductionCapturedAppendContext(
            route: CoordinatorFinalOnlyRoute(
                capability: .finalOnly,
                rebindCapability: nil,
                generation: 405
            ),
            packetEvents: [.partial(" \n "), .partial(unsafe), .partial("safe")],
            finishEvent: .cancelled
        )
        let identity = StreamingSessionIdentity(generation: 405)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xB6, count: 19_200))
        await waitUntil { await context.transport.sendCallCount == 3 }

        XCTAssertEqual(
            context.unicodePoster.requestedTexts,
            ["safe"],
            "contentless and unsafe packet responses must not advance the assembled snapshot"
        )

        context.viewModel.handleStreamingEventForTesting(
            .partial("stale"),
            identity: StreamingSessionIdentity(generation: 9_405)
        )
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        context.viewModel.handleStreamingEventForTesting(.partial("sealed"), identity: identity)
        context.viewModel.handleStreamingEventForTesting(.final("late final"), identity: identity)
        await waitUntil { context.viewModel.status == .idle }

        XCTAssertEqual(context.unicodePoster.requestedTexts, ["safe"])
        XCTAssertEqual(context.unicodePoster.destinationProcessIdentifiers, [42])
        XCTAssertEqual(context.output.syntheticInputCallCount, 0)
        XCTAssertEqual(context.output.copiedTexts, [])
    }

    func test_ineligiblePacketStillReservesItsIndexAgainstChangedHistoricalReplay() async {
        let cases = [
            (name: "contentless", response: " \n "),
            (name: "unsafe", response: "unsafe\u{001B}")
        ]

        for (offset, testCase) in cases.enumerated() {
            let firstSession = RetryCoordinatorStreamingSession(
                packetEvents: [
                    .partial("stable snapshot"),
                    .partial(testCase.response),
                    .failed(.network)
                ]
            )
            let replacementSession = RetryCoordinatorStreamingSession(
                packetEvents: [
                    .partial("changed historical zero"),
                    .partial("changed historical one"),
                    .partial("next snapshot")
                ]
            )
            let sleeper = ControlledCoordinatorRetrySleeper()
            let context = makeAppendRetryContext(
                sessions: [firstSession, replacementSession],
                sleeper: sleeper
            )
            let identity = StreamingSessionIdentity(generation: UInt64(410 + offset))

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            await waitUntil { await context.provider.makeSessionCallCount == 1 }
            context.recorder.emit(Data(repeating: 0xBA, count: 19_200))

            await waitUntil { await sleeper.callCount == 1 }
            XCTAssertEqual(
                context.appendSession.appliedTexts,
                ["stable snapshot"],
                "\(testCase.name) response must not mutate output before replay"
            )

            await sleeper.releaseNext()
            await waitUntil { await replacementSession.sendCallCount == 3 }

            XCTAssertEqual(
                context.appendSession.appliedTexts,
                ["stable snapshot", "next snapshot"],
                "\(testCase.name) response must reserve packet index 1 so changed replay is historical"
            )
            await context.viewModel.resetService()
        }
    }

    func test_multilineLFSnapshotReachesAccessibilityOutput() async {
        let snapshot = "first line\nsecond line"
        let context = makeContext(
            capability: .live,
            packetEvents: [.partial(snapshot)]
        )
        let identity = StreamingSessionIdentity(generation: 420)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xBB, count: 6_400))

        await waitUntil {
            context.accessibility.setSelectedTextCalls == [snapshot]
        }

        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [snapshot])
        await context.viewModel.resetService()
    }

    func test_multilineLFSnapshotNeverReachesKeyboardAndLaterSafeSnapshotReconcilesFromPriorOutput() async {
        let initialSnapshot = "safe base"
        let multilineSnapshot = "safe base\npassive line"
        let laterSafeSnapshot = "safe revised"
        let context = makeProductionCapturedAppendContext(
            route: CoordinatorFinalOnlyRoute(
                capability: .finalOnly,
                rebindCapability: nil,
                generation: 421
            ),
            packetEvents: [
                .partial(initialSnapshot),
                .partial(multilineSnapshot),
                .partial(laterSafeSnapshot)
            ],
            finishEvent: .cancelled
        )
        let identity = StreamingSessionIdentity(generation: 421)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xBC, count: 19_200))

        await waitUntil {
            await context.transport.sendCallCount == 3
        }

        XCTAssertEqual(
            context.unicodePoster.replacementRequests,
            [
                CoordinatorReplacementRequest(
                    deleteCharacterCount: 0,
                    insertText: initialSnapshot
                ),
                CoordinatorReplacementRequest(
                    deleteCharacterCount: 4,
                    insertText: "revised"
                )
            ],
            "LF must emit zero keyboard events and must not replace the previously emitted snapshot"
        )
        await context.viewModel.resetService()
    }

    func test_releaseActionTwoCannotCreateFirstOutputOrMutateOwnedSnapshot() async {
        let scenarios = [
            ReleaseAdmissionScenario(
                generation: 406,
                partial: " \n ",
                final: "terminal first output",
                expected: []
            ),
            ReleaseAdmissionScenario(
                generation: 407,
                partial: "seed",
                final: "seed terminal suffix",
                expected: ["seed"]
            )
        ]

        for scenario in scenarios {
            let context = makeProductionCapturedAppendContext(
                route: CoordinatorFinalOnlyRoute(
                    capability: .finalOnly,
                    rebindCapability: nil,
                    generation: scenario.generation
                ),
                packetEvents: [.partial(scenario.partial)],
                finishEvent: .final(scenario.final)
            )
            let identity = StreamingSessionIdentity(generation: scenario.generation)

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            await waitUntil { await context.provider.makeSessionCallCount == 1 }
            context.recorder.emit(Data(repeating: 0xB7, count: 6_400))
            await waitUntil { await context.transport.sendCallCount == 1 }
            context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
            context.viewModel.handleStreamingEventForTesting(.partial("late packet"), identity: identity)
            context.viewModel.handleStreamingEventForTesting(.final("late final"), identity: identity)
            await waitUntil { context.viewModel.status == .idle }

            XCTAssertEqual(
                context.unicodePoster.requestedTexts,
                scenario.expected,
                "release must only close the existing owner; action 2 and late events cannot acquire output ownership"
            )
            XCTAssertEqual(
                context.unicodePoster.destinationProcessIdentifiers,
                Array(repeating: pid_t(42), count: scenario.expected.count)
            )
            XCTAssertEqual(context.output.syntheticInputCallCount, 0)
            XCTAssertEqual(context.output.copiedTexts, [])
        }
    }

    func test_unboundRetryKeepsOwnershipAndPublishesOnlyChangedReplaySnapshot() async {
        let first = RetryCoordinatorStreamingSession(
            packetEvents: [.partial("prefix"), .failed(.network)]
        )
        let replacement = RetryCoordinatorStreamingSession(
            packetEvents: [.partial("historical"), .partial("prefix extension")]
        )
        let sleeper = ControlledCoordinatorRetrySleeper()
        let context = makeAppendRetryContext(
            sessions: [first, replacement],
            sleeper: sleeper
        )
        let identity = StreamingSessionIdentity(generation: 231)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x82, count: 12_800))
        await waitUntil { await sleeper.callCount == 1 }

        XCTAssertEqual(context.appendSession.appliedTexts, ["prefix"])
        XCTAssertEqual(context.appendSession.appliedSources, ["live"])

        await sleeper.releaseNext()
        await waitUntil { await replacement.sendCallCount == 2 }

        XCTAssertEqual(context.appendFactory.makeSessionCallCount, 1)
        XCTAssertEqual(context.appendSession.appliedTexts, ["prefix", "prefix extension"])
        XCTAssertEqual(context.appendSession.appliedSources, ["live", "replay"])
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
    }

    func test_initialFinalOnlyRetryKeepsCapturedOwnershipAtChangedReplaySnapshot() async {
        let first = RetryCoordinatorStreamingSession(
            packetEvents: [.partial("captured prefix"), .failed(.network)]
        )
        let replacement = RetryCoordinatorStreamingSession(
            packetEvents: [.partial("historical"), .partial("captured prefix extension")]
        )
        let sleeper = ControlledCoordinatorRetrySleeper()
        let context = makeAppendRetryContext(
            capability: .finalOnly,
            rebindCapability: nil,
            sessions: [first, replacement],
            sleeper: sleeper
        )
        let identity = StreamingSessionIdentity(generation: 308)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xAA, count: 12_800))
        await waitUntil { await sleeper.callCount == 1 }

        XCTAssertEqual(context.appendSession.appliedTexts, ["captured prefix"])
        XCTAssertEqual(context.appendSession.appliedSources, ["live"])

        await sleeper.releaseNext()
        await waitUntil { await replacement.sendCallCount == 2 }

        XCTAssertEqual(context.appendFactory.makeSessionCallCount, 1)
        XCTAssertEqual(
            context.appendSession.appliedTexts,
            ["captured prefix", "captured prefix extension"]
        )
        XCTAssertEqual(context.appendSession.appliedSources, ["live", "replay"])
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
    }

    func test_unboundDivergentAndEmptyFinalNeverFallThroughToOneShotOrClipboard() async {
        for (offset, finalText) in ["revised", ""].enumerated() {
            let context = makeAppendContext(
                autoInsert: true,
                packetEvents: [.partial("attempted realtime")],
                finishEvent: .final(finalText)
            )
            let identity = StreamingSessionIdentity(generation: UInt64(232 + offset))

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            await waitUntil { await context.provider.makeSessionCallCount == 1 }
            context.recorder.emit(Data(repeating: 0x83, count: 6_400))
            await waitUntil { await context.transport.sendCallCount == 1 }
            context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
            await waitUntil { await context.transport.finishCallCount == 1 }

            XCTAssertEqual(context.appendSession.finalizeCallCount, 1)
            XCTAssertEqual(context.appendSession.finalTexts, [nil])
            XCTAssertEqual(context.appendSession.lastAcceptedTexts, ["attempted realtime"])
            XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
            XCTAssertEqual(context.output.insertedTexts, [])
            XCTAssertEqual(context.output.copiedTexts, [])
            XCTAssertLessThanOrEqual(context.overlayPresenter.completionFeedbacks.count, 1)
        }
    }

    func test_autoInsertFalseCreatesNoAppendSessionAndSuccessfulAXRebindDoesNotUseIt() async {
        let disabled = makeAppendContext(
            autoInsert: false,
            packetEvents: [.partial("disabled")],
            finishEvent: .final("disabled final")
        )
        let disabledIdentity = StreamingSessionIdentity(generation: 234)
        disabled.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: disabledIdentity))
        await waitUntil { await disabled.provider.makeSessionCallCount == 1 }
        disabled.recorder.emit(Data(repeating: 0x84, count: 6_400))
        await waitUntil { await disabled.transport.sendCallCount == 1 }
        disabled.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: disabledIdentity))
        await waitUntil { await disabled.transport.finishCallCount == 1 }

        XCTAssertEqual(disabled.appendFactory.makeSessionCallCount, 0)
        XCTAssertEqual(disabled.appendSession.appliedTexts, [])
        XCTAssertEqual(disabled.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(disabled.output.copiedTexts, [])

        let rebound = makeAppendContext(
            autoInsert: true,
            rebindCapability: .live,
            packetEvents: [.partial("verified AX")],
            finishEvent: .final("verified AX final")
        )
        let reboundIdentity = StreamingSessionIdentity(generation: 235)
        rebound.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: reboundIdentity))
        await waitUntil { await rebound.provider.makeSessionCallCount == 1 }
        rebound.recorder.emit(Data(repeating: 0x85, count: 6_400))
        await waitUntil { await rebound.transport.sendCallCount == 1 }

        XCTAssertEqual(rebound.accessibility.setSelectedTextCalls, ["verified AX"])
        XCTAssertEqual(rebound.appendSession.appliedTexts, [])
        XCTAssertEqual(rebound.output.currentFocusAttemptedTexts, [])
    }

    func test_releaseDuringEstablishedReplayTreatsTypedCancellationAsSealedControlFlow() async {
        let failedAttempt = RetryCoordinatorStreamingSession(
            packetEvents: [.partial("journal frontier"), .failed(.network)]
        )
        let replacement = ReviewControllableStreamingSession(
            packetOutcomes: [
                .event(.partial("accepted replay frontier")),
                .event(.partial("unreachable replay continuation"))
            ],
            holdSendCallNumber: 2,
            cancelHeldSendOutcome: .failure(.cancelled),
            holdCancelCompletion: true
        )
        let sleeper = ControlledCoordinatorRetrySleeper()
        let context = makeRetryContext(
            capability: .finalOnly,
            sessions: [failedAttempt, replacement],
            sleeper: sleeper
        )
        let surface = RenderedStatusSurface(viewModel: context.viewModel)
        let identity = StreamingSessionIdentity(generation: 240)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x91, count: 12_800))
        await waitUntil { await sleeper.callCount == 1 }
        await sleeper.releaseNext()
        await waitUntil { await replacement.isHoldingSend }

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { await replacement.isHoldingCancelCompletion }
        await settle(iterations: 50)

        let cancelCallCount = await replacement.cancelCallCount
        let providerCallCount = await context.provider.makeSessionCallCount
        XCTAssertEqual(cancelCallCount, 1)
        XCTAssertEqual(providerCallCount, 2)
        XCTAssertEqual(context.viewModel.activeSessionIdentityForTesting, identity)
        XCTAssertEqual(context.viewModel.status, .sealing)
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertFalse(surface.states.contains(where: isError))

        await replacement.releaseCancelCompletionIfNeeded()
        await waitUntil { context.viewModel.activeSessionIdentityForTesting == nil }
        let finalCancelCallCount = await replacement.cancelCallCount
        let finalProviderCallCount = await context.provider.makeSessionCallCount
        XCTAssertEqual(finalCancelCallCount, 1)
        XCTAssertEqual(finalProviderCallCount, 2, "release closes retry admission permanently")
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertFalse(surface.states.contains(where: isError))
        await context.viewModel.resetService()
    }

    func test_recoverableFinishAfterSealCancelsOnceWithoutReleaseTimeFallback() async {
        for (offset, finishOutcome) in [
            ReviewPacketOutcome.event(.failed(.network)),
            .failure(.network)
        ].enumerated() {
            let session = ReviewControllableStreamingSession(
                packetOutcomes: [.event(.partial("last usable partial"))],
                finishOutcome: finishOutcome
            )
            let sleeper = ControlledCoordinatorRetrySleeper()
            let context = makeReviewContext(
                capability: .finalOnly,
                provider: RetryCoordinatorStreamingProvider(
                    factoryErrors: [],
                    sessions: [session]
                ),
                retrySleeper: { nanoseconds in
                    try await sleeper.sleep(nanoseconds: nanoseconds)
                }
            )
            let identity = StreamingSessionIdentity(generation: UInt64(241 + offset))

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            context.recorder.emit(Data(repeating: 0x92, count: 6_400))
            await waitUntil { await session.sendCallCount == 1 }
            context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
            await waitUntil { await session.finishCallCount == 1 }
            await waitUntil { context.viewModel.activeSessionIdentityForTesting == nil }

            let cancelCallCount = await session.cancelCallCount
            let sleeperCallCount = await sleeper.callCount
            XCTAssertEqual(cancelCallCount, 1)
            XCTAssertEqual(sleeperCallCount, 0)
            XCTAssertEqual(context.output.insertedTexts, [])
            XCTAssertEqual(context.viewModel.status, .idle)
            XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
        }
    }

    func test_releaseDuringRecoverableFactoryBackoffWithoutUsableTextPublishesOneFixedError() async {
        let privateFailureDetail = "PRIVATE_FACTORY_BACKOFF_DETAIL"
        let forbiddenSuccessor = RetryCoordinatorStreamingSession(packetEvents: [.partial("LATE")])
        let provider = ReviewFactoryPlanProvider(
            errors: [FeishuAPIService.APIError.networkError(privateFailureDetail)],
            successor: forbiddenSuccessor
        )
        let sleeper = CooperativeReviewRetrySleeper()
        let context = makeReviewContext(
            capability: .finalOnly,
            provider: provider,
            retrySleeper: { nanoseconds in
                try await sleeper.sleep(nanoseconds: nanoseconds)
            }
        )
        let surface = RenderedStatusSurface(viewModel: context.viewModel)
        let identity = StreamingSessionIdentity(generation: 243)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await sleeper.callCount == 1 }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { await sleeper.cancellationCount == 1 }
        await waitUntil { context.viewModel.activeSessionIdentityForTesting == nil }

        let errors = surface.states.filter(isError)
        let providerCallCount = await provider.makeSessionCallCount
        XCTAssertEqual(providerCallCount, 1)
        XCTAssertEqual(errors.map(\.text), ["流式识别失败"])
        XCTAssertFalse(errors.contains { $0.text.contains(privateFailureDetail) })
        XCTAssertEqual(context.overlayPresenter.completionFeedbacks, [])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        await context.viewModel.resetService()
    }

    func test_releaseDuringRecoverableFirstPacketBackoffWithoutUsableTextPublishesOneFixedError() async {
        let failed = RetryCoordinatorStreamingSession(packetEvents: [.failed(.network)])
        let forbiddenSuccessor = RetryCoordinatorStreamingSession(packetEvents: [.partial("LATE")])
        let provider = RetryCoordinatorStreamingProvider(
            factoryErrors: [],
            sessions: [failed, forbiddenSuccessor]
        )
        let sleeper = CooperativeReviewRetrySleeper()
        let context = makeReviewContext(
            capability: .finalOnly,
            provider: provider,
            retrySleeper: { nanoseconds in
                try await sleeper.sleep(nanoseconds: nanoseconds)
            }
        )
        let surface = RenderedStatusSurface(viewModel: context.viewModel)
        let identity = StreamingSessionIdentity(generation: 244)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        context.recorder.emit(Data(repeating: 0xA1, count: 6_400))
        await waitUntil { await sleeper.callCount == 1 }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { await sleeper.cancellationCount == 1 }
        await waitUntil { context.viewModel.activeSessionIdentityForTesting == nil }

        let errors = surface.states.filter(isError)
        let providerCallCount = await provider.makeSessionCallCount
        XCTAssertEqual(providerCallCount, 1)
        XCTAssertEqual(errors.map(\.text), ["流式识别失败"])
        XCTAssertEqual(context.overlayPresenter.completionFeedbacks, [])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        await context.viewModel.resetService()
    }

    func test_appendFactoryMissNeverRoutesRetainedValueAfterRelease() async {
        let retainedValue = "retained unbound value"
        let session = ReviewControllableStreamingSession(
            packetOutcomes: [.event(.partial(retainedValue))],
            finishOutcome: .event(.failed(.network))
        )
        let appendSession = CoordinatorCurrentFocusAppendSession()
        let missingAppendFactory = CoordinatorCurrentFocusAppendSessionFactory(
            session: appendSession,
            returnsSession: false
        )
        let context = makeReviewContext(
            capability: .accessibilityUnavailable,
            rebindCapability: .accessibilityUnavailable,
            provider: RetryCoordinatorStreamingProvider(factoryErrors: [], sessions: [session]),
            appendFactory: missingAppendFactory,
            retrySleeper: { _ in }
        )
        let surface = RenderedStatusSurface(viewModel: context.viewModel)
        let identity = StreamingSessionIdentity(generation: 245)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        context.recorder.emit(Data(repeating: 0xA2, count: 6_400))
        await waitUntil { await session.sendCallCount == 1 }
        XCTAssertEqual(missingAppendFactory.makeSessionCallCount, 1)
        XCTAssertEqual(appendSession.appliedTexts, [])

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { context.viewModel.activeSessionIdentityForTesting == nil }

        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.output.syntheticInputCallCount, 0)
        XCTAssertFalse(surface.states.contains(where: isError))
    }

    func test_releaseDuringRetryBackoffWaitsForRecorderBarrierBeforeSuccessorAdmission() async {
        let recorder = CoordinatorAudioRecorder(holdNextStopBarrier: true)
        let first = RetryCoordinatorStreamingSession(
            packetEvents: [.partial("retained before backoff"), .failed(.network)]
        )
        let successor = RetryCoordinatorStreamingSession(packetEvents: [.partial("successor alive")])
        let provider = RetryCoordinatorStreamingProvider(
            factoryErrors: [],
            sessions: [first, successor]
        )
        let sleeper = CooperativeReviewRetrySleeper()
        let context = makeReviewContext(
            capability: .finalOnly,
            provider: provider,
            recorder: recorder,
            retrySleeper: { nanoseconds in
                try await sleeper.sleep(nanoseconds: nanoseconds)
            }
        )
        let oldIdentity = StreamingSessionIdentity(generation: 246)
        let successorIdentity = StreamingSessionIdentity(generation: 247)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: oldIdentity))
        context.recorder.emit(Data(repeating: 0xA3, count: 12_800))
        await waitUntil { await sleeper.callCount == 1 }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: oldIdentity))
        await waitUntil { recorder.isHoldingStopBarrier }
        await waitUntil { await sleeper.cancellationCount == 1 }

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: successorIdentity))
        await settle(iterations: 50)
        let providerCountBeforeBarrier = await provider.makeSessionCallCount
        XCTAssertEqual(context.viewModel.activeSessionIdentityForTesting, oldIdentity)
        XCTAssertEqual(context.viewModel.status, .sealing)
        XCTAssertEqual(providerCountBeforeBarrier, 1)
        XCTAssertEqual(recorder.startStreamingCallCount, 1)
        XCTAssertEqual(recorder.finishedIngressIdentifiers, [])

        recorder.releaseStopBarrier()
        await waitUntil { context.viewModel.activeSessionIdentityForTesting != oldIdentity }
        XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
        XCTAssertEqual(context.viewModel.status, .idle)
        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: successorIdentity))
        await waitUntil { await provider.makeSessionCallCount == 2 }
        await waitUntil { recorder.startStreamingCallCount == 2 }

        XCTAssertEqual(recorder.finishedIngressIdentifiers, [recorder.startedIngressIdentifiers[0]])
        XCTAssertEqual(recorder.activeIngressIdentifier, recorder.startedIngressIdentifiers[1])
        context.recorder.emit(Data(repeating: 0xA4, count: 6_400))
        await waitUntil { await successor.sendCallCount == 1 }
        XCTAssertEqual(context.viewModel.activeSessionIdentityForTesting, successorIdentity)
        await context.viewModel.resetService()
    }

    func test_releaseDuringReplayWaitsForRecorderBarrierBeforeSuccessorAdmission() async {
        let recorder = CoordinatorAudioRecorder(holdNextStopBarrier: true)
        let failedAttempt = RetryCoordinatorStreamingSession(
            packetEvents: [.partial("retained before replay"), .failed(.network)]
        )
        let replacement = ReviewControllableStreamingSession(
            packetOutcomes: [
                .event(.partial("accepted replay")),
                .event(.partial("held replay"))
            ],
            holdSendCallNumber: 2
        )
        let successor = RetryCoordinatorStreamingSession(packetEvents: [.partial("successor alive")])
        let provider = RetryCoordinatorStreamingProvider(
            factoryErrors: [],
            sessions: [failedAttempt, replacement, successor]
        )
        let sleeper = ImmediateReviewRetrySleeper()
        let context = makeReviewContext(
            capability: .finalOnly,
            provider: provider,
            recorder: recorder,
            retrySleeper: { nanoseconds in
                await sleeper.sleep(nanoseconds: nanoseconds)
            }
        )
        let oldIdentity = StreamingSessionIdentity(generation: 248)
        let successorIdentity = StreamingSessionIdentity(generation: 249)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: oldIdentity))
        context.recorder.emit(Data(repeating: 0xA5, count: 12_800))
        await waitUntil { await replacement.isHoldingSend }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: oldIdentity))
        await waitUntil { recorder.isHoldingStopBarrier }
        await waitUntil { await replacement.cancelCallCount == 1 }

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: successorIdentity))
        await settle(iterations: 50)
        let providerCountBeforeBarrier = await provider.makeSessionCallCount
        XCTAssertEqual(context.viewModel.activeSessionIdentityForTesting, oldIdentity)
        XCTAssertEqual(context.viewModel.status, .sealing)
        XCTAssertEqual(providerCountBeforeBarrier, 2)
        XCTAssertEqual(recorder.startStreamingCallCount, 1)
        XCTAssertEqual(recorder.finishedIngressIdentifiers, [])

        recorder.releaseStopBarrier()
        await waitUntil { context.viewModel.activeSessionIdentityForTesting != oldIdentity }
        XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
        XCTAssertEqual(context.viewModel.status, .idle)
        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: successorIdentity))
        await waitUntil { await provider.makeSessionCallCount == 3 }
        await waitUntil { recorder.startStreamingCallCount == 2 }

        XCTAssertEqual(recorder.finishedIngressIdentifiers, [recorder.startedIngressIdentifiers[0]])
        XCTAssertEqual(recorder.activeIngressIdentifier, recorder.startedIngressIdentifiers[1])
        context.recorder.emit(Data(repeating: 0xA6, count: 6_400))
        await waitUntil { await successor.sendCallCount == 1 }
        XCTAssertEqual(context.viewModel.activeSessionIdentityForTesting, successorIdentity)
        await context.viewModel.resetService()
    }

    func test_retryAllowlistDeniesEveryTerminalFactoryClassAndHTTPBoundaryWithoutSuccessor() async {
        let denied: [(String, any Error)] = [
            ("authenticationUnavailable", FeishuAPIService.APIError.authenticationUnavailable),
            ("invalidResponse", FeishuAPIService.APIError.invalidResponse),
            ("recognitionFailed", FeishuAPIService.APIError.recognitionFailed("PRIVATE")),
            ("unknown", FeishuAPIService.APIError.unknown),
            ("authFailed", FeishuAPIService.APIError.authFailed("PRIVATE")),
            ("http400", FeishuAPIService.APIError.httpError(400)),
            ("http401", FeishuAPIService.APIError.httpError(401)),
            ("http424", FeishuAPIService.APIError.httpError(424)),
            ("http426", FeishuAPIService.APIError.httpError(426)),
            ("http499", FeishuAPIService.APIError.httpError(499)),
            ("http600", FeishuAPIService.APIError.httpError(600)),
            ("unclassified", ReviewUnclassifiedError())
        ]

        for (offset, sample) in denied.enumerated() {
            let successor = RetryCoordinatorStreamingSession(packetEvents: [.partial("LATE")])
            let provider = ReviewFactoryPlanProvider(
                errors: [sample.1],
                successor: successor
            )
            let sleeper = ImmediateReviewRetrySleeper()
            let context = makeReviewContext(
                capability: .live,
                provider: provider,
                retrySleeper: { nanoseconds in
                    await sleeper.sleep(nanoseconds: nanoseconds)
                }
            )
            let identity = StreamingSessionIdentity(generation: UInt64(250 + offset))

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            await waitUntil {
                await provider.makeSessionCallCount >= 2 ||
                    context.viewModel.activeSessionIdentityForTesting == nil
            }

            let providerCallCount = await provider.makeSessionCallCount
            let sleeperCallCount = await sleeper.callCount
            XCTAssertEqual(providerCallCount, 1, "denied factory error: \(sample.0)")
            XCTAssertEqual(sleeperCallCount, 0, "denied factory error: \(sample.0)")
            XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
            await context.viewModel.resetService()
        }
    }

    func test_retryAllowlistDeniesEveryTerminalStreamClassAndHTTPBoundaryWithoutSuccessor() async {
        let denied: [(String, StreamFailure)] = [
            ("invalidRequest", .invalidRequest),
            ("authentication", .authentication),
            ("malformedResponse", .malformedResponse),
            ("responseIdentityMismatch", .responseIdentityMismatch),
            ("cancelled", .cancelled),
            ("backendOther", .backend(code: 10023)),
            ("http400", .httpStatus(400)),
            ("http401", .httpStatus(401)),
            ("http424", .httpStatus(424)),
            ("http426", .httpStatus(426)),
            ("http499", .httpStatus(499)),
            ("http600", .httpStatus(600))
        ]

        for (offset, sample) in denied.enumerated() {
            let failure = sample.1
            let failed = RetryCoordinatorStreamingSession(packetEvents: [.failed(failure)])
            let successor = RetryCoordinatorStreamingSession(packetEvents: [.partial("LATE")])
            let provider = RetryCoordinatorStreamingProvider(
                factoryErrors: [],
                sessions: [failed, successor]
            )
            let sleeper = ImmediateReviewRetrySleeper()
            let context = makeReviewContext(
                capability: .live,
                provider: provider,
                retrySleeper: { nanoseconds in
                    await sleeper.sleep(nanoseconds: nanoseconds)
                }
            )
            let identity = StreamingSessionIdentity(generation: UInt64(260 + offset))

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            context.recorder.emit(Data(repeating: 0x93, count: 6_400))
            await waitUntil {
                await provider.makeSessionCallCount >= 2 ||
                    context.viewModel.activeSessionIdentityForTesting == nil
            }

            let providerCallCount = await provider.makeSessionCallCount
            let sleeperCallCount = await sleeper.callCount
            XCTAssertEqual(providerCallCount, 1, "denied stream failure: \(sample.0)")
            XCTAssertEqual(sleeperCallCount, 0, "denied stream failure: \(sample.0)")
            XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
            await context.viewModel.resetService()
        }
    }

    func test_retryAllowlistAdmitsEveryReviewedFactoryAndStreamBoundary() async {
        let factoryErrors: [(String, FeishuAPIService.APIError)] = [
            ("networkUnavailable", .networkUnavailable),
            ("connectionFailed", .connectionFailed),
            ("networkError", .networkError("")),
            ("timeout", .timeout),
            ("http408", .httpError(408)),
            ("http425", .httpError(425)),
            ("http429", .httpError(429)),
            ("http500", .httpError(500)),
            ("http599", .httpError(599))
        ]

        for (offset, sample) in factoryErrors.enumerated() {
            let successor = RetryCoordinatorStreamingSession(packetEvents: [.partial("")])
            let provider = ReviewFactoryPlanProvider(errors: [sample.1], successor: successor)
            let sleeper = ImmediateReviewRetrySleeper()
            let context = makeReviewContext(
                capability: .live,
                provider: provider,
                retrySleeper: { nanoseconds in
                    await sleeper.sleep(nanoseconds: nanoseconds)
                }
            )
            let identity = StreamingSessionIdentity(generation: UInt64(270 + offset))

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            await waitUntil { await provider.makeSessionCallCount == 2 }

            let sleeperCallCount = await sleeper.callCount
            XCTAssertEqual(sleeperCallCount, 1, "admitted factory error: \(sample.0)")
            XCTAssertEqual(
                context.viewModel.activeSessionIdentityForTesting,
                identity,
                "admitted factory error: \(sample.0)"
            )
            XCTAssertEqual(context.recorder.forceCleanupCallCount, 0, "admitted factory error: \(sample.0)")
            await context.viewModel.resetService()
        }

        let streamFailures: [(String, StreamFailure)] = [
            ("network", .network),
            ("timeout", .timeout),
            ("http408", .httpStatus(408)),
            ("http425", .httpStatus(425)),
            ("http429", .httpStatus(429)),
            ("http500", .httpStatus(500)),
            ("http599", .httpStatus(599)),
            ("backend10024", .backend(code: 10024))
        ]
        for (offset, sample) in streamFailures.enumerated() {
            let failure = sample.1
            let failed = RetryCoordinatorStreamingSession(packetEvents: [.failed(failure)])
            let successor = RetryCoordinatorStreamingSession(packetEvents: [.partial("caught up")])
            let provider = RetryCoordinatorStreamingProvider(
                factoryErrors: [],
                sessions: [failed, successor]
            )
            let sleeper = ImmediateReviewRetrySleeper()
            let context = makeReviewContext(
                capability: .live,
                provider: provider,
                retrySleeper: { nanoseconds in
                    await sleeper.sleep(nanoseconds: nanoseconds)
                }
            )
            let identity = StreamingSessionIdentity(generation: UInt64(280 + offset))

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            context.recorder.emit(Data(repeating: 0x94, count: 6_400))
            await waitUntil { await successor.sendCallCount == 1 }

            let providerCallCount = await provider.makeSessionCallCount
            let sleeperCallCount = await sleeper.callCount
            XCTAssertEqual(providerCallCount, 2, "admitted stream failure: \(sample.0)")
            XCTAssertEqual(sleeperCallCount, 1, "admitted stream failure: \(sample.0)")
            XCTAssertEqual(
                context.viewModel.activeSessionIdentityForTesting,
                identity,
                "admitted stream failure: \(sample.0)"
            )
            await context.viewModel.resetService()
        }
    }

    func test_releaseActivelyCancelsCooperativeRetrySleepWithoutWaitingOrRetrying() async {
        let failed = RetryCoordinatorStreamingSession(packetEvents: [.failed(.network)])
        let forbidden = RetryCoordinatorStreamingSession(packetEvents: [.partial("LATE")])
        let provider = RetryCoordinatorStreamingProvider(
            factoryErrors: [],
            sessions: [failed, forbidden]
        )
        let sleeper = CooperativeReviewRetrySleeper()
        let context = makeReviewContext(
            capability: .live,
            provider: provider,
            retrySleeper: { nanoseconds in
                try await sleeper.sleep(nanoseconds: nanoseconds)
            }
        )
        let identity = StreamingSessionIdentity(generation: 290)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        context.recorder.emit(Data(repeating: 0x95, count: 6_400))
        await waitUntil { await sleeper.callCount == 1 }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))

        await waitUntil { await sleeper.cancellationCount == 1 }
        await waitUntil { context.viewModel.activeSessionIdentityForTesting == nil }

        let providerCallCount = await provider.makeSessionCallCount
        XCTAssertEqual(providerCallCount, 1)
        XCTAssertTrue(isError(context.viewModel.status))

        await sleeper.releaseIfNeeded()
        await settle(iterations: 50)
    }

    func test_releaseCancelsCooperativeSessionCreationAndLateSessionCannotBecomeActive() async {
        let lateSession = RetryCoordinatorStreamingSession(packetEvents: [.partial("LATE")])
        let provider = CooperativeReviewSessionCreationProvider(lateSession: lateSession)
        let context = makeReviewContext(
            capability: .live,
            provider: provider,
            retrySleeper: { _ in }
        )
        let identity = StreamingSessionIdentity(generation: 291)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await provider.makeSessionCallCount == 1 }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))

        await waitUntil { await provider.cancellationCount == 1 }
        await waitUntil { context.viewModel.activeSessionIdentityForTesting == nil }

        await provider.releaseLateSessionIfNeeded()
        await settle(iterations: 50)
        let lateSendCallCount = await lateSession.sendCallCount
        let lateCancelCallCount = await lateSession.cancelCallCount
        let providerCallCount = await provider.makeSessionCallCount
        XCTAssertEqual(lateSendCallCount, 0)
        XCTAssertLessThanOrEqual(lateCancelCallCount, 1)
        XCTAssertEqual(providerCallCount, 1)
        XCTAssertEqual(context.viewModel.status, .idle)
    }

    func test_contentlessUpdatesNeverEnableFinalOnlyReleaseFallback() async {
        let session = ReviewControllableStreamingSession(
            packetOutcomes: [
                .event(.partial("last usable value")),
                .event(.partial("  \n  ")),
                .event(.failed(.network))
            ],
            holdSendCallNumber: 3
        )
        let context = makeReviewContext(
            capability: .finalOnly,
            provider: RetryCoordinatorStreamingProvider(factoryErrors: [], sessions: [session]),
            retrySleeper: { _ in }
        )
        let identity = StreamingSessionIdentity(generation: 292)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        context.recorder.emit(Data(repeating: 0x96, count: 19_200))
        await waitUntil { await session.isHoldingSend }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await session.releaseHeldIfNeeded()
        await waitUntil { context.viewModel.activeSessionIdentityForTesting == nil }

        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.viewModel.status, .idle)
    }

    func test_emptyFinalNeverCreatesFinalOnlyOutputAndClosesOwnerWithHeldSnapshot() async {
        let finalOnly = makeContext(
            capability: .finalOnly,
            packetEvents: [.partial("last usable final-only"), .partial(" \n ")],
            finishEvent: .final("")
        )
        let finalOnlyIdentity = StreamingSessionIdentity(generation: 293)
        finalOnly.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: finalOnlyIdentity))
        await waitUntil { await finalOnly.provider.makeSessionCallCount == 1 }
        finalOnly.recorder.emit(Data(repeating: 0x97, count: 12_800))
        await waitUntil { await finalOnly.session.sendCallCount == 2 }
        finalOnly.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: finalOnlyIdentity))
        await waitUntil { finalOnly.viewModel.status == .idle }

        XCTAssertEqual(finalOnly.output.insertedTexts, [])
        XCTAssertEqual(finalOnly.output.copiedTexts, [])

        let append = makeAppendContext(
            autoInsert: true,
            packetEvents: [.partial("last usable append"), .partial(" \n ")],
            finishEvent: .final("")
        )
        let appendIdentity = StreamingSessionIdentity(generation: 294)
        append.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: appendIdentity))
        await waitUntil { await append.provider.makeSessionCallCount == 1 }
        append.recorder.emit(Data(repeating: 0x98, count: 12_800))
        await waitUntil { await append.transport.sendCallCount == 2 }
        append.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: appendIdentity))
        await waitUntil { append.viewModel.status == .idle }

        XCTAssertEqual(append.appendSession.finalizeCallCount, 1)
        XCTAssertEqual(append.appendSession.lastAcceptedTexts, ["last usable append"])
        XCTAssertEqual(append.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(append.output.copiedTexts, [])
    }

    func test_firstPartialSecureRebindFailsClosedWithoutAppendOrFallbackOutput() async {
        let transcript = "PRIVATE_SECURE_REBIND"
        let context = makeAppendContext(
            autoInsert: true,
            rebindCapability: .secureRejected,
            packetEvents: [.partial(transcript)],
            finishEvent: .cancelled
        )
        let identity = StreamingSessionIdentity(generation: 295)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x99, count: 6_400))
        await waitUntil {
            await context.transport.sendCallCount == 1 &&
                context.viewModel.activeSessionIdentityForTesting == nil
        }

        XCTAssertEqual(context.accessibility.captureCount, 2)
        XCTAssertEqual(context.appendFactory.makeSessionCallCount, 0)
        XCTAssertEqual(context.appendSession.appliedTexts, [])
        XCTAssertTrue(isError(context.viewModel.status))
        XCTAssertTrue(context.viewModel.status.text.contains("安全输入"))
        XCTAssertFalse(visibleFeedback(context.viewModel).contains(transcript))
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        await context.viewModel.resetService()
    }

    func test_firstPartialFinalOnlyRebindArmsAppendAndAppliesTriggerBeforeRelease() async {
        let context = makeAppendContext(
            autoInsert: true,
            rebindCapability: .finalOnly,
            packetEvents: [.partial("provisional")],
            finishEvent: .final("provisional suffix"),
            appendFinalOutcomes: [.exactCommitted]
        )
        let identity = StreamingSessionIdentity(generation: 296)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x9A, count: 6_400))
        await waitUntil { await context.transport.sendCallCount == 1 }

        XCTAssertEqual(context.accessibility.captureCount, 2)
        XCTAssertEqual(context.appendFactory.makeSessionCallCount, 1)
        XCTAssertEqual(context.appendSession.appliedTexts, ["provisional"])
        XCTAssertEqual(context.appendSession.appliedSources, ["live"])
        XCTAssertEqual(context.appendSession.finalizeCallCount, 0)
        XCTAssertEqual(context.recorder.stopStreamingCallCount, 0, "triggering partial must be visible while Fn is held")
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.output.syntheticInputCallCount, 0)

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { context.viewModel.status == .idle }

        XCTAssertEqual(context.appendSession.finalizeCallCount, 1)
        XCTAssertEqual(context.appendSession.finalTexts, [nil])
        XCTAssertEqual(context.appendSession.lastAcceptedTexts, ["provisional"])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.output.syntheticInputCallCount, 0, "release must only close the existing owner")
    }

    func test_initialAndReboundFinalOnlyUnsafeResponseNeverPostsOrCopies() async {
        let unsafeText = "PRIVATE_UNSAFE\u{001B}"
        let routes: [CoordinatorFinalOnlyRoute] = [
            CoordinatorFinalOnlyRoute(capability: .finalOnly, rebindCapability: nil, generation: 302),
            CoordinatorFinalOnlyRoute(
                capability: .accessibilityUnavailable,
                rebindCapability: .finalOnly,
                generation: 303
            )
        ]

        for (routeIndex, route) in routes.enumerated() {
            let context = makeAppendContext(
                capability: route.capability,
                autoInsert: true,
                rebindCapability: route.rebindCapability,
                packetEvents: [.partial(unsafeText)],
                finishEvent: .final(unsafeText),
                appendApplyOutcomes: [.unsafeTextSuppressed],
                appendFinalOutcomes: [.noUsableText]
            )
            let identity = StreamingSessionIdentity(generation: route.generation)

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            await waitUntil { await context.provider.makeSessionCallCount == 1 }
            context.recorder.emit(Data(repeating: 0xA7, count: 6_400))
            await waitUntil { await context.transport.sendCallCount == 1 }

            XCTAssertEqual(context.appendSession.appliedTexts, [])
            XCTAssertEqual(context.appendSession.postAttemptCount, 0)
            XCTAssertEqual(context.output.syntheticInputCallCount, 0)
            XCTAssertEqual(context.output.copiedTexts, [])

            context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
            await waitUntil { context.viewModel.status == .idle }

            XCTAssertEqual(
                context.appendSession.finalizeCallCount,
                routeIndex == 0 ? 1 : 0,
                "an unsafe first response cannot arm a rebound owner, while an initially captured owner only closes"
            )
            XCTAssertEqual(context.output.copiedTexts, [])
            XCTAssertEqual(context.output.syntheticInputCallCount, 0)
            XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
            XCTAssertEqual(context.overlayPresenter.completionFeedbacks, [])
            XCTAssertFalse(
                context.overlayPresenter.completionFeedbacks.first?.text.contains(unsafeText) == true
            )
        }
    }

    func test_productionInitialAndReboundUnsafeResponseNeverPostsOrCopies() async {
        let unsafeText = "PRIVATE_PRODUCTION_UNSAFE\u{001B}"
        let routes = productionCapturedRoutes(startingGeneration: 311)

        for route in routes {
            let context = makeProductionCapturedAppendContext(
                route: route,
                packetEvents: [.partial(unsafeText)],
                finishEvent: .final(unsafeText)
            )
            let identity = StreamingSessionIdentity(generation: route.generation)

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            await waitUntil { await context.provider.makeSessionCallCount == 1 }
            context.recorder.emit(Data(repeating: 0xAD, count: 6_400))
            await waitUntil { await context.transport.sendCallCount == 1 }

            XCTAssertEqual(context.unicodePoster.requestedTexts, [])
            XCTAssertEqual(context.output.copiedTexts, [])

            context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
            await waitUntil { context.viewModel.status == .idle }

            XCTAssertEqual(context.unicodePoster.requestedTexts, [])
            XCTAssertEqual(context.output.copiedTexts, [])
            XCTAssertEqual(context.output.syntheticInputCallCount, 0)
            XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
            XCTAssertEqual(context.overlayPresenter.completionFeedbacks, [])
        }
    }

    func test_productionInitialAndReboundUnsafeZeroPostDriftNeverCopiesOrUsesAlternateOutput() async {
        let unsafeText = "PRIVATE_PRODUCTION_DRIFT\u{007F}"
        let scenarios = ProductionCapturedDriftScenario.allCases
        var generation: UInt64 = 320

        for scenario in scenarios {
            for route in productionCapturedRoutes(startingGeneration: generation) {
                let context = makeProductionCapturedAppendContext(
                    route: route,
                    packetEvents: [.partial(unsafeText)],
                    finishEvent: .final(unsafeText)
                )
                let identity = StreamingSessionIdentity(generation: route.generation)

                context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
                await waitUntil { await context.provider.makeSessionCallCount == 1 }
                context.recorder.emit(Data(repeating: 0xAE, count: 6_400))
                await waitUntil { await context.transport.sendCallCount == 1 }
                XCTAssertEqual(context.unicodePoster.requestedTexts, [], "scenario: \(scenario)")

                applyProductionCapturedDrift(scenario, to: context)
                context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
                await waitUntil { context.viewModel.activeSessionIdentityForTesting == nil }

                XCTAssertEqual(context.unicodePoster.requestedTexts, [], "scenario: \(scenario)")
                XCTAssertEqual(context.output.copiedTexts, [], "scenario: \(scenario)")
                XCTAssertEqual(context.output.insertedTexts, [], "scenario: \(scenario)")
                XCTAssertEqual(context.output.currentFocusAttemptedTexts, [], "scenario: \(scenario)")
                XCTAssertEqual(context.output.syntheticInputCallCount, 0, "scenario: \(scenario)")
                XCTAssertFalse(
                    context.overlayPresenter.completionFeedbacks.contains(.manualRecoveryCopied),
                    "scenario: \(scenario)"
                )
            }
            generation += 2
        }
    }

    func test_initialAndReboundFinalOnlyAttemptOrUncertaintyNeverCopiesOrResendsFullText() async {
        let unsafeFinal = "PRIVATE_UNSAFE_AFTER_ATTEMPT\u{007F}"
        let routes: [CoordinatorFinalOnlyRoute] = [
            CoordinatorFinalOnlyRoute(capability: .finalOnly, rebindCapability: nil, generation: 304),
            CoordinatorFinalOnlyRoute(
                capability: .accessibilityUnavailable,
                rebindCapability: .finalOnly,
                generation: 305
            )
        ]

        let outcomes: [(CurrentFocusAppendOutcome, CurrentFocusAppendFinalOutcome)] = [
            (.insertedFirst, .preservedDivergence),
            (.deliveryUncertain, .deliveryUncertain)
        ]

        for (scenarioOffset, outcome) in outcomes.enumerated() {
            for route in routes {
                let context = makeAppendContext(
                    capability: route.capability,
                    autoInsert: true,
                    rebindCapability: route.rebindCapability,
                    packetEvents: [.partial("attempted provisional")],
                    finishEvent: .final(unsafeFinal),
                    appendApplyOutcomes: [outcome.0],
                    appendFinalOutcomes: [outcome.1]
                )
                let identity = StreamingSessionIdentity(
                    generation: route.generation + UInt64(scenarioOffset * 10)
                )

                context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
                await waitUntil { await context.provider.makeSessionCallCount == 1 }
                context.recorder.emit(Data(repeating: 0xA8, count: 6_400))
                await waitUntil { await context.transport.sendCallCount == 1 }
                context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
                await waitUntil { context.viewModel.status == .idle }

                XCTAssertEqual(context.appendSession.postAttemptCount, 1)
                XCTAssertEqual(context.output.copiedTexts, [])
                XCTAssertEqual(context.output.insertedTexts, [])
                XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
                XCTAssertEqual(context.output.syntheticInputCallCount, 0)
                XCTAssertEqual(context.overlayPresenter.completionFeedbacks, [.provisionalOutputPreserved])
            }
        }
    }

    func test_initialAndReboundFinalOnlyFactoryMissNeverFallsBackAtRelease() async {
        let routes: [CoordinatorFinalOnlyRoute] = [
            CoordinatorFinalOnlyRoute(capability: .finalOnly, rebindCapability: nil, generation: 306),
            CoordinatorFinalOnlyRoute(
                capability: .accessibilityUnavailable,
                rebindCapability: .finalOnly,
                generation: 307
            )
        ]

        for route in routes {
            let context = makeAppendContext(
                capability: route.capability,
                autoInsert: true,
                rebindCapability: route.rebindCapability,
                packetEvents: [.partial("retained")],
                finishEvent: .final("retained final"),
                returnsAppendSession: false
            )
            let identity = StreamingSessionIdentity(generation: route.generation)

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            await waitUntil { await context.provider.makeSessionCallCount == 1 }
            context.recorder.emit(Data(repeating: 0xA9, count: 6_400))
            await waitUntil { await context.transport.sendCallCount == 1 }

            XCTAssertEqual(context.appendSession.appliedTexts, [])
            XCTAssertEqual(context.output.syntheticInputCallCount, 0)

            context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
            await waitUntil { context.viewModel.status == .idle }

            XCTAssertEqual(context.output.insertedTexts, [])
            XCTAssertEqual(context.output.syntheticInputCallCount, 0)
            XCTAssertEqual(context.output.copiedTexts, [])
        }
    }

    func test_initialFinalOnlyPostSealCallbacksCannotApplyBeforeSingleTerminalFinalize() async {
        let context = makeAppendContext(
            capability: .finalOnly,
            autoInsert: true,
            rebindCapability: nil,
            packetEvents: [.partial("visible")],
            finishEvent: .final("visible final"),
            appendFinalOutcomes: [.exactCommitted]
        )
        let identity = StreamingSessionIdentity(generation: 309)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xAB, count: 6_400))
        await waitUntil { await context.transport.sendCallCount == 1 }
        XCTAssertEqual(context.appendSession.appliedTexts, ["visible"])

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        context.viewModel.handleStreamingEventForTesting(.partial("late partial"), identity: identity)
        context.viewModel.handleStreamingEventForTesting(.final("late final"), identity: identity)
        await waitUntil { context.viewModel.status == .idle }

        XCTAssertEqual(context.appendSession.appliedTexts, ["visible"])
        XCTAssertEqual(context.appendSession.finalizeCallCount, 1)
        XCTAssertEqual(context.appendSession.finalTexts, [nil])
        XCTAssertEqual(context.appendSession.lastAcceptedTexts, ["visible"])
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
    }

    func test_initialFinalOnlyResetInvalidatesOwnerBeforeLateCallbacks() async {
        let context = makeAppendContext(
            capability: .finalOnly,
            autoInsert: true,
            rebindCapability: nil,
            packetEvents: [.partial("visible")],
            finishEvent: .cancelled
        )
        let identity = StreamingSessionIdentity(generation: 310)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0xAC, count: 6_400))
        await waitUntil { await context.transport.sendCallCount == 1 }
        await context.viewModel.resetService()

        context.viewModel.handleStreamingEventForTesting(.partial("late partial"), identity: identity)
        context.viewModel.handleStreamingEventForTesting(.final("late final"), identity: identity)

        XCTAssertEqual(context.appendSession.invalidateCallCount, 1)
        XCTAssertEqual(context.appendSession.appliedTexts, ["visible"])
        XCTAssertEqual(context.appendSession.finalizeCallCount, 0)
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
    }

    func test_appendSecurityRejectionTerminatesImmediatelyWithFixedSecurityError() async {
        let transcript = "PRIVATE_APPEND_SECURITY"
        let context = makeAppendContext(
            autoInsert: true,
            packetEvents: [.partial(transcript)],
            finishEvent: .cancelled,
            appendApplyOutcomes: [.securityRejected]
        )
        let identity = StreamingSessionIdentity(generation: 297)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x9B, count: 6_400))
        await waitUntil {
            await context.transport.sendCallCount == 1 &&
                context.viewModel.activeSessionIdentityForTesting == nil
        }

        XCTAssertNil(context.viewModel.activeSessionIdentityForTesting)
        XCTAssertTrue(isError(context.viewModel.status))
        XCTAssertTrue(context.viewModel.status.text.contains("安全输入"))
        XCTAssertFalse(visibleFeedback(context.viewModel).contains(transcript))
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        await context.viewModel.resetService()
    }

    func test_appendPreservationFinalOutcomesPublishOneTranscriptFreeCompletion() async {
        let outcomes: [CurrentFocusAppendFinalOutcome] = [
            .preservedDestinationLoss,
            .deliveryUncertain,
            .preservedDivergence
        ]
        for (offset, outcome) in outcomes.enumerated() {
            let transcript = "PRIVATE_PRESERVED_\(offset)"
            let context = makeAppendContext(
                autoInsert: true,
                packetEvents: [.partial("attempted realtime")],
                finishEvent: .final(transcript),
                appendFinalOutcomes: [outcome]
            )
            let identity = StreamingSessionIdentity(generation: UInt64(298 + offset))

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            await waitUntil { await context.provider.makeSessionCallCount == 1 }
            context.recorder.emit(Data(repeating: 0x9C, count: 6_400))
            await waitUntil { await context.transport.sendCallCount == 1 }
            context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
            await waitUntil { context.viewModel.status == .idle }

            XCTAssertEqual(context.overlayPresenter.completionFeedbacks.count, 1, "outcome \(outcome)")
            let feedback = context.overlayPresenter.completionFeedbacks.first
            XCTAssertFalse(feedback?.text.contains(transcript) == true)
            XCTAssertFalse(feedback?.text.contains("attempted realtime") == true)
            XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
            XCTAssertEqual(context.output.insertedTexts, [])
            XCTAssertEqual(context.output.copiedTexts, [])
        }
    }

    func test_appendNoUsableTerminalTextAfterSealedRecoveryClosesExistingOwner() async {
        let transcript = "PRIVATE_NO_USABLE"
        let context = makeAppendContext(
            autoInsert: true,
            packetEvents: [.partial(transcript)],
            finishEvent: .failed(.network),
            appendFinalOutcomes: [.noUsableText]
        )
        let surface = RenderedStatusSurface(viewModel: context.viewModel)
        let identity = StreamingSessionIdentity(generation: 301)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { await context.provider.makeSessionCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x9D, count: 6_400))
        await waitUntil { await context.transport.sendCallCount == 1 }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { context.viewModel.activeSessionIdentityForTesting == nil }

        let errorStates = surface.states.filter(isError)
        XCTAssertEqual(errorStates.count, 0)
        XCTAssertEqual(context.overlayPresenter.completionFeedbacks.count, 0)
        XCTAssertEqual(context.output.currentFocusAttemptedTexts, [])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
    }

    private func makeContext(
        capability: CoordinatorAccessibilityClient.Capability,
        rebindCapability: CoordinatorAccessibilityClient.Capability? = nil,
        autoInsert: Bool = true,
        packetEvents: [StreamingRecognitionEvent] = [],
        finishEvent: StreamingRecognitionEvent = .cancelled,
        holdFirstPacketResponse: Bool = false,
        providerError: FeishuAPIService.APIError? = nil
    ) -> StreamingCoordinatorContext {
        let recorder = CoordinatorAudioRecorder()
        let session = CoordinatorStreamingSession(
            packetEvents: packetEvents,
            finishEvent: finishEvent,
            holdFirstPacketResponse: holdFirstPacketResponse
        )
        let provider = CoordinatorStreamingProvider(
            session: session,
            makeSessionError: providerError
        )
        let accessibility = CoordinatorAccessibilityClient(
            capability: capability,
            rebindCapability: rebindCapability
        )
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

    private func makeRetryContext(
        capability: CoordinatorAccessibilityClient.Capability,
        autoInsert: Bool = true,
        factoryErrors: [FeishuAPIService.APIError] = [],
        sessions: [any SpeechStreamingSession],
        sleeper: ControlledCoordinatorRetrySleeper
    ) -> RetryStreamingCoordinatorContext {
        let recorder = CoordinatorAudioRecorder()
        let provider = RetryCoordinatorStreamingProvider(
            factoryErrors: factoryErrors,
            sessions: sessions
        )
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
            overlayPresenter: overlayPresenter,
            streamingRetryDelay: { ordinal in
                UInt64(250_000_000) << UInt64(max(0, ordinal - 1))
            },
            streamingRetrySleeper: { nanoseconds in
                try await sleeper.sleep(nanoseconds: nanoseconds)
            }
        )
        recorder.resetTracking()
        return RetryStreamingCoordinatorContext(
            viewModel: viewModel,
            recorder: recorder,
            provider: provider,
            accessibility: accessibility,
            output: output,
            overlayPresenter: overlayPresenter
        )
    }

    private func makeAppendContext(
        capability: CoordinatorAccessibilityClient.Capability = .accessibilityUnavailable,
        autoInsert: Bool,
        rebindCapability: CoordinatorAccessibilityClient.Capability? = .accessibilityUnavailable,
        packetEvents: [StreamingRecognitionEvent],
        finishEvent: StreamingRecognitionEvent,
        appendApplyOutcomes: [CurrentFocusAppendOutcome] = [],
        appendFinalOutcomes: [CurrentFocusAppendFinalOutcome] = [],
        returnsAppendSession: Bool = true
    ) -> AppendStreamingCoordinatorContext {
        let recorder = CoordinatorAudioRecorder()
        let transport = CoordinatorStreamingSession(
            packetEvents: packetEvents,
            finishEvent: finishEvent
        )
        let provider = CoordinatorStreamingProvider(session: transport)
        let accessibility = CoordinatorAccessibilityClient(
            capability: capability,
            rebindCapability: rebindCapability
        )
        let output = CoordinatorFinalTextOutput()
        let overlayPresenter = CoordinatorOverlayPresenter()
        let appendSession = CoordinatorCurrentFocusAppendSession(
            applyOutcomes: appendApplyOutcomes,
            finalOutcomes: appendFinalOutcomes
        )
        let appendFactory = CoordinatorCurrentFocusAppendSessionFactory(
            session: appendSession,
            returnsSession: returnsAppendSession
        )
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
            overlayPresenter: overlayPresenter,
            currentFocusAppendSessionFactory: appendFactory
        )
        recorder.resetTracking()
        return AppendStreamingCoordinatorContext(
            viewModel: viewModel,
            recorder: recorder,
            transport: transport,
            provider: provider,
            accessibility: accessibility,
            output: output,
            overlayPresenter: overlayPresenter,
            appendSession: appendSession,
            appendFactory: appendFactory
        )
    }

    private func makeProductionCapturedAppendContext(
        route: CoordinatorFinalOnlyRoute,
        packetEvents: [StreamingRecognitionEvent],
        finishEvent: StreamingRecognitionEvent
    ) -> ProductionCapturedAppendContext {
        let recorder = CoordinatorAudioRecorder()
        let transport = CoordinatorStreamingSession(
            packetEvents: packetEvents,
            finishEvent: finishEvent
        )
        let provider = CoordinatorStreamingProvider(session: transport)
        let accessibility = CoordinatorAccessibilityClient(
            capability: route.capability,
            rebindCapability: route.rebindCapability
        )
        let output = CoordinatorFinalTextOutput()
        let overlayPresenter = CoordinatorOverlayPresenter()
        let unicodePoster = CoordinatorProductionUnicodePoster()
        let secureInput = CoordinatorMutableSecureInputProvider()
        let frontmostProcess = CoordinatorMutableProcessProvider(processIdentifier: 42)
        let appendFactory = SystemCurrentFocusProvisionalOutputSessionFactory(
            eventPoster: unicodePoster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess,
            activationMonitorFactory: { CoordinatorProductionActivationMonitor() }
        )
        let viewModel = MainViewModel(
            audioRecorder: recorder,
            settings: AppSettings(
                appId: "configured-app",
                appSecret: "configured-secret",
                autoInsert: true,
                playSound: false
            ),
            hotKeyWakeRecovering: TrackingHotKeyWakeRecoverer(),
            streamingProvider: provider,
            accessibilityClient: accessibility,
            finalTextOutput: output,
            overlayPresenter: overlayPresenter,
            currentFocusAppendSessionFactory: appendFactory
        )
        recorder.resetTracking()
        return ProductionCapturedAppendContext(
            viewModel: viewModel,
            recorder: recorder,
            transport: transport,
            provider: provider,
            accessibility: accessibility,
            output: output,
            overlayPresenter: overlayPresenter,
            unicodePoster: unicodePoster,
            secureInput: secureInput,
            frontmostProcess: frontmostProcess
        )
    }

    private func productionCapturedRoutes(
        startingGeneration: UInt64
    ) -> [CoordinatorFinalOnlyRoute] {
        [
            CoordinatorFinalOnlyRoute(
                capability: .finalOnly,
                rebindCapability: nil,
                generation: startingGeneration
            ),
            CoordinatorFinalOnlyRoute(
                capability: .accessibilityUnavailable,
                rebindCapability: .finalOnly,
                generation: startingGeneration + 1
            )
        ]
    }

    private func applyProductionCapturedDrift(
        _ scenario: ProductionCapturedDriftScenario,
        to context: ProductionCapturedAppendContext
    ) {
        switch scenario {
        case .focusedElement:
            context.accessibility.currentFocusedElement = AXUIElementCreateApplication(99)
        case .secureInput:
            context.secureInput.isEnabled = true
        case .secureToken:
            context.accessibility.currentSecurityState = .secure
        case .unverifiableToken:
            context.accessibility.currentSecurityState = .unverifiable
        case .frontmostPIDLoss:
            context.frontmostProcess.processIdentifier = nil
            context.accessibility.currentProcessIdentifier = nil
        case .accessibilityQueryFailure:
            context.accessibility.focusedElementError = .cannotComplete
        }
    }

    private func makeReviewContext(
        capability: CoordinatorAccessibilityClient.Capability,
        rebindCapability: CoordinatorAccessibilityClient.Capability? = nil,
        autoInsert: Bool = true,
        provider: any SpeechStreamingSessionProviding,
        recorder suppliedRecorder: CoordinatorAudioRecorder? = nil,
        appendFactory: (any CurrentFocusProvisionalOutputSessionFactory)? = nil,
        retrySleeper: @escaping @Sendable (UInt64) async throws -> Void
    ) -> ReviewStreamingCoordinatorContext {
        let recorder = suppliedRecorder ?? CoordinatorAudioRecorder()
        let accessibility = CoordinatorAccessibilityClient(
            capability: capability,
            rebindCapability: rebindCapability
        )
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
            overlayPresenter: overlayPresenter,
            currentFocusAppendSessionFactory: appendFactory,
            streamingRetryDelay: { _ in 250_000_000 },
            streamingRetrySleeper: retrySleeper
        )
        recorder.resetTracking()
        return ReviewStreamingCoordinatorContext(
            viewModel: viewModel,
            recorder: recorder,
            accessibility: accessibility,
            output: output,
            overlayPresenter: overlayPresenter
        )
    }

    private func makeAppendRetryContext(
        capability: CoordinatorAccessibilityClient.Capability = .accessibilityUnavailable,
        rebindCapability: CoordinatorAccessibilityClient.Capability? = .accessibilityUnavailable,
        sessions: [RetryCoordinatorStreamingSession],
        sleeper: ControlledCoordinatorRetrySleeper
    ) -> AppendRetryStreamingCoordinatorContext {
        let recorder = CoordinatorAudioRecorder()
        let provider = RetryCoordinatorStreamingProvider(factoryErrors: [], sessions: sessions)
        let accessibility = CoordinatorAccessibilityClient(
            capability: capability,
            rebindCapability: rebindCapability
        )
        let output = CoordinatorFinalTextOutput()
        let overlayPresenter = CoordinatorOverlayPresenter()
        let appendSession = CoordinatorCurrentFocusAppendSession()
        let appendFactory = CoordinatorCurrentFocusAppendSessionFactory(session: appendSession)
        let viewModel = MainViewModel(
            audioRecorder: recorder,
            settings: AppSettings(
                appId: "configured-app",
                appSecret: "configured-secret",
                autoInsert: true,
                playSound: false
            ),
            hotKeyWakeRecovering: TrackingHotKeyWakeRecoverer(),
            streamingProvider: provider,
            accessibilityClient: accessibility,
            finalTextOutput: output,
            overlayPresenter: overlayPresenter,
            currentFocusAppendSessionFactory: appendFactory,
            streamingRetryDelay: { ordinal in
                UInt64(250_000_000) << UInt64(max(0, ordinal - 1))
            },
            streamingRetrySleeper: { nanoseconds in
                try await sleeper.sleep(nanoseconds: nanoseconds)
            }
        )
        recorder.resetTracking()
        return AppendRetryStreamingCoordinatorContext(
            viewModel: viewModel,
            recorder: recorder,
            provider: provider,
            accessibility: accessibility,
            output: output,
            overlayPresenter: overlayPresenter,
            appendSession: appendSession,
            appendFactory: appendFactory
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
        visibleFeedback(viewModel).contains(transcript)
    }

    private func visibleFeedback(_ viewModel: MainViewModel) -> String {
        String(describing: viewModel.status) + viewModel.status.text + (viewModel.overlayMessage ?? "")
    }

    private func isError(_ state: RecordingState) -> Bool {
        if case .error = state {
            return true
        }
        return false
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

private struct CoordinatorFinalOnlyRoute {
    let capability: CoordinatorAccessibilityClient.Capability
    let rebindCapability: CoordinatorAccessibilityClient.Capability?
    let generation: UInt64
}

private struct ReleaseAdmissionScenario {
    let generation: UInt64
    let partial: String
    let final: String
    let expected: [String]
}

private enum ProductionCapturedDriftScenario: String, CaseIterable {
    case focusedElement
    case secureInput
    case secureToken
    case unverifiableToken
    case frontmostPIDLoss
    case accessibilityQueryFailure
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
private struct RetryStreamingCoordinatorContext {
    let viewModel: MainViewModel
    let recorder: CoordinatorAudioRecorder
    let provider: RetryCoordinatorStreamingProvider
    let accessibility: CoordinatorAccessibilityClient
    let output: CoordinatorFinalTextOutput
    let overlayPresenter: CoordinatorOverlayPresenter
}

@MainActor
private struct AppendStreamingCoordinatorContext {
    let viewModel: MainViewModel
    let recorder: CoordinatorAudioRecorder
    let transport: CoordinatorStreamingSession
    let provider: CoordinatorStreamingProvider
    let accessibility: CoordinatorAccessibilityClient
    let output: CoordinatorFinalTextOutput
    let overlayPresenter: CoordinatorOverlayPresenter
    let appendSession: CoordinatorCurrentFocusAppendSession
    let appendFactory: CoordinatorCurrentFocusAppendSessionFactory
}

@MainActor
private struct ProductionCapturedAppendContext {
    let viewModel: MainViewModel
    let recorder: CoordinatorAudioRecorder
    let transport: CoordinatorStreamingSession
    let provider: CoordinatorStreamingProvider
    let accessibility: CoordinatorAccessibilityClient
    let output: CoordinatorFinalTextOutput
    let overlayPresenter: CoordinatorOverlayPresenter
    let unicodePoster: CoordinatorProductionUnicodePoster
    let secureInput: CoordinatorMutableSecureInputProvider
    let frontmostProcess: CoordinatorMutableProcessProvider
}

@MainActor
private struct AppendRetryStreamingCoordinatorContext {
    let viewModel: MainViewModel
    let recorder: CoordinatorAudioRecorder
    let provider: RetryCoordinatorStreamingProvider
    let accessibility: CoordinatorAccessibilityClient
    let output: CoordinatorFinalTextOutput
    let overlayPresenter: CoordinatorOverlayPresenter
    let appendSession: CoordinatorCurrentFocusAppendSession
    let appendFactory: CoordinatorCurrentFocusAppendSessionFactory
}

@MainActor
private struct ReviewStreamingCoordinatorContext {
    let viewModel: MainViewModel
    let recorder: CoordinatorAudioRecorder
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
private final class ReviewAsyncCompletionProbe {
    private(set) var completed = false

    func markCompleted() {
        completed = true
    }
}

@MainActor
private final class CoordinatorOverlayPresenter: RecordingOverlayPresenting {
    private(set) var visibleStatus: RecordingState?
    private(set) var lastCompletionFeedback: RecordingState?
    private(set) var lastMinimumVisibleDuration: TimeInterval?
    private(set) var hideCallCount = 0
    private(set) var completionFeedbacks: [RecordingState] = []
    private var remainingVisibleDuration: TimeInterval?

    func show(status: RecordingState) {
        visibleStatus = status
        remainingVisibleDuration = nil
    }

    func update(status: RecordingState) {
        visibleStatus = status
    }

    func hide() {
        hideCallCount += 1
        visibleStatus = nil
        remainingVisibleDuration = nil
    }

    func presentCompletionFeedback(
        _ feedback: RecordingState,
        minimumVisibleDuration: TimeInterval
    ) {
        completionFeedbacks.append(feedback)
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

@MainActor
private final class CoordinatorCurrentFocusAppendSession: CurrentFocusProvisionalOutputSession {
    private var applyOutcomes: [CurrentFocusAppendOutcome]
    private var finalOutcomes: [CurrentFocusAppendFinalOutcome]
    private(set) var appliedTexts: [String] = []
    private(set) var appliedSources: [String] = []
    private(set) var finalTexts: [String?] = []
    private(set) var lastAcceptedTexts: [String?] = []
    private(set) var postAttemptCount = 0
    private(set) var finalizeCallCount = 0
    private(set) var invalidateCallCount = 0

    init(
        applyOutcomes: [CurrentFocusAppendOutcome] = [],
        finalOutcomes: [CurrentFocusAppendFinalOutcome] = []
    ) {
        self.applyOutcomes = applyOutcomes
        self.finalOutcomes = finalOutcomes
    }

    func applyOpaqueHypothesis(
        _ text: String,
        generation: UInt64,
        source: CurrentFocusHypothesisSource
    ) -> CurrentFocusAppendOutcome {
        appliedTexts.append(text)
        switch source {
        case .livePacket:
            appliedSources.append("live")
        case .replayCatchUp:
            appliedSources.append("replay")
        }
        let outcome: CurrentFocusAppendOutcome
        if !applyOutcomes.isEmpty {
            outcome = applyOutcomes.removeFirst()
        } else {
            outcome = appliedTexts.count == 1 ? .insertedFirst : .appendedSuffix
        }
        switch outcome {
        case .insertedFirst, .appendedSuffix, .deliveryUncertain, .securityRejected:
            postAttemptCount += 1
        case .duplicate, .revisionSuppressed, .contentless, .unsafeTextSuppressed,
             .destinationChanged, .staleGeneration:
            break
        }
        return outcome
    }

    func finalize(
        finalText: String?,
        lastAcceptedText: String?,
        generation: UInt64
    ) -> CurrentFocusAppendFinalOutcome {
        finalizeCallCount += 1
        finalTexts.append(finalText)
        lastAcceptedTexts.append(lastAcceptedText)
        if !finalOutcomes.isEmpty {
            return finalOutcomes.removeFirst()
        }
        return .preservedDivergence
    }

    func invalidate() {
        invalidateCallCount += 1
    }
}

@MainActor
private final class CoordinatorCurrentFocusAppendSessionFactory: CurrentFocusProvisionalOutputSessionFactory {
    private let session: CoordinatorCurrentFocusAppendSession
    private let returnsSession: Bool
    private(set) var makeSessionCallCount = 0
    private(set) var generations: [UInt64] = []

    init(session: CoordinatorCurrentFocusAppendSession, returnsSession: Bool = true) {
        self.session = session
        self.returnsSession = returnsSession
    }

    func makeSession(generation: UInt64) -> (any CurrentFocusProvisionalOutputSession)? {
        makeSessionCallCount += 1
        generations.append(generation)
        return returnsSession ? session : nil
    }
}

private actor ControlledCoordinatorRetrySleeper {
    private(set) var delays: [UInt64] = []
    private var continuations: [CheckedContinuation<Void, Error>] = []

    var callCount: Int {
        delays.count
    }

    func sleep(nanoseconds: UInt64) async throws {
        delays.append(nanoseconds)
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func releaseNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

private enum ReviewPacketOutcome {
    case event(StreamingRecognitionEvent)
    case failure(StreamFailure)
}

private actor ReviewControllableStreamingSession: SpeechStreamingSession {
    private var packetOutcomes: [ReviewPacketOutcome]
    private let finishOutcome: ReviewPacketOutcome
    private let holdSendCallNumber: Int?
    private let cancelHeldSendOutcome: ReviewPacketOutcome?
    private let holdCancelCompletion: Bool
    private var heldContinuation: CheckedContinuation<StreamingRecognitionEvent, Error>?
    private var heldOutcome: ReviewPacketOutcome?
    private var cancelCompletionContinuation: CheckedContinuation<Void, Never>?
    private(set) var sendCallCount = 0
    private(set) var finishCallCount = 0
    private(set) var cancelCallCount = 0

    var isHoldingSend: Bool {
        heldContinuation != nil
    }

    var isHoldingCancelCompletion: Bool {
        cancelCompletionContinuation != nil
    }

    init(
        packetOutcomes: [ReviewPacketOutcome],
        holdSendCallNumber: Int? = nil,
        finishOutcome: ReviewPacketOutcome = .event(.cancelled),
        cancelHeldSendOutcome: ReviewPacketOutcome? = nil,
        holdCancelCompletion: Bool = false
    ) {
        self.packetOutcomes = packetOutcomes
        self.holdSendCallNumber = holdSendCallNumber
        self.finishOutcome = finishOutcome
        self.cancelHeldSendOutcome = cancelHeldSendOutcome
        self.holdCancelCompletion = holdCancelCompletion
    }

    func sendAudioPacket(_ pcm16: Data) async throws -> StreamingRecognitionEvent {
        _ = pcm16
        sendCallCount += 1
        let outcome = packetOutcomes.isEmpty
            ? ReviewPacketOutcome.event(.partial(""))
            : packetOutcomes.removeFirst()
        guard sendCallCount == holdSendCallNumber else {
            return try resolve(outcome)
        }
        heldOutcome = outcome
        return try await withCheckedThrowingContinuation { continuation in
            heldContinuation = continuation
        }
    }

    func releaseHeldIfNeeded() {
        guard let continuation = heldContinuation, let outcome = heldOutcome else { return }
        heldContinuation = nil
        heldOutcome = nil
        switch outcome {
        case .event(let event):
            continuation.resume(returning: event)
        case .failure(let failure):
            continuation.resume(throwing: failure)
        }
    }

    func finish() async throws -> StreamingRecognitionEvent {
        finishCallCount += 1
        return try resolve(finishOutcome)
    }

    func cancel() async {
        cancelCallCount += 1
        heldOutcome = nil
        if let heldContinuation {
            switch cancelHeldSendOutcome {
            case .event(let event):
                heldContinuation.resume(returning: event)
            case .failure(let failure):
                heldContinuation.resume(throwing: failure)
            case nil:
                heldContinuation.resume(throwing: CancellationError())
            }
        }
        heldContinuation = nil
        if holdCancelCompletion {
            await withCheckedContinuation { continuation in
                cancelCompletionContinuation = continuation
            }
        }
    }

    func releaseCancelCompletionIfNeeded() {
        cancelCompletionContinuation?.resume()
        cancelCompletionContinuation = nil
    }

    private func resolve(_ outcome: ReviewPacketOutcome) throws -> StreamingRecognitionEvent {
        switch outcome {
        case .event(let event):
            return event
        case .failure(let failure):
            throw failure
        }
    }
}

private actor ImmediateReviewRetrySleeper {
    private(set) var delays: [UInt64] = []

    var callCount: Int {
        delays.count
    }

    func sleep(nanoseconds: UInt64) {
        delays.append(nanoseconds)
    }
}

private actor CooperativeReviewRetrySleeper {
    private var continuation: CheckedContinuation<Void, Error>?
    private var cancellationRequested = false
    private(set) var callCount = 0
    private(set) var cancellationCount = 0

    func sleep(nanoseconds: UInt64) async throws {
        _ = nanoseconds
        callCount += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                if cancellationRequested {
                    continuation.resume(throwing: CancellationError())
                } else {
                    self.continuation = continuation
                }
            }
        } onCancel: {
            Task {
                await self.cancelPending()
            }
        }
    }

    func releaseIfNeeded() {
        continuation?.resume()
        continuation = nil
    }

    private func cancelPending() {
        guard !cancellationRequested else { return }
        cancellationRequested = true
        cancellationCount += 1
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

private struct ReviewUnclassifiedError: Error {}

private actor ReviewFactoryPlanProvider: SpeechStreamingSessionProviding {
    private var errors: [any Error]
    private let successor: any SpeechStreamingSession
    private(set) var makeSessionCallCount = 0

    init(errors: [any Error], successor: any SpeechStreamingSession) {
        self.errors = errors
        self.successor = successor
    }

    func makeStreamingSession(
        appId: String,
        appSecret: String
    ) async throws -> any SpeechStreamingSession {
        _ = appId
        _ = appSecret
        makeSessionCallCount += 1
        if !errors.isEmpty {
            throw errors.removeFirst()
        }
        return successor
    }
}

private actor CooperativeReviewSessionCreationProvider: SpeechStreamingSessionProviding {
    private let lateSession: any SpeechStreamingSession
    private var continuation: CheckedContinuation<any SpeechStreamingSession, Error>?
    private var cancellationRequested = false
    private(set) var makeSessionCallCount = 0
    private(set) var cancellationCount = 0

    init(lateSession: any SpeechStreamingSession) {
        self.lateSession = lateSession
    }

    func makeStreamingSession(
        appId: String,
        appSecret: String
    ) async throws -> any SpeechStreamingSession {
        _ = appId
        _ = appSecret
        makeSessionCallCount += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<any SpeechStreamingSession, Error>) in
                if cancellationRequested {
                    continuation.resume(throwing: CancellationError())
                } else {
                    self.continuation = continuation
                }
            }
        } onCancel: {
            Task {
                await self.cancelPendingCreation()
            }
        }
    }

    func releaseLateSessionIfNeeded() {
        continuation?.resume(returning: lateSession)
        continuation = nil
    }

    private func cancelPendingCreation() {
        guard !cancellationRequested else { return }
        cancellationRequested = true
        cancellationCount += 1
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

private actor RetryCoordinatorStreamingSession: SpeechStreamingSession {
    private var packetEvents: [StreamingRecognitionEvent]
    private let finishEvent: StreamingRecognitionEvent
    private(set) var sendCallCount = 0
    private(set) var finishCallCount = 0
    private(set) var cancelCallCount = 0
    private(set) var packetFirstBytes: [UInt8] = []

    init(
        packetEvents: [StreamingRecognitionEvent],
        finishEvent: StreamingRecognitionEvent = .cancelled
    ) {
        self.packetEvents = packetEvents
        self.finishEvent = finishEvent
    }

    func sendAudioPacket(_ pcm16: Data) async throws -> StreamingRecognitionEvent {
        sendCallCount += 1
        packetFirstBytes.append(pcm16.first ?? 0)
        guard !packetEvents.isEmpty else { return .partial("") }
        return packetEvents.removeFirst()
    }

    func finish() async throws -> StreamingRecognitionEvent {
        finishCallCount += 1
        return finishEvent
    }

    func cancel() async {
        cancelCallCount += 1
    }
}

private actor RetryCoordinatorStreamingProvider: SpeechStreamingSessionProviding {
    private var factoryErrors: [FeishuAPIService.APIError]
    private var sessions: [any SpeechStreamingSession]
    private(set) var makeSessionCallCount = 0

    init(
        factoryErrors: [FeishuAPIService.APIError],
        sessions: [any SpeechStreamingSession]
    ) {
        self.factoryErrors = factoryErrors
        self.sessions = sessions
    }

    func makeStreamingSession(
        appId: String,
        appSecret: String
    ) async throws -> any SpeechStreamingSession {
        makeSessionCallCount += 1
        if !factoryErrors.isEmpty {
            throw factoryErrors.removeFirst()
        }
        guard !sessions.isEmpty else {
            throw FeishuAPIService.APIError.networkError("")
        }
        return sessions.removeFirst()
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
    private let makeSessionError: FeishuAPIService.APIError?
    private(set) var makeSessionCallCount = 0

    init(
        session: CoordinatorStreamingSession,
        makeSessionError: FeishuAPIService.APIError? = nil
    ) {
        self.session = session
        self.makeSessionError = makeSessionError
    }

    func makeStreamingSession(
        appId: String,
        appSecret: String
    ) async throws -> any SpeechStreamingSession {
        makeSessionCallCount += 1
        if let makeSessionError {
            throw makeSessionError
        }
        return session
    }
}

@MainActor
private final class CoordinatorAudioRecorder: AudioRecorder {
    private var ingress: ByteBoundedAudioIngress?
    private var holdNextStopBarrier: Bool
    private var stopBarrierContinuation: CheckedContinuation<Void, Never>?
    private(set) var startStreamingCallCount = 0
    private(set) var stopStreamingCallCount = 0
    private(set) var forceCleanupCallCount = 0
    private(set) var startedIngressIdentifiers: [ObjectIdentifier] = []
    private(set) var finishedIngressIdentifiers: [ObjectIdentifier] = []
    var onForceCleanup: (() -> Void)?

    var isHoldingStopBarrier: Bool {
        stopBarrierContinuation != nil
    }

    var activeIngressIdentifier: ObjectIdentifier? {
        ingress.map(ObjectIdentifier.init)
    }

    init(holdNextStopBarrier: Bool = false) {
        self.holdNextStopBarrier = holdNextStopBarrier
        super.init()
    }

    override func startStreamingRecording(
        ingress: ByteBoundedAudioIngress,
        completion: @escaping (_ started: Bool) -> Void
    ) -> Bool {
        startStreamingCallCount += 1
        self.ingress = ingress
        startedIngressIdentifiers.append(ObjectIdentifier(ingress))
        isRecording = true
        completion(true)
        return true
    }

    override func stopStreamingRecording(streamEstablished: Bool) async {
        stopStreamingCallCount += 1
        isRecording = false
        let stoppingIngress = ingress
        if holdNextStopBarrier {
            holdNextStopBarrier = false
            await withCheckedContinuation { continuation in
                stopBarrierContinuation = continuation
            }
        }
        stoppingIngress?.finish(streamEstablished: streamEstablished)
        if let stoppingIngress {
            finishedIngressIdentifiers.append(ObjectIdentifier(stoppingIngress))
            if ingress === stoppingIngress {
                ingress = nil
            }
        }
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

    func releaseStopBarrier() {
        stopBarrierContinuation?.resume()
        stopBarrierContinuation = nil
    }

    func resetTracking() {
        startStreamingCallCount = 0
        stopStreamingCallCount = 0
        forceCleanupCallCount = 0
        startedIngressIdentifiers = []
        finishedIngressIdentifiers = []
        onForceCleanup = nil
    }
}

@MainActor
private final class CoordinatorAccessibilityClient: AccessibilityClient {
    enum Capability: Equatable {
        case live
        case finalOnly
        case secureRejected
        case accessibilityUnavailable
        case captureThrows(AccessibilityClientError)
    }

    private let capability: Capability
    private let rebindCapability: Capability?
    private let token: CursorDestinationToken
    private(set) var captureCount = 0
    private(set) var frontmostProcessQueryCount = 0
    private(set) var focusedElementQueryCount = 0
    var currentProcessIdentifier: pid_t? = 42
    var currentFocusedElement: AXUIElement
    var selectedRange = CursorTextRange(location: 2, length: 0)
    var rangeText = ""
    var returnedWriteLengths: [Int] = []
    var currentSecurityState: DestinationSecurityState = .safe
    var securityStateError: AccessibilityClientError?
    var focusedElementError: AccessibilityClientError?
    private(set) var setSelectedTextCalls: [String] = []

    init(capability: Capability, rebindCapability: Capability? = nil) {
        self.capability = capability
        self.rebindCapability = rebindCapability
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
        let currentCapability = captureCount > 1 ? (rebindCapability ?? capability) : capability
        switch currentCapability {
        case .live:
            return .live(captured)
        case .finalOnly:
            return .finalOnly(captured)
        case .secureRejected:
            return .rejected(.secureTarget)
        case .accessibilityUnavailable:
            return .rejected(.accessibilityUnavailable)
        case .captureThrows(let error):
            throw error
        }
    }

    func frontmostProcessIdentifier() -> pid_t? {
        frontmostProcessQueryCount += 1
        return currentProcessIdentifier
    }

    func focusedElement() throws -> AXUIElement {
        focusedElementQueryCount += 1
        if let focusedElementError {
            throw focusedElementError
        }
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
    private(set) var currentFocusAttemptedTexts: [String] = []
    private(set) var currentFocusInsertedTexts: [String] = []
    private(set) var copiedTexts: [String] = []
    private(set) var syntheticInputCallCount = 0
    private(set) var destinationProcessIdentifiers: [pid_t] = []
    var onInsertOnce: (() -> Void)?
    var currentFocusInsertionResult: FinalTextInsertionResult = .inserted

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

    func insertAtCurrentFocusOnce(_ text: String) -> FinalTextInsertionResult {
        currentFocusAttemptedTexts.append(text)
        if currentFocusInsertionResult == .inserted {
            currentFocusInsertedTexts.append(text)
            syntheticInputCallCount += 1
        }
        return currentFocusInsertionResult
    }
}

@MainActor
private final class CoordinatorProductionUnicodePoster: FinalTextCurrentFocusEventPosting {
    private(set) var requestedTexts: [String] = []
    private(set) var destinationProcessIdentifiers: [pid_t] = []
    private(set) var replacementRequests: [CoordinatorReplacementRequest] = []

    func postUnicodeText(
        _ text: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult {
        requestedTexts.append(text)
        destinationProcessIdentifiers.append(processIdentifier)
        replacementRequests.append(
            CoordinatorReplacementRequest(deleteCharacterCount: 0, insertText: text)
        )
        return .posted
    }

    func postReplacement(
        deleteCharacterCount: Int,
        insertText: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult {
        requestedTexts.append(insertText)
        destinationProcessIdentifiers.append(processIdentifier)
        replacementRequests.append(
            CoordinatorReplacementRequest(
                deleteCharacterCount: deleteCharacterCount,
                insertText: insertText
            )
        )
        return .posted
    }
}

private struct CoordinatorReplacementRequest: Equatable {
    let deleteCharacterCount: Int
    let insertText: String
}

@MainActor
private final class CoordinatorMutableSecureInputProvider: SecureInputStateProviding {
    var isEnabled = false
    private(set) var queryCount = 0

    func isSecureInputEnabled() -> Bool {
        queryCount += 1
        return isEnabled
    }
}

@MainActor
private final class CoordinatorMutableProcessProvider: FrontmostProcessProviding {
    var processIdentifier: pid_t?
    private(set) var queryCount = 0

    init(processIdentifier: pid_t?) {
        self.processIdentifier = processIdentifier
    }

    func frontmostProcessIdentifier() -> pid_t? {
        queryCount += 1
        return processIdentifier
    }
}

@MainActor
private final class CoordinatorProductionActivationMonitor: CurrentFocusActivationMonitoring {
    private var handler: (@MainActor (pid_t) -> Void)?

    func startMonitoring(_ handler: @escaping @MainActor (pid_t) -> Void) {
        self.handler = handler
    }

    func stopMonitoring() {
        handler = nil
    }
}
