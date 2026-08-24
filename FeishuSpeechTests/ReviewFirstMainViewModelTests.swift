import Foundation
import AppKit
import ApplicationServices
import Combine
import SwiftUI
import os.log
import XCTest

@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "ReviewFirstMainViewModelTests"
)

@MainActor
final class ReviewFirstMainViewModelTests: XCTestCase {
    override func tearDown() async throws {
        HotKeyService.shared.resetToIdle()
        PermissionManager.shared.resetStateForTesting()
        try await super.tearDown()
    }

    func test_reviewFirst_presentsReadOnlyStreamingSurfaceAndUpdatesOpaqueSnapshot() async {
        let context = makeContext(
            packetEvents: [.partial("PRIVATE_PARTIAL")],
            finishEvent: .final("PRIVATE_FINAL")
        )
        let identity = StreamingSessionIdentity(generation: 3_801)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil {
            context.recorder.startStreamingCallCount == 1 && context.presenter.renderReadOnlyCallCount >= 1
        }

        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .streaming(preview: ""),
            "the review surface must exist while holding Fn, before any terminal result"
        )
        XCTAssertEqual(context.presenter.lastReadOnlyPreview, "")
        XCTAssertEqual(context.presenter.lastReadOnlyPhase, .streaming)

        context.recorder.emit(Data(repeating: 0x51, count: 6_400))
        await waitUntilAsync { await context.session.sendCallCount == 1 }
        await waitUntil {
            context.viewModel.transcriptionReviewState == .streaming(preview: "PRIVATE_PARTIAL") &&
                context.presenter.lastReadOnlyPreview == "PRIVATE_PARTIAL" &&
                context.presenter.lastReadOnlyPhase == .streaming
        }

