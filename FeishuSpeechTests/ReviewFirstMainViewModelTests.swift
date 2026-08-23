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

        context.viewModel.reviewDraftText = "PRIVATE_EDITED_DRAFT"
        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .editable(draft: "PRIVATE_EDITED_DRAFT", isPossiblyIncomplete: false)
        )

        context.viewModel.confirmReviewDraft()
        context.viewModel.confirmReviewDraft()
        await waitUntil { context.delivery.deliveredTexts.count == 1 }

        XCTAssertEqual(context.delivery.deliveredTexts, ["PRIVATE_EDITED_DRAFT"])
        XCTAssertEqual(context.delivery.copyCalls, 0)
        XCTAssertEqual(context.viewModel.transcriptionReviewState, .idle)
    }

    func test_reviewFirst_confirmationFreezesExactCurrentNonWhitespaceDraftAndDeliversOnce() async {
        let context = makeContext(finishEvent: .final("PRIVATE_FINAL"))
        let identity = StreamingSessionIdentity(generation: 3_839)
        let draft = "  PRIVATE_EDITED_DRAFT\n"

        await startAndSeal(context, identity: identity)
        context.viewModel.reviewDraftText = draft
        context.viewModel.confirmReviewDraft()
        context.viewModel.confirmReviewDraft()
        await waitUntil { context.delivery.deliveredTexts.count == 1 }

        XCTAssertEqual(
            context.delivery.deliveredTexts,
            [draft],
            "confirmation must deliver the current non-whitespace draft without trimming or normalizing"
        )
        XCTAssertEqual(context.delivery.copyCalls, 0)
        XCTAssertEqual(context.viewModel.transcriptionReviewState, .idle)
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
            let event = try XCTUnwrap(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: "\r",
                    charactersIgnoringModifiers: "\r",
                    isARepeat: false,
                    keyCode: 36
                )
            )
            editor.keyDown(with: event)
        }

        await waitUntil { context.delivery.deliveredTexts.count == 1 }
        XCTAssertEqual(context.delivery.deliveredTexts, [editedDraft])
        XCTAssertEqual(context.delivery.copyCalls, 0)
        XCTAssertEqual(context.viewModel.transcriptionReviewState, .idle)
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
        context.viewModel.reviewDraftText = " \n\t"
        context.viewModel.confirmReviewDraft()
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
        context.viewModel.reviewDraftText = "PRIVATE_EDITED"
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
            context.viewModel.reviewDraftText = "PRIVATE_EDITED_\(offset)"

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
            context.viewModel.reviewDraftText = "PRIVATE_FROZEN_DRAFT_\(offset)"
            context.viewModel.confirmReviewDraft()
            context.viewModel.confirmReviewDraft()
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
        context.viewModel.reviewDraftText = "PRIVATE_CANCELLED_DRAFT"
        context.viewModel.confirmReviewDraft()
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
            context.viewModel.reviewDraftText = frozenDraft

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
        context.viewModel.reviewDraftText = "PRIVATE_HUMAN_EDIT"

        context.viewModel.handleStreamingEventForTesting(
            .partial("PRIVATE_LATE_PARTIAL"),
            identity: identity
        )
        context.viewModel.handleStreamingEventForTesting(
            .final("PRIVATE_LATE_FINAL"),
            identity: identity
        )
        let readOnlyRenderCount = context.presenter.renderReadOnlyCallCount
        context.presenter.invokeDraftChange("PRIVATE_LATE_CALLBACK")
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
        XCTAssertEqual(context.presenter.renderDraftCallCount, 2)
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
        XCTAssertEqual(context.presenter.renderDraftCallCount, 2)
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

    func test_reviewFirst_editableReadinessFailureRetainsDraftAndAuthorityWithoutOutput() async {
        let failures: [ReviewEditableReadinessFailure] = [
            .activationRejected,
            .timedOut(lastUnmet: .panelKey),
            .timedOut(lastUnmet: .editorMaterialized),
            .timedOut(lastUnmet: .editorFirstResponder),
            .cancelled(lastUnmet: .editorMaterialized),
            .timedOut(lastUnmet: .editorFirstResponder)
        ]

        for (offset, failure) in failures.enumerated() {
            let context = makeContext(
                finishEvent: .final("PRIVATE_FROZEN_ACTION_TWO_\(offset)"),
                editableReadinessResult: .pending(failure)
            )
            let identity = StreamingSessionIdentity(generation: UInt64(3_826 + offset))
            let frozenDraft = "PRIVATE_FROZEN_ACTION_TWO_\(offset)"

            await startAndSeal(context, identity: identity)

            XCTAssertEqual(
                context.viewModel.transcriptionReviewState,
                .editablePending(
                    draft: frozenDraft,
                    isPossiblyIncomplete: false,
                    readiness: .blocked(attempt: 1, failure: failure),
                    feedback: nil
                ),
                "\(failure) must leave the durable draft and authority pending without output"
            )
            XCTAssertEqual(context.presenter.lastEditableDraft, frozenDraft)
            XCTAssertEqual(context.presenter.readinessFailures, [failure])
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
            XCTAssertEqual(context.accessibility.setSelectedTextCalls, [])

            context.presenter.invokeDraftChange("PRIVATE_EDITED_AFTER_\(failure)")
            XCTAssertEqual(
                context.viewModel.reviewDraftText,
                "PRIVATE_EDITED_AFTER_\(failure)",
                "presenter failure must retain the same review authority for later edits"
            )
            XCTAssertEqual(
                context.viewModel.transcriptionReviewState,
                .editablePending(
                    draft: "PRIVATE_EDITED_AFTER_\(failure)",
                    isPossiblyIncomplete: false,
                    readiness: .blocked(attempt: 1, failure: failure),
                    feedback: nil
                )
            )
            XCTAssertEqual(context.delivery.deliveredTexts, [])
        }
    }

    func test_reviewFirst_deliveryFailureReturnsExactDraftToEditableWithoutCopyOrAutomaticRetry() async {
        let context = makeContext(finishEvent: .final("PRIVATE_FINAL"))
        context.delivery.result = .deliveryFailed
        let identity = StreamingSessionIdentity(generation: 3_827)
        let draft = "  PRIVATE_DELIVERY_FAILURE_DRAFT\n"

        await startAndSeal(context, identity: identity)
        context.viewModel.reviewDraftText = draft
        context.viewModel.confirmReviewDraft()
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

        context.delivery.result = .inserted
        context.viewModel.confirmReviewDraft()
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
        context.viewModel.reviewDraftText = draft
        context.viewModel.confirmReviewDraft()
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
        case .inserted:
            return .deliveryFailed
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
        editableReadinessResult: ReviewEditableTransitionResult = .ready,
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
        presenter.editableReadinessResult = editableReadinessResult
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

    private func isTerminalReviewDraftState(_ state: TranscriptionReviewState) -> Bool {
        switch state {
        case .idle:
            return true
        case .editable:
            return true
        case .editablePending(_, _, .blocked, _):
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
    private let application: ReviewApplicationIdentity
    private let element: AXUIElement
    private(set) var captureCallCount = 0
    private(set) var deliveredTexts: [String] = []
    private(set) var copyCalls = 0
    private(set) var copiedTexts: [String] = []
    private(set) var eventTrace: [String] = []
    var result: ReviewDeliveryResult = .inserted
    var captureResult: ReviewDestinationCaptureResult

    init() {
        element = AXUIElementCreateApplication(42)
        application = ReviewApplicationIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.example.review-target",
            executableURL: URL(fileURLWithPath: "/Applications/ReviewTarget.app"),
            launchDate: Date(timeIntervalSince1970: 42)
        )
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
        deliveredTexts.append(frozenText)
        return result
    }

    func copyForManualRecovery(_ frozenText: String) {
        copyCalls += 1
        copiedTexts.append(frozenText)
    }
}

@MainActor
private final class Issue38ReviewSurfacePresenter: ReviewSurfacePresenting {
    let surfaceIdentity = UUID()
    private(set) var renderReadOnlyCallCount = 0
    private(set) var readOnlyPhases: [ReviewReadOnlyPhase] = []
    private(set) var readOnlyPreviews: [String] = []
    private(set) var surfaceIDs: [UUID] = []
    private(set) var renderDraftCallCount = 0
    private(set) var editablePresentationCount = 0
    private(set) var readinessRequestCount = 0
    private(set) var readinessFailures: [ReviewEditableReadinessFailure] = []
    private(set) var dismissCallCount = 0
    private(set) var lastReadOnlyPreview = ""
    private(set) var lastReadOnlyPhase: ReviewReadOnlyPhase?
    private(set) var lastEditableDraft = ""
    private(set) var lastEditablePossiblyIncomplete = false
    private(set) var draftStates: [TranscriptionReviewState] = []
    private(set) var eventTrace: [String] = []
    var readOnlyRenderGateOpen = true
    var editableReadinessResult: ReviewEditableTransitionResult = .ready
    private var draftChange: (@MainActor (String) -> Void)?
    private var confirm: (@MainActor () -> Void)?
    private var retryReadiness: (@MainActor () -> Void)?
    private var discard: (@MainActor () -> Void)?
    private var gatedReadOnlyCommands: [(ReviewReadOnlyPhase, String)] = []

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
        onConfirm: @escaping @MainActor () -> Void,
        onRetryReadiness: @escaping @MainActor () -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) {
        renderDraftCallCount += 1
        draftStates.append(state)
        switch state {
        case .editable(let draft, let isPossiblyIncomplete, _),
             .editablePending(let draft, let isPossiblyIncomplete, _, _),
             .confirming(let draft, let isPossiblyIncomplete):
            lastEditableDraft = draft
            lastEditablePossiblyIncomplete = isPossiblyIncomplete
            if case .editable = state {
                editablePresentationCount += 1
            }
        case .idle, .streaming, .sealing:
            break
        }
        surfaceIDs.append(surfaceIdentity)
        eventTrace.append("draft")
        draftChange = onDraftChange
        confirm = onConfirm
        retryReadiness = onRetryReadiness
        discard = onDiscard
    }

    func requestEditableReadiness() async -> ReviewEditableTransitionResult {
        readinessRequestCount += 1
        if case .pending(let failure) = editableReadinessResult {
            readinessFailures.append(failure)
        }
        return editableReadinessResult
    }

    func dismiss() {
        dismissCallCount += 1
        eventTrace.append("dismiss")
    }

    var gatedReadOnlyCommandCount: Int { gatedReadOnlyCommands.count }

    func invokeDraftChange(_ draft: String) {
        draftChange?(draft)
    }

    func invokeConfirm() {
        confirm?()
    }

    func invokeRetryReadiness() {
        retryReadiness?()
    }

    func invokeDiscard() {
        discard?()
    }
}

