import Foundation
import AppKit
import Combine
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "HotKey")

class HotKeyService: ObservableObject {
    static let shared = HotKeyService()

    @Published private(set) var state: HotKeyState = .idle
    @Published private(set) var isMonitoring = false
    @Published private(set) var monitoringState: MonitoringState = .stopped

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var previousFlags: CGEventFlags = []
    // Guards previousFlags against concurrent access between the tap thread and the main actor.
    private let previousFlagsLock = NSLock()
    private var pendingWorkItem: DispatchWorkItem?
    private var restartRetryCount = 0

    // Issue #9: the event-tap run-loop source must live on a private, long-lived thread
    // — NOT CFRunLoopGetMain(). AVCaptureSession.startRunning() blocks the main actor, so
    // sharing the main run loop would starve/drop Fn events. The thread starts LAZILY when
    // the first monitoring session begins and is torn down (CFRunLoopStop + nil) on
    // stopMonitoring().
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

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
            DispatchQueue.main.async { [weak self] in
                self?.monitoringState = .failed(.accessibilityNotTrusted)
            }
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
            DispatchQueue.main.async { [weak self] in
                self?.monitoringState = .failed(.tapCreationFailed)
            }
            scheduleRestartRetry()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        // Issue #9: add the source to the private tap run loop, never CFRunLoopGetMain().
        let runLoop = ensureTapRunLoop()
        CFRunLoopAddSource(runLoop, runLoopSource, .commonModes)
        // Wake the private run loop so it picks up the freshly added source immediately
        // (it may currently be parked in CFRunLoopRun() waiting for input).
        CFRunLoopWakeUp(runLoop)
        CGEvent.tapEnable(tap: tap, enable: true)