        XCTAssertEqual(context.presenter.lastReadOnlyPreview, "PRIVATE_PARTIAL")
        XCTAssertEqual(context.presenter.lastReadOnlyPhase, .streaming)
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.delivery.deliveredTexts, [])
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])

        context.presenter.invokeDraftChange("PRIVATE_EDIT_ATTEMPT")
        context.presenter.invokeConfirm()
        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .streaming(preview: "PRIVATE_PARTIAL"),
            "streaming preview is read-only; editor callbacks must not mutate recognition ownership"
        )

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil {
            if case .sealing = context.viewModel.transcriptionReviewState {
                return context.presenter.lastReadOnlyPhase == .sealing
            }
            return false
        }
        XCTAssertEqual(context.presenter.lastReadOnlyPreview, "PRIVATE_PARTIAL")
        XCTAssertEqual(context.presenter.lastReadOnlyPhase, .sealing)
        context.presenter.invokeDraftChange("PRIVATE_SEALING_EDIT_ATTEMPT")
        context.presenter.invokeConfirm()
        XCTAssertEqual(Set(context.presenter.surfaceIDs), Set([context.presenter.surfaceIdentity]))
        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .sealing(preview: "PRIVATE_PARTIAL"),
            "sealing must remain read-only until authoritative action 2"
        )
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
    }

    func test_reviewFirst_multilineStreamingPreviewNeverMutatesTargetBeforeConfirmation() async {
        let multilineSnapshot = "PRIVATE_FIRST_LINE\nPRIVATE_SECOND_LINE"
        let context = makeContext(packetEvents: [.partial(multilineSnapshot)])
        context.viewModel.handleHotKeyStateForTesting(
            .streaming(sessionID: StreamingSessionIdentity(generation: 3_801))
        )
        await waitUntil { context.recorder.startStreamingCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x53, count: 6_400))
        await waitUntilAsync { await context.session.sendCallCount == 1 }
        await waitUntil { context.presenter.lastReadOnlyPreview == multilineSnapshot }

        XCTAssertEqual(context.presenter.lastReadOnlyPhase, .streaming)
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.delivery.deliveredTexts, [])
        XCTAssertEqual(context.delivery.copyCalls, 0)
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
    }

    func test_reviewFirst_actionTwoFinalTransitionsSameSurfaceToEditableAndOnlyConfirmDelivers() async {
        let context = makeContext(finishEvent: .final("PRIVATE_ACTION_TWO"))
        let identity = StreamingSessionIdentity(generation: 3_802)

        await startAndSeal(context, identity: identity)

        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .editable(draft: "PRIVATE_ACTION_TWO", isPossiblyIncomplete: false)
        )
        XCTAssertEqual(context.presenter.lastEditableDraft, "PRIVATE_ACTION_TWO")
        XCTAssertEqual(context.presenter.lastReadOnlyPhase, .sealing)
        XCTAssertEqual(Set(context.presenter.surfaceIDs), Set([context.presenter.surfaceIdentity]))
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.delivery.deliveredTexts, [])

        context.presenter.invokeDraftChange("PRIVATE_EDITED_DRAFT")
        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .editable(draft: "PRIVATE_EDITED_DRAFT", isPossiblyIncomplete: false)
        )

        context.presenter.invokeConfirm()
        context.presenter.invokeConfirm()
        await waitUntil { context.delivery.deliveredTexts.count == 1 }
        await waitUntil { context.viewModel.transcriptionReviewState == .idle }

        XCTAssertEqual(context.delivery.deliveredTexts, ["PRIVATE_EDITED_DRAFT"])
        XCTAssertEqual(context.delivery.copyCalls, 0)
        XCTAssertEqual(context.viewModel.transcriptionReviewState, .idle)
        XCTAssertEqual(context.viewModel.reviewDraftText, "")
        XCTAssertGreaterThanOrEqual(context.presenter.dismissCallCount, 1)
    }

    func test_reviewFirst_confirmationFreezesExactCurrentNonWhitespaceDraftAndDeliversOnce() async {
        let context = makeContext(finishEvent: .final("PRIVATE_FINAL"))
        let identity = StreamingSessionIdentity(generation: 3_839)
        let draft = "  PRIVATE_EDITED_DRAFT\n"

        await startAndSeal(context, identity: identity)
        context.presenter.invokeDraftChange(draft)
        context.presenter.invokeConfirm()
        context.presenter.invokeConfirm()
        await waitUntil { context.delivery.deliveredTexts.count == 1 }
        await waitUntil { context.viewModel.transcriptionReviewState == .idle }

        XCTAssertEqual(
            context.delivery.deliveredTexts,
            [draft],
            "confirmation must deliver the current non-whitespace draft without trimming or normalizing"
        )
        XCTAssertEqual(context.delivery.copyCalls, 0)
        XCTAssertEqual(context.viewModel.transcriptionReviewState, .idle)
        XCTAssertEqual(context.viewModel.reviewDraftText, "")
        XCTAssertGreaterThanOrEqual(context.presenter.dismissCallCount, 1)
    }

    func test_reviewFirst_realProductionSurfaceMakesFrozenDraftConfirmableWithoutRetryEditing() async throws {
        let production = ReviewWindowController.ReadinessEnvironment.appKit
        let firstResponderProbe = Issue40ProductionFirstResponderProbe()
        let controller = ReviewWindowController(
            readinessEnvironment: ReviewWindowController.ReadinessEnvironment(
                requestActivation: { true },
                applicationIsActive: { true },
                frontmostApplication: { Issue38ReviewDestinationDelivery.testApplicationIdentity },
                feishuSpeechIsActive: { false },
                panelIsKey: { _ in true },
                editorLookup: production.editorLookup,
                editorAttached: production.editorAttached,
                makeFirstResponder: { panel, editor in
                    firstResponderProbe.make(panel: panel, editor: editor)
                },
                firstResponderIsEditor: { panel, editor in
                    firstResponderProbe.check(panel: panel, editor: editor)
                },
                nowNanoseconds: production.nowNanoseconds,
                sleep: production.sleep
            )
        )
        let presenter = Issue40ProductionReviewSurfacePresenter(controller: controller)
        let context = makeProductionReviewContext(
            finishEvent: .final("PRIVATE_REAL_PRODUCTION_DRAFT"),
            presenter: presenter
        )
        defer { controller.dismiss() }

        await startAndSealProduction(
            context,
            identity: StreamingSessionIdentity(generation: 3_842)
        )
        await settle()

        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .editable(
                draft: "PRIVATE_REAL_PRODUCTION_DRAFT",
                isPossiblyIncomplete: false,
                feedback: nil
            ),
            "a genuinely ready production surface must transition out of pending into confirmable editable state"
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await waitUntil {
            firstResponderProbe.makeCallCount > 0 &&
                firstResponderProbe.checkCallCount > 0
        }
        let panel = try XCTUnwrap(presenter.retainedPanel)
        let editor = try XCTUnwrap(
            editableTextView(in: panel.contentView),
            "production presenter must materialize the native editable editor"
        )
        XCTAssertTrue(editor.isEditable)
        XCTAssertTrue(editor.window === panel)
        XCTAssertTrue(
            firstResponderProbe.requestedEditorWasAttached,
            "readiness must request the real attached editor as first responder"
        )
        XCTAssertGreaterThan(firstResponderProbe.makeCallCount, 0)
        XCTAssertGreaterThan(firstResponderProbe.checkCallCount, 0)
        XCTAssertTrue(
            presenter.renderedStates.contains {
                if case .editable = $0 { return true }
                return false
            },
            "the real presenter must render the confirmable editable state"
        )
        XCTAssertEqual(context.delivery.deliveredTexts, [])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])

        presenter.invokeConfirm()
        await waitUntil { context.delivery.deliveredTexts.count == 1 }
        XCTAssertEqual(
            context.delivery.deliveredTexts,
            ["PRIVATE_REAL_PRODUCTION_DRAFT"],
            "only the explicit confirm callback may deliver the frozen draft"
        )
        XCTAssertEqual(context.delivery.copyCalls, 0)
    }

    func test_reviewFirst_realControllerRecoveryRendersEditableAgainAndRoutesSecondSend() async throws {
        let controller = ReviewWindowController(
            readinessEnvironment: ReviewWindowController.ReadinessEnvironment(
                requestActivation: { false },
                applicationIsActive: { true },
                frontmostApplication: { nil },
                feishuSpeechIsActive: { false },
                panelIsKey: { _ in true },
                editorLookup: { [self] view in self.editableTextView(in: view) },
                editorAttached: { editor, panel in editor.window === panel },
                makeFirstResponder: { panel, editor in panel.makeFirstResponder(editor) },
                firstResponderIsEditor: { panel, editor in panel.firstResponder === editor },
                nowNanoseconds: { DispatchTime.now().uptimeNanoseconds },
                sleep: { nanoseconds in try await Task.sleep(nanoseconds: nanoseconds) }
            )
        )
        let presenter = Issue40ProductionReviewSurfacePresenter(controller: controller)
        var currentDraft = "PRIVATE_RECOVERY_A"
        var callbackDrafts: [String] = []
        let onDraftChange: @MainActor (String) -> Void = { draft in
            currentDraft = draft
        }
        let onConfirm: @MainActor (ReviewConfirmationIntent) -> Void = { _ in
            callbackDrafts.append(currentDraft)
        }
        let onDiscard: @MainActor () -> Void = {}
        defer { controller.dismiss() }

        presenter.renderDraft(
            state: .editable(draft: currentDraft, isPossiblyIncomplete: false, feedback: nil),
            onDraftChange: onDraftChange,
            onConfirm: onConfirm,
            onDiscard: onDiscard
        )
        let firstPanel = try XCTUnwrap(presenter.retainedPanel)
        XCTAssertTrue(presenter.invokeSend(), "the first Send must use the real controller/panel gesture")
        XCTAssertEqual(callbackDrafts, ["PRIVATE_RECOVERY_A"])

        presenter.renderDraft(
            state: .preparingSubmission(draft: currentDraft, isPossiblyIncomplete: false),
            onDraftChange: onDraftChange,
            onConfirm: onConfirm,
            onDiscard: onDiscard
        )
        presenter.renderDraft(
            state: .editable(
                draft: currentDraft,
                isPossiblyIncomplete: false,
                feedback: .deliveryUncertain
            ),
            onDraftChange: onDraftChange,
            onConfirm: onConfirm,
            onDiscard: onDiscard
        )
        presenter.replaceDraft("PRIVATE_RECOVERY_B")
        XCTAssertEqual(currentDraft, "PRIVATE_RECOVERY_B")
        XCTAssertTrue(presenter.retainedPanel === firstPanel, "recovery must retain the same production ReviewPanel")
        XCTAssertTrue(
            presenter.invokeSend(),
            "recovered editable A must accept an edited B and route a second real Send"
        )
        XCTAssertEqual(callbackDrafts, ["PRIVATE_RECOVERY_A", "PRIVATE_RECOVERY_B"])
        XCTAssertEqual(presenter.confirmGestureCount, 2)
    }

    func test_v5CoordinatorProductionFacadeUsesOneHandleAndTerminalStateCannotResend() async {
        let facade = V5ReviewSubmissionFacadeSpy()
        let production = ReviewWindowController.ReadinessEnvironment.appKit
        let controller = ReviewWindowController(
            readinessEnvironment: ReviewWindowController.ReadinessEnvironment(
                requestActivation: { false },
                applicationIsActive: { true },
                frontmostApplication: { facade.identity },
                feishuSpeechIsActive: { false },
                panelIsKey: { _ in true },
                editorLookup: production.editorLookup,
                editorAttached: production.editorAttached,
                makeFirstResponder: production.makeFirstResponder,
                firstResponderIsEditor: production.firstResponderIsEditor,
                nowNanoseconds: production.nowNanoseconds,
                sleep: production.sleep
            )
        )
        let recorder = Issue38ReviewAudioRecorder(holdStopBarrier: false)
        let session = Issue38ReviewStreamingSession(
            packetEvents: [.partial("PRIVATE_FACADE_PARTIAL")],
            finishEvent: .final("PRIVATE_FACADE_FINAL")
        )
        let provider = Issue38ReviewStreamingProvider(session: session)
        let presenter = Issue40ProductionReviewSurfacePresenter(controller: controller)
        let delivery = Issue38ReviewDestinationDelivery()
        defer { controller.dismiss() }
        let viewModel = MainViewModel(
            audioRecorder: recorder,
            settings: AppSettings(
                appId: "configured-app",
                appSecret: "configured-secret",
                autoInsert: true,
                playSound: false,
                reviewBeforeInsert: true
            ),
            hotKeyWakeRecovering: TrackingHotKeyWakeRecoverer(),
            streamingProvider: provider,
            overlayPresenter: Issue38ReviewOverlayPresenter(),
            reviewDestinationDelivery: nil,
            reviewSubmissionFacade: facade,
            reviewSurfacePresenter: presenter
        )
        let identity = StreamingSessionIdentity(generation: 5_100)

        viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { recorder.startStreamingCallCount == 1 }
        recorder.emit(Data(repeating: 0x55, count: 6_400))
        await waitUntilAsync { await session.sendCallCount == 1 }
        await waitUntil {
            if case .streaming = viewModel.transcriptionReviewState {
                return facade.captureRequests.count == 1 && facade.captureCompletedCount == 1
            }
            return false
        }
        await waitUntilAsync { await provider.makeSessionCallCount == 1 }
        await settle()
        viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntilAsync { await session.finishCallCount == 1 }
        // The production consumer owns the terminal flag on the finish event;
        // allow that MainActor admission to run before asserting the editable
        // transition.  The DEBUG event hook is intentionally non-terminal and
        // must not be used as a coordinator bypass here.
        await settle()
        await waitUntil {
            if case .editable = viewModel.transcriptionReviewState {
                return true
            }
            return false
        }

        presenter.replaceDraft("PRIVATE_FACADE_EDIT")
        // Use the real retained ReviewPanel's visible Send mouse route as the
        // opaque confirmation source. Native Return is independently pinned
        // by the controller readiness suite, while this case exercises the
        // production coordinator/facade admission contract.
        XCTAssertTrue(presenter.invokeConfirm())
        _ = presenter.invokeConfirm()
        XCTAssertEqual(presenter.confirmGestureCount, 1)
        await waitUntil {
            if case .preparingSubmission = viewModel.transcriptionReviewState {
                return facade.admissionEnvelopes.count == 1
            }
            return false
        }
        guard let firstEnvelope = facade.admissionEnvelopes.first else {
            return XCTFail("the production facade must receive one admission envelope")
        }
        XCTAssertEqual(facade.issuedHandleCount, 1)
        XCTAssertEqual(facade.startedHandles, [])
        let firstHandle = firstEnvelope.handle
        facade.emit(.admissionAccepted(firstHandle))
        await waitUntil { facade.startedHandles == [firstHandle] }
        facade.emit(.terminal(firstHandle, .notStarted(.cancellation)))
        await waitUntil {
            if case .editable(
                let draft,
                _,
                feedback: .deliveryCancelled
            ) = viewModel.transcriptionReviewState {
                return draft == "PRIVATE_FACADE_EDIT"
            }
            return false
        }

        // The coordinator publishes the editable recovery state before the
        // presenter receives its replacement render on the MainActor.
        await settle()
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(
            presenter.renderedStates.contains {
                if case .editable(_, _, feedback: .deliveryCancelled) = $0 { return true }
                return false
            },
            "cancellation must re-render the retained draft as editable before explicit retry"
        )
        presenter.replaceDraft("PRIVATE_FACADE_RETRY")
        await settle()
        XCTAssertTrue(presenter.invokeConfirm())
        XCTAssertEqual(presenter.confirmGestureCount, 2)
        await waitUntil {
            if case .preparingSubmission = viewModel.transcriptionReviewState {
                return facade.admissionEnvelopes.count == 2
            }
            return false
        }
        guard facade.admissionEnvelopes.count == 2 else {
            return XCTFail("the explicit retry must create exactly one new admission envelope")
        }
        let secondHandle = facade.admissionEnvelopes[1].handle
        XCTAssertNotEqual(firstHandle, secondHandle)
        XCTAssertEqual(facade.admissionEnvelopes[1].request.frozenDraft, "PRIVATE_FACADE_RETRY")
        facade.emit(.admissionAccepted(secondHandle))
        await waitUntil { facade.startedHandles == [firstHandle, secondHandle] }
        facade.emit(
            .terminal(
                secondHandle,
                .submittedUnverified(
                    ReviewPostBoundaryObservation(
                        mandatoryKeyUpAttempted: true,
                        cancellationObservedAfterDown: false,
                        postflightStable: true
                    )
                )
            )
        )
        for _ in 0 ..< 200 {
            if case .submittedUnverifiedTerminal(let draft, _, _) = viewModel.transcriptionReviewState,
               draft == "PRIVATE_FACADE_RETRY" {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(
            viewModel.transcriptionReviewState,
            .idle,
            "a submitted-unverified terminal receipt must dismiss the ordinary preview and return the review axis to idle"
        )
        XCTAssertEqual(
            viewModel.reviewDraftText,
            "",
            "terminal uncertainty must not leave transcript text projected into the ordinary preview"
        )
        XCTAssertNil(
            presenter.retainedPanel,
            "terminal uncertainty must dismiss the retained ReviewPanel"
        )
        XCTAssertFalse(
            presenter.hasSendControl,
            "submitted-unverified terminal state must not expose a resend control"
        )
        XCTAssertEqual(facade.issuedHandleCount, 2)
        XCTAssertEqual(facade.releasedTargetIDs, [facade.target.targetID])
        XCTAssertEqual(delivery.deliveredTexts, [])
    }

    func test_reviewFirst_repeatedBareReturnFromNativeEditorDeliversExactDraftOnce() async throws {
        let nativePresenter = Issue39NativeReviewSurfacePresenter()
        let context = makeContext(
            finishEvent: .final("PRIVATE_NATIVE_FINAL"),
            reviewSurfacePresenter: nativePresenter
        )
        let identity = StreamingSessionIdentity(generation: 3_840)
        let editedDraft = "  PRIVATE_NATIVE_EDIT\n"

        defer { nativePresenter.dismiss() }
        await startAndSeal(context, identity: identity)

        let window = try XCTUnwrap(nativePresenter.window)
        let editor = try XCTUnwrap(nativePresenter.editor)
        XCTAssertTrue(window.firstResponder === editor)

        let initialRange = NSRange(location: 0, length: editor.string.utf16.count)
        editor.setSelectedRange(initialRange)
        editor.insertText(editedDraft, replacementRange: initialRange)
        XCTAssertEqual(context.viewModel.reviewDraftText, editedDraft)

        for _ in 0 ..< 2 {
            nativePresenter.invokeQualifiedReturnIntent()
        }

        await waitUntil { context.delivery.deliveredTexts.count == 1 }
        await waitUntil { context.viewModel.transcriptionReviewState == .idle }
        XCTAssertEqual(context.delivery.deliveredTexts, [editedDraft])
        XCTAssertEqual(context.delivery.copyCalls, 0)
        XCTAssertEqual(context.viewModel.transcriptionReviewState, .idle)
        XCTAssertEqual(context.viewModel.reviewDraftText, "")
        XCTAssertNil(nativePresenter.window)
    }

    func test_v5CoordinatorExpiredStartPreservesExactDraftAndRequiresNewRealConfirmation() async throws {
        let facade = V5ExpiredStartReviewSubmissionFacade()
        let production = ReviewWindowController.ReadinessEnvironment.appKit
        let controller = ReviewWindowController(
            readinessEnvironment: ReviewWindowController.ReadinessEnvironment(
                requestActivation: { false },
                applicationIsActive: { true },
                frontmostApplication: { facade.identity },
                feishuSpeechIsActive: { false },
                panelIsKey: { _ in true },
                editorLookup: production.editorLookup,
                editorAttached: production.editorAttached,
                makeFirstResponder: production.makeFirstResponder,
                firstResponderIsEditor: production.firstResponderIsEditor,
                nowNanoseconds: production.nowNanoseconds,
                sleep: production.sleep
            )
        )
        let presenter = Issue40ProductionReviewSurfacePresenter(controller: controller)
        let context = makeProductionReviewContext(
            finishEvent: .final("PRIVATE_EXPIRED_START_DRAFT"),
            presenter: presenter,
            reviewSubmissionFacade: facade
        )
        defer { controller.dismiss() }

        await startAndSealProduction(
            context,
            identity: StreamingSessionIdentity(generation: 5_210),
            captureReady: { facade.captureCompletedCount == 1 }
        )
        XCTAssertEqual(facade.captureCompletedCount, 1, "production facade capture must complete during action 1")
        presenter.replaceDraft("PRIVATE_EXPIRED_START_DRAFT_EDITED")
        XCTAssertTrue(presenter.invokeSend(), "the first real Send must create one admission")
        await waitUntil { facade.admissionEnvelopes.count == 1 }
        await waitUntilDelayed {
            facade.observedEvents.contains { event in
                if case .terminal = event { return true }
                return false
            }
        }
        await waitUntilDelayed {
            if case .editable(
                let draft,
                _,
                feedback: .deliveryFailed
            ) = context.viewModel.transcriptionReviewState {
                return draft == "PRIVATE_EXPIRED_START_DRAFT_EDITED"
            }
            return false
        }

        XCTAssertEqual(facade.issuedHandleCount, 1)
        XCTAssertEqual(facade.enqueueStartCallCount, 1)
        XCTAssertEqual(
            context.viewModel.reviewDraftText,
            "PRIVATE_EXPIRED_START_DRAFT_EDITED"
        )
        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .editable(
                draft: "PRIVATE_EXPIRED_START_DRAFT_EDITED",
                isPossiblyIncomplete: false,
                feedback: .deliveryFailed
            )
        )
        XCTAssertEqual(
            presenter.confirmGestureCount,
            1,
            "deadline terminalization must not synthesize a second confirmation"
        )

        XCTAssertTrue(
            presenter.invokeSend(),
            "only a new real Send gesture may create the replacement attempt"
        )
        await waitUntilDelayed { facade.issuedHandleCount == 2 }
        XCTAssertEqual(presenter.confirmGestureCount, 2)
    }

    func test_reviewFirst_nonterminalFinalIsStillReadOnlyUntilAuthoritativeActionTwo() async {
        let context = makeContext(
            packetEvents: [.final("PRIVATE_NONTERMINAL_FINAL")],
            finishEvent: .final("PRIVATE_ACTION_TWO_FINAL")
        )
        let identity = StreamingSessionIdentity(generation: 3_815)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { context.recorder.startStreamingCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x55, count: 6_400))
        await waitUntilAsync { await context.session.sendCallCount == 1 }

        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .streaming(preview: "PRIVATE_NONTERMINAL_FINAL")
        )
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.delivery.deliveredTexts, [])
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil {
            context.viewModel.transcriptionReviewState ==
                .editable(draft: "PRIVATE_ACTION_TWO_FINAL", isPossiblyIncomplete: false)
        }
    }

    func test_reviewFirst_duplicateSnapshotsAreSuppressedWithoutReopeningOrMutatingEditor() async {
        let context = makeContext(
            packetEvents: [
                .partial("PRIVATE_DUPLICATE"),
                .partial("PRIVATE_DUPLICATE")
            ],
            finishEvent: .cancelled
        )
        let identity = StreamingSessionIdentity(generation: 3_816)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { context.recorder.startStreamingCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x56, count: 6_400))
        await waitUntilAsync { await context.session.sendCallCount == 1 }
        await waitUntil {
            context.presenter.lastReadOnlyPreview == "PRIVATE_DUPLICATE" &&
                context.presenter.lastReadOnlyPhase == .streaming
        }
        let presentationCountAfterFirstSnapshot = context.presenter.renderReadOnlyCallCount

        context.recorder.emit(Data(repeating: 0x57, count: 6_400))
        await waitUntilAsync { await context.session.sendCallCount == 2 }

        XCTAssertEqual(context.presenter.renderReadOnlyCallCount, presentationCountAfterFirstSnapshot)
        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .streaming(preview: "PRIVATE_DUPLICATE")
        )
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
    }

    func test_reviewFirst_changedShorterOpaqueSnapshotReplacesInFullAndReplayStaysSuppressed() async {
        let context = makeContext(
            packetEvents: [
                .partial("PRIVATE_LONG_SNAPSHOT"),
                .partial("PRIVATE_SHORT"),
                .partial("PRIVATE_SHORT")
            ],
            finishEvent: .cancelled
        )
        let identity = StreamingSessionIdentity(generation: 3_819)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { context.recorder.startStreamingCallCount == 1 }

        for byte in [0x59, 0x5A, 0x5B] {
            context.recorder.emit(Data(repeating: UInt8(byte), count: 6_400))
            await waitUntilAsync { await context.session.sendCallCount >= byte - 0x58 }
        }

        await waitUntil {
            context.viewModel.transcriptionReviewState == .streaming(preview: "PRIVATE_SHORT")
        }
        XCTAssertEqual(
            context.presenter.readOnlyPreviews,
            ["", "PRIVATE_LONG_SNAPSHOT", "PRIVATE_SHORT"],
            "each changed snapshot must replace the prior value instead of appending a delta"
        )
        XCTAssertEqual(context.presenter.renderReadOnlyCallCount, 3)
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.delivery.deliveredTexts, [])
    }

    func test_reviewFirst_contentlessActionTwoFallsBackToLatestSnapshotAndMarksIncomplete() async {
        let context = makeContext(
            packetEvents: [.partial("PRIVATE_LAST_USABLE")],
            finishEvent: .final("")
        )
        let identity = StreamingSessionIdentity(generation: 3_803)

        await startAndSeal(context, identity: identity)

        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .editable(draft: "PRIVATE_LAST_USABLE", isPossiblyIncomplete: true)
        )
        XCTAssertTrue(context.presenter.lastEditablePossiblyIncomplete)
        XCTAssertEqual(context.delivery.deliveredTexts, [])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
    }

    func test_reviewFirst_contentlessActionTwoWithoutSnapshotReturnsIdleWithoutEditor() async {
        let context = makeContext(finishEvent: .final(""))
        let identity = StreamingSessionIdentity(generation: 3_804)

        await startAndSeal(context, identity: identity)

        XCTAssertEqual(context.viewModel.transcriptionReviewState, .idle)
        XCTAssertEqual(context.presenter.editablePresentationCount, 0)
        XCTAssertEqual(context.delivery.deliveredTexts, [])
        XCTAssertEqual(context.delivery.copyCalls, 0)
    }

    func test_reviewFirst_whitespaceDraftRemainsEditableAndCannotConfirm() async {
        let context = makeContext(finishEvent: .final("PRIVATE_FINAL"))
        let identity = StreamingSessionIdentity(generation: 3_805)

        await startAndSeal(context, identity: identity)
        context.presenter.invokeDraftChange(" \n\t")
        context.presenter.invokeConfirm()
        await settle()

        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .editable(draft: " \n\t", isPossiblyIncomplete: false)
        )
        XCTAssertEqual(context.delivery.deliveredTexts, [])
        XCTAssertEqual(context.delivery.copyCalls, 0)
    }

    func test_reviewFirst_discardAndLateWindowCallbacksRevokeAuthorityWithoutOutputOrCopy() async {
        let context = makeContext(finishEvent: .final("PRIVATE_FINAL"))
        let identity = StreamingSessionIdentity(generation: 3_806)

        await startAndSeal(context, identity: identity)
        context.presenter.invokeDraftChange("PRIVATE_EDITED")
        context.viewModel.discardReviewDraft()

        XCTAssertEqual(context.viewModel.transcriptionReviewState, .idle)
        XCTAssertGreaterThanOrEqual(context.presenter.dismissCallCount, 1)
        XCTAssertEqual(context.delivery.deliveredTexts, [])
        XCTAssertEqual(context.delivery.copyCalls, 0)
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])

        context.presenter.invokeConfirm()
        context.presenter.invokeDraftChange("PRIVATE_LATE_CALLBACK")
        await settle()

        XCTAssertEqual(context.viewModel.transcriptionReviewState, .idle)
        XCTAssertEqual(context.delivery.deliveredTexts, [])
        XCTAssertEqual(context.delivery.copyCalls, 0)
    }

    func test_reviewFirst_closeEscapeResetSleepWakeAndCleanupClearAuthorityWithoutCopy() async {
        let lifecycleActions: [(String, (Issue38ReviewContext) async -> Void)] = [
            ("reset", { context in await context.viewModel.resetService() }),
            ("sleep", { context in await context.viewModel.handleSystemWillSleep() }),
            ("wake", { context in await context.viewModel.handleSystemDidWake() }),
            ("cleanup", { context in context.viewModel.cleanup() })
        ]

        for (offset, action) in lifecycleActions.enumerated() {
            let context = makeContext(finishEvent: .final("PRIVATE_FINAL_\(offset)"))
            await startAndSeal(
                context,
                identity: StreamingSessionIdentity(generation: UInt64(3_820 + offset))
            )
            context.presenter.invokeDraftChange("PRIVATE_EDITED_\(offset)")

            await action.1(context)
            XCTAssertEqual(
                context.viewModel.transcriptionReviewState,
                .idle,
                "\(action.0) must revoke unresolved review authority"
            )
            XCTAssertEqual(context.delivery.copyCalls, 0)
            XCTAssertEqual(context.delivery.deliveredTexts, [])
            XCTAssertEqual(context.output.insertedTexts, [])
            XCTAssertEqual(context.output.copiedTexts, [])
        }

        let closeContext = makeContext(finishEvent: .final("PRIVATE_CLOSE"))
        await startAndSeal(closeContext, identity: StreamingSessionIdentity(generation: 3_824))
        closeContext.presenter.invokeDiscard()
        XCTAssertEqual(closeContext.viewModel.transcriptionReviewState, .idle)
        XCTAssertEqual(closeContext.delivery.copyCalls, 0)
    }

    func test_reviewFirst_nonCancellationDeliveryFailureReturnsFrozenDraftToEditableWithoutRecoveryCopy() async {
        let failures: [ReviewDeliveryResult] = [
            .activationFailed,
            .identityChanged,
            .destinationInvalid,
            .securityRejected,
            .unsafeText,
            .deliveryFailed,
            .deliveryUncertain
        ]

        for (offset, failure) in failures.enumerated() {
            let context = makeContext(finishEvent: .final("PRIVATE_FINAL_\(offset)"))
            context.delivery.result = failure
            await startAndSeal(
                context,
                identity: StreamingSessionIdentity(generation: UInt64(3_830 + offset))
            )
            context.presenter.invokeDraftChange("PRIVATE_FROZEN_DRAFT_\(offset)")
            context.presenter.invokeConfirm()
            context.presenter.invokeConfirm()
            await waitUntil { context.delivery.deliveredTexts.count == 1 }
            await settle()

            XCTAssertEqual(
                context.delivery.deliveredTexts,
                ["PRIVATE_FROZEN_DRAFT_\(offset)"],
                "delivery must use the frozen edited draft exactly once"
            )
            XCTAssertEqual(context.delivery.copyCalls, 0)
            XCTAssertEqual(
                context.viewModel.transcriptionReviewState,
                .editable(
                    draft: "PRIVATE_FROZEN_DRAFT_\(offset)",
                    isPossiblyIncomplete: false,
                    feedback: reviewFeedback(for: failure)
                ),
                "delivery failure must return the exact draft to editable review"
            )
            XCTAssertEqual(
                context.viewModel.reviewDraftText,
                "PRIVATE_FROZEN_DRAFT_\(offset)"
            )
            XCTAssertFalse(context.viewModel.statusText.contains("PRIVATE_FROZEN_DRAFT"))
            XCTAssertEqual(context.output.insertedTexts, [])
            XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
            XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])

            if case .deliveryUncertain = failure {
                let editedAfterUncertainty = "PRIVATE_EDITED_AFTER_UNCERTAINTY"
                context.presenter.invokeDraftChange(editedAfterUncertainty)

                XCTAssertEqual(
                    context.viewModel.transcriptionReviewState,
                    .editable(
                        draft: editedAfterUncertainty,
                        isPossiblyIncomplete: false,
                        feedback: nil
                    ),
                    "an accepted edit after presentation-only readiness retry must clear stale uncertainty feedback"
                )
                XCTAssertEqual(context.viewModel.reviewDraftText, editedAfterUncertainty)
                XCTAssertEqual(
                    context.delivery.deliveredTexts,
                    ["PRIVATE_FROZEN_DRAFT_\(offset)"],
                    "editing after uncertainty must not automatically redeliver"
                )
                XCTAssertEqual(context.delivery.copyCalls, 0)
                XCTAssertEqual(context.output.insertedTexts, [])
                XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
                XCTAssertEqual(context.output.copiedTexts, [])
                XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
            }
        }
    }

    func test_reviewFirst_cancellationDoesNotCopyOrRetryFrozenDraft() async {
        let context = makeContext(finishEvent: .final("PRIVATE_FINAL"))
        context.delivery.result = .cancelled
        await startAndSeal(context, identity: StreamingSessionIdentity(generation: 3_837))
        context.presenter.invokeDraftChange("PRIVATE_CANCELLED_DRAFT")
        context.presenter.invokeConfirm()
        await waitUntil { context.delivery.deliveredTexts.count == 1 }
        await settle()

        XCTAssertEqual(context.delivery.copyCalls, 0)
        XCTAssertEqual(context.delivery.deliveredTexts, ["PRIVATE_CANCELLED_DRAFT"])
        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .editable(
                draft: "PRIVATE_CANCELLED_DRAFT",
                isPossiblyIncomplete: false,
                feedback: .deliveryCancelled
            )
        )
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
    }

    func test_reviewFirst_postFreezeSecurityPermissionChangeRetainsDraftAuthorityWithoutOutput() async {
        enum FailureTrigger {
            case secureInput
            case permissionsRevoked
        }

        for (offset, trigger) in [
            (0, FailureTrigger.secureInput),
            (1, FailureTrigger.permissionsRevoked)
        ] {
            let context = makeContext(finishEvent: .final("PRIVATE_FINAL_\(offset)"))
            await startAndSeal(
                context,
                identity: StreamingSessionIdentity(generation: UInt64(3_838 + offset))
            )
            let frozenDraft = "PRIVATE_POST_FREEZE_DRAFT_\(offset)"
            context.presenter.invokeDraftChange(frozenDraft)

            switch trigger {
            case .secureInput:
                PermissionManager.shared.simulateSecureInputState(true)
            case .permissionsRevoked:
                PermissionManager.shared.allPermissionsGranted = true
                PermissionManager.shared.allPermissionsGranted = false
            }
            await settle()

            XCTAssertEqual(
                context.viewModel.transcriptionReviewState,
                .editable(
                    draft: frozenDraft,
                    isPossiblyIncomplete: false,
                    feedback: .securityRejected
                ),
                "post-freeze (trigger) failure must retain an editable, fail-closed draft"
            )
            XCTAssertEqual(context.viewModel.reviewDraftText, frozenDraft)
            XCTAssertEqual(
                context.presenter.dismissCallCount,
                0,
                "post-freeze (trigger) failure must not dismiss the only draft surface"
            )
            XCTAssertEqual(context.delivery.deliveredTexts, [])
            XCTAssertEqual(context.delivery.copyCalls, 0)
            XCTAssertEqual(context.output.insertedTexts, [])
            XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
            XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])

            context.presenter.invokeDraftChange("PRIVATE_POST_FREEZE_EDIT_\(offset)")
            XCTAssertEqual(
                context.viewModel.reviewDraftText,
                "PRIVATE_POST_FREEZE_EDIT_\(offset)",
                "retained authority must continue accepting an explicit human edit"
            )

            switch trigger {
            case .secureInput:
                PermissionManager.shared.simulateSecureInputState(false)
            case .permissionsRevoked:
                PermissionManager.shared.allPermissionsGranted = true
            }
            await context.viewModel.resetService()
        }
    }

    func test_reviewFirst_monitoringFailureAfterRecognitionRetainsExactDraftAndPanelAuthorityWithoutOutput() async {
        let context = makeContext(finishEvent: .final("PRIVATE_MONITORING_FINAL"))
        await startAndSeal(
            context,
            identity: StreamingSessionIdentity(generation: 3_841)
        )
        let frozenDraft = "PRIVATE_MONITORING_EDITED_DRAFT"
        context.presenter.invokeDraftChange(frozenDraft)
        let surfaceIdentity = context.presenter.surfaceIdentity

        context.viewModel.handleMonitoringStateForTesting(
            .failed(.tapCreationFailed)
        )
        await settle()

        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .editable(
                draft: frozenDraft,
                isPossiblyIncomplete: false,
                feedback: .securityRejected
            ),
            "post-freeze monitoring failure must retain the exact editable draft with fixed security feedback"
        )
        XCTAssertEqual(context.viewModel.reviewDraftText, frozenDraft)
        XCTAssertEqual(
            Set(context.presenter.surfaceIDs),
            Set([surfaceIdentity]),
            "monitoring failure must preserve the same review surface authority"
        )
        XCTAssertEqual(context.presenter.dismissCallCount, 0)
        XCTAssertEqual(context.delivery.deliveredTexts, [])
        XCTAssertEqual(context.delivery.copyCalls, 0)
        XCTAssertEqual(context.delivery.copiedTexts, [])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
        XCTAssertEqual(
            context.viewModel.status,
            .error("热键不可用，请检查辅助功能权限")
        )
    }

    func test_reviewFirst_lateRecognitionCannotOverwriteHumanEditAfterEditableTransition() async {
        let context = makeContext(
            packetEvents: [.partial("PRIVATE_PARTIAL")],
            finishEvent: .final("PRIVATE_FINAL")
        )
        let identity = StreamingSessionIdentity(generation: 3_807)

        await startAndSeal(context, identity: identity)
        context.presenter.invokeDraftChange("PRIVATE_HUMAN_EDIT")

        context.viewModel.handleStreamingEventForTesting(
            .partial("PRIVATE_LATE_PARTIAL"),
            identity: StreamingSessionIdentity(generation: identity.generation + 1)
        )
        context.viewModel.handleStreamingEventForTesting(
            .final("PRIVATE_LATE_FINAL"),
            identity: StreamingSessionIdentity(generation: identity.generation + 1)
        )
        let readOnlyRenderCount = context.presenter.renderReadOnlyCallCount
        await settle()

        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .editable(draft: "PRIVATE_HUMAN_EDIT", isPossiblyIncomplete: false)
        )
        XCTAssertEqual(context.delivery.deliveredTexts, [])
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(
            context.presenter.renderReadOnlyCallCount,
            readOnlyRenderCount,
            "late recognition must not enqueue a stale read-only revision after editable authority"
        )
    }

    func test_reviewFirst_stalePresentationCannotRemountAfterDiscardOrCleanup() async {
        let context = makeContext(
            packetEvents: [.partial("PRIVATE_PARTIAL")],
            finishEvent: .final("PRIVATE_FINAL")
        )
        let identity = StreamingSessionIdentity(generation: 3_817)

        await startAndSeal(context, identity: identity)
        let renderCountBeforeDiscard = context.presenter.renderReadOnlyCallCount
        context.viewModel.discardReviewDraft()
        let dismissCount = context.presenter.dismissCallCount

        context.viewModel.handleStreamingEventForTesting(
            .partial("PRIVATE_STALE_AFTER_DISCARD"),
            identity: identity
        )
        context.viewModel.handleStreamingEventForTesting(
            .final("PRIVATE_STALE_FINAL_AFTER_DISCARD"),
            identity: identity
        )
        await settle()

        XCTAssertEqual(context.viewModel.transcriptionReviewState, .idle)
        XCTAssertEqual(context.presenter.renderReadOnlyCallCount, renderCountBeforeDiscard)
        XCTAssertEqual(context.presenter.dismissCallCount, dismissCount)
        XCTAssertEqual(context.presenter.renderDraftCallCount, 1)
        XCTAssertEqual(context.delivery.deliveredTexts, [])
    }

    func test_reviewFirst_newFnWhileEditableResetsOnlyNewHotKeyAndCannotReplaceDraft() async {
        let context = makeContext(finishEvent: .final("PRIVATE_FINAL"))
        let identity = StreamingSessionIdentity(generation: 3_808)

        await startAndSeal(context, identity: identity)
        let recorderStarts = context.recorder.startStreamingCallCount
        let providerCalls = await context.provider.makeSessionCallCount

        context.viewModel.handleHotKeyStateForTesting(
            .streaming(sessionID: StreamingSessionIdentity(generation: 3_809))
        )
        await settle()

        XCTAssertEqual(context.recorder.startStreamingCallCount, recorderStarts)
        let currentProviderCalls = await context.provider.makeSessionCallCount
        XCTAssertEqual(currentProviderCalls, providerCalls)
        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .editable(draft: "PRIVATE_FINAL", isPossiblyIncomplete: false)
        )
        XCTAssertEqual(context.presenter.lastEditableDraft, "PRIVATE_FINAL")
    }

    func test_reviewFirst_settingsAreSampledAtAcceptedFnStart() async {
        let context = makeContext(
            packetEvents: [.partial("PRIVATE_PARTIAL")],
            finishEvent: .final("PRIVATE_FINAL")
        )
        let identity = StreamingSessionIdentity(generation: 3_810)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { context.recorder.startStreamingCallCount == 1 }
        context.viewModel.settings.reviewBeforeInsert = false
        context.recorder.emit(Data(repeating: 0x54, count: 6_400))
        await waitUntilAsync { await context.session.sendCallCount == 1 }

        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .streaming(preview: "PRIVATE_PARTIAL")
        )
        XCTAssertEqual(context.output.insertedTexts, [])

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil {
            if case .editable = context.viewModel.transcriptionReviewState { return true }
            return false
        }
        XCTAssertEqual(context.viewModel.reviewDraftText, "PRIVATE_FINAL")
    }

    func test_reviewFirst_capturePrecedesAudioAndProviderButDoesNotBlockCaptureDrain() async {
        let context = makeContext(
            finishEvent: .cancelled,
            holdProviderFactory: true
        )
        let identity = StreamingSessionIdentity(generation: 3_811)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { context.recorder.startStreamingCallCount == 1 }

        XCTAssertEqual(context.delivery.captureCallCount, 1)
        XCTAssertEqual(Array(context.delivery.eventTrace.prefix(2)), ["capture", "audio-start"])

        context.recorder.emit(Data(repeating: 0x52, count: 6_400))
        await waitUntil { context.viewModel.journalCountForTesting > 0 }
        let providerCalls = await context.provider.makeSessionCallCount
        XCTAssertEqual(providerCalls, 1)
        XCTAssertEqual(context.viewModel.transcriptionReviewState, .streaming(preview: ""))
        await context.provider.releaseFactory()
    }

    func test_reviewFirst_secureCaptureRejectionStaysBeforeSurfaceAudioAndProvider() async {
        let context = makeContext(finishEvent: .cancelled)
        context.delivery.captureResult = .rejected(.secureInput)
        let identity = StreamingSessionIdentity(generation: 3_824)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { context.delivery.captureCallCount == 1 }
        await settle()

        XCTAssertEqual(context.viewModel.transcriptionReviewState, .idle)
        XCTAssertEqual(context.presenter.renderReadOnlyCallCount, 0)
        XCTAssertEqual(context.recorder.startStreamingCallCount, 0)
        let providerCallCount = await context.provider.makeSessionCallCount
        XCTAssertEqual(providerCallCount, 0)
        XCTAssertEqual(context.viewModel.journalCountForTesting, 0)
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
    }

    func test_reviewFirst_journalAndActionTwoProgressWhileReviewSurfaceIsGated() async {
        let context = makeContext(
            packetEvents: [.partial("PRIVATE_GATED_PARTIAL")],
            finishEvent: .final("PRIVATE_GATED_FINAL"),
            holdReadOnlyPresentation: true
        )
        let identity = StreamingSessionIdentity(generation: 3_818)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { context.recorder.startStreamingCallCount == 1 }
        context.recorder.emit(Data(repeating: 0x58, count: 6_400))
        await waitUntilAsync { await context.session.sendCallCount == 1 }
        await waitUntil { context.viewModel.journalCountForTesting > 0 }

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil {
            context.viewModel.transcriptionReviewState ==
                .editable(draft: "PRIVATE_GATED_FINAL", isPossiblyIncomplete: false)
        }
        await waitUntilAsync { await context.session.finishCallCount == 1 }

        XCTAssertFalse(context.presenter.readOnlyRenderGateOpen)
        XCTAssertGreaterThan(context.presenter.renderReadOnlyCallCount, 0)
        XCTAssertGreaterThan(context.presenter.gatedReadOnlyCommandCount, 0)
        XCTAssertEqual(context.presenter.renderDraftCallCount, 1)
        XCTAssertGreaterThan(context.viewModel.journalCountForTesting, 0)
        XCTAssertEqual(context.presenter.lastEditableDraft, "PRIVATE_GATED_FINAL")
        XCTAssertEqual(context.viewModel.transcriptionReviewState,
                       .editable(draft: "PRIVATE_GATED_FINAL", isPossiblyIncomplete: false))
    }

    func test_reviewFirst_releaseWaitsForRecorderBarrierBeforeEditableUIAndKeepsConsumerSeparate() async {
        let context = makeContext(
            finishEvent: .final("PRIVATE_FINAL"),
            holdStopBarrier: true
        )
        let identity = StreamingSessionIdentity(generation: 3_812)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { context.recorder.startStreamingCallCount == 1 }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { context.recorder.stopStreamingCallCount == 1 }

        XCTAssertEqual(context.presenter.editablePresentationCount, 0)
        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .sealing(preview: "")
        )

        context.recorder.releaseStopBarrier()
        await waitUntil {
            context.viewModel.transcriptionReviewState ==
                .editable(draft: "PRIVATE_FINAL", isPossiblyIncomplete: false)
        }
        XCTAssertEqual(context.presenter.editablePresentationCount, 1)
        XCTAssertEqual(context.delivery.deliveredTexts, [])
    }

    func test_reviewFirst_presentationFocusOutcomeCannotGateEditableOrConfirmation() async {
        let failures: [ReviewPresentationFocusFailure] = [
            .timedOut(lastUnmet: .panelKey),
            .timedOut(lastUnmet: .editorMaterialized),
            .timedOut(lastUnmet: .editorFirstResponder),
            .cancelled(lastUnmet: .editorMaterialized),
            .surfaceInvalidated
        ]

        for (offset, failure) in failures.enumerated() {
            let context = makeContext(
                finishEvent: .final("PRIVATE_FROZEN_ACTION_TWO_\(offset)")
            )
            context.presenter.presentationFocusResult = .notFocused(failure)
            let identity = StreamingSessionIdentity(generation: UInt64(3_826 + offset))
            let frozenDraft = "PRIVATE_FROZEN_ACTION_TWO_\(offset)"

            await startAndSeal(context, identity: identity)

            XCTAssertEqual(
                context.viewModel.transcriptionReviewState,
                .editable(
                    draft: frozenDraft,
                    isPossiblyIncomplete: false,
                    feedback: nil
                ),
                "\(failure) is presentation telemetry only; the frozen draft must be immediately editable"
            )
            XCTAssertEqual(context.presenter.lastEditableDraft, frozenDraft)
            XCTAssertEqual(
                Set(context.presenter.surfaceIDs),
                Set([context.presenter.surfaceIdentity]),
                "\(failure) must keep the same preview panel identity while readiness recovers"
            )
            XCTAssertEqual(
                context.presenter.dismissCallCount,
                0,
                "\(failure) must not dismiss the only draft surface"
            )
            XCTAssertEqual(context.delivery.copyCalls, 0)
            XCTAssertEqual(context.delivery.deliveredTexts, [])
            XCTAssertEqual(context.output.insertedTexts, [])
            XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
            XCTAssertEqual(context.output.copiedTexts, [])
            XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
            XCTAssertEqual(context.delivery.eventTrace.filter { $0 == "deliver" || $0 == "copy" || $0 == "retry" }, [])
            XCTAssertEqual(context.presenter.eventTrace.filter { $0 == "retry" }, [])

            context.presenter.invokeDraftChange("PRIVATE_EDITED_AFTER_\(failure)")
            XCTAssertEqual(
                context.viewModel.reviewDraftText,
                "PRIVATE_EDITED_AFTER_\(failure)",
                "presenter failure must retain the same review authority for later edits"
            )
            XCTAssertEqual(
                context.viewModel.transcriptionReviewState,
                .editable(
                    draft: "PRIVATE_EDITED_AFTER_\(failure)",
                    isPossiblyIncomplete: false,
                    feedback: nil
                )
            )
            context.presenter.invokeConfirm()
            await waitUntil { context.delivery.deliveredTexts.count == 1 }
            XCTAssertEqual(
                context.delivery.deliveredTexts,
                ["PRIVATE_EDITED_AFTER_\(failure)"],
                "explicit Send must remain available regardless of focus telemetry"
            )
            XCTAssertEqual(context.delivery.copyCalls, 0)
        }

        let suspended = makeContext(
            finishEvent: .final("PRIVATE_SUSPENDED_FOCUS"),
            holdPresentationFocusRequest: true
        )
        await startAndSealUntilPresentationFocusRequest(
            suspended,
            identity: StreamingSessionIdentity(generation: 3_831)
        )
        XCTAssertEqual(
            suspended.viewModel.transcriptionReviewState,
            .editable(
                draft: "PRIVATE_SUSPENDED_FOCUS",
                isPossiblyIncomplete: false,
                feedback: nil
            ),
            "a focus request that never completes must not keep the draft pending"
        )
        suspended.presenter.invokeDraftChange("PRIVATE_TYPED_WHILE_FOCUS_SUSPENDED")
        suspended.presenter.invokeDraftChange("PRIVATE_TYPED_WHILE_FOCUS_SUSPENDED_2")
        XCTAssertEqual(
            suspended.viewModel.reviewDraftText,
            "PRIVATE_TYPED_WHILE_FOCUS_SUSPENDED_2"
        )
        XCTAssertEqual(suspended.delivery.deliveredTexts, [])
        XCTAssertEqual(suspended.delivery.copyCalls, 0)
        XCTAssertEqual(suspended.output.insertedTexts, [])
        XCTAssertEqual(suspended.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(suspended.output.copiedTexts, [])
        XCTAssertEqual(suspended.accessibility.setSelectedTextCalls, [])
        XCTAssertEqual(suspended.delivery.eventTrace.filter { $0 == "deliver" || $0 == "copy" || $0 == "retry" }, [])
        XCTAssertEqual(suspended.presenter.eventTrace.filter { $0 == "retry" }, [])
        suspended.presenter.invokeConfirm()
        await waitUntil { suspended.delivery.deliveredTexts.count == 1 }
        XCTAssertEqual(
            suspended.delivery.deliveredTexts,
            ["PRIVATE_TYPED_WHILE_FOCUS_SUSPENDED_2"]
        )
        suspended.presenter.releasePresentationFocus(
            .notFocused(.cancelled(lastUnmet: .editorFirstResponder))
        )
        await settle()
        XCTAssertEqual(suspended.delivery.copyCalls, 0)
    }

    func test_reviewFirst_zeroSideEffectLedgerStaysEmptyFromCaptureThroughDraftEdits() async {
        let context = makeContext(
            packetEvents: [.partial("PRIVATE_STREAMING_PARTIAL")],
            finishEvent: .final("PRIVATE_FROZEN_LEDGER"),
            holdPresentationFocusRequest: true
        )
        let identity = StreamingSessionIdentity(generation: 3_832)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { context.recorder.startStreamingCallCount == 1 }
        XCTAssertEqual(context.delivery.deliveredTexts, [])
        XCTAssertEqual(context.delivery.copyCalls, 0)
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])

        context.recorder.emit(Data(repeating: 0x53, count: 6_400))
        await waitUntilAsync { await context.session.sendCallCount == 1 }
        XCTAssertEqual(context.delivery.deliveredTexts, [])
        XCTAssertEqual(context.delivery.copyCalls, 0)
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.output.copiedTexts, [])
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])

        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { context.presenter.presentationFocusRequestCount == 1 }
        await waitUntilAsync { await context.session.finishCallCount == 1 }
        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .editable(
                draft: "PRIVATE_FROZEN_LEDGER",
                isPossiblyIncomplete: false,
                feedback: nil
            ),
            "focus telemetry must not gate the editable authority after the recorder barrier"
        )

        for edit in ["P", "PR", "PRIVATE_FROZEN_LEDGER_EDITED"] {
            context.presenter.invokeDraftChange(edit)
            XCTAssertEqual(context.viewModel.reviewDraftText, edit)
            XCTAssertEqual(context.delivery.deliveredTexts, [])
            XCTAssertEqual(context.delivery.copyCalls, 0)
            XCTAssertEqual(context.output.insertedTexts, [])
            XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
            XCTAssertEqual(context.output.copiedTexts, [])
            XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
            XCTAssertEqual(
                context.delivery.eventTrace.filter { $0 == "deliver" || $0 == "copy" || $0 == "retry" },
                []
            )
            XCTAssertEqual(context.presenter.eventTrace.filter { $0 == "retry" }, [])
        }
        context.presenter.releasePresentationFocus(
            .notFocused(.timedOut(lastUnmet: .editorFirstResponder))
        )
        await settle()
    }

    func test_reviewFirst_deliveryFailureReturnsExactDraftToEditableWithoutFocusRetry() async {
        let context = makeContext(finishEvent: .final("PRIVATE_FINAL"))
        context.delivery.result = .deliveryFailed
        let identity = StreamingSessionIdentity(generation: 3_827)
        let draft = "  PRIVATE_DELIVERY_FAILURE_DRAFT\n"

        await startAndSeal(context, identity: identity)
        context.presenter.invokeDraftChange(draft)
        context.presenter.invokeConfirm()
        await waitUntil { context.delivery.deliveredTexts.count == 1 }
        await settle()

        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .editable(
                draft: draft,
                isPossiblyIncomplete: false,
                feedback: .deliveryFailed
            ),
            "delivery failure must return the exact frozen draft to editable review"
        )
        XCTAssertEqual(context.viewModel.reviewDraftText, draft)
        XCTAssertEqual(context.delivery.deliveredTexts, [draft])
        XCTAssertEqual(context.delivery.copyCalls, 0)
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])

        XCTAssertEqual(context.delivery.deliveredTexts.count, 1, "failure must not retry automatically")
        context.delivery.result = .submittedUnverified
        context.presenter.invokeConfirm()
        await waitUntil { context.delivery.deliveredTexts.count == 2 }

        XCTAssertEqual(context.delivery.deliveredTexts, [draft, draft])
        XCTAssertEqual(context.delivery.copyCalls, 0)
    }

    func test_reviewFirst_deliveryFailureDraftCanBeDiscardedWithoutCopyOrSecondDelivery() async {
        let context = makeContext(finishEvent: .final("PRIVATE_FINAL"))
        context.delivery.result = .deliveryFailed
        let identity = StreamingSessionIdentity(generation: 3_828)
        let draft = "PRIVATE_DISCARD_AFTER_DELIVERY_FAILURE"

        await startAndSeal(context, identity: identity)
        context.presenter.invokeDraftChange(draft)
        context.presenter.invokeConfirm()
        await waitUntil { context.delivery.deliveredTexts.count == 1 }
        await settle()

        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .editable(
                draft: draft,
                isPossiblyIncomplete: false,
                feedback: .deliveryFailed
            )
        )
        context.viewModel.discardReviewDraft()

        XCTAssertEqual(context.viewModel.transcriptionReviewState, .idle)
        XCTAssertEqual(context.delivery.deliveredTexts, [draft])
        XCTAssertEqual(context.delivery.copyCalls, 0)
        XCTAssertEqual(context.output.insertedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
    }

    func test_legacyReviewAndAutoInsertValuesUseOnePreviewRouteWithoutPreConfirmationOutput() async {
        let combinations = [(reviewBeforeInsert: true, autoInsert: true),
                            (reviewBeforeInsert: true, autoInsert: false),
                            (reviewBeforeInsert: false, autoInsert: true),
                            (reviewBeforeInsert: false, autoInsert: false)]
        for (offset, combination) in combinations.enumerated() {
            let reviewBeforeInsert = combination.reviewBeforeInsert
            let autoInsert = combination.autoInsert
            let context = makeContext(
                reviewBeforeInsert: reviewBeforeInsert,
                autoInsert: autoInsert,
                packetEvents: [.partial("PRIVATE_LEGACY_PARTIAL_\(offset)")],
                finishEvent: .final("PRIVATE_LEGACY_FINAL_\(offset)")
            )
            let identity = StreamingSessionIdentity(generation: UInt64(3_829 + offset))

            context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
            await waitUntil { context.recorder.startStreamingCallCount == 1 }
            await settle()

            XCTAssertEqual(
                context.viewModel.transcriptionReviewState,
                .streaming(preview: ""),
                "reviewBeforeInsert=\(reviewBeforeInsert), autoInsert=\(autoInsert) must enter the same preview route"
            )
            XCTAssertGreaterThan(
                context.presenter.renderReadOnlyCallCount,
                0,
                "reviewBeforeInsert=\(reviewBeforeInsert), autoInsert=\(autoInsert) must render the read-only preview"
            )
            XCTAssertEqual(context.output.insertedTexts, [])
            XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
            XCTAssertEqual(context.delivery.deliveredTexts, [])
            XCTAssertEqual(context.delivery.copyCalls, 0)
            XCTAssertEqual(
                context.accessibility.setSelectedTextCalls,
                [],
                "no target mutation is allowed while Fn is still held"
            )

            // The baseline false-setting path never enters preview. The two
            // assertions above are the intended RED signal for that iteration;
            // only a preview-capable implementation may continue to snapshot
            // assertions below.
            guard case .streaming = context.viewModel.transcriptionReviewState else {
                continue
            }

            context.recorder.emit(Data(repeating: 0x5D, count: 6_400))
            await waitUntilAsync { await context.session.sendCallCount == 1 }
            await waitUntil {
                context.viewModel.transcriptionReviewState ==
                    .streaming(preview: "PRIVATE_LEGACY_PARTIAL_\(offset)")
            }

            XCTAssertEqual(context.output.insertedTexts, [])
            XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
            XCTAssertEqual(context.delivery.deliveredTexts, [])
            XCTAssertEqual(context.delivery.copyCalls, 0)
            XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])
        }
    }

    private func reviewFeedback(for result: ReviewDeliveryResult) -> ReviewDraftFeedback {
        switch result {
        case .activationFailed:
            return .activationFailed
        case .identityChanged, .destinationInvalid:
            return .destinationChanged
        case .securityRejected:
            return .securityRejected
        case .unsafeText:
            return .unsafeText
        case .deliveryFailed:
            return .deliveryFailed
        case .deliveryUncertain:
            return .deliveryUncertain
        case .cancelled:
            return .deliveryCancelled
        case .submittedUnverified:
            return .deliveryUncertain
        }
    }

    private func makeContext(
        reviewBeforeInsert: Bool = true,
        autoInsert: Bool = true,
        packetEvents: [StreamingRecognitionEvent] = [],
        finishEvent: StreamingRecognitionEvent = .cancelled,
        holdStopBarrier: Bool = false,
        holdProviderFactory: Bool = false,
        holdReadOnlyPresentation: Bool = false,
        holdPresentationFocusRequest: Bool = false,
        reviewSurfacePresenter: (any ReviewSurfacePresenting)? = nil
    ) -> Issue38ReviewContext {
        let recorder = Issue38ReviewAudioRecorder(holdStopBarrier: holdStopBarrier)
        let session = Issue38ReviewStreamingSession(
            packetEvents: packetEvents,
            finishEvent: finishEvent
        )
        let provider = Issue38ReviewStreamingProvider(
            session: session,
            holdFactory: holdProviderFactory
        )
        let accessibility = Issue38ReviewAccessibilityClient()
        let output = Issue38ReviewFinalTextOutput()
        let delivery = Issue38ReviewDestinationDelivery()
        let presenter = Issue38ReviewSurfacePresenter()
        presenter.readOnlyRenderGateOpen = !holdReadOnlyPresentation
        presenter.holdPresentationFocusRequest = holdPresentationFocusRequest
        recorder.onStart = { delivery.record(event: "audio-start") }
        let viewModel = MainViewModel(
            audioRecorder: recorder,
            settings: AppSettings(
                appId: "configured-app",
                appSecret: "configured-secret",
                autoInsert: autoInsert,
                playSound: false,
                reviewBeforeInsert: reviewBeforeInsert
            ),
            hotKeyWakeRecovering: TrackingHotKeyWakeRecoverer(),
            streamingProvider: provider,
            accessibilityClient: accessibility,
            finalTextOutput: output,
            overlayPresenter: Issue38ReviewOverlayPresenter(),
            reviewDestinationDelivery: delivery,
            reviewSurfacePresenter: reviewSurfacePresenter ?? presenter
        )
        recorder.resetTracking()
        return Issue38ReviewContext(
            viewModel: viewModel,
            recorder: recorder,
            session: session,
            provider: provider,
            accessibility: accessibility,
            output: output,
            delivery: delivery,
            presenter: presenter
        )
    }

    private func makeProductionReviewContext(
        finishEvent: StreamingRecognitionEvent,
        presenter: Issue40ProductionReviewSurfacePresenter,
        reviewSubmissionFacade: ReviewSubmissionFacade? = nil
    ) -> Issue40ProductionReviewContext {
        let recorder = Issue38ReviewAudioRecorder(holdStopBarrier: false)
        let session = Issue38ReviewStreamingSession(
            packetEvents: [],
            finishEvent: finishEvent
        )
        let provider = Issue38ReviewStreamingProvider(session: session)
        let accessibility = Issue38ReviewAccessibilityClient()
        let output = Issue38ReviewFinalTextOutput()
        let delivery = Issue38ReviewDestinationDelivery()
        let viewModel = MainViewModel(
            audioRecorder: recorder,
            settings: AppSettings(
                appId: "configured-app",
                appSecret: "configured-secret",
                autoInsert: true,
                playSound: false,
                reviewBeforeInsert: true
            ),
            hotKeyWakeRecovering: TrackingHotKeyWakeRecoverer(),
            streamingProvider: provider,
            accessibilityClient: accessibility,
            finalTextOutput: output,
            overlayPresenter: Issue38ReviewOverlayPresenter(),
            reviewDestinationDelivery: delivery,
            reviewSubmissionFacade: reviewSubmissionFacade,
            reviewSurfacePresenter: presenter
        )
        return Issue40ProductionReviewContext(
            viewModel: viewModel,
            recorder: recorder,
            session: session,
            provider: provider,
            accessibility: accessibility,
            output: output,
            delivery: delivery,
            presenter: presenter
        )
    }

    private func startAndSeal(
        _ context: Issue38ReviewContext,
        identity: StreamingSessionIdentity
    ) async {
        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { context.recorder.startStreamingCallCount == 1 }
        if await context.session.hasPacketEvents() {
            context.recorder.emit(Data(repeating: 0x53, count: 6_400))
            await waitUntilAsync { await context.session.sendCallCount == 1 }
        }
        await waitUntilAsync { await context.provider.makeSessionCallCount == 1 }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil {
            self.isTerminalReviewDraftState(context.viewModel.transcriptionReviewState)
        }
        await waitUntilAsync { await context.session.finishCallCount == 1 }
    }

    private func startAndSealUntilPresentationFocusRequest(
        _ context: Issue38ReviewContext,
        identity: StreamingSessionIdentity
    ) async {
        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { context.recorder.startStreamingCallCount == 1 }
        await waitUntilAsync { await context.provider.makeSessionCallCount == 1 }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil { context.presenter.presentationFocusRequestCount == 1 }
        await waitUntilAsync { await context.session.finishCallCount == 1 }
    }

    private func startAndSealProduction(
        _ context: Issue40ProductionReviewContext,
        identity: StreamingSessionIdentity,
        captureReady: (@MainActor () -> Bool)? = nil
    ) async {
        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { context.recorder.startStreamingCallCount == 1 }
        await waitUntilAsync { await context.provider.makeSessionCallCount == 1 }
        if let captureReady {
            await waitUntil(captureReady)
        }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntilAsync { await context.session.finishCallCount == 1 }
        await waitUntil {
            if case .editable = context.viewModel.transcriptionReviewState {
                return true
            }
            return false
        }
    }

    private func editableTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView, textView.isEditable {
            return textView
        }
        for subview in view.subviews.reversed() {
            if let textView = editableTextView(in: subview) {
                return textView
            }
        }
        return nil
    }

    private func isTerminalReviewDraftState(_ state: TranscriptionReviewState) -> Bool {
        switch state {
        case .idle:
            return true
        case .editable:
            return true
        default:
            return false
        }
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0 ..< 200 {
            if predicate() { return }
            await Task.yield()
        }
        logger.debug("review state wait timed out")
        XCTFail("timed out waiting for review-first state transition")
    }

    private func waitUntilDelayed(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0 ..< 200 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("timed out waiting for delayed review submission event")
    }

    private func waitUntilAsync(
        _ predicate: @escaping @MainActor () async -> Bool
    ) async {
        for _ in 0 ..< 200 {
            if await predicate() { return }
            await Task.yield()
        }
        logger.debug("review async boundary wait timed out")
        XCTFail("timed out waiting for review-first async boundary")
    }

    private func settle() async {
        for _ in 0 ..< 20 {
            await Task.yield()
        }
    }
}

