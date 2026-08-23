import AppKit
import SwiftUI
@testable import FeishuSpeech
import XCTest

@MainActor
final class ReviewWindowControllerReadinessTests: XCTestCase {
    private var requestOrdinal: UInt64 = 0

    func test_activationRequestFailureIsAdvisoryWhenPredicatesAreReady() async {
        let clock = ReviewReadinessClock()
        let probe = ReviewReadinessProbe()
        probe.activationAllowed = false
        probe.editor = probe.makeEditor()
        let controller = makeController(probe: probe, clock: clock)
        defer { controller.dismiss() }

        var discardCallCount = 0
        controller.renderDraft(
            state: .editable(
                draft: "PRIVATE_CONTROLLER_DRAFT",
                isPossiblyIncomplete: false,
                feedback: nil
            ),
            onDraftChange: { _ in },
            onConfirm: { _ in },
            onDiscard: { discardCallCount += 1 }
        )
        guard let initialPanel = reviewPanel() else {
            XCTFail("renderDraft must materialize a production ReviewPanel")
            return
        }

        let result = await controller.requestPresentationFocus(makeRequest())

        XCTAssertEqual(
            result.result,
            .focused,
            "an activation request failure must remain advisory when real readiness predicates are already true"
        )
        XCTAssertTrue(initialPanel.isVisible)
        XCTAssertTrue(reviewPanel() === initialPanel, "readiness failure must retain the same panel")
        XCTAssertTrue(controller.windowShouldClose(initialPanel))
        XCTAssertEqual(discardCallCount, 1, "failure must retain the explicit discard callback")
        XCTAssertEqual(probe.activationRequestCount, 1)
        XCTAssertEqual(clock.sleepCallCount, 0)
    }

    func test_activationRequestFailurePollsDelayedPredicatesUntilReady() async {
        let clock = ReviewReadinessClock()
        let probe = ReviewReadinessProbe()
        probe.activationAllowed = false
        probe.applicationActive = false
        probe.applicationActiveAfterCheckCount = 2
        probe.panelKey = false
        probe.panelKeyAfterCheckCount = 2
        probe.editor = probe.makeEditor()
        let controller = makeController(probe: probe, clock: clock)
        defer { controller.dismiss() }
        renderDraft(on: controller, draft: "PRIVATE_DELAYED_READINESS_DRAFT")
        guard let panel = reviewPanel() else {
            XCTFail("renderDraft must materialize a production ReviewPanel")
            return
        }

        let result = await controller.requestPresentationFocus(makeRequest())

        XCTAssertEqual(
            result.result,
            .focused,
            "an activation request failure must not prevent polling real application/key predicates"
        )
        XCTAssertGreaterThanOrEqual(clock.sleepCallCount, 2)
        XCTAssertGreaterThanOrEqual(probe.applicationActiveCheckCount, 2)
        XCTAssertGreaterThanOrEqual(probe.panelKeyCheckCount, 2)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(reviewPanel() === panel)
    }

    func test_activationRequestFailureWithNeverReadyPredicatesTimesOutWithActualPredicate() async {
        let clock = ReviewReadinessClock()
        clock.setAdvanceToDeadlineOnNextSleep()
        let probe = ReviewReadinessProbe()
        probe.activationAllowed = false
        probe.applicationActive = false
        let controller = makeController(probe: probe, clock: clock)
        defer { controller.dismiss() }
        renderDraft(on: controller, draft: "PRIVATE_TIMEOUT_AFTER_ACTIVATION_FAILURE")
        guard let panel = reviewPanel() else {
            XCTFail("renderDraft must materialize a production ReviewPanel")
            return
        }

        let result = await controller.requestPresentationFocus(makeRequest())

        XCTAssertEqual(
            result.result,
            .notFocused(.timedOut(lastUnmet: .applicationActive)),
            "failure must be typed from the actual unmet predicate, never as activationRejected"
        )
        XCTAssertNotEqual(result.result, .focused, "an actually unready surface must never become confirmable")
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(reviewPanel() === panel)
        XCTAssertEqual(probe.activationRequestCount, 1)
    }

    func test_inactiveApplicationIsTypedPendingWithoutDismissingPanel() async {
        let clock = ReviewReadinessClock()
        let probe = ReviewReadinessProbe()
        probe.applicationActive = false
        let controller = makeController(probe: probe, clock: clock)
        defer { controller.dismiss() }
        renderDraft(on: controller)
        guard let panel = reviewPanel() else {
            XCTFail("renderDraft must materialize a production ReviewPanel")
            return
        }

        let result = await controller.requestPresentationFocus(makeRequest())

        XCTAssertEqual(result.result, .notFocused(.timedOut(lastUnmet: .applicationActive)))
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(reviewPanel() === panel)
    }

