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
final class ReviewWindowController: NSObject, NSWindowDelegate, ReviewSurfacePresenting,
    ReviewEditableReadinessPresenting {
    static let shared = ReviewWindowController()

    private let initialWindowSize = NSSize(width: 520, height: 320)
    private let minimumWindowSize = NSSize(width: 420, height: 240)
    private let maximumWindowSize = NSSize(width: 760, height: 600)
    private static let editableReadinessTimeoutNanoseconds: UInt64 = 2_000_000_000
    private static let editableReadinessPollNanoseconds: UInt64 = 20_000_000

    private var panel: ReviewPanel?
    private var hostingView: NSHostingView<TranscriptionReviewView>?
    private var onDraftChange: (@MainActor (String) -> Void)?
    private var onConfirm: (@MainActor () -> Void)?
    private var onDiscard: (@MainActor () -> Void)?
    private var isEditable = false
    private var editableReadinessTask: Task<ReviewEditableTransitionResult, Never>?
    private var editableReadinessID: UUID?
    private var editableReadinessObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
    }

    func renderReadOnly(phase: ReviewReadOnlyPhase, preview: String) {
        guard !isEditable else { return }

        onDraftChange = nil
        onConfirm = nil
        onDiscard = nil

        let state: TranscriptionReviewState
        switch phase {
        case .streaming:
            state = .streaming(preview: preview)
        case .sealing:
            state = .sealing(preview: preview)
        }

        let panel = ensurePanel()
        install(TranscriptionReviewView(state: state))

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
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
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
        var styleMask = panel.styleMask
        if closable {
            styleMask.insert(.closable)
        } else {
            styleMask.remove(.closable)
        }
        panel.styleMask = styleMask
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

    func renderEditable(
        draft: String,
        isPossiblyIncomplete: Bool,
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor () -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) -> ReviewEditableTransitionResult {
        guard !isEditable else { return .ready }

        let panel = configureEditableSurface(
            draft: draft,
            isPossiblyIncomplete: isPossiblyIncomplete,
            onDraftChange: onDraftChange,
            onConfirm: onConfirm,
            onDiscard: onDiscard
        )

        guard requestEditableActivation(on: panel) else {
            dismiss()
            return .failed
        }

        guard editableSurfaceIsReady(on: panel) else {
            dismiss()
            return .failed
        }

        logger.debug("review editable surface activated")
        return .ready
    }

    func renderEditableWhenReady(
        draft: String,
        isPossiblyIncomplete: Bool,
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor () -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) async -> ReviewEditableTransitionResult {
        guard !Task.isCancelled else { return .failed }
        guard !isEditable else { return .ready }

        cancelEditableReadiness()
        let panel = configureEditableSurface(
            draft: draft,
            isPossiblyIncomplete: isPossiblyIncomplete,
            onDraftChange: onDraftChange,
            onConfirm: onConfirm,
            onDiscard: onDiscard
        )

        guard requestEditableActivation(on: panel) else {
            dismiss()
            return .failed
        }

        let readinessID = UUID()
        editableReadinessID = readinessID
        installEditableReadinessObservers(on: panel, readinessID: readinessID)
        let readinessTask = Task { @MainActor [weak self] in
            guard let self else { return ReviewEditableTransitionResult.failed }
            return await self.waitForEditableReadiness(
                on: panel,
                readinessID: readinessID
            )
        }
        editableReadinessTask = readinessTask

        let result = await withTaskCancellationHandler {
            await readinessTask.value
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelEditableReadiness()
            }
        }

        guard editableReadinessID == readinessID else {
            return .failed
        }
        clearEditableReadiness()
        guard result == .ready else {
            dismiss()
            return .failed
        }

        logger.debug("review editable surface activated")
        return .ready
    }

    private func configureEditableSurface(
        draft: String,
        isPossiblyIncomplete: Bool,
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor () -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) -> ReviewPanel {
        let panel = ensurePanel()
        self.onDraftChange = onDraftChange
        self.onConfirm = onConfirm
        self.onDiscard = onDiscard
        install(
            TranscriptionReviewView(
                state: .editable(
                    draft: draft,
                    isPossiblyIncomplete: isPossiblyIncomplete
                ),
                onDraftChange: onDraftChange,
                onConfirm: onConfirm,
                onDiscard: onDiscard
            ),
            on: panel
        )

        isEditable = true
        panel.allowsKeyInteraction = true
        panel.ignoresMouseEvents = false
        setClosable(true, on: panel)
        return panel
    }

    private func requestEditableActivation(on panel: ReviewPanel) -> Bool {
        guard NSRunningApplication.current.activate(options: []) else {
            return false
        }
        materializeEditableSurface(on: panel)
        return true
    }

    private func materializeEditableSurface(on panel: ReviewPanel) {
        panel.makeKeyAndOrderFront(nil)
        panel.displayIfNeeded()
        panel.contentView?.layoutSubtreeIfNeeded()
        hostingView?.layoutSubtreeIfNeeded()
    }

    private func editableSurfaceIsReady(on panel: ReviewPanel) -> Bool {
        guard NSApp.isActive, panel.isKeyWindow,
              let editor = editableTextView(in: hostingView),
              editor.window === panel,
              panel.makeFirstResponder(editor),
              panel.firstResponder === editor else {
            return false
        }
        return true
    }

    private func waitForEditableReadiness(
        on panel: ReviewPanel,
        readinessID: UUID
    ) async -> ReviewEditableTransitionResult {
        let startNanoseconds = DispatchTime.now().uptimeNanoseconds
        while !Task.isCancelled {
            guard editableReadinessID == readinessID,
                  isEditable,
                  let currentPanel = self.panel,
                  currentPanel === panel else {
                return .failed
            }

            materializeEditableSurface(on: panel)
            if editableSurfaceIsReady(on: panel) {
                return .ready
            }

            let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startNanoseconds
            guard elapsedNanoseconds < Self.editableReadinessTimeoutNanoseconds else {
                return .failed
            }
            let remainingNanoseconds = Self.editableReadinessTimeoutNanoseconds - elapsedNanoseconds
            do {
                try await Task.sleep(
                    nanoseconds: min(
                        Self.editableReadinessPollNanoseconds,
                        remainingNanoseconds
                    )
                )
            } catch {
                return .failed
            }
        }
        return .failed
    }

    private func installEditableReadinessObservers(
        on panel: ReviewPanel,
        readinessID: UUID
    ) {
        let notificationCenter = NotificationCenter.default
        editableReadinessObservers = [
            notificationCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.probeEditableReadiness(on: panel, readinessID: readinessID)
                }
            },
            notificationCenter.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.probeEditableReadiness(on: panel, readinessID: readinessID)
                }
            }
        ]
    }

    private func probeEditableReadiness(on panel: ReviewPanel, readinessID: UUID) {
        guard editableReadinessID == readinessID,
              isEditable,
              let currentPanel = self.panel,
              currentPanel === panel else {
            return
        }
        materializeEditableSurface(on: panel)
        _ = editableSurfaceIsReady(on: panel)
    }

    private func cancelEditableReadiness() {
        editableReadinessTask?.cancel()
        clearEditableReadiness()
    }

    private func clearEditableReadiness() {
        for observer in editableReadinessObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        editableReadinessObservers.removeAll()
        editableReadinessTask = nil
        editableReadinessID = nil
    }

    func dismiss() {
        cancelEditableReadiness()
        isEditable = false
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
        guard isEditable else { return false }

        isEditable = false
        if let onDiscard {
            onDiscard()
        } else {
            dismiss()
        }
        return true
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

@MainActor
protocol ReviewSurfacePresenting: AnyObject {
    func renderReadOnly(phase: ReviewReadOnlyPhase, preview: String)

    func renderEditable(
        draft: String,
        isPossiblyIncomplete: Bool,
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor () -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) -> ReviewEditableTransitionResult

    func dismiss()
}

@MainActor
protocol ReviewEditableReadinessPresenting: AnyObject {
    func renderEditableWhenReady(
        draft: String,
        isPossiblyIncomplete: Bool,
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor () -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) async -> ReviewEditableTransitionResult
}