@MainActor
private struct Issue38ReviewContext {
    let viewModel: MainViewModel
    let recorder: Issue38ReviewAudioRecorder
    let session: Issue38ReviewStreamingSession
    let provider: Issue38ReviewStreamingProvider
    let accessibility: Issue38ReviewAccessibilityClient
    let output: Issue38ReviewFinalTextOutput
    let delivery: Issue38ReviewDestinationDelivery
    let presenter: Issue38ReviewSurfacePresenter
}

@MainActor
private struct Issue40ProductionReviewContext {
    let viewModel: MainViewModel
    let recorder: Issue38ReviewAudioRecorder
    let session: Issue38ReviewStreamingSession
    let provider: Issue38ReviewStreamingProvider
    let accessibility: Issue38ReviewAccessibilityClient
    let output: Issue38ReviewFinalTextOutput
    let delivery: Issue38ReviewDestinationDelivery
    let presenter: Issue40ProductionReviewSurfacePresenter
}

@MainActor
private final class V5ExpiredStartReviewSubmissionFacade: ReviewSubmissionFacade {
    let identity = ReviewApplicationIdentity(
        processIdentifier: 42,
        bundleIdentifier: "com.example.issue40.v5.expired-start",
        executableURL: URL(fileURLWithPath: "/Applications/Issue40V5ExpiredStart.app"),
        launchDate: Date(timeIntervalSince1970: 5)
    )
    private let controlPlane: ReviewSubmissionControlPlane
    private let eventRelay: ReviewSubmissionEventRelay
    private let issuer: ReviewAttemptTicketIssuer
    private(set) var issuedHandleCount = 0
    private(set) var enqueueStartCallCount = 0
    private(set) var captureCompletedCount = 0
    private(set) var admissionEnvelopes: [ReviewSubmissionAdmissionEnvelope] = []
    private(set) var observedEvents: [ReviewSubmissionControlEvent] = []

