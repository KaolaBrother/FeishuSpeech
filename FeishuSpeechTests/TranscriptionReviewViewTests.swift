import Foundation
import os.log
import XCTest

@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "TranscriptionReviewViewTests"
)

final class TranscriptionReviewViewTests: XCTestCase {
    func test_reviewView_isMultilineAndRegistersOnlyExplicitConfirmAndCancelShortcuts() throws {
        logger.debug("checking review window shortcut policy")
        let source = try productionSource(relativePath: "FeishuSpeech/Views/TranscriptionReviewView.swift")

        XCTAssertTrue(source.contains("TextEditor"), "review must remain a multiline editable surface")
        XCTAssertTrue(
            source.contains("keyboardShortcut(.return, modifiers: .command)"),
            "Command+Return is the explicit confirmation shortcut"
        )
        XCTAssertTrue(
            source.contains("keyboardShortcut(.cancelAction)"),
            "Escape/cancelAction must discard the unresolved review"
        )
        XCTAssertFalse(
            source.contains("keyboardShortcut(.return)"),
            "bare Return must remain ordinary multiline editing"
        )
        XCTAssertFalse(
            source.contains("keyboardShortcut(.enter)"),
            "the editor must not intercept bare Enter as confirmation"
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
        XCTAssertTrue(source.contains("renderEditable"))

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
        if let readOnlyStart = source.range(of: "renderReadOnly"),
           let editableStart = source.range(of: "renderEditable"),
           readOnlyStart.lowerBound < editableStart.lowerBound {
            let readOnlyBody = source[readOnlyStart.lowerBound ..< editableStart.lowerBound]
            XCTAssertFalse(
                readOnlyBody.contains("activate("),
                "read-only rendering must never activate FeishuSpeech"
            )
            XCTAssertTrue(readOnlyBody.contains("orderFrontRegardless()"))
        }
        if let editableStart = source.range(of: "renderEditable") {
            XCTAssertFalse(
                source[editableStart.lowerBound...].contains("ReviewPanel("),
                "editable transition must not allocate a second panel"
            )
        }
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
}
