import Foundation
import AppKit
import SwiftUI
import os.log
import XCTest

@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "TranscriptionReviewViewTests"
)

final class TranscriptionReviewViewTests: XCTestCase {
    @MainActor
    func test_transcriptFontIsMateriallyLargerInStreamingAndEditableSurfaces() throws {
        let expectedMinimumPointSize: CGFloat = 18
        let previewText = "PRIVATE_FONT_PREVIEW"
        let previewWindow = makeWindow(
            rootView: TranscriptionReviewView(
                state: .streaming(preview: previewText)
            )
        )
        defer {
            previewWindow.orderOut(nil)
            previewWindow.close()
        }

        let previewField = try XCTUnwrap(
            textField(containing: previewText, in: previewWindow.contentView),
            "streaming preview must expose a measurable transcript text control"
        )
        let previewPointSize = previewField.font?.pointSize ?? 0
        XCTAssertGreaterThanOrEqual(
            previewPointSize,
            expectedMinimumPointSize,
            "streaming/read-only transcript text must use the explicit larger transcript size"
        )

        let editableText = "PRIVATE_FONT_EDITABLE"
        let editableWindow = makeWindow(
            rootView: TranscriptionReviewView(
                state: .editable(
                    draft: editableText,
                    isPossiblyIncomplete: false,
                    feedback: nil
                )
            )
        )
        defer {
            editableWindow.orderOut(nil)
            editableWindow.close()
        }

        let editor = try XCTUnwrap(
            editableTextView(in: editableWindow.contentView),
            "editable review must materialize its native text editor"
        )
        let editorPointSize = editor.font?.pointSize ?? 0
        XCTAssertGreaterThanOrEqual(
            editorPointSize,
            expectedMinimumPointSize,
            "editable transcript text must share the explicit larger transcript size"
        )
        XCTAssertEqual(
            editorPointSize,
            previewPointSize,
            "streaming and editable transcript surfaces must use the same shared/default font size"
        )
    }

    @MainActor
    func test_frozenDraftExposesSendAndReturnWithoutRetryEditingControl() throws {
        let source = try productionSource(relativePath: "FeishuSpeech/Views/TranscriptionReviewView.swift")
        XCTAssertFalse(
            source.contains("重试编辑"),
            "the frozen editable review must not expose the obsolete retry-editing control or text"
        )
        XCTAssertFalse(
            source.contains("editablePending"),
            "v4 must not expose focus readiness as a durable product state"
        )
        XCTAssertFalse(
            source.contains("onRetryReadiness"),
            "v4 must not expose a user-facing focus-readiness retry callback"
        )
        XCTAssertTrue(
            source.contains("Button(\"发送\")"),
            "the frozen editable review must retain an explicit Send confirmation control"
        )

        let editableWindow = makeWindow(
            rootView: TranscriptionReviewView(
                state: .editable(
                    draft: "PRIVATE_CONFIRMABLE_DRAFT",
                    isPossiblyIncomplete: false,
                    feedback: nil
                )
            )
        )
        defer {
            editableWindow.orderOut(nil)
            editableWindow.close()
        }
        XCTAssertNotNil(editableWindow.contentView)
        XCTAssertNil(button(titled: "重试编辑", in: editableWindow.contentView))
    }

    @MainActor
    func test_deliveryUncertainFeedbackWarnsAboutPossibleDuplicateSendWithoutRetryEditing() throws {
        let source = try productionSource(relativePath: "FeishuSpeech/Views/TranscriptionReviewView.swift")
        XCTAssertFalse(
            source.contains("重试编辑"),
            "delivery uncertainty must not restore the removed retry-editing action"
        )
        XCTAssertTrue(
            source.contains("再次发送") && source.contains("重复"),
            "delivery uncertainty feedback must explicitly warn that another Send may duplicate prior output"
        )

        let window = makeWindow(
            rootView: TranscriptionReviewView(
                state: .editable(
                    draft: "PRIVATE_UNCERTAIN_DRAFT",
                    isPossiblyIncomplete: false,
                    feedback: .deliveryUncertain
                )
            )
        )
        defer {
            window.orderOut(nil)
            window.close()
        }

        XCTAssertNil(
            button(titled: "重试编辑", in: window.contentView),
            "delivery uncertainty must remain an explicit-send state without retry-editing control"
        )
    }