    func test_nonKeyPanelIsTypedPendingWithoutDismissingPanel() async {
        let clock = ReviewReadinessClock()
        let probe = ReviewReadinessProbe()
        probe.panelKey = false
        let controller = makeController(probe: probe, clock: clock)
        defer { controller.dismiss() }
        renderDraft(on: controller)
        guard let panel = reviewPanel() else {
            XCTFail("renderDraft must materialize a production ReviewPanel")
            return
        }

        let result = await controller.requestPresentationFocus(makeRequest())

        XCTAssertEqual(result.result, .notFocused(.timedOut(lastUnmet: .panelKey)))
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(reviewPanel() === panel)
    }

    func test_editorMaterializationAttachmentAndFirstResponderPredicatesAreTyped() async {
        let cases: [(String, (ReviewReadinessProbe) -> Void, ReviewPresentationFocusPredicate)] = [
            (
                "materialization",
                { probe in probe.editor = nil },
                .editorMaterialized
            ),
            (
                "attachment",
                { probe in
                    probe.editor = probe.makeEditor()
                    probe.editorAttached = false
                },
                .editorAttachedToPanel
            ),
            (
                "first responder",
                { probe in
                    probe.editor = probe.makeEditor()
                    probe.firstResponderAssignmentSucceeds = false
                },
                .editorFirstResponder
            )
        ]

        for (offset, testCase) in cases.enumerated() {
            let clock = ReviewReadinessClock()
            let probe = ReviewReadinessProbe()
            testCase.1(probe)
            let controller = makeController(probe: probe, clock: clock)
            renderDraft(on: controller, draft: "PRIVATE_EDITOR_DRAFT_\(offset)")
            let result = await controller.requestPresentationFocus(makeRequest())
            controller.dismiss()

            XCTAssertEqual(
                result.result,
                .notFocused(.timedOut(lastUnmet: testCase.2)),
                "the production controller must identify the unmet \(testCase.0) predicate"
            )
        }
    }

    func test_timeoutIsTypedAndRetainsPanelForExplicitRetry() async {
        let clock = ReviewReadinessClock()
        clock.setAdvanceToDeadlineOnNextSleep()
        let probe = ReviewReadinessProbe()
        let controller = makeController(probe: probe, clock: clock)
        defer { controller.dismiss() }
        renderDraft(on: controller)
        guard let panel = reviewPanel() else {
            XCTFail("renderDraft must materialize a production ReviewPanel")
            return
        }

        let timedOut = await controller.requestPresentationFocus(makeRequest())

        XCTAssertEqual(
            timedOut.result,
            .notFocused(.timedOut(lastUnmet: .editorMaterialized))
        )
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(reviewPanel() === panel)

        probe.editor = probe.makeEditor()
        let retry = await controller.requestPresentationFocus(makeRequest())

        XCTAssertEqual(retry.result, .focused)
        XCTAssertTrue(reviewPanel() === panel, "retry must reuse the same production panel")
        XCTAssertEqual(probe.firstResponderAssignmentCount, 1)
    }

    func test_cancellationIsTypedAndDoesNotDismissOrDropCallbacks() async {
        let clock = ReviewReadinessClock()
        let probe = ReviewReadinessProbe()
        let controller = makeController(probe: probe, clock: clock)
        defer { controller.dismiss() }
        var discardCallCount = 0
        controller.renderDraft(
            state: .editable(
                draft: "PRIVATE_CANCELLED_CONTROLLER_DRAFT",
                isPossiblyIncomplete: false,
                feedback: nil
            ),
            onDraftChange: { _ in },
            onConfirm: { _ in },
            onDiscard: { discardCallCount += 1 }
        )
        guard let panel = reviewPanel() else {
            XCTFail("renderDraft must materialize a production ReviewPanel")
            return
        }

        let request = makeRequest()
        let readinessTask = Task { @MainActor in
            await controller.requestPresentationFocus(request)
        }
        for _ in 0 ..< 20 where clock.sleepCallCount == 0 {
            await Task.yield()
        }
        readinessTask.cancel()
        let result = await readinessTask.value

        XCTAssertEqual(
            result.result,
            .notFocused(.cancelled(lastUnmet: .editorMaterialized))
        )
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(reviewPanel() === panel)
        XCTAssertTrue(controller.windowShouldClose(panel))
        XCTAssertEqual(discardCallCount, 1, "cancellation must retain explicit discard authority")
    }