        restartRetryCount = 0
        DispatchQueue.main.async { [weak self] in
            self?.monitoringState = .active
            self?.isMonitoring = true
        }
        logger.info("Started monitoring keyboard events")
    }
    
    private func scheduleRestartRetry() {
        restartRetryCount += 1
        let delay = min(1.0 * pow(2.0, Double(restartRetryCount - 1)), 30.0)
        let currentRetry = restartRetryCount
        logger.info("Scheduling restart retry \(currentRetry) in \(delay)s")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startMonitoring()
        }
    }
    
    /// Lazily spins up the long-lived private tap thread and returns its CFRunLoop.
    /// The thread body parks in CFRunLoopRun(); CFRunLoopStop() (in stopMonitoring())
    /// unwinds it. Blocks the caller until the thread has published its run loop.
    private func ensureTapRunLoop() -> CFRunLoop {
        if let existing = tapRunLoop {
            return existing
        }

        let semaphore = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let runLoop = CFRunLoopGetCurrent()
            self?.tapRunLoop = runLoop
            semaphore.signal()
            // Keep the run loop alive even with no sources by adding a no-op port,
            // so CFRunLoopRun() does not return immediately before the tap source lands.
            let keepAlivePort = Port()
            RunLoop.current.add(keepAlivePort, forMode: .common)
            CFRunLoopRun()
            // Reached only after CFRunLoopStop(); clear the keep-alive port.
            RunLoop.current.remove(keepAlivePort, forMode: .common)
        }
        thread.name = "com.feishuspeech.hotkey.tap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
        // Wait until the thread has published its run loop reference.
        semaphore.wait()
        return tapRunLoop ?? CFRunLoopGetCurrent()
    }

    func stopMonitoring() {
        guard let tap = eventTap else {
            previousFlagsLock.lock(); previousFlags = []; previousFlagsLock.unlock()
            monitoringState = .stopped
            isMonitoring = false
            teardownTapThread()
            return
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource, let runLoop = tapRunLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        cancelPendingTransition()
        state = .idle
        previousFlagsLock.lock(); previousFlags = []; previousFlagsLock.unlock()
        monitoringState = .stopped
        isMonitoring = false
        teardownTapThread()
        logger.info("Stopped monitoring")
    }

    /// Stops the private tap run loop and releases the thread reference so the next
    /// monitoring session starts a fresh thread.
    private func teardownTapThread() {
        if let runLoop = tapRunLoop {
            CFRunLoopStop(runLoop)
        }
        tapRunLoop = nil
        tapThread = nil
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let rawType = type.rawValue
        
        if rawType == CGEventType.tapDisabledByTimeout.rawValue {
            logger.warning("Event tap disabled by timeout, re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            // Issue #9: while the tap was disabled a Fn release may have been missed,
            // leaving the machine stuck in .recording. Resync against live modifier
            // state and fire a synthetic release if Fn is no longer held.
            let live = CGEventSource.flagsState(.combinedSessionState)
            resyncFnState(liveFlags: live)
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
        previousFlagsLock.lock()
        let wasFnPressed = previousFlags.contains(.maskSecondaryFn)
        previousFlagsLock.unlock()

        logger.debug("Flags changed: fnPressed=\(fnPressed), wasFnPressed=\(wasFnPressed)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if fnPressed && !wasFnPressed {
                self.handleFnPressed(flags: flags)
            } else if !fnPressed && wasFnPressed {
                self.handleFnReleased()
            }
        }

        previousFlagsLock.lock()
        previousFlags = flags
        previousFlagsLock.unlock()
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
    
    func handleFnReleased() {
        logger.info("Fn key released, current state: \(String(describing: self.state))")

        switch state {
        case .pending(let startTime):
            let duration = Date().timeIntervalSince(startTime)
            logger.info("Released during pending, duration: \(duration)s")
            transitionToCancelled(reason: .releasedTooSoon(duration: duration))
        case .recording:
            logger.info("Released from recording - transitioning to transcribing")
            state = .transcribing
        case .transcribing, .error, .cancelled, .idle:
            logger.info("Fn released in non-active state \(String(describing: self.state)) - ignoring")
        }
    }

    /// Issue #9: reconcile cached `previousFlags` against a live modifier snapshot.
    /// Runs on the private tap thread (from the tapDisabledByTimeout path). If we
    /// believed Fn was held but the live state says it is up, a release was missed
    /// while the tap was disabled — marshal handleFnReleased() to main. Always update
    /// `previousFlags` to mirror the live snapshot.
    private func resyncFnState(liveFlags: CGEventFlags) {
        let fnNow = liveFlags.contains(.maskSecondaryFn)
        previousFlagsLock.lock()
        let fnWas = previousFlags.contains(.maskSecondaryFn)
        previousFlagsLock.unlock()
        if fnWas && !fnNow {
            logger.warning("Missed Fn release detected during tap-timeout resync")
            DispatchQueue.main.async { [weak self] in self?.handleFnReleased() }
        }
        previousFlagsLock.lock()
        previousFlags = CGEventFlags(rawValue: liveFlags.rawValue)
        previousFlagsLock.unlock()
    }

    #if DEBUG
    /// Test-only helper: directly set state without going through the event tap.
    func forceState(_ newState: HotKeyState) {
        logger.info("forceState called: \(String(describing: newState))")
        state = newState
    }
    #endif

    /// Called by MainViewModel when the max-duration timer fires.
    /// Transitions .recording or .pending → .transcribing so the $state sink
    /// routes through handleTranscribingState() → stopRecordingAndTranscribe().
    func forceTranscribing() {
        logger.info("Force transcribing requested, current state: \(String(describing: self.state))")
        cancelPendingTransition()
        switch state {
        case .recording, .pending:
            state = .transcribing
        default:
            logger.info("forceTranscribing ignored in state \(String(describing: self.state))")
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

    // MARK: - Test-only simulation helpers (issue #5)

    /// Simulates the accessibility-not-trusted failure branch of startMonitoring()
    /// without calling AXIsProcessTrusted() or CGEvent.tapCreate().
    /// This allows unit tests to verify monitoringState transitions without
    /// requiring real system permissions.
    func simulateStartMonitoringWithAccessibilityTrusted(_ trusted: Bool) {
        guard !trusted else {
            // If trusted=true, fall through to the tap-creation step.
            simulateStartMonitoringWithTapCreationResult(true)
            return
        }
        logger.info("TEST HOOK: simulating accessibility-not-trusted failure")
        monitoringState = .failed(.accessibilityNotTrusted)
    }

    /// Simulates the tap-creation step of startMonitoring() with a controllable
    /// result. tapCreated=true simulates success; false simulates tapCreate returning nil.
    func simulateStartMonitoringWithTapCreationResult(_ tapCreated: Bool) {
        if tapCreated {
            logger.info("TEST HOOK: simulating successful tap creation")
            restartRetryCount = 0
            monitoringState = .active
            isMonitoring = true
        } else {
            logger.info("TEST HOOK: simulating tap creation failure")
            monitoringState = .failed(.tapCreationFailed)
        }
    }

    // MARK: - Test-only hooks (issue #9)

    /// Read access to the cached modifier flags, for verifying the stopMonitoring() reset.
    var previousFlagsForTesting: CGEventFlags {
        previousFlagsLock.lock()
        defer { previousFlagsLock.unlock() }
        return previousFlags
    }

    /// Seed `previousFlags` to simulate a believed Fn-down state.
    func setPreviousFlagsForTesting(_ flags: CGEventFlags) {
        previousFlagsLock.lock()
        previousFlags = flags
        previousFlagsLock.unlock()
    }

    /// Read access to the private tap run loop, for verifying it is NOT the main run loop.
    var tapRunLoopForTesting: CFRunLoop? {
        tapRunLoop
    }

    /// Drives the post-timeout Fn resync with an injected live-flags snapshot.
    /// The resync's release marshals to DispatchQueue.main.async; tests run on the main
    /// actor, so this hook runs the body synchronously to keep assertions deterministic.
    func resyncFnStateForTesting(liveFlags: CGEventFlags) {
        let fnNow = liveFlags.contains(.maskSecondaryFn)
        previousFlagsLock.lock()
        let fnWas = previousFlags.contains(.maskSecondaryFn)
        previousFlagsLock.unlock()
        if fnWas && !fnNow {
            handleFnReleased()
        }
        previousFlagsLock.lock()
        previousFlags = CGEventFlags(rawValue: liveFlags.rawValue)
        previousFlagsLock.unlock()
    }
}