    @MainActor
    func test_activationFailedFeedbackNamesTargetApplicationWithoutPreparationOrRetryText() throws {
        let source = try productionSource(relativePath: "FeishuSpeech/Views/TranscriptionReviewView.swift")
        XCTAssertTrue(
            source.contains("无法激活目标应用；请确认后再发送。"),
            "activation failure after readiness must name target application activation and require explicit confirmation"
        )
        XCTAssertFalse(
            source.contains("编辑器正在准备，请稍候。"),
            "activation failure must not claim the editor is still preparing after readiness failed"
        )
        XCTAssertFalse(
            source.contains("重试编辑"),
            "activation failure must not restore the removed retry-editing control or action"
        )

        let window = makeWindow(
            rootView: TranscriptionReviewView(
                state: .editable(
                    draft: "PRIVATE_ACTIVATION_FAILURE_DRAFT",
                    isPossiblyIncomplete: false,
                    feedback: .activationFailed
                )
            )
        )
        defer {
            window.orderOut(nil)
            window.close()
        }
        XCTAssertNil(
            button(titled: "重试编辑", in: window.contentView),
            "activation failure must remain an explicit-send state without retry-editing control"
        )
    }

    @MainActor
    func test_streamingReviewContentDoesNotIntersectTrafficLightControls() throws {
        let controller = ReviewWindowController()
        defer { controller.dismiss() }
        controller.renderReadOnly(
            phase: .streaming,
            preview: "PRIVATE_TRAFFIC_LIGHT_PREVIEW"
        )

        let panel = try XCTUnwrap(
            NSApp.windows.compactMap { $0 as? ReviewPanel }.last,
            "streaming review must materialize the production review panel"
        )
        guard let contentView = panel.contentView else {
            XCTFail("streaming review must install a content view")
            return
        }
        guard let coordinateView = contentView.superview else {
            XCTFail("streaming review content must be attached to the panel frame view")
            return
        }
        panel.displayIfNeeded()
        contentView.layoutSubtreeIfNeeded()

        let contentRect = contentView.frame
        let trafficLightButtons = [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton
        ].compactMap { panel.standardWindowButton($0) }
        XCTAssertEqual(trafficLightButtons.count, 3)

        for button in trafficLightButtons {
            guard let buttonSuperview = button.superview else {
                XCTFail("traffic-light button must remain attached to the panel titlebar")
                continue
            }
            let buttonRect = buttonSuperview.convert(button.frame, to: coordinateView)
            XCTAssertTrue(
                contentRect.intersection(buttonRect).isNull,
                "read-only streaming content must stay below and clear of titlebar traffic-light controls"
            )
        }
    }