    func test_readyMaterializesEditorAttachesItAndMakesItFirstResponder() async {
        let clock = ReviewReadinessClock()
        let probe = ReviewReadinessProbe()
        probe.editor = probe.makeEditor()
        let controller = makeController(probe: probe, clock: clock)
        defer { controller.dismiss() }
        renderDraft(on: controller)
        guard let panel = reviewPanel() else {
            XCTFail("renderDraft must materialize a production ReviewPanel")
            return
        }

        let result = await controller.requestPresentationFocus(makeRequest())

        XCTAssertEqual(result.result, .focused)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(probe.editorLookupCount, 1)
        XCTAssertEqual(probe.editorAttachedCount, 1)
        XCTAssertEqual(probe.firstResponderAssignmentCount, 1)
        XCTAssertEqual(probe.firstResponderCheckCount, 1)
    }

    func test_productionEditorMaterializesInRetainedPanelAndSurvivesReadinessRetry() async throws {
        let clock = ReviewReadinessClock()
        let firstResponderGate = ReviewReadinessFirstResponderGate()
        let productionEnvironment = ReviewWindowController.ReadinessEnvironment.appKit
        let controller = ReviewWindowController(
            readinessEnvironment: ReviewWindowController.ReadinessEnvironment(
                requestActivation: { true },
                applicationIsActive: { true },
                panelIsKey: { _ in true },
                editorLookup: productionEnvironment.editorLookup,
                editorAttached: productionEnvironment.editorAttached,
                makeFirstResponder: { _, _ in
                    firstResponderGate.isReady
                },
                firstResponderIsEditor: { _, _ in
                    firstResponderGate.isReady
                },
                nowNanoseconds: { clock.nowNanoseconds() },
                sleep: { nanoseconds in
                    try await clock.sleep(nanoseconds: nanoseconds)
                }
            )
        )
        defer { controller.dismiss() }

        var discardCallCount = 0
        controller.renderDraft(
            state: .editable(
                draft: "PRIVATE_REAL_EDITOR_DRAFT",
                isPossiblyIncomplete: false,
                feedback: nil
            ),
            onDraftChange: { _ in },
            onConfirm: { _ in },
            onDiscard: { discardCallCount += 1 }
        )
        guard let panel = reviewPanel() else {
            XCTFail("renderDraft must materialize the retained production panel")
            return
        }

        XCTAssertTrue(
            panel.contentView is NSHostingView<TranscriptionReviewView>,
            "the retained panel must host the real TranscriptionReviewView"
        )
        clock.setAdvanceToDeadlineOnNextSleep()
        let firstResult = await controller.requestPresentationFocus(makeRequest())
        XCTAssertEqual(
            firstResult.result,
            .notFocused(.timedOut(lastUnmet: .editorFirstResponder)),
            "the first readiness attempt must reach the real editor before the deterministic responder gate"
        )

        let editorAfterTimeout = try XCTUnwrap(
            editableTextView(in: panel.contentView),
            "production editor lookup must find the SwiftUI-created editable NSTextView"
        )
        XCTAssertTrue(editorAfterTimeout.isEditable)
        XCTAssertTrue(
            editorAfterTimeout.window === panel,
            "production attachment must keep the editor in the retained ReviewPanel"
        )
        XCTAssertTrue(panel.isVisible)

        firstResponderGate.isReady = true
        let retryResult = await controller.requestPresentationFocus(makeRequest())

        XCTAssertEqual(retryResult.result, .focused)
        XCTAssertTrue(reviewPanel() === panel, "readiness retry must reuse the same panel")
        let editorAfterRetry = try XCTUnwrap(editableTextView(in: panel.contentView))
        XCTAssertTrue(editorAfterRetry.window === panel)
        XCTAssertTrue(
            controller.windowShouldClose(panel),
            "the retained discard callback must remain wired after readiness retry"
        )
        XCTAssertEqual(discardCallCount, 1)
    }

    func test_v4PresentationFocusCompletionIsFencedByReviewGenerationAndAttempt() throws {
        let source = try productionSource(relativePath: "FeishuSpeech/Controllers/ReviewWindowController.swift")
        for identity in ["reviewID", "generation", "focusAttemptID"] {
            XCTAssertTrue(
                source.contains(identity),
                "presentation focus completion must echo and validate \(identity)"
            )
        }
        XCTAssertTrue(source.contains("requestPresentationFocus"))
        XCTAssertFalse(source.contains("requestEditableReadiness"))
        XCTAssertFalse(source.contains("onRetryReadiness"))
        XCTAssertTrue(
            source.contains("late") || source.contains("stale") || source.contains("isCurrent"),
            "a late focus completion must be inert after a newer render/generation"
        )
    }

