import AppKit
import Combine
import SwiftUI

import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "OverlayWindowController")

@MainActor
protocol RecordingOverlayPresenting: AnyObject {
    func show(status: RecordingState)
    func update(status: RecordingState)
    func hide()
    func presentCompletionFeedback(
        _ feedback: RecordingState,
        minimumVisibleDuration: TimeInterval
    )
}

@MainActor
final class OverlayWindowController: ObservableObject, RecordingOverlayPresenting {
    static let shared = OverlayWindowController()

    private var window: NSPanel?
    private var hostingView: NSHostingView<RecordingOverlayView>?
    private var cancellables = Set<AnyCancellable>()
    private var generation: UInt64 = 0
    private var completionFeedbackTask: Task<Void, Never>?

    private let windowSize = NSSize(width: 280, height: 100)

    private init() {}

    func show() {
        show(status: .recording)
    }

    func show(status: RecordingState) {
        let presentationGeneration = beginPresentation()
        logger.debug("show — generation \(presentationGeneration)")
        ensureWindow(status: status)
        update(status: status)

        guard let window = window else { return }

        let targetFrame = centeredFrame(size: windowSize)
        let startFrame = targetFrame.offsetBy(dx: 0, dy: -20)

        window.setFrame(startFrame, display: true)
        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(targetFrame, display: true)
            window.animator().alphaValue = 1
        }
    }

    func update(status: RecordingState) {
        hostingView?.rootView = RecordingOverlayView(status: status)
    }

    func hide() {
        let hideGeneration = beginPresentation()
        animateHide(generation: hideGeneration)
    }

    func presentCompletionFeedback(
        _ feedback: RecordingState,
        minimumVisibleDuration: TimeInterval
    ) {
        let boundedDuration = min(max(minimumVisibleDuration, 1.0), 5.0)
        let feedbackGeneration = beginPresentation()
        logger.debug("completion feedback — generation \(feedbackGeneration)")
        ensureWindow(status: feedback)
        update(status: feedback)

        guard let window else { return }
        window.setFrame(centeredFrame(size: windowSize), display: true)
        window.alphaValue = 1
        window.orderFrontRegardless()

        completionFeedbackTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(boundedDuration * 1_000_000_000)
                )
            } catch {
                return
            }
            guard let self, self.generation == feedbackGeneration else { return }
            self.completionFeedbackTask = nil
            self.animateHide(generation: feedbackGeneration)
        }
    }

    private func beginPresentation() -> UInt64 {
        completionFeedbackTask?.cancel()
        completionFeedbackTask = nil
        generation &+= 1
        return generation
    }

    private func animateHide(generation capturedGeneration: UInt64) {
        guard let window else { return }

        logger.debug("hide — capturedGeneration \(capturedGeneration)")
        let targetFrame = window.frame.offsetBy(dx: 0, dy: 20)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(targetFrame, display: true)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.generation == capturedGeneration else {
                    logger.debug("hide completion skipped — generation advanced to \(self.generation)")
                    return
                }
                window.orderOut(nil)
            }
        }
    }
    
    private func ensureWindow(status: RecordingState) {
        guard window == nil else { return }
        
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        
        let hostingView = NSHostingView(rootView: RecordingOverlayView(status: status))
        hostingView.frame = NSRect(origin: .zero, size: windowSize)
        panel.contentView = hostingView
        
        self.hostingView = hostingView
        self.window = panel
    }
    
    private func centeredFrame(size: NSSize) -> NSRect {
        let screen = getActiveScreen()
        let screenFrame = screen.frame
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2 + screenFrame.height * 0.1
        )
        
        return NSRect(origin: origin, size: size)
    }
    
    private func getActiveScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        
        for screen in NSScreen.screens where screen.frame.contains(mouseLocation) {
            return screen
        }
        
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }
}