    @MainActor
    func test_reviewPanelRetainsExistingSizeAcrossStreamingAndEditableStates() throws {
        let controller = ReviewWindowController()
        defer { controller.dismiss() }

        controller.renderReadOnly(
            phase: .streaming,
            preview: "PRIVATE_PANEL_SIZE_PREVIEW"
        )
        let panel = try XCTUnwrap(
            NSApp.windows.compactMap { $0 as? ReviewPanel }.last,
            "the production review panel must be materialized"
        )
        panel.displayIfNeeded()
        panel.contentView?.layoutSubtreeIfNeeded()
        let originalSize = panel.frame.size

        controller.renderReadOnly(
            phase: .sealing,
            preview: "PRIVATE_PANEL_SIZE_SEALING"
        )
        controller.renderDraft(
            state: .editable(
                draft: "PRIVATE_PANEL_SIZE_DRAFT",
                isPossiblyIncomplete: false,
                feedback: nil
            ),
            onDraftChange: { _ in },
            onConfirm: { _ in },
            onDiscard: {}
        )
        panel.displayIfNeeded()
        panel.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            panel.frame.size,
            originalSize,
            "streaming, sealing, and editable content must reuse the existing panel size"
        )
    }

    func test_reviewView_keepsExplicitConfirmAndCancelShortcuts() throws {
        logger.debug("checking review window shortcut policy")
        let source = try productionSource(relativePath: "FeishuSpeech/Views/TranscriptionReviewView.swift")

        XCTAssertFalse(
            source.contains("keyboardShortcut(.return"),
            "confirmation must not be granted by a default Return key equivalent"
        )
        XCTAssertTrue(
            source.contains("keyboardShortcut(.cancelAction)"),
            "Escape/cancelAction must discard the unresolved review"
        )
        XCTAssertFalse(
            source.contains("keyboardShortcut(.enter)"),
            "the editor must not use Enter as a second confirmation shortcut"
        )
    }

    func test_v5SendButtonHasNoDefaultKeyEquivalent() throws {
        let source = try productionSource(relativePath: "FeishuSpeech/Views/TranscriptionReviewView.swift")

        XCTAssertFalse(
            source.contains("keyboardShortcut(.return"),
            "Send must be an explicit button intent, not an AppKit default Return key equivalent"
        )
    }

    func test_reviewPanel_isOneNSPanelWithSafeReadOnlyAndEditableAuthorityModes() throws {
        let source = try productionSource(relativePath: "FeishuSpeech/Controllers/ReviewWindowController.swift")

        XCTAssertTrue(
            source.contains("class ReviewPanel: NSPanel") ||
                source.contains("final class ReviewPanel: NSPanel"),
            "the review surface must be owned by the dedicated ReviewPanel NSPanel"
        )
        XCTAssertTrue(source.contains("canBecomeKey"))
        XCTAssertTrue(source.contains("canBecomeMain"))
        XCTAssertTrue(source.contains("allowsKeyInteraction"))
        XCTAssertTrue(source.contains("allowsKeyInteraction = false"))
        XCTAssertTrue(source.contains("allowsKeyInteraction = true"))
        XCTAssertTrue(
            source.contains("ignoresMouseEvents = true"),
            "streaming/sealing must remain read-only and non-interactive"
        )
        XCTAssertTrue(source.contains("ignoresMouseEvents = false"))
        XCTAssertTrue(
            source.contains("orderFrontRegardless()"),
            "read-only presentation must not activate or steal the target focus"
        )
        XCTAssertTrue(
            source.contains("makeKeyAndOrderFront"),
            "editable transition must make the same panel key-capable when needed"
        )
        XCTAssertTrue(source.contains("renderReadOnly"))
        XCTAssertTrue(
            source.contains("renderDraft("),
            "the canonical surface owns editable/pending/confirming draft states"
        )
        XCTAssertTrue(
            source.contains("requestPresentationFocus("),
            "focus assistance must remain a typed telemetry-only seam"
        )
        XCTAssertFalse(
            source.contains("requestEditableReadiness()"),
            "editable authority must not be granted through focus readiness"
        )

        XCTAssertTrue(source.contains("width: 520"))
        XCTAssertTrue(source.contains("height: 320"))
        XCTAssertTrue(source.contains("width: 420"))
        XCTAssertTrue(source.contains("height: 240"))
        XCTAssertTrue(source.contains("width: 760"))
        XCTAssertTrue(source.contains("height: 600"))
        XCTAssertTrue(
            source.contains("center()") || source.contains("center"),
            "review must center on the active screen rather than reuse the recording overlay"
        )
        XCTAssertFalse(source.contains("OverlayWindowController.shared"))
        XCTAssertTrue(
            source.contains(".nonactivatingPanel"),
            "the retained panel must preserve the captured target with a non-activating style"
        )

        let panelConstructionCount = source.components(separatedBy: "ReviewPanel(").count - 1
        XCTAssertEqual(
            panelConstructionCount,
            1,
            "streaming/sealing/editable must reuse one panel identity instead of recreating it"
        )
        guard let readOnlyStart = source.range(of: "func renderReadOnly("),
              let editableStart = source.range(of: "func renderDraft(") else {
            XCTFail("ReviewWindowController must expose the canonical renderReadOnly/renderDraft methods")
            return
        }
        XCTAssertLessThan(
            readOnlyStart.lowerBound,
            editableStart.lowerBound,
            "read-only rendering must precede the canonical draft transition"
        )
        let readOnlyBody = source[readOnlyStart.lowerBound ..< editableStart.lowerBound]
        XCTAssertFalse(
            readOnlyBody.contains("activate("),
            "read-only rendering must never activate FeishuSpeech"
        )
        XCTAssertTrue(readOnlyBody.contains("orderFrontRegardless()"))
        XCTAssertFalse(
            source[editableStart.lowerBound...].contains("ReviewPanel("),
            "editable transition must not allocate a second panel"
        )
    }

    func test_reviewWindowCloseRoutesToDiscardAndDismissClearsTranscriptCallbacks() throws {
        let source = try productionSource(relativePath: "FeishuSpeech/Controllers/ReviewWindowController.swift")

        XCTAssertTrue(
            source.contains("windowShouldClose") || source.contains("windowWillClose"),
            "closing the window must be an explicit discard action"
        )
        XCTAssertTrue(source.contains("onDiscard"))
        XCTAssertTrue(
            source.contains("rootView = EmptyView") || source.contains("hostingView = nil"),
            "dismiss must release transcript-bearing hosted content"
        )
    }

    func test_reviewUI_contract_neverUsesDraftInWindowTitleOrFixedFeedbackStrings() throws {
        let viewSource = try productionSource(relativePath: "FeishuSpeech/Views/TranscriptionReviewView.swift")
        let windowSource = try productionSource(relativePath: "FeishuSpeech/Controllers/ReviewWindowController.swift")

        XCTAssertFalse(windowSource.contains("title = draft"))
        XCTAssertFalse(windowSource.contains("title: draft"))
        XCTAssertFalse(viewSource.contains("accessibilityLabel(draft"))
        XCTAssertFalse(viewSource.contains("help(draft"))
        XCTAssertFalse(viewSource.contains("logger.info(\"\\(draft"))
        XCTAssertFalse(windowSource.contains("logger.info(\"\\(draft"))
    }

    func test_v4OnlyOpaqueIntentFromQualifiedNativeReturnCanAuthorizeDelivery() throws {
        let viewSource = try productionSource(relativePath: "FeishuSpeech/Views/TranscriptionReviewView.swift")
        let controllerSource = try productionSource(relativePath: "FeishuSpeech/Controllers/ReviewWindowController.swift")
        let coordinatorSource = try productionSource(relativePath: "FeishuSpeech/ViewModels/MainViewModel.swift")

        XCTAssertFalse(
            viewSource.contains("ReviewConfirmationIntent") ||
                viewSource.contains("qualifiedPreviewReturn") ||
                viewSource.contains("sendButton()"),
            "SwiftUI view code must receive only a no-argument gesture callback and never own intent construction"
        )
        XCTAssertTrue(
            controllerSource.contains("fileprivate init(source:") &&
                controllerSource.contains("fileprivate static func sendButton()") &&
                controllerSource.contains("fileprivate static func qualifiedPreviewReturn()"),
            "the controller must own both fileprivate intent factories and the initializer"
        )
        XCTAssertTrue(
            controllerSource.contains("ReviewPreviewReturnArbiter.qualifies") &&
                controllerSource.contains("ReviewConfirmationIntent.qualifiedPreviewReturn()") &&
                controllerSource.contains("ReviewConfirmationIntent.sendButton()"),
            "only the production panel Send/Return gesture bridges may mint the opaque confirmation intent"
        )
        XCTAssertTrue(controllerSource.contains("panel.onPreviewReturn"))
        XCTAssertFalse(
            coordinatorSource.contains("func confirmReviewDraft()"),
            "the coordinator must not expose a forgeable zero-argument confirmation entry point"
        )
        XCTAssertFalse(
            coordinatorSource.contains("callbackRevision: UInt64?"),
            "an optional revision must not authorize a programmatic or stale confirmation"
        )
        XCTAssertFalse(
            coordinatorSource.contains("confirmReviewDraft(reviewID: reviewID)"),
            "review ID alone is not an opaque UI intent"
        )
    }

    func test_v5IntentConstructionIsConfinedToRealSendOrPanelReturnGestureSites() throws {
        let viewSource = try productionSource(
            relativePath: "FeishuSpeech/Views/TranscriptionReviewView.swift"
        )
        let controllerSource = try productionSource(
            relativePath: "FeishuSpeech/Controllers/ReviewWindowController.swift"
        )
        let coordinatorSource = try productionSource(
            relativePath: "FeishuSpeech/ViewModels/MainViewModel.swift"
        )

        XCTAssertFalse(
            viewSource.contains("ReviewConfirmationIntent") ||
                viewSource.contains("qualifiedPreviewReturn") ||
                viewSource.contains("sendButton()"),
            "intent construction must not remain in the SwiftUI view"
        )
        XCTAssertTrue(
            controllerSource.contains("fileprivate init(source:") &&
                controllerSource.contains("fileprivate static func sendButton()") &&
                controllerSource.contains("fileprivate static func qualifiedPreviewReturn()"),
            "both intent factories and the initializer must be fileprivate in the controller"
        )
        XCTAssertTrue(
            controllerSource.contains("panel.sendEvent") ||
                controllerSource.contains("onPreviewReturn"),
            "the production panel must mint Return intent only from its native event route"
        )
        XCTAssertFalse(
            coordinatorSource.contains("qualifiedPreviewReturn()") ||
                coordinatorSource.contains("sendButton()") ||
                coordinatorSource.contains("ReviewConfirmationIntent("),
            "the coordinator must never manufacture a confirmation capability"
        )
    }

    func test_v4NoProgrammaticOrStaleConfirmationPathCanBypassTheOpaqueIntentFence() throws {
        let windowSource = try productionSource(relativePath: "FeishuSpeech/Controllers/ReviewWindowController.swift")
        let coordinatorSource = try productionSource(relativePath: "FeishuSpeech/ViewModels/MainViewModel.swift")
        XCTAssertTrue(windowSource.contains("ReviewConfirmationIntent"))
        XCTAssertFalse(coordinatorSource.contains("onConfirm: { [weak self]"))
        XCTAssertFalse(windowSource.contains("onConfirm: @escaping @MainActor () -> Void"))
        XCTAssertTrue(
            windowSource.contains("event.keyCode == 36 || event.keyCode == 76") &&
                windowSource.contains("event.isARepeat") &&
                windowSource.contains("deviceIndependentFlagsMask"),
            "native Return/Enter qualification must remain explicit and modifier-aware"
        )
    }

    private func productionSource(relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    @MainActor
    private func makeWindow(rootView: TranscriptionReviewView) -> NSWindow {
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
        return window
    }

    @MainActor
    private func textField(containing text: String, in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let textField = view as? NSTextField,
           textField.stringValue.contains(text) {
            return textField
        }
        for subview in view.subviews.reversed() {
            if let textField = textField(containing: text, in: subview) {
                return textField
            }
        }
        return nil
    }

    @MainActor
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

    @MainActor
    private func button(titled title: String, in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton,
           button.title == title ||
            button.accessibilityTitle() == title ||
            button.accessibilityLabel() == title {
            return button
        }
        for subview in view.subviews.reversed() {
            if let button = button(titled: title, in: subview) {
                return button
            }
        }
        return nil
    }

}

