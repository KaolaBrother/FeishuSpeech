import AppKit
import SwiftUI
import Combine

@MainActor
final class OverlayWindowController: ObservableObject {
    static let shared = OverlayWindowController()
    
    private var window: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    
    private let windowSize = NSSize(width: 280, height: 100)
    
    private init() {}
    
    func show() {
        ensureWindow()
        
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
    
    func hide() {
        guard let window = window else { return }
        
        let targetFrame = window.frame.offsetBy(dx: 0, dy: 20)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(targetFrame, display: true)
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
        }
    }
    
    private func ensureWindow() {
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
        
        let hostingView = NSHostingView(rootView: RecordingOverlayView())
        hostingView.frame = NSRect(origin: .zero, size: windowSize)
        panel.contentView = hostingView
        
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
        
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                return screen
            }
        }
        
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }
}