@MainActor
private final class Issue39NativeReviewSurfacePresenter: ReviewSurfacePresenting {
    private(set) var window: NSWindow?
    private(set) var editor: NSTextView?
    private var hostingView: NSHostingView<TranscriptionReviewView>?
    private var onRetryReadiness: (@MainActor () -> Void)?

    func renderReadOnly(phase: ReviewReadOnlyPhase, preview: String) {}

    func renderDraft(
        state: TranscriptionReviewState,
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor () -> Void,
        onRetryReadiness: @escaping @MainActor () -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) {
        let rootView = TranscriptionReviewView(
            state: state,
            onDraftChange: onDraftChange,
            onConfirm: onConfirm,
            onRetryReadiness: onRetryReadiness,
            onDiscard: onDiscard
        )
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        guard let editor = editableTextView(in: hostingView),
              window.makeFirstResponder(editor) else {
            window.close()
            return
        }

        self.hostingView = hostingView
        self.window = window
        self.editor = editor
        self.onRetryReadiness = onRetryReadiness
    }

    func requestEditableReadiness() async -> ReviewEditableTransitionResult {
        .ready
    }

    func dismiss() {
        window?.orderOut(nil)
        window?.close()
        editor = nil
        hostingView = nil
        onRetryReadiness = nil
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