@MainActor
private final class Issue40KeyboardRecorder {
    var currentDraft: String
    var confirmedDrafts: [String] = []
    var discardCount = 0

    init(draft: String) {
        currentDraft = draft
    }
}

@MainActor
private final class Issue40KeyboardProductionSurface {
    @MainActor
    final class ReadinessState {
        var panelIsKey = true
    }

    let recorder: Issue40KeyboardRecorder
    let readinessState: ReadinessState
    private(set) var controller: ReviewWindowController!
    private(set) var panel: ReviewPanel!
    private(set) var editor: NSTextView!

    init(draft: String) throws {
        recorder = Issue40KeyboardRecorder(draft: draft)
        readinessState = ReadinessState()
        let appKit = ReviewWindowController.ReadinessEnvironment.appKit
        let controller = ReviewWindowController(
            readinessEnvironment: ReviewWindowController.ReadinessEnvironment(
                requestActivation: { false },
                applicationIsActive: { true },
                frontmostApplication: { nil },
                feishuSpeechIsActive: { false },
                panelIsKey: { [readinessState] _ in readinessState.panelIsKey },
                editorLookup: appKit.editorLookup,
                editorAttached: appKit.editorAttached,
                makeFirstResponder: appKit.makeFirstResponder,
                firstResponderIsEditor: appKit.firstResponderIsEditor,
                nowNanoseconds: appKit.nowNanoseconds,
                sleep: appKit.sleep
            )
        )
        self.controller = controller
        controller.renderDraft(
            state: .editable(
                draft: draft,
                isPossiblyIncomplete: false,
                feedback: nil
            ),
            onDraftChange: { [weak recorder] value in
                recorder?.currentDraft = value
            },
            onConfirm: { [weak recorder] _ in
                guard let recorder else { return }
                recorder.confirmedDrafts.append(recorder.currentDraft)
            },
            onDiscard: { [weak recorder] in
                recorder?.discardCount += 1
            }
        )

        guard let panel = NSApp.windows.compactMap({ $0 as? ReviewPanel }).last,
              let contentView = panel.contentView else {
            controller.dismiss()
            throw NSError(
                domain: "Issue40KeyboardProductionSurface",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "real ReviewPanel/editor did not materialize"]
            )
        }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        panel.displayIfNeeded()
        contentView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        guard let editor = editableTextView(in: contentView) else {
            controller.dismiss()
            throw NSError(
                domain: "Issue40KeyboardProductionSurface",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "real ReviewPanel/editor did not materialize"]
            )
        }
        self.editor = editor
        guard panel.makeFirstResponder(editor) else {
            controller.dismiss()
            throw NSError(
                domain: "Issue40KeyboardProductionSurface",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "real editor did not become first responder"]
            )
        }
    }

    func dismiss() {
        controller.dismiss()
    }

    @MainActor
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

