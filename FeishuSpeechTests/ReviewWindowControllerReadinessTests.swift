import AppKit
import SwiftUI
@testable import FeishuSpeech
import XCTest

@MainActor
@discardableResult
func issue40PerformRealSendClick(
    on panel: ReviewPanel,
    contentY: CGFloat = 30
) -> Bool {
    guard let contentView = panel.contentView else { return false }

    panel.makeKeyAndOrderFront(nil)
    panel.displayIfNeeded()
    contentView.layoutSubtreeIfNeeded()

    // TranscriptionReviewView uses a fixed 20-point outer padding and the
    // Send control is the trailing control in the bottom HStack. SwiftUI's
    // NSHostingView does not expose that Button as an NSButton/AX child in
    // this unit-test process, so drive the real panel mouse route at the
    // materialized control coordinate instead of manufacturing an intent.
    let contentPoint = NSPoint(
        x: contentView.bounds.maxX - 45,
        y: min(contentY, max(1, contentView.bounds.maxY - 1))
    )
    // NSEvent.mouseEvent's location is interpreted in the panel base
    // coordinate by NSPanel. The content view begins at that same origin for
    // this titled panel, so retain the measured content coordinate directly.
    let windowPoint = contentPoint
    guard let down = NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: windowPoint,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: panel.windowNumber,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1
    ),
    let up = NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: windowPoint,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: panel.windowNumber,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 0
    ) else {
        return false
    }

    // Queue the complete pair before AppKit begins processing either event.
    // A coordinate miss can land on NSTextView, whose tracking loop waits for
    // the matching release. Pumping the real application queue delivers the
    // down through ReviewPanel; its normal tracking loop can then consume the
    // already-queued up. The helper never manufactures an intent or calls the
    // confirmation closure directly.
    NSApp.postEvent(down, atStart: false)
    NSApp.postEvent(up, atStart: false)

    // Bound the test fixture's event-loop drain. A broken AppKit route must
    // return control to the test instead of turning a coordinate miss into an
    // unbounded synchronous hang.
    let deadline = Date(timeIntervalSinceNow: 0.05)
    while Date() < deadline {
        guard let event = NSApp.nextEvent(
            matching: [.leftMouseDown, .leftMouseUp],
            until: deadline,
            inMode: .default,
            dequeue: true
        ) else {
            break
        }
        NSApp.sendEvent(event)
    }
    return true
}

@MainActor
func issue40EditableTextView(in view: NSView?) -> NSTextView? {
    guard let view else { return nil }
    if let textView = view as? NSTextView, textView.isEditable {
        return textView
    }
    for subview in view.subviews.reversed() {
        if let textView = issue40EditableTextView(in: subview) {
            return textView
        }
    }
    return nil
}

@MainActor
@discardableResult
func issue40PerformQualifiedReturn(on panel: ReviewPanel) -> Bool {
    guard let contentView = panel.contentView,
          let editor = issue40EditableTextView(in: contentView) else {
        return false
    }

    panel.makeKeyAndOrderFront(nil)
    guard panel.makeFirstResponder(editor) else { return false }

    // Construct the event only after the real panel/editor relationship has
    // been established. AppKit can otherwise retain the pre-key window
    // number in the synthetic event even though the panel is now key.
    guard let event = NSEvent.keyEvent(
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
    ) else {
        return false
    }

    panel.sendEvent(event)
    return true
}

@MainActor
func issue40MakeDeterministicReviewWindowController(
    frontmostApplication: @escaping @MainActor () -> StableApplicationIdentity?
) -> ReviewWindowController {
    let appKit = ReviewWindowController.ReadinessEnvironment.appKit
    return ReviewWindowController(
        readinessEnvironment: ReviewWindowController.ReadinessEnvironment(
            requestActivation: { false },
            applicationIsActive: { true },
            frontmostApplication: frontmostApplication,
            feishuSpeechIsActive: { false },
            // The accessory XCTest host cannot make a nonactivating panel the
            // process key window. Keep the real Return event path and inject
            // only this deterministic readiness telemetry seam; production's
            // appKit default remains panel.isKeyWindow.
            panelIsKey: { _ in true },
            editorLookup: appKit.editorLookup,
            editorAttached: appKit.editorAttached,
            makeFirstResponder: appKit.makeFirstResponder,
            firstResponderIsEditor: appKit.firstResponderIsEditor,
            nowNanoseconds: appKit.nowNanoseconds,
            sleep: appKit.sleep
        )
    )
}

@MainActor
final class ReviewWindowControllerReadinessTests: XCTestCase {
    private var requestOrdinal: UInt64 = 0