    init() {
        let controlPlane = ReviewSubmissionControlPlane()
        let eventRelay = ReviewSubmissionEventRelay()
        self.controlPlane = controlPlane
        self.eventRelay = eventRelay
        self.issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        controlPlane.attachEventHandler { [eventRelay] event in
            eventRelay.receive(event)
        }
    }

    func setEventHandler(
        _ handler: (@MainActor @Sendable (ReviewSubmissionControlEvent) -> Void)?
    ) {
        eventRelay.install { [weak self] event in
            self?.observedEvents.append(event)
            handler?(event)
        }
    }

    func snapshotFrontmostApplication() -> StableApplicationIdentity? {
        identity
    }

    func captureTarget(
        _ request: ReviewTargetCaptureRequestDescriptor,
        completion: @escaping @MainActor @Sendable (
            Result<CapturedReviewTargetDescriptor, ReviewPreBoundaryFailure>
        ) -> Void
    ) {
        // This facade is only the deterministic expired-start harness. Complete
        // capture inline so the test's action-2/barrier sequencing cannot race
        // an unobserved MainActor task; the production facade remains async.
        captureCompletedCount += 1
        completion(
            .success(
                CapturedReviewTargetDescriptor(
                    generation: request.generation,
                    application: request.application,
                    binding: .applicationBoundCurrentFocus,
                    securityAtCapture: .safe
                )
            )
        )
    }

