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
        XCTAssertTrue(
            source.contains("Button(\"发送\")"),
            "the frozen editable review must retain an explicit Send confirmation control"
        )

        let pendingWindow = makeWindow(
            rootView: TranscriptionReviewView(
                state: .editablePending(
                    draft: "PRIVATE_PENDING_DRAFT",
                    isPossiblyIncomplete: false,
                    readiness: .blocked(
                        attempt: 1,
                        failure: .surfaceInvalidated
                    ),
                    feedback: nil
                )
            )
        )
        defer {
            pendingWindow.orderOut(nil)
            pendingWindow.close()
        }
        XCTAssertNil(
            button(titled: "重试编辑", in: pendingWindow.contentView),
            "no review state may render the removed retry-editing control"
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
            onConfirm: {},
            onRetryReadiness: {},
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

        XCTAssertTrue(
            source.contains("keyboardShortcut(.return, modifiers: .command)"),
            "Command+Return is the explicit confirmation shortcut"
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
            "editable transition must make the same panel key-capable"
        )
        XCTAssertTrue(
            source.contains("activate(options: [])"),
            "editable transition must explicitly activate FeishuSpeech"
        )
        XCTAssertTrue(source.contains("renderReadOnly"))
        XCTAssertTrue(
            source.contains("renderDraft("),
            "the canonical surface owns editable/pending/confirming draft states"
        )
        XCTAssertTrue(
            source.contains("requestEditableReadiness()"),
            "editable authority must be granted through the typed readiness seam"
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
        XCTAssertFalse(
            source.contains(".nonactivatingPanel"),
            "authority mode must not depend on a runtime nonactivatingPanel style flip"
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
        if let button = view as? NSButton, button.title == title {
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
        var currentDraft = "  draft with spaces  "
        var confirmedDrafts: [String] = []
        var discardCount = 0
        let (window, editor) = try makeEditableSurface(
            draft: currentDraft,
            onDraftChange: { currentDraft = $0 },
            onConfirm: { confirmedDrafts.append(currentDraft) },
            onDiscard: { discardCount += 1 }
        )

        sendKey(
            keyCode: 36,
            modifiers: [],
            characters: "\r",
            to: editor,
            in: window
        )

        XCTAssertEqual(
            confirmedDrafts,
            ["  draft with spaces  "],
            "bare Return must confirm the current untrimmed draft exactly once"
        )
        XCTAssertEqual(discardCount, 0)
    }

    func test_editableReview_keypadEnterConfirmsCurrentDraftExactlyOnce() throws {
        var currentDraft = "  keypad draft  "
        var confirmedDrafts: [String] = []
        let (window, editor) = try makeEditableSurface(
            draft: currentDraft,
            onDraftChange: { currentDraft = $0 },
            onConfirm: { confirmedDrafts.append(currentDraft) },
            onDiscard: {}
        )

        sendKey(
            keyCode: 76,
            modifiers: [],
            characters: "\r",
            to: editor,
            in: window
        )

        XCTAssertEqual(confirmedDrafts, ["  keypad draft  "])
    }

    func test_editableReview_commandReturnConfirmsExactlyOnce() throws {
        var currentDraft = "command draft"
        var confirmedDrafts: [String] = []
        let (window, editor) = try makeEditableSurface(
            draft: currentDraft,
            onDraftChange: { currentDraft = $0 },
            onConfirm: { confirmedDrafts.append(currentDraft) },
            onDiscard: {}
        )

        sendKey(
            keyCode: 36,
            modifiers: [.command],
            characters: "\r",
            to: editor,
            in: window
        )

        XCTAssertEqual(confirmedDrafts, ["command draft"])
    }

    func test_editableReview_mainAndKeypadCommandAndShiftCommandConfirmExactlyOnce() throws {
        let cases: [(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, label: String)] = [
            (36, [.command], "main Command+Return"),
            (36, [.command, .shift], "main Shift+Command+Return"),
            (76, [.command], "keypad Command+Enter"),
            (76, [.command, .shift], "keypad Shift+Command+Enter")
        ]

        for testCase in cases {
            var currentDraft = "  exact \(testCase.label) draft  "
            var confirmedDrafts: [String] = []
            let (window, editor) = try makeEditableSurface(
                draft: currentDraft,
                onDraftChange: { currentDraft = $0 },
                onConfirm: { confirmedDrafts.append(currentDraft) },
                onDiscard: {}
            )

            sendKey(
                keyCode: testCase.keyCode,
                modifiers: testCase.modifiers,
                characters: "\r",
                to: editor,
                in: window
            )

            XCTAssertEqual(
                confirmedDrafts,
                ["  exact \(testCase.label) draft  "],
                "\(testCase.label) must confirm exactly once"
            )
        }
    }

    func test_editableReview_mainAndKeypadShiftReturnInsertExactlyOneLFWithoutConfirming() throws {
        let cases: [(keyCode: UInt16, label: String)] = [
            (36, "main Return"),
            (76, "keypad Enter")
        ]

        for testCase in cases {
            var currentDraft = "first line"
            var confirmCount = 0
            let (window, editor) = try makeEditableSurface(
                draft: currentDraft,
                onDraftChange: { currentDraft = $0 },
                onConfirm: { confirmCount += 1 },
                onDiscard: {}
            )

            sendKey(
                keyCode: testCase.keyCode,
                modifiers: [.shift],
                characters: "\r",
                to: editor,
                in: window
            )

            XCTAssertEqual(currentDraft, "first line\n", "\(testCase.label) must insert one LF")
            XCTAssertEqual(editor.string, "first line\n", "\(testCase.label) must grow the document by one LF")
            XCTAssertEqual(confirmCount, 0, "Shift+\(testCase.label) is multiline editing, not confirmation")
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
            var currentDraft = "first line"
            var confirmCount = 0
            let (window, editor) = try makeEditableSurface(
                draft: currentDraft,
                onDraftChange: { currentDraft = $0 },
                onConfirm: { confirmCount += 1 },
                onDiscard: {}
            )

            sendKey(
                keyCode: testCase.keyCode,
                modifiers: testCase.modifiers,
                characters: "\r",
                to: editor,
                in: window
            )

            XCTAssertEqual(
                currentDraft,
                "first line\(testCase.expectedSuffix)",
                "\(testCase.label) must be passed through to the editor"
            )
            XCTAssertEqual(confirmCount, 0, "\(testCase.label) must never confirm")
        }
    }

    func test_editableReview_markedTextReturnIsPassedToIMEWithoutConfirming() throws {
        let cases: [(keyCode: UInt16, label: String)] = [
            (36, "main Return"),
            (76, "keypad Enter")
        ]

        for testCase in cases {
            var currentDraft = "prefix"
            var confirmCount = 0
            let (window, editor) = try makeEditableSurface(
                draft: currentDraft,
                onDraftChange: { currentDraft = $0 },
                onConfirm: { confirmCount += 1 },
                onDiscard: {}
            )
            let insertionPoint = editor.string.utf16.count
            editor.setSelectedRange(NSRange(location: insertionPoint, length: 0))
            editor.setMarkedText(
                "拼",
                selectedRange: NSRange(location: 1, length: 0),
                replacementRange: NSRange(location: insertionPoint, length: 0)
            )

            XCTAssertTrue(editor.hasMarkedText(), "the test must establish a live IME composition")
            sendKey(
                keyCode: testCase.keyCode,
                modifiers: [],
                characters: "\r",
                to: editor,
                in: window
            )

            XCTAssertEqual(confirmCount, 0, "marked-text \(testCase.label) must not confirm")
            XCTAssertEqual(
                editor.string,
                "prefix\n",
                "marked-text \(testCase.label) must be processed by NSTextView instead of confirming"
            )
            XCTAssertEqual(currentDraft, "prefix\n")
        }
    }

    func test_editableReview_editorChangeImmediatelyBeforeReturnConfirmsExactUntrimmedDraft() throws {
        var currentDraft = "seed"
        var confirmedDrafts: [String] = []
        let (window, editor) = try makeEditableSurface(
            draft: currentDraft,
            onDraftChange: { currentDraft = $0 },
            onConfirm: { confirmedDrafts.append(currentDraft) },
            onDiscard: {}
        )
        let replacementRange = NSRange(location: 0, length: editor.string.utf16.count)
        editor.setSelectedRange(replacementRange)
        editor.insertText("  edited immediately  ", replacementRange: replacementRange)

        XCTAssertEqual(currentDraft, "  edited immediately  ")
        sendKey(
            keyCode: 36,
            modifiers: [],
            characters: "\r",
            to: editor,
            in: window
        )

        XCTAssertEqual(confirmedDrafts, ["  edited immediately  "])
    }

    func test_editableReview_mainAndKeypadWhitespaceReturnNeverConfirm() throws {
        for keyCode in [UInt16(36), UInt16(76)] {
            var currentDraft = " \n\t"
            var confirmCount = 0
            let (window, editor) = try makeEditableSurface(
                draft: currentDraft,
                onDraftChange: { currentDraft = $0 },
                onConfirm: { confirmCount += 1 },
                onDiscard: {}
            )

            sendKey(
                keyCode: keyCode,
                modifiers: [],
                characters: "\r",
                to: editor,
                in: window
            )

            XCTAssertEqual(confirmCount, 0)
            XCTAssertEqual(currentDraft, " \n\t")
            XCTAssertEqual(editor.string, " \n\t")
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
        var confirmCount = 0
        var discardCount = 0
        let (window, _) = try makeEditableSurface(
            draft: "discard me",
            onDraftChange: { _ in },
            onConfirm: { confirmCount += 1 },
            onDiscard: { discardCount += 1 }
        )

        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: 53
            )
        )
        XCTAssertTrue(window.performKeyEquivalent(with: event))

        XCTAssertEqual(confirmCount, 0)
        XCTAssertEqual(discardCount, 1)
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
}