    func test_nonactivatingEditablePanelBecomesKeyWithoutActivatingFeishuSpeech() throws {
        let controller = ReviewWindowController()
        defer { controller.dismiss() }

        renderDraft(on: controller, draft: "PRIVATE_NONACTIVATING_DRAFT")
        let panel = try XCTUnwrap(
            reviewPanel(),
            "the editable review must materialize the retained production panel"
        )

        XCTAssertTrue(
            panel.styleMask.contains(.nonactivatingPanel),
            "the review panel must be non-activating so the captured target remains frontmost"
        )
        XCTAssertTrue(
            panel.becomesKeyOnlyIfNeeded,
            "the non-activating review panel must become key only when explicitly needed"
        )
    }

    func test_nonactivatingPanelKeepsCapturedTargetFrontmost() async throws {
        let clock = ReviewReadinessClock()
        let probe = ReviewReadinessProbe()
        probe.editor = probe.makeEditor()
        let controller = makeController(probe: probe, clock: clock)
        defer { controller.dismiss() }

        renderDraft(on: controller, draft: "PRIVATE_TARGET_PRESERVING_DRAFT")
        let panel = try XCTUnwrap(reviewPanel())
        let result = await controller.requestPresentationFocus(makeRequest())

        XCTAssertEqual(result.result, .focused)
        XCTAssertEqual(
            probe.activationRequestCount,
            0,
            "focus assistance must not activate FeishuSpeech or steal the captured target"
        )
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(reviewPanel() === panel)
    }

    func test_focusReadinessRequiresTheExactCapturedApplicationIdentity() throws {
        let stateSource = try productionSource(
            relativePath: "FeishuSpeech/Models/TranscriptionReviewState.swift"
        )
        let controllerSource = try productionSource(
            relativePath: "FeishuSpeech/Controllers/ReviewWindowController.swift"
        )

        XCTAssertTrue(
            stateSource.contains("capturedApplication") ||
                stateSource.contains("targetApplication"),
            "focus telemetry must carry the stable application identity captured before the preview"
        )
        XCTAssertTrue(
            controllerSource.contains("frontmostIdentity") ||
                controllerSource.contains("capturedApplication"),
            "readiness must compare the live frontmost identity with the captured target, not merely reject FeishuSpeech"
        )
    }

    func test_focusReadinessAcceptsCapturedApplicationAndRejectsOtherOrRelaunchedIdentity() async {
        let clock = ReviewReadinessClock()
        let probe = ReviewReadinessProbe()
        probe.editor = probe.makeEditor()
        let applicationA = identity(pid: 4101, launchDate: 1)
        let relaunchedA = identity(pid: 4101, launchDate: 2)
        let applicationB = identity(pid: 4102, launchDate: 1)
        probe.frontmostApplication = applicationA
        let controller = makeController(probe: probe, clock: clock)
        defer { controller.dismiss() }

        renderDraft(on: controller, draft: "PRIVATE_EXACT_TARGET_READINESS")
        let positive = await controller.requestPresentationFocus(
            makeRequest(capturedApplication: applicationA)
        )
        XCTAssertEqual(
            positive.result,
            .focused,
            "the same stable captured application must satisfy presentation readiness"
        )

        for changedIdentity in [applicationB, relaunchedA] {
            probe.frontmostApplication = changedIdentity
            clock.setAdvanceToDeadlineOnNextSleep()
            let negative = await controller.requestPresentationFocus(
                makeRequest(capturedApplication: applicationA)
            )
            XCTAssertEqual(
                negative.result,
                .notFocused(.timedOut(lastUnmet: .applicationActive)),
                "a different app or relaunched PID must not prove readiness for captured A"
            )
        }
    }