    func issueAttemptHandle() -> ReviewSubmissionAttemptHandle? {
        issuedHandleCount += 1
        return issuer.issue()
    }

    func makeAdmissionEnvelope(
        handle: ReviewSubmissionAttemptHandle,
        request: ReviewSubmissionRequestDescriptor
    ) -> ReviewSubmissionAdmissionEnvelope {
        ReviewSubmissionAdmissionEnvelope(
            handle: handle,
            request: request,
            absolutePreBoundaryDeadline: request.confirmationUptime + 50_000_000
        )
    }

    func enqueueAdmission(_ envelope: ReviewSubmissionAdmissionEnvelope) {
        admissionEnvelopes.append(envelope)
        controlPlane.enqueueAdmission(envelope)
    }

    func enqueueStart(_ handle: ReviewSubmissionAttemptHandle) {
        enqueueStartCallCount += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            self?.controlPlane.enqueueStart(handle)
        }
    }

    func enqueueCancellation(_ handle: ReviewSubmissionAttemptHandle) {
        controlPlane.enqueueCancellation(handle)
    }

    func releaseCapturedTarget(_ targetID: CapturedReviewTargetID) {
        _ = targetID
    }
}

@MainActor
private final class V5ReviewSubmissionFacadeSpy: ReviewSubmissionFacade {
    let identity = ReviewApplicationIdentity(
        processIdentifier: 42,
        bundleIdentifier: "com.example.issue40.v5.coordinator",
        executableURL: URL(fileURLWithPath: "/Applications/Issue40V5Coordinator.app"),
        launchDate: Date(timeIntervalSince1970: 5)
    )
    let target = CapturedReviewTargetDescriptor(
        generation: 5_100,
        application: ReviewApplicationIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.example.issue40.v5.coordinator",
            executableURL: URL(fileURLWithPath: "/Applications/Issue40V5Coordinator.app"),
            launchDate: Date(timeIntervalSince1970: 5)
        ),
        binding: .applicationBoundCurrentFocus,
        securityAtCapture: .safe
    )
    private let issuer: ReviewAttemptTicketIssuer
    private var eventHandler: (@MainActor @Sendable (ReviewSubmissionControlEvent) -> Void)?
    private(set) var captureRequests: [ReviewTargetCaptureRequestDescriptor] = []
    private(set) var captureCompletedCount = 0
    private(set) var admissionEnvelopes: [ReviewSubmissionAdmissionEnvelope] = []
    private(set) var startedHandles: [ReviewSubmissionAttemptHandle] = []
    private(set) var cancellationHandles: [ReviewSubmissionAttemptHandle] = []
    private(set) var releasedTargetIDs: [CapturedReviewTargetID] = []
    private(set) var issuedHandleCount = 0

    init() {
        issuer = ReviewAttemptTicketIssuer(controlPlaneInstanceNonce: 5_100)
    }

    func setEventHandler(
        _ handler: (@MainActor @Sendable (ReviewSubmissionControlEvent) -> Void)?
    ) {
        eventHandler = handler
    }

    func snapshotFrontmostApplication() -> StableApplicationIdentity? {
        identity
    }

    func captureTarget(
        _ request: ReviewTargetCaptureRequestDescriptor,
        completion: @escaping @MainActor @Sendable (
            Result<CapturedReviewTargetDescriptor, ReviewPreBoundaryFailure>
        ) -> Void
    ) {
        captureRequests.append(request)
        Task { @MainActor in
            await Task.yield()
            captureCompletedCount += 1
            completion(
                .success(
                    CapturedReviewTargetDescriptor(
                        targetID: target.targetID,
                        generation: request.generation,
                        application: request.application,
                        binding: target.binding,
                        securityAtCapture: .safe
                    )
                )
            )
        }
    }

    func issueAttemptHandle() -> ReviewSubmissionAttemptHandle? {
        issuedHandleCount += 1
        return issuer.issue()
    }

    func makeAdmissionEnvelope(
        handle: ReviewSubmissionAttemptHandle,
        request: ReviewSubmissionRequestDescriptor
    ) -> ReviewSubmissionAdmissionEnvelope {
        ReviewSubmissionAdmissionEnvelope(
            handle: handle,
            request: request,
            absolutePreBoundaryDeadline: request.confirmationUptime + 1_000_000_000
        )
    }

    func enqueueAdmission(_ envelope: ReviewSubmissionAdmissionEnvelope) {
        admissionEnvelopes.append(envelope)
    }

    func enqueueStart(_ handle: ReviewSubmissionAttemptHandle) {
        startedHandles.append(handle)
    }

    func enqueueCancellation(_ handle: ReviewSubmissionAttemptHandle) {
        cancellationHandles.append(handle)
    }

    func releaseCapturedTarget(_ targetID: CapturedReviewTargetID) {
        releasedTargetIDs.append(targetID)
    }

    func emit(_ event: ReviewSubmissionControlEvent) {
        eventHandler?(event)
    }
}

