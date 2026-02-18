import Foundation
import AppKit
import Combine
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "HotKey")

class HotKeyService: ObservableObject {
    static let shared = HotKeyService()
    
    @Published private(set) var state: HotKeyState = .idle
    @Published private(set) var isMonitoring = false
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var previousFlags: CGEventFlags = []
    private var pendingWorkItem: DispatchWorkItem?
    private var restartRetryCount = 0
    private let maxRestartRetries = 3
    private var restartRetryDelay: TimeInterval = 1.0
    
    let delayInterval: TimeInterval = 0.3
    
    private let unwantedModifiers: CGEventFlags = [
        .maskCommand,
        .maskAlternate,
        .maskControl,
        .maskShift
    ]
    
    private init() {}
    
    var isFnKeyPressed: Bool {
        state.isActive
    }
    
    func startMonitoring() {
        guard eventTap == nil else { return }
        
        let trusted = AXIsProcessTrusted()
        logger.info("Accessibility trusted: \(trusted)")
        
        if !trusted {
            logger.error("Accessibility permission not granted!")
            scheduleRestartRetry()
            return
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << CGEventType.tapDisabledByTimeout.rawValue) |
                        (1 << CGEventType.tapDisabledByUserInput.rawValue)
        
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
            scheduleRestartRetry()
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        restartRetryCount = 0
        isMonitoring = true
        logger.info("Started monitoring keyboard events")
    }
    
    private func scheduleRestartRetry() {
        guard restartRetryCount < maxRestartRetries else {
            logger.error("Max restart retries reached, giving up")
            return
        }
        
        restartRetryCount += 1
        let delay = restartRetryDelay * Double(restartRetryCount)
        let currentRetry = restartRetryCount
        let maxRetries = maxRestartRetries
        logger.info("Scheduling restart retry \(currentRetry)/\(maxRetries) in \(delay)s")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startMonitoring()
        }
    }
    
    func stopMonitoring() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        cancelPendingTransition()
        state = .idle
        isMonitoring = false
        logger.info("Stopped monitoring")
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let rawType = type.rawValue
        
        if rawType == CGEventType.tapDisabledByTimeout.rawValue {
            logger.warning("Event tap disabled by timeout, re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
        }
        
        if rawType == CGEventType.tapDisabledByUserInput.rawValue {
            logger.warning("Event tap disabled by user input, attempting restart")
            DispatchQueue.main.async { [weak self] in
                self?.handleTapDisabled()
            }
            return nil
        }
        
        switch type {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .keyDown:
            handleKeyDown(event)
        default:
            break
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func handleTapDisabled() {
        stopMonitoring()
        state = .cancelled(reason: .eventTapDisabled)
        resetToIdleAfterDelay()
        
        restartRetryCount = 0
        startMonitoring()
    }
    
    private func handleFlagsChanged(_ event: CGEvent) {
        let flags = event.flags
        let fnPressed = flags.contains(.maskSecondaryFn)
        let wasFnPressed = previousFlags.contains(.maskSecondaryFn)
        
        logger.debug("Flags changed: fnPressed=\(fnPressed), wasFnPressed=\(wasFnPressed)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if fnPressed && !wasFnPressed {
                self.handleFnPressed(flags: flags)
            } else if !fnPressed && wasFnPressed {
                self.handleFnReleased()
            }
        }
        
        previousFlags = flags
    }
    
    private func handleFnPressed(flags: CGEventFlags) {
        logger.info("Fn key pressed, current state: \(String(describing: self.state))")
        
        if !flags.intersection(unwantedModifiers).isEmpty {
            logger.info("Modifier key detected, ignoring Fn press")
            return
        }
        
        switch state {
        case .idle:
            transitionToPending()
        case .cancelled, .error:
            state = .idle
            transitionToPending()
        default:
            break
        }
    }
    
    private func handleFnReleased() {
        logger.info("Fn key released, current state: \(String(describing: self.state))")
        
        switch state {
        case .pending(let startTime):
            let duration = Date().timeIntervalSince(startTime)
            logger.info("Released during pending, duration: \(duration)s")
            transitionToCancelled(reason: .releasedTooSoon(duration: duration))
            
        case .recording:
            logger.info("Released from recording state - stopping and transcribing")
            state = .transcribing
            
        default:
            state = .idle
        }
    }
    
    private func handleKeyDown(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch self.state {
            case .pending:
                logger.info("Key down detected during pending state: keyCode=\(keyCode)")
                self.transitionToCancelled(reason: .otherKeyPressed(keyCode: UInt32(keyCode)))
            default:
                break
            }
        }
    }
    
    private func transitionToPending() {
        logger.info("Transitioning to pending state")
        cancelPendingTransition()
        
        state = .pending(startTime: Date())
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.transitionToRecording()
        }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delayInterval, execute: workItem)
    }
    
    private func transitionToRecording() {
        guard case .pending = state else {
            logger.info("Not in pending state, skipping recording transition")
            return
        }
        logger.info("Transitioning to recording state (Fn held for \(self.delayInterval)s)")
        state = .recording
    }
    
    private func transitionToCancelled(reason: CancelReason) {
        logger.info("Transitioning to cancelled: \(reason.description)")
        cancelPendingTransition()
        state = .cancelled(reason: reason)
        resetToIdleAfterDelay()
    }
    
    private func cancelPendingTransition() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }
    
    private func resetToIdleAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if case .cancelled = self?.state {
                self?.state = .idle
            }
        }
    }
    
    func resetToIdle() {
        logger.info("Manual reset to idle")
        cancelPendingTransition()
        state = .idle
    }
    
    func setError(_ message: String) {
        logger.error("Setting error state: \(message)")
        cancelPendingTransition()
        state = .error(message)
    }
}
