import Foundation
import AppKit
import Combine
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "HotKey")

class HotKeyService: ObservableObject {
    static let shared = HotKeyService()
    
    @Published var isFnKeyPressed = false
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var previousFlags: CGEventFlags = []
    
    private init() {}
    
    func startMonitoring() {
        guard eventTap == nil else { return }
        
        let trusted = AXIsProcessTrusted()
        logger.info("Accessibility trusted: \(trusted)")
        
        if !trusted {
            logger.error("Accessibility permission not granted!")
            return
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, userInfo in
                guard let service = Unmanaged<HotKeyService>.fromOpaque(userInfo!).takeUnretainedValue() as HotKeyService? else {
                    return Unmanaged.passUnretained(event)
                }
                return service.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            logger.error("Failed to create event tap")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        logger.info("Started monitoring all keyboard events")
    }
    
    func stopMonitoring() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        logger.info("Stopped monitoring")
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        
        logger.info("Event type: \(type.rawValue), flags: \(flags.rawValue)")
        
        let fnPressed = flags.contains(.maskSecondaryFn)
        let wasFnPressed = self.previousFlags.contains(.maskSecondaryFn)
        
        if fnPressed != wasFnPressed {
            logger.info("Fn key state changed to: \(fnPressed)")
            DispatchQueue.main.async { [weak self] in
                self?.isFnKeyPressed = fnPressed
            }
        }
        
        self.previousFlags = flags
        return Unmanaged.passUnretained(event)
    }
}