@MainActor
private final class Issue40ProductionReviewSurfacePresenter: ReviewSurfacePresenting {
    let controller: ReviewWindowController
    private(set) var retainedPanel: ReviewPanel?
    private(set) var renderedStates: [TranscriptionReviewState] = []
    private(set) var confirmGestureCount = 0

    init(controller: ReviewWindowController) {
        self.controller = controller
    }

    func renderReadOnly(phase: ReviewReadOnlyPhase, preview: String) {
        controller.renderReadOnly(phase: phase, preview: preview)
        retainedPanel = currentPanel()
    }

    func renderDraft(
        state: TranscriptionReviewState,
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor (ReviewConfirmationIntent) -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) {
        renderedStates.append(state)
        controller.renderDraft(
            state: state,
            onDraftChange: onDraftChange,
            onConfirm: { [weak self] intent in
                self?.confirmGestureCount += 1
                onConfirm(intent)
            },
            onDiscard: onDiscard
        )
        retainedPanel = currentPanel()
    }

    @discardableResult
    func invokeQualifiedReturnIntent() -> Bool {
        guard let panel = retainedPanel else { return false }
        return issue40PerformQualifiedReturn(on: panel)
    }

    func requestPresentationFocus(
        _ request: ReviewPresentationFocusRequest
    ) async -> ReviewPresentationFocusOutcome {
        await controller.requestPresentationFocus(request)
    }

