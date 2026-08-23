import AppKit
import SwiftUI

import os.log

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "ReviewWindowController"
)

@MainActor
final class ReviewPanel: NSPanel {
    var allowsKeyInteraction = false

    override var canBecomeKey: Bool {
        allowsKeyInteraction
    }

    override var canBecomeMain: Bool {
        allowsKeyInteraction
    }
}

@MainActor
final class ReviewWindowController: NSObject, NSWindowDelegate, ReviewSurfacePresenting {
    struct ReadinessEnvironment {
        let requestActivation: @MainActor () -> Bool
        let applicationIsActive: @MainActor () -> Bool
        let panelIsKey: @MainActor (ReviewPanel) -> Bool
        let editorLookup: @MainActor (NSView?) -> NSTextView?
        let editorAttached: @MainActor (NSTextView, ReviewPanel) -> Bool
        let makeFirstResponder: @MainActor (ReviewPanel, NSTextView) -> Bool
        let firstResponderIsEditor: @MainActor (ReviewPanel, NSTextView) -> Bool
        let nowNanoseconds: @Sendable () -> UInt64
        let sleep: @Sendable (UInt64) async throws -> Void

        static var appKit: ReadinessEnvironment {
            ReadinessEnvironment(
                requestActivation: {
                    NSRunningApplication.current.activate(options: [])
                },
                applicationIsActive: {
                    NSApp.isActive
                },
                panelIsKey: { panel in
                    panel.isKeyWindow
                },
                editorLookup: { view in
                    ReviewWindowController.editableTextView(in: view)
                },
                editorAttached: { editor, panel in
                    editor.window === panel
                },
                makeFirstResponder: { panel, editor in
                    panel.makeFirstResponder(editor)
                },
                firstResponderIsEditor: { panel, editor in
                    panel.firstResponder === editor
                },
                nowNanoseconds: {
                    DispatchTime.now().uptimeNanoseconds
                },
                sleep: { nanoseconds in
                    try await Task.sleep(nanoseconds: nanoseconds)
                }
            )
        }
    }

    static let shared = ReviewWindowController()

    private let initialWindowSize = NSSize(width: 520, height: 320)
    private let minimumWindowSize = NSSize(width: 420, height: 240)
    private let maximumWindowSize = NSSize(width: 760, height: 600)
    private static let presentationFocusTimeoutNanoseconds: UInt64 = 2_000_000_000
    private static let presentationFocusPollNanoseconds: UInt64 = 20_000_000
    private let readinessEnvironment: ReadinessEnvironment

    private var panel: ReviewPanel?
    private var hostingView: NSHostingView<TranscriptionReviewView>?
    private var onDraftChange: (@MainActor (String) -> Void)?
    private var onConfirm: (@MainActor (ReviewConfirmationIntent) -> Void)?
    private var onDiscard: (@MainActor () -> Void)?
    private var isDraftSurfaceActive = false
    private var isConfirming = false
    private var presentationFocusID: UUID?
    private var presentationFocusAttemptOrdinal: UInt64 = 0
    private var currentPresentationFocusRequest: ReviewPresentationFocusRequest?

    init(readinessEnvironment: ReadinessEnvironment? = nil) {
        self.readinessEnvironment = readinessEnvironment ?? .appKit
        super.init()
    }

    func renderReadOnly(phase: ReviewReadOnlyPhase, preview: String) {
        guard !isDraftSurfaceActive else { return }

        onDraftChange = nil
        onConfirm = nil
        onDiscard = nil

        let panel = ensurePanel()
        let rootView: TranscriptionReviewView
        switch phase {
        case .streaming:
            rootView = TranscriptionReviewView(
                state: .streaming(preview: preview)
            )
        case .sealing:
            rootView = TranscriptionReviewView(
                state: .sealing(preview: preview)
            )
        case .recovery:
            rootView = TranscriptionReviewView(
                state: .sealing(preview: preview),
                readOnlyRecovery: true
            )
        }

        install(rootView, on: panel)

        panel.allowsKeyInteraction = false
        panel.ignoresMouseEvents = true
        setClosable(false, on: panel)
        panel.orderFrontRegardless()
        logger.debug("review read-only surface rendered")
    }

    private func ensurePanel() -> ReviewPanel {
        if let panel {
            return panel
        }

        let panel = ReviewPanel(
            contentRect: NSRect(origin: .zero, size: initialWindowSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.title = "输入前预览"
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = false
        panel.minSize = minimumWindowSize
        panel.maxSize = maximumWindowSize
        panel.setFrame(centeredFrame(for: initialWindowSize), display: false)
        panel.center()
        panel.setFrame(centeredFrame(for: initialWindowSize), display: false)

        self.panel = panel
        install(TranscriptionReviewView(state: .idle), on: panel)
        setClosable(false, on: panel)
        return panel
    }

    private func install(
        _ rootView: TranscriptionReviewView,
        on panel: ReviewPanel? = nil
    ) {
        let targetPanel = panel ?? self.panel
        guard let targetPanel else { return }

        if let hostingView {
            hostingView.rootView = rootView
            return
        }

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: targetPanel.contentRect(forFrameRect: targetPanel.frame).size)
        hostingView.autoresizingMask = [.width, .height]
        targetPanel.contentView = hostingView
        self.hostingView = hostingView
    }

    private func setClosable(_ closable: Bool, on panel: ReviewPanel) {
        panel.standardWindowButton(.closeButton)?.isHidden = !closable
    }

    private func centeredFrame(for size: NSSize) -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        } ?? NSScreen.main