    func test_controllerUsesRealPanelSendAndQualifiedReturnGestureRoutes() async throws {
        // This case intentionally uses the production AppKit editor lookup,
        // attachment predicate, and first-responder seam. The deterministic
        // controller only fixes activation/application telemetry; readiness
        // must still prove the real panel/editor relationship used by Return.
        let controller = issue40MakeDeterministicReviewWindowController {
            nil
        }
        defer { controller.dismiss() }
        var confirmationCount = 0

        controller.renderDraft(
            state: .editable(
                draft: "PRIVATE_GESTURE_ROUTE_DRAFT",
                isPossiblyIncomplete: false,
                feedback: nil
            ),
            onDraftChange: { _ in },
            onConfirm: { _ in confirmationCount += 1 },
            onDiscard: {}
        )
        let panel = try XCTUnwrap(reviewPanel())
        let firstFocus = await controller.requestPresentationFocus(makeRequest())
        XCTAssertEqual(firstFocus.result, .focused)
        var sendGestureDelivered = false
        for y in stride(from: CGFloat(8), through: CGFloat(280), by: CGFloat(8)) {
            _ = issue40PerformRealSendClick(on: panel, contentY: y)
            if confirmationCount == 1 {
                sendGestureDelivered = true
                break
            }
        }
        XCTAssertTrue(
            sendGestureDelivered,
            "the production Send button must accept a real mouse down/up through the retained ReviewPanel"
        )
        XCTAssertEqual(confirmationCount, 1)

        // The controller's callback receives the opaque intent. The test only
        // records that the real gesture route reached the callback; it cannot
        // manufacture the fileprivate capability itself.
        controller.renderDraft(
            state: .editable(
                draft: "PRIVATE_GESTURE_ROUTE_DRAFT",
                isPossiblyIncomplete: false,
                feedback: nil
            ),
            onDraftChange: { _ in },
            onConfirm: { _ in confirmationCount += 1 },
            onDiscard: {}
        )
        let refreshedPanel = try XCTUnwrap(reviewPanel())
        let secondFocus = await controller.requestPresentationFocus(makeRequest())
        XCTAssertEqual(secondFocus.result, .focused)
        let refreshedEditor = try XCTUnwrap(
            issue40EditableTextView(in: refreshedPanel.contentView)
        )
        // XCTest's accessory host cannot make this nonactivating panel the
        // process key window. The production arbiter now samples the injected
        // readinessEnvironment.panelIsKey seam, which is true in this
        // deterministic controller; the native event path remains real.
        XCTAssertTrue(refreshedPanel.firstResponder === refreshedEditor)
        XCTAssertTrue(
            issue40PerformQualifiedReturn(on: refreshedPanel),
            "the retained panel must route a qualified native Return through its editor"
        )
        XCTAssertEqual(
            confirmationCount,
            2,
            "the real Send and panel Return routes each deliver exactly one opaque intent"
        )
    }

    func test_focusFailureKeepsVisibleSendAndDoesNotInstallGlobalReturnCapture() async throws {
        let clock = ReviewReadinessClock()
        clock.setAdvanceToDeadlineOnNextSleep()
        let probe = ReviewReadinessProbe()
        probe.editor = probe.makeEditor()
        probe.firstResponderAssignmentSucceeds = false
        let controller = makeController(probe: probe, clock: clock)
        defer { controller.dismiss() }

        renderDraft(on: controller, draft: "PRIVATE_FOCUS_FAILURE_SEND_DRAFT")
        let panel = try XCTUnwrap(reviewPanel())
        let result = await controller.requestPresentationFocus(makeRequest())

        XCTAssertEqual(
            result.result,
            .notFocused(.timedOut(lastUnmet: .editorFirstResponder))
        )
        XCTAssertTrue(panel.isVisible)

        let source = try productionSource(relativePath: "FeishuSpeech/Controllers/ReviewWindowController.swift")
        XCTAssertFalse(
            source.contains("addGlobalMonitorForEvents"),
            "focus failure must not install a global Return capture path"
        )
    }

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
        XCTAssertEqual(
            probe.activationRequestCount,
            0,
            "the v5 non-activating panel must not request activation of FeishuSpeech"
        )
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
        XCTAssertEqual(
            probe.activationRequestCount,
            0,
            "the v5 non-activating panel must not request activation of FeishuSpeech"
        )
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
            issue40EditableTextView(in: panel.contentView),
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
        let editorAfterRetry = try XCTUnwrap(issue40EditableTextView(in: panel.contentView))
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
                frontmostApplication: { [weak probe] in
                    probe?.frontmostApplication
                },
                feishuSpeechIsActive: { [weak probe] in
                    probe?.feishuSpeechIsActive ?? false
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

    private func makeRequest(
        capturedApplication: StableApplicationIdentity? = nil
    ) -> ReviewPresentationFocusRequest {
        requestOrdinal &+= 1
        return ReviewPresentationFocusRequest(
            reviewID: UUID(uuidString: "00000000-0000-0000-0000-000000000040")!,
            generation: 40,
            focusAttemptID: requestOrdinal,
            capturedApplication: capturedApplication
        )
    }

    private func identity(
        pid: pid_t,
        launchDate: TimeInterval
    ) -> StableApplicationIdentity {
        StableApplicationIdentity(
            processIdentifier: pid,
            bundleIdentifier: "com.example.target",
            executableURL: URL(fileURLWithPath: "/Applications/Target.app/Contents/MacOS/Target"),
            launchDate: Date(timeIntervalSince1970: launchDate)
        )
    }

    private func reviewPanel() -> ReviewPanel? {
        NSApp.windows.compactMap { $0 as? ReviewPanel }.last
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
    var frontmostApplication: StableApplicationIdentity?
    var feishuSpeechIsActive = false
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