    func dismiss() {
        controller.dismiss()
        retainedPanel = nil
    }

    @discardableResult
    func invokeConfirm() -> Bool {
        invokeSend()
    }

    func replaceDraft(_ draft: String) {
        guard let panel = retainedPanel,
              prepare(panel),
              let editor = issue40EditableTextView(in: panel.contentView) else {
            XCTFail("the production presenter must expose the real native editor")
            return
        }
        _ = panel.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
        editor.insertText(draft, replacementRange: editor.selectedRange())
    }

    @discardableResult
    func invokeSend() -> Bool {
        guard let panel = retainedPanel,
              prepare(panel) else {
            return false
        }
        let priorConfirmCount = confirmGestureCount
        // Feedback is rendered below the editor and shifts the bottom control
        // band. Probe the full plausible control band with real mouse events,
        // stopping immediately after the controller's opaque callback is
        // observed so one gesture cannot become multiple submissions.
        for y in stride(from: CGFloat(8), through: CGFloat(280), by: CGFloat(8)) {
            guard issue40PerformRealSendClick(on: panel, contentY: y) else {
                continue
            }
            if confirmGestureCount > priorConfirmCount {
                return true
            }
        }
        return false
    }

    var hasSendControl: Bool {
        guard let panel = retainedPanel, prepare(panel) else { return false }
        return panel.contentView != nil
    }

    @discardableResult
    private func prepare(_ panel: ReviewPanel) -> Bool {
        panel.makeKeyAndOrderFront(nil)
        panel.ignoresMouseEvents = false
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.contentView?.layoutSubtreeIfNeeded()
        return true
    }

    private func currentPanel() -> ReviewPanel? {
        NSApp.windows.compactMap { $0 as? ReviewPanel }.last
    }

}

@MainActor
private final class Issue40ProductionFirstResponderProbe {
    private(set) var makeCallCount = 0
    private(set) var checkCallCount = 0
    private(set) var requestedEditorWasAttached = false

    func make(panel: ReviewPanel, editor: NSTextView) -> Bool {
        makeCallCount += 1
        requestedEditorWasAttached = editor.window === panel
        _ = panel.makeFirstResponder(editor)
        // AppKit cannot always install a first responder in a headless test
        // window, but the production readiness path must still request it.
        return true
    }

    func check(panel: ReviewPanel, editor: NSTextView) -> Bool {
        checkCallCount += 1
        return editor.window === panel
    }
}

private actor Issue38ReviewStreamingSession: SpeechStreamingSession {
    private var packetEvents: [StreamingRecognitionEvent]
    private let finishEvent: StreamingRecognitionEvent
    private(set) var sendCallCount = 0
    private(set) var finishCallCount = 0

    init(packetEvents: [StreamingRecognitionEvent], finishEvent: StreamingRecognitionEvent) {
        self.packetEvents = packetEvents
        self.finishEvent = finishEvent
    }

    func hasPacketEvents() -> Bool { !packetEvents.isEmpty }

    func sendAudioPacket(_ pcm16: Data) async throws -> StreamingRecognitionEvent {
        sendCallCount += 1
        return packetEvents.isEmpty ? .partial("") : packetEvents.removeFirst()
    }

    func finish() async throws -> StreamingRecognitionEvent {
        finishCallCount += 1
        return finishEvent
    }

    func cancel() async {}
}

private actor Issue38ReviewStreamingProvider: SpeechStreamingSessionProviding {
    let session: Issue38ReviewStreamingSession
    private let holdFactory: Bool
    private var factoryContinuation: CheckedContinuation<Void, Never>?
    private(set) var makeSessionCallCount = 0

    init(session: Issue38ReviewStreamingSession, holdFactory: Bool = false) {
        self.session = session
        self.holdFactory = holdFactory
    }

    func makeStreamingSession(
        appId: String,
        appSecret: String
    ) async throws -> any SpeechStreamingSession {
        makeSessionCallCount += 1
        if holdFactory {
            await withCheckedContinuation { continuation in
                factoryContinuation = continuation
            }
        }
        return session
    }

    func releaseFactory() {
        factoryContinuation?.resume()
        factoryContinuation = nil
    }
}

@MainActor
private final class Issue38ReviewAudioRecorder: AudioRecorder {
    private var ingress: ByteBoundedAudioIngress?
    private var stopContinuation: CheckedContinuation<Void, Never>?
    private let holdStopBarrier: Bool
    var onStart: (() -> Void)?
    private(set) var startStreamingCallCount = 0
    private(set) var stopStreamingCallCount = 0
    private(set) var forceCleanupCallCount = 0

    init(holdStopBarrier: Bool) {
        self.holdStopBarrier = holdStopBarrier
        super.init()
    }

    override func startStreamingRecording(
        ingress: ByteBoundedAudioIngress,
        completion: @escaping (_ started: Bool) -> Void
    ) -> Bool {
        startStreamingCallCount += 1
        self.ingress = ingress
        isRecording = true
        onStart?()
        completion(true)
        return true
    }

    override func stopStreamingRecording(streamEstablished: Bool) async {
        stopStreamingCallCount += 1
        isRecording = false
        if holdStopBarrier {
            await withCheckedContinuation { continuation in
                stopContinuation = continuation
            }
        }
        ingress?.finish(streamEstablished: streamEstablished)
    }

    override func forceCleanup() {
        forceCleanupCallCount += 1
        ingress?.fail(.cancelled)
        ingress = nil
        isRecording = false
    }

    func emit(_ data: Data) {
        _ = ingress?.append(data)
    }

    func releaseStopBarrier() {
        stopContinuation?.resume()
        stopContinuation = nil
    }

    func resetTracking() {
        startStreamingCallCount = 0
        stopStreamingCallCount = 0
        forceCleanupCallCount = 0
    }
}

@MainActor
private final class Issue38ReviewAccessibilityClient: AccessibilityClient {
    let element = AXUIElementCreateApplication(42)
    private(set) var setSelectedTextCalls: [String] = []
    var selectedRange = CursorTextRange(location: 4, length: 0)
    private var ownedTextStart: Int?
    private var ownedText = ""

    func captureDestination(generation: UInt64) throws -> CursorCapabilityResult {
        .live(
            CursorDestinationToken(
                generation: generation,
                processIdentifier: 42,
                element: element,
                originalSelection: selectedRange
            )
        )
    }

    func frontmostProcessIdentifier() -> pid_t? { 42 }
    func focusedElement() throws -> AXUIElement { element }
    func currentSecurityState(for token: CursorDestinationToken) throws -> DestinationSecurityState { .safe }
    func selectedTextRange(for token: CursorDestinationToken) throws -> CursorTextRange { selectedRange }
    func string(for range: CursorTextRange, in token: CursorDestinationToken) throws -> String {
        guard let ownedTextStart,
              range.location == ownedTextStart,
              range.length == ownedText.utf16.count else {
            return ""
        }
        return ownedText
    }
    func setSelectedTextRange(_ range: CursorTextRange, for token: CursorDestinationToken) throws {
        selectedRange = range
    }
    func setSelectedText(_ text: String, for token: CursorDestinationToken) throws {
        setSelectedTextCalls.append(text)
        ownedTextStart = selectedRange.location
        ownedText = text
        selectedRange = CursorTextRange(
            location: selectedRange.location + text.utf16.count,
            length: 0
        )
    }
}