@MainActor
final class TranscriptionReviewViewKeyboardTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        super.tearDown()
    }

    func test_editableReview_bareReturnConfirmsCurrentDraftExactlyOnce() throws {
        let surface = try Issue40KeyboardProductionSurface(draft: "  draft with spaces  ")
        defer { surface.dismiss() }
        sendPanelKey(
            to: surface,
            keyCode: 36,
            modifiers: [],
            characters: "\r",
            isARepeat: false
        )

        XCTAssertEqual(
            surface.recorder.confirmedDrafts,
            ["  draft with spaces  "],
            "bare Return must confirm the current untrimmed draft exactly once"
        )
        XCTAssertEqual(surface.recorder.discardCount, 0)
    }

    func test_editableReview_keypadEnterConfirmsCurrentDraftExactlyOnce() throws {
        let surface = try Issue40KeyboardProductionSurface(draft: "  keypad draft  ")
        defer { surface.dismiss() }
        sendPanelKey(
            to: surface,
            keyCode: 76,
            modifiers: [],
            characters: "\r",
            isARepeat: false
        )

        XCTAssertEqual(surface.recorder.confirmedDrafts, ["  keypad draft  "])
    }

    func test_exactUnmodifiedNonrepeatReturnThroughKeyPanelConfirmsExactlyOnce() throws {
        let draft = "PRIVATE_NATIVE_MAIN_RETURN"
        let surface = try Issue40KeyboardProductionSurface(draft: draft)
        defer { surface.dismiss() }
        sendPanelKey(
            to: surface,
            keyCode: 36,
            modifiers: [],
            characters: "\r",
            isARepeat: false
        )

        XCTAssertEqual(surface.recorder.confirmedDrafts, [draft])
    }

    func test_exactUnmodifiedNonrepeatKeypadEnterThroughKeyPanelConfirmsExactlyOnce() throws {
        let draft = "PRIVATE_NATIVE_KEYPAD_ENTER"
        let surface = try Issue40KeyboardProductionSurface(draft: draft)
        defer { surface.dismiss() }
        sendPanelKey(
            to: surface,
            keyCode: 76,
            modifiers: [],
            characters: "\r",
            isARepeat: false
        )

        XCTAssertEqual(surface.recorder.confirmedDrafts, [draft])
    }

    func test_previewReturnRepeatMainAndKeypadNeverCreatesConfirmation() throws {
        for keyCode in [UInt16(36), UInt16(76)] {
            let surface = try Issue40KeyboardProductionSurface(
                draft: "PRIVATE_REPEAT_\(keyCode)"
            )
            defer { surface.dismiss() }

            sendPanelKey(
                to: surface,
                keyCode: keyCode,
                modifiers: [],
                characters: "\r",
                isARepeat: true
            )

            XCTAssertEqual(
                surface.recorder.confirmedDrafts,
                [],
                "repeating Return/Enter must not create controller confirmation"
            )
        }
    }

    func test_previewReturnFromWrongWindowNeverCreatesConfirmation() throws {
        let surface = try Issue40KeyboardProductionSurface(draft: "PRIVATE_WRONG_WINDOW")
        defer { surface.dismiss() }

        sendPanelKey(
            to: surface,
            keyCode: 36,
            modifiers: [],
            characters: "\r",
            isARepeat: false,
            windowNumber: surface.panel.windowNumber + 1
        )

        XCTAssertEqual(
            surface.recorder.confirmedDrafts,
            [],
            "a Return event from another window must not create controller confirmation"
        )
    }

    func test_previewReturnFromNonKeyPanelNeverCreatesConfirmation() throws {
        let surface = try Issue40KeyboardProductionSurface(draft: "PRIVATE_NON_KEY_PANEL")
        defer { surface.dismiss() }
        surface.readinessState.panelIsKey = false

        sendPanelKey(
            to: surface,
            keyCode: 76,
            modifiers: [],
            characters: "\r",
            isARepeat: false
        )

        XCTAssertEqual(
            surface.recorder.confirmedDrafts,
            [],
            "Return in a non-key panel must not create controller confirmation"
        )
    }

    func test_controlReturnAndControlKeypadEnterProduceZeroIntentAndZeroDelivery() throws {
        let cases: [(keyCode: UInt16, label: String)] = [
            (36, "main Control+Return"),
            (76, "keypad Control+Enter")
        ]

        for testCase in cases {
            let draft = "PRIVATE_CONTROL_\(testCase.label)"
            let surface = try Issue40KeyboardProductionSurface(draft: draft)
            defer { surface.dismiss() }
            sendPanelKey(
                to: surface,
                keyCode: testCase.keyCode,
                modifiers: [.control],
                characters: "\r",
                isARepeat: false
            )

            XCTAssertEqual(
                surface.recorder.confirmedDrafts,
                [],
                "\(testCase.label) must not create a controller confirmation intent"
            )
            XCTAssertTrue(
                surface.editor.string.hasPrefix(draft),
                "\(testCase.label) must not replace or discard the current draft"
            )
        }
    }

    func test_editableReview_commandReturnDoesNotCreateConfirmationIntent() throws {
        let surface = try Issue40KeyboardProductionSurface(draft: "command draft")
        defer { surface.dismiss() }
        sendPanelKey(
            to: surface,
            keyCode: 36,
            modifiers: [.command],
            characters: "\r",
            isARepeat: false
        )

        XCTAssertEqual(surface.recorder.confirmedDrafts, [])
    }

    func test_editableReview_mainAndKeypadCommandAndShiftCommandDoNotConfirm() throws {
        let cases: [(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, label: String)] = [
            (36, [.command], "main Command+Return"),
            (36, [.command, .shift], "main Shift+Command+Return"),
            (76, [.command], "keypad Command+Enter"),
            (76, [.command, .shift], "keypad Shift+Command+Enter")
        ]

        for testCase in cases {
            let surface = try Issue40KeyboardProductionSurface(
                draft: "  exact \(testCase.label) draft  "
            )
            defer { surface.dismiss() }
            sendPanelKey(
                to: surface,
                keyCode: testCase.keyCode,
                modifiers: testCase.modifiers,
                characters: "\r",
                isARepeat: false
            )

            XCTAssertEqual(
                surface.recorder.confirmedDrafts,
                [],
                "\(testCase.label) must not create a controller confirmation intent"
            )
        }
    }

    func test_editableReview_mainAndKeypadShiftReturnInsertExactlyOneLFWithoutConfirming() throws {
        let cases: [(keyCode: UInt16, label: String)] = [
            (36, "main Return"),
            (76, "keypad Enter")
        ]

        for testCase in cases {
            let surface = try Issue40KeyboardProductionSurface(draft: "first line")
            defer { surface.dismiss() }
            sendPanelKey(
                to: surface,
                keyCode: testCase.keyCode,
                modifiers: [.shift],
                characters: "\r",
                isARepeat: false
            )

            XCTAssertEqual(
                surface.recorder.confirmedDrafts,
                [],
                "Shift+\(testCase.label) is multiline editing, not confirmation"
            )
            XCTAssertEqual(surface.editor.string, "first line\n", "\(testCase.label) must insert one LF")
            XCTAssertEqual(
                surface.recorder.currentDraft,
                "first line\n",
                "\(testCase.label) must update the real editor binding"
            )
        }
    }

    func test_editableReview_mainAndKeypadOptionAndControlReturnPassThroughWithoutConfirming() throws {
        let cases: [(
            keyCode: UInt16,
            modifiers: NSEvent.ModifierFlags,
            expectedSuffix: String,
            label: String
        )] = [
            (36, [.option], "\n", "main Option+Return"),
            (36, [.control], "\u{2028}", "main Control+Return"),
            (76, [.option], "\n", "keypad Option+Enter"),
            (76, [.control], "\u{2028}", "keypad Control+Enter")
        ]

        for testCase in cases {
            let surface = try Issue40KeyboardProductionSurface(draft: "first line")
            defer { surface.dismiss() }
            sendPanelKey(
                to: surface,
                keyCode: testCase.keyCode,
                modifiers: testCase.modifiers,
                characters: "\r",
                isARepeat: false
            )

            XCTAssertEqual(
                surface.editor.string,
                "first line\(testCase.expectedSuffix)",
                "\(testCase.label) must be passed through to the editor"
            )
            XCTAssertEqual(
                surface.recorder.confirmedDrafts,
                [],
                "\(testCase.label) must never create controller confirmation"
            )
        }
    }

    func test_editableReview_markedTextReturnIsPassedToIMEWithoutConfirming() throws {
        let cases: [(keyCode: UInt16, label: String)] = [
            (36, "main Return"),
            (76, "keypad Enter")
        ]

        for testCase in cases {
            let surface = try Issue40KeyboardProductionSurface(draft: "prefix")
            defer { surface.dismiss() }
            let insertionPoint = surface.editor.string.utf16.count
            surface.editor.setSelectedRange(NSRange(location: insertionPoint, length: 0))
            surface.editor.setMarkedText(
                "拼",
                selectedRange: NSRange(location: 1, length: 0),
                replacementRange: NSRange(location: insertionPoint, length: 0)
            )

            XCTAssertTrue(
                surface.editor.hasMarkedText(),
                "the test must establish a live IME composition"
            )
            sendPanelKey(
                to: surface,
                keyCode: testCase.keyCode,
                modifiers: [],
                characters: "\r",
                isARepeat: false
            )

            XCTAssertEqual(
                surface.recorder.confirmedDrafts,
                [],
                "marked-text \(testCase.label) must not create controller confirmation"
            )
            XCTAssertEqual(
                surface.editor.string,
                "prefix\n",
                "marked-text \(testCase.label) must be processed by NSTextView instead of confirming"
            )
            XCTAssertEqual(surface.recorder.currentDraft, "prefix\n")
        }
    }

    func test_editableReview_editorChangeImmediatelyBeforeReturnConfirmsExactUntrimmedDraft() throws {
        let surface = try Issue40KeyboardProductionSurface(draft: "seed")
        defer { surface.dismiss() }
        let replacementRange = NSRange(location: 0, length: surface.editor.string.utf16.count)
        surface.editor.setSelectedRange(replacementRange)
        surface.editor.insertText("  edited immediately  ", replacementRange: replacementRange)

        XCTAssertEqual(surface.recorder.currentDraft, "  edited immediately  ")
        sendPanelKey(
            to: surface,
            keyCode: 36,
            modifiers: [],
            characters: "\r",
            isARepeat: false
        )

        XCTAssertEqual(surface.recorder.confirmedDrafts, ["  edited immediately  "])
    }

    func test_editableReview_mainAndKeypadWhitespaceReturnNeverConfirm() throws {
        for keyCode in [UInt16(36), UInt16(76)] {
            let surface = try Issue40KeyboardProductionSurface(draft: " \n\t")
            defer { surface.dismiss() }
            sendPanelKey(
                to: surface,
                keyCode: keyCode,
                modifiers: [],
                characters: "\r",
                isARepeat: false
            )

            XCTAssertEqual(surface.recorder.confirmedDrafts, [])
            XCTAssertEqual(surface.recorder.currentDraft, " \n\t")
            XCTAssertEqual(surface.editor.string, " \n\t")
        }
    }

    func test_editableReview_selectionReplacementAndUndoPreserveBinding() throws {
        var currentDraft = "original text"
        let (_, editor) = try makeEditableSurface(
            draft: currentDraft,
            onDraftChange: { currentDraft = $0 },
            onConfirm: {},
            onDiscard: {}
        )
        let selectedRange = NSRange(location: 0, length: "original".utf16.count)
        editor.setSelectedRange(selectedRange)
        XCTAssertEqual(editor.selectedRange(), selectedRange)

        for character in "replacement" {
            sendKey(
                keyCode: 0,
                modifiers: [],
                characters: String(character),
                to: editor,
                in: editor.window!
            )
        }
        XCTAssertEqual(editor.string, "replacement text")
        XCTAssertEqual(currentDraft, "replacement text")
        XCTAssertEqual(
            editor.selectedRange(),
            NSRange(location: "replacement".utf16.count, length: 0)
        )

        let undoManager = try XCTUnwrap(editor.undoManager)
        undoManager.undo()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        XCTAssertEqual(editor.string, "original text")

        undoManager.redo()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        XCTAssertEqual(editor.string, "replacement text")
    }

    func test_editableReview_editorUsesStandardTextAreaAccessibilityRoleAndValue() throws {
        let draft = "accessible draft"
        let (_, editor) = try makeEditableSurface(
            draft: draft,
            onDraftChange: { _ in },
            onConfirm: {},
            onDiscard: {}
        )

        XCTAssertEqual(editor.accessibilityRole(), NSAccessibility.Role.textArea)
        XCTAssertEqual(editor.accessibilityValue(), draft)
    }

    func test_editableReview_escapeInvokesDiscardWithoutConfirming() throws {
        let surface = try Issue40KeyboardProductionSurface(draft: "discard me")
        defer { surface.dismiss() }

        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: surface.panel.windowNumber,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: 53
            )
        )
        XCTAssertTrue(surface.panel.performKeyEquivalent(with: event))

        XCTAssertEqual(surface.recorder.confirmedDrafts, [])
        XCTAssertEqual(surface.recorder.discardCount, 1)
    }

    func test_editableReview_exposesMultilineNativeEditorAndScrollingDocument() throws {
        let longDraft = String(repeating: "long line\n", count: 120)
        let (_, editor) = try makeEditableSurface(
            draft: longDraft,
            onDraftChange: { _ in },
            onConfirm: {},
            onDiscard: {}
        )
        let scrollView = try XCTUnwrap(editor.enclosingScrollView)

        XCTAssertTrue(editor.isEditable)
        XCTAssertTrue(editor.isSelectable)
        XCTAssertTrue(editor.allowsUndo)
        XCTAssertTrue(editor.isVerticallyResizable)
        XCTAssertFalse(editor.isHorizontallyResizable)
        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)

        editor.window?.displayIfNeeded()
        editor.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()

        let usedHeight: CGFloat
        if let textContainer = editor.textContainer,
           let layoutManager = editor.layoutManager {
            usedHeight = layoutManager.usedRect(for: textContainer).height
        } else {
            usedHeight = 0
        }
        XCTAssertGreaterThan(
            usedHeight,
            scrollView.contentView.bounds.height,
            "a long draft must grow the document beyond the visible editor viewport"
        )
        XCTAssertEqual(editor.string, longDraft)
    }

    private func makeEditableSurface(
        draft: String,
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor () -> Void,
        onDiscard: @escaping @MainActor () -> Void,
        size: NSSize = NSSize(width: 520, height: 320)
    ) throws -> (NSWindow, NSTextView) {
        let rootView = TranscriptionReviewView(
            state: .editable(draft: draft, isPossiblyIncomplete: false),
            onDraftChange: onDraftChange,
            onConfirm: onConfirm,
            onDiscard: onDiscard
        )
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        windows.append(window)

        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        let editor = try XCTUnwrap(editableTextView(in: hostingView))
        XCTAssertTrue(window.makeFirstResponder(editor))
        return (window, editor)
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

    private func sendKey(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String,
        to editor: NSTextView,
        in window: NSWindow
    ) {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
        editor.keyDown(with: event!)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }

    @discardableResult
    private func sendPanelKey(
        to surface: Issue40KeyboardProductionSurface,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String,
        isARepeat: Bool,
        windowNumber: Int? = nil
    ) -> Bool {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: windowNumber ?? surface.panel.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isARepeat,
            keyCode: keyCode
        ) else {
            return false
        }
        XCTAssertTrue(surface.panel.makeFirstResponder(surface.editor))
        surface.panel.sendEvent(event)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        return true
    }
}