        guard let screen else {
            return NSRect(origin: .zero, size: size)
        }

        let visibleFrame = screen.visibleFrame
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    func renderDraft(
        state: TranscriptionReviewState,
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor (ReviewConfirmationIntent) -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) {
        switch state {
        case .editable, .confirming:
            break
        case .idle, .streaming, .sealing:
            logger.error("invalid review draft state supplied to presenter")
            return
        }

        cancelPresentationFocus()
        if case .confirming = state {
            isConfirming = true
        } else {
            isConfirming = false
        }
        let panel = ensurePanel()
        self.onDraftChange = onDraftChange
        self.onConfirm = onConfirm
        self.onDiscard = onDiscard
        install(
            TranscriptionReviewView(
                state: state,
                onDraftChange: onDraftChange,
                onConfirm: onConfirm,
                onDiscard: onDiscard
            ),
            on: panel
        )

        isDraftSurfaceActive = true
        panel.allowsKeyInteraction = true
        panel.ignoresMouseEvents = false
        setClosable(true, on: panel)
        panel.orderFrontRegardless()
    }

    func requestPresentationFocus(
        _ request: ReviewPresentationFocusRequest
    ) async -> ReviewPresentationFocusOutcome {
        guard !Task.isCancelled else {
            return ReviewPresentationFocusOutcome(
                request: request,
                result: .notFocused(.cancelled(lastUnmet: nil))
            )
        }
        guard isDraftSurfaceActive,
              let panel,
              panel.contentView != nil else {
            return ReviewPresentationFocusOutcome(
                request: request,
                result: .notFocused(.surfaceInvalidated)
            )
        }

        cancelPresentationFocus()
        let focusID = UUID()
        presentationFocusID = focusID
        currentPresentationFocusRequest = request
        presentationFocusAttemptOrdinal &+= 1
        let attempt = presentationFocusAttemptOrdinal
        let attemptStart = readinessEnvironment.nowNanoseconds()
        logPresentationFocus(
            event: "review_presentation_focus_started",
            attempt: attempt,
            result: "started",
            predicate: nil,
            startNanoseconds: attemptStart
        )

        if !readinessEnvironment.requestActivation() {
            logPresentationFocus(
                event: "review_presentation_focus_activation_advisory_rejected",
                attempt: attempt,
                result: "activationAdvisoryRejected",
                predicate: .activationRequest,
                startNanoseconds: attemptStart
            )
        }

        materializeEditableSurface(on: panel)
        let result = await waitForPresentationFocus(
            on: panel,
            focusID: focusID,
            request: request,
            attempt: attempt,
            startNanoseconds: attemptStart
        )
        guard presentationFocusID == focusID,
              isCurrentPresentationFocusRequest(request) else {
            return ReviewPresentationFocusOutcome(
                request: request,
                result: .notFocused(.surfaceInvalidated)
            )
        }
        clearPresentationFocus()
        return ReviewPresentationFocusOutcome(request: request, result: result)
    }

    private func materializeEditableSurface(on panel: ReviewPanel) {
        panel.makeKeyAndOrderFront(nil)
        panel.displayIfNeeded()
        panel.contentView?.layoutSubtreeIfNeeded()
        hostingView?.layoutSubtreeIfNeeded()
    }