    private func productionSource(relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeController(
        probe: ReviewReadinessProbe,
        clock: ReviewReadinessClock
    ) -> ReviewWindowController {
        ReviewWindowController(
            readinessEnvironment: ReviewWindowController.ReadinessEnvironment(
                requestActivation: { [weak probe] in
                    probe?.requestActivation() ?? false
                },
                applicationIsActive: { [weak probe] in
                    probe?.applicationIsActiveCheck() ?? false
                },
                panelIsKey: { [weak probe] _ in
                    probe?.panelKeyCheck() ?? false
                },
                editorLookup: { [weak probe] _ in
                    probe?.editorLookup()
                },
                editorAttached: { [weak probe] _, _ in
                    probe?.editorAttachedCheck() ?? false
                },
                makeFirstResponder: { [weak probe] _, _ in
                    probe?.makeFirstResponder() ?? false
                },
                firstResponderIsEditor: { [weak probe] _, _ in
                    probe?.firstResponderCheck() ?? false
                },
                nowNanoseconds: { [clock] in
                    clock.nowNanoseconds()
                },
                sleep: { [clock] nanoseconds in
                    try await clock.sleep(nanoseconds: nanoseconds)
                }
            )
        )
    }

    private func renderDraft(
        on controller: ReviewWindowController,
        draft: String = "PRIVATE_CONTROLLER_DRAFT"
    ) {
        controller.renderDraft(
            state: .editable(
                draft: draft,
                isPossiblyIncomplete: false,
                feedback: nil
            ),
            onDraftChange: { _ in },
            onConfirm: { _ in },
            onDiscard: {}
        )
    }

    private func makeRequest() -> ReviewPresentationFocusRequest {
        requestOrdinal &+= 1
        return ReviewPresentationFocusRequest(
            reviewID: UUID(uuidString: "00000000-0000-0000-0000-000000000040")!,
            generation: 40,
            focusAttemptID: requestOrdinal
        )
    }

    private func reviewPanel() -> ReviewPanel? {
        NSApp.windows.compactMap { $0 as? ReviewPanel }.last
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
}

private final class ReviewReadinessProbe: @unchecked Sendable {
    var activationAllowed = true
    var applicationActive = true
    var applicationActiveAfterCheckCount: Int?
    var panelKey = true
    var panelKeyAfterCheckCount: Int?
    var editor: NSTextView?
    var editorAttached = true
    var firstResponderAssignmentSucceeds = true
    private(set) var activationRequestCount = 0
    private(set) var applicationActiveCheckCount = 0
    private(set) var panelKeyCheckCount = 0
    private(set) var editorLookupCount = 0
    private(set) var editorAttachedCount = 0
    private(set) var firstResponderAssignmentCount = 0
    private(set) var firstResponderCheckCount = 0

    func requestActivation() -> Bool {
        activationRequestCount += 1
        return activationAllowed
    }

    func applicationIsActiveCheck() -> Bool {
        applicationActiveCheckCount += 1
        if let applicationActiveAfterCheckCount {
            return applicationActiveCheckCount >= applicationActiveAfterCheckCount
        }
        return applicationActive
    }

    func panelKeyCheck() -> Bool {
        panelKeyCheckCount += 1
        if let panelKeyAfterCheckCount {
            return panelKeyCheckCount >= panelKeyAfterCheckCount
        }
        return panelKey
    }

    func editorLookup() -> NSTextView? {
        editorLookupCount += 1
        return editor
    }

    func editorAttachedCheck() -> Bool {
        editorAttachedCount += 1
        return editorAttached
    }

    func makeFirstResponder() -> Bool {
        firstResponderAssignmentCount += 1
        return firstResponderAssignmentSucceeds
    }

    func firstResponderCheck() -> Bool {
        firstResponderCheckCount += 1
        return firstResponderAssignmentSucceeds
    }

    func makeEditor() -> NSTextView {
        let editor = NSTextView(frame: .zero)
        editor.isEditable = true
        return editor
    }
}

@MainActor
private final class ReviewReadinessFirstResponderGate {
    var isReady = false
}

private final class ReviewReadinessClock: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var value: UInt64 = 0
    nonisolated(unsafe) private var sleeps = 0
    nonisolated(unsafe) private var advanceToDeadlineOnNextSleep = false

    nonisolated var sleepCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sleeps
    }

    nonisolated func setAdvanceToDeadlineOnNextSleep() {
        lock.lock()
        advanceToDeadlineOnNextSleep = true
        lock.unlock()
    }

    nonisolated func nowNanoseconds() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    nonisolated func sleep(nanoseconds: UInt64) async throws {
        recordSleep(nanoseconds: nanoseconds)

        await Task.yield()
        try Task.checkCancellation()
    }

    nonisolated private func recordSleep(nanoseconds: UInt64) {
        lock.lock()
        sleeps += 1
        let shouldAdvanceToDeadline = advanceToDeadlineOnNextSleep
        advanceToDeadlineOnNextSleep = false
        if shouldAdvanceToDeadline {
            value = 2_000_000_000
        } else {
            value &+= nanoseconds
        }
        lock.unlock()
    }
}