@MainActor
private final class Issue38ReviewFinalTextOutput: FinalTextOutput {
    private(set) var insertedTexts: [String] = []
    private(set) var currentFocusInsertedTexts: [String] = []
    private(set) var copiedTexts: [String] = []

    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateDestination: () throws -> Bool
    ) -> FinalTextInsertionResult {
        do {
            guard try validateDestination() else { return .destinationInvalid }
        } catch {
            return .destinationInvalid
        }
        insertedTexts.append(text)
        return .inserted
    }

    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateBeforeMutation: () throws -> Bool,
        validateAfterPosting: () throws -> Bool
    ) -> FinalTextInsertionResult {
        do {
            guard try validateBeforeMutation() else { return .destinationInvalid }
            insertedTexts.append(text)
            return try validateAfterPosting() ? .inserted : .deliveryUncertain
        } catch {
            return .deliveryUncertain
        }
    }

    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateBeforeMutation: @escaping () throws -> Bool,
        validateAfterPosting: () throws -> Bool,
        postPairIfPreflightRemainsValid pairGate: (@escaping () -> Void) -> Bool
    ) -> FinalTextInsertionResult {
        do {
            guard try validateBeforeMutation() else { return .destinationInvalid }
            var didInsert = false
            guard pairGate({ [self] in
                self.insertedTexts.append(text)
                didInsert = true
            }), didInsert else {
                return .deliveryFailed
            }
            return try validateAfterPosting() ? .inserted : .deliveryUncertain
        } catch {
            return .deliveryUncertain
        }
    }

    func insertAtCurrentFocusOnce(_ text: String) -> FinalTextInsertionResult {
        currentFocusInsertedTexts.append(text)
        return .inserted
    }

    func copyForManualRecovery(_ text: String) {
        copiedTexts.append(text)
    }
}

@MainActor
private final class Issue38ReviewDestinationDelivery: ReviewDestinationDelivering {
    static let testApplicationIdentity = ReviewApplicationIdentity(
        processIdentifier: 42,
        bundleIdentifier: "com.example.review-target",
        executableURL: URL(fileURLWithPath: "/Applications/ReviewTarget.app"),
        launchDate: Date(timeIntervalSince1970: 42)
    )

    private let application: ReviewApplicationIdentity
    private let element: AXUIElement
    private(set) var captureCallCount = 0
    private(set) var deliveredTexts: [String] = []
    private(set) var copyCalls = 0
    private(set) var copiedTexts: [String] = []
    private(set) var eventTrace: [String] = []
    var result: ReviewDeliveryResult = .submittedUnverified
    var captureResult: ReviewDestinationCaptureResult

    init() {
        element = AXUIElementCreateApplication(42)
        application = Self.testApplicationIdentity
        captureResult = .captured(
            ReviewDestinationToken(
                generation: 1,
                application: application,
                binding: .exactCursor(
                    CursorDestinationToken(
                        generation: 1,
                        processIdentifier: 42,
                        element: element,
                        originalSelection: CursorTextRange(location: 4, length: 0)
                    )
                ),
                capturedSecurityState: .safe
            )
        )
    }

    func capture(generation: UInt64) -> ReviewDestinationCaptureResult {
        captureCallCount += 1
        eventTrace.append("capture")
        switch captureResult {
        case .captured:
            return .captured(
                ReviewDestinationToken(
                    generation: generation,
                    application: application,
                    binding: .exactCursor(
                        CursorDestinationToken(
                            generation: generation,
                            processIdentifier: application.processIdentifier,
                            element: element,
                            originalSelection: CursorTextRange(location: 4, length: 0)
                        )
                    ),
                    capturedSecurityState: .safe
                )
            )
        case .rejected:
            return captureResult
        }
    }

    func record(event: String) {
        eventTrace.append(event)
    }

    func deliver(
        _ frozenText: String,
        to destination: ReviewDestinationToken
    ) async -> ReviewDeliveryResult {
        eventTrace.append("deliver")
        deliveredTexts.append(frozenText)
        return result
    }

    func copyForManualRecovery(_ frozenText: String) {
        eventTrace.append("copy")
        copyCalls += 1
        copiedTexts.append(frozenText)
    }
}

@MainActor
private final class Issue38ReviewSurfacePresenter: ReviewSurfacePresenting {
    private var capturedApplication: StableApplicationIdentity?
    private lazy var productionController = issue40MakeDeterministicReviewWindowController { [weak self] in
        self?.capturedApplication
    }
    let surfaceIdentity = UUID()
    private(set) var renderReadOnlyCallCount = 0
    private(set) var readOnlyPhases: [ReviewReadOnlyPhase] = []
    private(set) var readOnlyPreviews: [String] = []
    private(set) var surfaceIDs: [UUID] = []
    private(set) var renderDraftCallCount = 0
    private(set) var editablePresentationCount = 0
    private(set) var dismissCallCount = 0
    private(set) var lastReadOnlyPreview = ""
    private(set) var lastReadOnlyPhase: ReviewReadOnlyPhase?
    private(set) var lastEditableDraft = ""
    private(set) var lastEditablePossiblyIncomplete = false
    private(set) var draftStates: [TranscriptionReviewState] = []
    private(set) var eventTrace: [String] = []
    private(set) var confirmGestureCount = 0
    var readOnlyRenderGateOpen = true
    private(set) var presentationFocusRequestCount = 0
    var holdPresentationFocusRequest = false
    var presentationFocusResult: ReviewPresentationFocusResult = .focused
    private var presentationFocusContinuation: CheckedContinuation<ReviewPresentationFocusOutcome, Never>?
    private var currentPresentationFocusRequest: ReviewPresentationFocusRequest?
    private var draftChange: (@MainActor (String) -> Void)?
    private var discard: (@MainActor () -> Void)?
    private var gatedReadOnlyCommands: [(ReviewReadOnlyPhase, String)] = []
    private var lastDraftState: TranscriptionReviewState?

    func renderReadOnly(phase: ReviewReadOnlyPhase, preview: String) {
        renderReadOnlyCallCount += 1
        readOnlyPhases.append(phase)
        readOnlyPreviews.append(preview)
        surfaceIDs.append(surfaceIdentity)
        eventTrace.append("readOnly")
        guard readOnlyRenderGateOpen else {
            gatedReadOnlyCommands.append((phase, preview))
            return
        }
        lastReadOnlyPhase = phase
        lastReadOnlyPreview = preview
    }

    func renderDraft(
        state: TranscriptionReviewState,
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor (ReviewConfirmationIntent) -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) {
        renderDraftCallCount += 1
        draftStates.append(state)
        lastDraftState = state
        switch state {
        case .editable(let draft, let isPossiblyIncomplete, _),
             .confirming(let draft, let isPossiblyIncomplete):
            lastEditableDraft = draft
            lastEditablePossiblyIncomplete = isPossiblyIncomplete
            if case .editable = state {
                editablePresentationCount += 1
            }
        case .idle, .streaming, .sealing,
             .preparingSubmission, .submittedUnverifiedTerminal:
            break
        }
        surfaceIDs.append(surfaceIdentity)
        eventTrace.append("draft")
        draftChange = onDraftChange
        discard = onDiscard
        productionController.renderDraft(
            state: state,
            onDraftChange: onDraftChange,
            onConfirm: { [weak self] intent in
                self?.confirmGestureCount += 1
                onConfirm(intent)
            },
            onDiscard: onDiscard
        )
    }

    func requestPresentationFocus(
        _ request: ReviewPresentationFocusRequest
    ) async -> ReviewPresentationFocusOutcome {
        capturedApplication = request.capturedApplication
        presentationFocusRequestCount += 1
        if presentationFocusResult == .focused {
            return await productionController.requestPresentationFocus(request)
        }
        currentPresentationFocusRequest = request
        if holdPresentationFocusRequest {
            return await withCheckedContinuation { continuation in
                presentationFocusContinuation = continuation
            }
        }
        return ReviewPresentationFocusOutcome(
            request: request,
            result: presentationFocusResult
        )
    }

    func releasePresentationFocus(_ result: ReviewPresentationFocusResult) {
        guard let request = currentPresentationFocusRequest else { return }
        presentationFocusContinuation?.resume(
            returning: ReviewPresentationFocusOutcome(request: request, result: result)
        )
        presentationFocusContinuation = nil
    }

    func dismiss() {
        dismissCallCount += 1
        eventTrace.append("dismiss")
        productionController.dismiss()
    }

    var gatedReadOnlyCommandCount: Int { gatedReadOnlyCommands.count }

    func invokeDraftChange(_ draft: String) {
        draftChange?(draft)
        if case .editable(_, let isPossiblyIncomplete, _) = lastDraftState {
            lastDraftState = .editable(
                draft: draft,
                isPossiblyIncomplete: isPossiblyIncomplete,
                feedback: nil
            )
        }
    }

    func invokeConfirm() {
        guard let state = lastDraftState,
              case .editable = state,
              let panel = NSApp.windows.compactMap({ $0 as? ReviewPanel }).last else { return }
        let priorConfirmCount = confirmGestureCount
        for y in stride(from: CGFloat(8), through: CGFloat(280), by: CGFloat(8)) {
            _ = issue40PerformRealSendClick(on: panel, contentY: y)
            if confirmGestureCount > priorConfirmCount {
                return
            }
        }
    }

    func invokeDiscard() {
        discard?()
    }

}

@MainActor
private final class Issue39NativeReviewSurfacePresenter: ReviewSurfacePresenting {
    private var capturedApplication: StableApplicationIdentity?
    private lazy var controller = issue40MakeDeterministicReviewWindowController { [weak self] in
        self?.capturedApplication
    }
    private(set) var window: NSWindow?
    private(set) var editor: NSTextView?

    func renderReadOnly(phase: ReviewReadOnlyPhase, preview: String) {}

    func renderDraft(
        state: TranscriptionReviewState,
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor (ReviewConfirmationIntent) -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) {
        controller.renderDraft(
            state: state,
            onDraftChange: onDraftChange,
            onConfirm: onConfirm,
            onDiscard: onDiscard
        )
        let panel = NSApp.windows.compactMap { $0 as? ReviewPanel }.last
        self.window = panel
        self.editor = nil
        if let panel,
           let contentView = panel.contentView {
            contentView.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        if let panel,
           let contentView = panel.contentView,
           let editor = editableTextView(in: contentView) {
            self.editor = editor
            _ = panel.makeFirstResponder(editor)
        }
    }

    func invokeQualifiedReturnIntent() {
        guard let panel = window as? ReviewPanel,
              let editor,
              let event = NSEvent.keyEvent(
                  with: .keyDown,
                  location: .zero,
                  modifierFlags: [],
                  timestamp: 0,
                  windowNumber: panel.windowNumber,
                  context: nil,
                  characters: "\r",
                  charactersIgnoringModifiers: "\r",
                  isARepeat: false,
                  keyCode: 36
              ) else { return }
        _ = panel.makeFirstResponder(editor)
        panel.makeKeyAndOrderFront(nil)
        panel.sendEvent(event)
    }

    func requestPresentationFocus(
        _ request: ReviewPresentationFocusRequest
    ) async -> ReviewPresentationFocusOutcome {
        capturedApplication = request.capturedApplication
        return await controller.requestPresentationFocus(request)
    }

    func dismiss() {
        controller.dismiss()
        editor = nil
        window = nil
    }

    private func editableTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView, textView.isEditable {
            return textView
        }
        for subview in view.subviews.reversed() {
            if let textView = editableTextView(in: subview) {
                return textView
            }
        }
        return nil
    }
}

@MainActor
private final class Issue38ReviewOverlayPresenter: RecordingOverlayPresenting {
    func show(status: RecordingState) {}
    func update(status: RecordingState) {}
    func hide() {}
    func presentCompletionFeedback(
        _ feedback: RecordingState,
        minimumVisibleDuration: TimeInterval
    ) {}
}