    private func waitForPresentationFocus(
        on panel: ReviewPanel,
        focusID: UUID,
        request: ReviewPresentationFocusRequest,
        attempt: UInt64,
        startNanoseconds: UInt64
    ) async -> ReviewPresentationFocusResult {
        var lastUnmet: ReviewPresentationFocusPredicate?
        while true {
            guard presentationFocusID == focusID,
                  isCurrentPresentationFocusRequest(request),
                  isDraftSurfaceActive,
                  let currentPanel = self.panel,
                  currentPanel === panel else {
                return .notFocused(.surfaceInvalidated)
            }

            if Task.isCancelled {
                logPresentationFocus(
                    event: "review_presentation_focus_cancelled",
                    attempt: attempt,
                    result: "cancelled",
                    predicate: lastUnmet,
                    startNanoseconds: startNanoseconds
                )
                return .notFocused(.cancelled(lastUnmet: lastUnmet))
            }

            materializeEditableSurface(on: panel)
            if let unmet = firstUnmetReadinessPredicate(on: panel) {
                lastUnmet = unmet
            } else {
                logPresentationFocus(
                    event: "review_presentation_focus_focused",
                    attempt: attempt,
                    result: "ready",
                    predicate: nil,
                    startNanoseconds: startNanoseconds
                )
                return .focused
            }

            let now = readinessEnvironment.nowNanoseconds()
            let elapsedNanoseconds = now >= startNanoseconds
                ? now - startNanoseconds
                : Self.presentationFocusTimeoutNanoseconds
            guard elapsedNanoseconds < Self.presentationFocusTimeoutNanoseconds else {
                logPresentationFocus(
                    event: "review_presentation_focus_not_focused",
                    attempt: attempt,
                    result: "timedOut",
                    predicate: lastUnmet,
                    startNanoseconds: startNanoseconds
                )
                return .notFocused(
                    .timedOut(lastUnmet: lastUnmet ?? .activationRequest)
                )
            }
            let remainingNanoseconds = Self.presentationFocusTimeoutNanoseconds - elapsedNanoseconds
            do {
                try await readinessEnvironment.sleep(
                    min(
                        Self.presentationFocusPollNanoseconds,
                        remainingNanoseconds
                    )
                )
            } catch {
                logPresentationFocus(
                    event: "review_presentation_focus_cancelled",
                    attempt: attempt,
                    result: "cancelled",
                    predicate: lastUnmet,
                    startNanoseconds: startNanoseconds
                )
                return .notFocused(.cancelled(lastUnmet: lastUnmet))
            }
        }
    }

    private func firstUnmetReadinessPredicate(
        on panel: ReviewPanel
    ) -> ReviewPresentationFocusPredicate? {
        guard readinessEnvironment.applicationIsActive() else {
            return .applicationActive
        }
        guard readinessEnvironment.panelIsKey(panel) else {
            return .panelKey
        }
        guard let editor = readinessEnvironment.editorLookup(hostingView) else {
            return .editorMaterialized
        }
        guard readinessEnvironment.editorAttached(editor, panel) else {
            return .editorAttachedToPanel
        }
        guard readinessEnvironment.makeFirstResponder(panel, editor),
              readinessEnvironment.firstResponderIsEditor(panel, editor) else {
            return .editorFirstResponder
        }
        return nil
    }

    private func logPresentationFocus(
        event: String,
        attempt: UInt64,
        result: String,
        predicate: ReviewPresentationFocusPredicate?,
        startNanoseconds: UInt64
    ) {
        let now = readinessEnvironment.nowNanoseconds()
        let elapsedMilliseconds = now >= startNanoseconds
            ? (now - startNanoseconds) / 1_000_000
            : 0
        let predicateName = predicate?.rawValue ?? "none"
        logger.info(
            "\(event, privacy: .public) attempt=\(attempt, privacy: .public) result=\(result, privacy: .public) predicate=\(predicateName, privacy: .public) elapsedMs=\(elapsedMilliseconds, privacy: .public)"
        )
    }

    private func cancelPresentationFocus() {
        clearPresentationFocus()
    }

    private func clearPresentationFocus() {
        presentationFocusID = nil
        currentPresentationFocusRequest = nil
    }

    private func isCurrentPresentationFocusRequest(
        _ request: ReviewPresentationFocusRequest
    ) -> Bool {
        guard let current = currentPresentationFocusRequest else { return false }
        return current.reviewID == request.reviewID
            && current.generation == request.generation
            && current.focusAttemptID == request.focusAttemptID
    }

    func dismiss() {
        cancelPresentationFocus()
        isDraftSurfaceActive = false
        isConfirming = false
        onDraftChange = nil
        onConfirm = nil
        onDiscard = nil

        guard let panel else {
            hostingView = nil
            return
        }

        panel.resignKey()
        panel.allowsKeyInteraction = false
        panel.ignoresMouseEvents = true
        setClosable(false, on: panel)
        panel.orderOut(nil)
        panel.contentView = nil
        hostingView = nil
        logger.debug("review surface dismissed")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isDraftSurfaceActive else { return false }
        guard !isConfirming else { return false }

        if let onDiscard {
            onDiscard()
        } else {
            dismiss()
        }
        return true
    }

    private static func editableTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView, textView.isEditable {
            return textView
        }

        for subview in view.subviews.reversed() {
            if let textView = Self.editableTextView(in: subview) {
                return textView
            }
        }
        return nil
    }
}

@MainActor
protocol ReviewSurfacePresenting: AnyObject {
    func renderReadOnly(phase: ReviewReadOnlyPhase, preview: String)

    func renderDraft(
        state: TranscriptionReviewState,
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor (ReviewConfirmationIntent) -> Void,
        onDiscard: @escaping @MainActor () -> Void
    )

    func requestPresentationFocus(
        _ request: ReviewPresentationFocusRequest
    ) async -> ReviewPresentationFocusOutcome

    func dismiss()
}
