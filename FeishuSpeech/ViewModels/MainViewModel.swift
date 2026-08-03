import AppKit
import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "ViewModel")

let maxRecordingDuration: TimeInterval = 60.0
let errorRecoveryDelay: TimeInterval = 3.0
private let hotKeyMonitoringErrorMessage = "热键不可用，请检查辅助功能权限"
private let completionFeedbackDuration: TimeInterval = 2.0
private let streamingIngressConfiguration = AudioIngressConfiguration(
    packetByteCount: 6_400,
    minimumTailByteCount: 3_200,
    maximumBufferedByteCount: 1_920_000
)

protocol HotKeyWakeRecovering: AnyObject {
    func recoverAfterWake()
}

extension HotKeyService: HotKeyWakeRecovering {}

private enum FinalOnlyDestinationValidation {
    case valid
    case securityRejected
    case destinationInvalid
}

@MainActor
class MainViewModel: ObservableObject {
    @Published var status: RecordingState = .idle
    @Published var settings: AppSettings
    @Published var overlayMessage: String?

    private let hotKeyService = HotKeyService.shared
    private let hotKeyWakeRecovering: HotKeyWakeRecovering
    private let audioRecorder: AudioRecorder
    private let streamingProvider: any SpeechStreamingSessionProviding
    private let accessibilityClient: AccessibilityClient
    private let finalTextOutput: FinalTextOutput
    private let overlayPresenter: RecordingOverlayPresenting
    private let permissionManager = PermissionManager.shared

    private var cancellables = Set<AnyCancellable>()
    var stateCancellable: AnyCancellable?
    private var isMonitoring = false
    private var maxDurationTimer: Timer?
    private var isShowingHotKeyMonitoringError = false

    private var activeSessionIdentity: StreamingSessionIdentity?
    private var activeIngress: ByteBoundedAudioIngress?
    private var activeStreamingSession: (any SpeechStreamingSession)?
    private var cursorSession: CursorTextSession?
    private var finalOnlyDestination: CursorDestinationToken?
    private var usesCurrentFocusFinalOutput = false
    private var deliveredCurrentFocusFinal = false
    private var latestFinalOnlyValue: String?
    private var consumerTask: Task<Void, Never>?
    private var sealingTask: Task<Void, Never>?
    private var sealStarted = false
    private var acceptedPacket = false
    private var stopSoundPlayed = false
    private var isCompletionFeedbackPresented = false

    var statusText: String {
        status.text
    }

    init(
        audioRecorder: AudioRecorder? = nil,
        settings: AppSettings? = nil,
        hotKeyWakeRecovering: HotKeyWakeRecovering? = nil,
        streamingProvider: (any SpeechStreamingSessionProviding)? = nil,
        accessibilityClient: AccessibilityClient? = nil,
        finalTextOutput: FinalTextOutput? = nil,
        overlayPresenter: RecordingOverlayPresenting? = nil
    ) {
        let resolvedAudioRecorder = audioRecorder ?? AudioRecorder()
        self.audioRecorder = resolvedAudioRecorder
        self.settings = settings ?? AppSettings.load()
        self.hotKeyWakeRecovering = hotKeyWakeRecovering ?? HotKeyService.shared
        self.streamingProvider = streamingProvider ?? FeishuAPIService.shared
        self.accessibilityClient = accessibilityClient ?? MacAccessibilityClient()
        self.finalTextOutput = finalTextOutput ?? SystemFinalTextOutput()
        self.overlayPresenter = overlayPresenter ?? OverlayWindowController.shared
        logger.info("MainViewModel init")
        resolvedAudioRecorder.forceCleanup()
        setupAudioRecorderFailureObserver()
        setupPermissionObserver()
        setupErrorRecovery()
    }

    private func setupAudioRecorderFailureObserver() {
        audioRecorder.$failure
            .compactMap { $0 }
            .sink { [weak self] failure in
                self?.handleAudioRecorderFailure(failure)
            }
            .store(in: &cancellables)
    }

    private func setupPermissionObserver() {
        permissionManager.$allPermissionsGranted
            .removeDuplicates()
            .sink { [weak self] granted in
                logger.info("All permissions granted: \(granted)")
                guard let self else { return }
                if granted {
                    self.startHotKeyMonitoring()
                } else {
                    self.stopHotKeyMonitoring()
                    if self.activeSessionIdentity != nil {
                        Task { @MainActor [weak self] in
                            await self?.terminateAbnormally(
                                message: "权限已失效",
                                reportsError: true
                            )
                        }
                    }
                }
            }
            .store(in: &cancellables)

        permissionManager.$secureInputEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard enabled, let self, self.activeSessionIdentity != nil else { return }
                logger.warning("Secure input activated during an active interaction")
                self.invalidateActiveIdentityAndCursor()
                Task { @MainActor [weak self] in
                    await self?.terminateAbnormally(
                        message: "安全输入已启用",
                        reportsError: true
                    )
                }
            }
            .store(in: &cancellables)
    }

    func startHotKeyMonitoring() {
        guard !isMonitoring else { return }
        logger.info("Starting hot key monitoring with state machine")

        stateCancellable = hotKeyService.$state
            .sink { [weak self] state in
                logger.info("HotKey state changed: \(String(describing: state))")
                self?.handleHotKeyState(state)
            }

        hotKeyService.$monitoringState
            .dropFirst()
            .sink { [weak self] monitoringState in
                logger.info("HotKey monitoring state changed: \(String(describing: monitoringState))")
                self?.handleMonitoringState(monitoringState)
            }
            .store(in: &cancellables)

        isMonitoring = true
        hotKeyService.startMonitoring()
    }

    func stopHotKeyMonitoring() {
        stateCancellable = nil
        guard isMonitoring else { return }
        logger.info("Stopping hot key monitoring")
        hotKeyService.stopMonitoring()
        isMonitoring = false
    }

    private func handleHotKeyState(_ state: HotKeyState, startsTranscriptionTask: Bool = true) {
        switch state {
        case .idle:
            if activeSessionIdentity == nil {
                if !isCompletionFeedbackPresented {
                    hideOverlay()
                }
                status = .idle
                stopMaxDurationTimer()
            }
        case .pending:
            break
        case .streaming(let identity):
            beginStreaming(identity: identity)
        case .sealing(let identity):
            beginSealing(identity: identity)
        case .cancelled(let reason):
            logger.info("Interaction cancelled: \(reason.description)")
            Task { @MainActor [weak self] in
                await self?.terminateAbnormally(message: nil, reportsError: false)
            }
        case .error(let message):
            Task { @MainActor [weak self] in
                await self?.terminateAbnormally(message: message, reportsError: true)
            }
        case .recording, .transcribing:
            logger.warning("Ignoring retired whole-file hot-key state")
        }
        _ = startsTranscriptionTask
    }

    #if DEBUG
    func handleHotKeyStateForTesting(
        _ state: HotKeyState,
        startsTranscriptionTask: Bool = true
    ) {
        handleHotKeyState(state, startsTranscriptionTask: startsTranscriptionTask)
    }

    var activeSessionIdentityForTesting: StreamingSessionIdentity? {
        activeSessionIdentity
    }

    func handleStreamingEventForTesting(
        _ event: StreamingRecognitionEvent,
        identity: StreamingSessionIdentity
    ) {
        _ = handleStreamingEvent(event, identity: identity, isTerminal: false)
    }
    #endif

    private func beginStreaming(identity: StreamingSessionIdentity) {
        guard activeSessionIdentity == nil else {
            logger.info("Ignoring streaming start while another generation is active")
            return
        }

        activeSessionIdentity = identity
        isCompletionFeedbackPresented = false
        overlayMessage = nil
        sealStarted = false
        acceptedPacket = false
        stopSoundPlayed = false

        guard !permissionManager.secureInputEnabled else {
            failStartup(identity: identity, message: "安全输入框不支持语音输入")
            return
        }
        guard prepareCursorTarget(identity: identity) else { return }
        guard settings.isConfigured else {
            failStartup(identity: identity, message: "请先配置 App ID 和 Secret")
            return
        }

        showOverlay(status: status)
        let ingress = ByteBoundedAudioIngress(configuration: streamingIngressConfiguration)
        activeIngress = ingress

        guard startStreamingCapture(identity: identity, ingress: ingress) else {
            failStartup(identity: identity, message: "无法启动录音")
            return
        }

        if settings.playSound {
            playSound(named: "start")
        }
        startMaxDurationTimer(identity: identity)

        consumerTask = Task(priority: .userInitiated) { [weak self] in
            await self?.consumeAudio(identity: identity, ingress: ingress)
        }
    }

    private func prepareCursorTarget(identity: StreamingSessionIdentity) -> Bool {
        let newCursorSession = CursorTextSession(
            generation: identity.generation,
            accessibilityClient: accessibilityClient
        )
        cursorSession = newCursorSession

        let capability: CursorCapabilityResult
        do {
            capability = try newCursorSession.begin()
        } catch {
            configureUnboundCursorFallback(cursorSession: newCursorSession)
            return true
        }

        if let rejectionMessage = configureCursorCapability(
            capability,
            cursorSession: newCursorSession
        ) {
            failStartup(identity: identity, message: rejectionMessage)
            return false
        }
        return true
    }

    private func configureCursorCapability(
        _ capability: CursorCapabilityResult,
        cursorSession newCursorSession: CursorTextSession
    ) -> String? {
        switch capability {
        case .rejected(.secureTarget):
            return "安全输入框不支持语音输入"
        case .rejected(.accessibilityUnavailable):
            configureUnboundCursorFallback(cursorSession: newCursorSession)
        case .live:
            if settings.autoInsert {
                status = .streaming
            } else {
                newCursorSession.invalidate()
                cursorSession = nil
                status = .streaming
            }
        case .finalOnly(let token):
            newCursorSession.invalidate()
            cursorSession = nil
            if settings.autoInsert {
                finalOnlyDestination = token
                status = .finalOnly
            } else {
                status = .streaming
            }
        }
        return nil
    }

    private func configureUnboundCursorFallback(cursorSession newCursorSession: CursorTextSession) {
        newCursorSession.invalidate()
        cursorSession = nil
        usesCurrentFocusFinalOutput = settings.autoInsert
        deliveredCurrentFocusFinal = false
        status = .streaming
        logger.info("Accessibility destination unavailable; using current-focus final output")
    }

    private func startStreamingCapture(
        identity: StreamingSessionIdentity,
        ingress: ByteBoundedAudioIngress
    ) -> Bool {
        let configured = audioRecorder.startStreamingRecording(
            ingress: ingress
        ) { [weak self] started in
            guard let self, self.isActive(identity) else { return }
            guard started else {
                Task { @MainActor [weak self] in
                    await self?.terminateAbnormally(message: "无法启动录音", reportsError: true)
                }
                return
            }
            logger.info("Streaming capture started for generation \(identity.generation)")
        }
        return configured
    }

    private func failStartup(identity: StreamingSessionIdentity, message: String) {
        guard isActive(identity) else { return }
        invalidateActiveIdentityAndCursor()
        activeIngress?.fail(.cancelled)
        clearInteractionReferences()
        stopMaxDurationTimer()
        hideOverlay()
        status = .error(message)
        hotKeyService.setError(message)
    }

    private func consumeAudio(
        identity: StreamingSessionIdentity,
        ingress: ByteBoundedAudioIngress
    ) async {
        do {
            let session = try await streamingProvider.makeStreamingSession(
                appId: settings.appId,
                appSecret: settings.appSecret
            )
            guard isActive(identity) else {
                await session.cancel()
                return
            }
            activeStreamingSession = session

            try await consumePackets(from: ingress, with: session, identity: identity)
            guard isActive(identity), !Task.isCancelled else { return }
            await finishConsumedAudio(with: session, identity: identity)
        } catch is CancellationError {
            return
        } catch {
            await handleStreamingFailure(identity: identity)
        }
    }

    private func consumePackets(
        from ingress: ByteBoundedAudioIngress,
        with session: any SpeechStreamingSession,
        identity: StreamingSessionIdentity
    ) async throws {
        for try await packet in ingress.stream {
            guard isActive(identity), !Task.isCancelled else { return }
            let event = try await session.sendAudioPacket(packet)
            guard isActive(identity), !Task.isCancelled else { return }
            acceptedPacket = true
            if handleStreamingEvent(event, identity: identity, isTerminal: false) {
                return
            }
        }
    }

    private func finishConsumedAudio(
        with session: any SpeechStreamingSession,
        identity: StreamingSessionIdentity
    ) async {
        guard sealStarted else {
            await terminateAbnormally(message: "音频流意外结束", reportsError: true)
            return
        }

        guard acceptedPacket else {
            await session.cancel()
            guard isActive(identity), !Task.isCancelled else { return }
            publishCompletionFeedback(.emptyFinalPreservedPartial)
            completeNormally(identity: identity)
            return
        }

        do {
            let event = try await session.finish()
            guard isActive(identity), !Task.isCancelled else { return }
            _ = handleStreamingEvent(event, identity: identity, isTerminal: true)
        } catch {
            await handleStreamingFailure(identity: identity)
        }
    }

    private func handleStreamingFailure(identity: StreamingSessionIdentity) async {
        guard isActive(identity), !Task.isCancelled else { return }
        if let cursorSession {
            try? cursorSession.handle(.failed(.network), generation: identity.generation)
        }
        await terminateAbnormally(message: "流式识别失败", reportsError: true)
    }

    @discardableResult
    private func handleStreamingEvent(
        _ event: StreamingRecognitionEvent,
        identity: StreamingSessionIdentity,
        isTerminal: Bool
    ) -> Bool {
        guard isActive(identity) else { return true }

        switch event {
        case .partial(let text):
            return handlePartial(text, identity: identity)

        case .final(let text):
            return handleFinal(text, identity: identity, isTerminal: isTerminal)

        case .failed:
            return handleTerminalEvent(
                event,
                identity: identity,
                message: "流式识别失败",
                reportsError: true
            )

        case .cancelled:
            return handleTerminalEvent(
                event,
                identity: identity,
                message: nil,
                reportsError: false
            )
        }
    }

    private func handlePartial(
        _ text: String,
        identity: StreamingSessionIdentity
    ) -> Bool {
        latestFinalOnlyValue = text
        guard !isContentless(text), settings.autoInsert else { return false }
        if let cursorSession {
            try? cursorSession.handle(.partial(text), generation: identity.generation)
        }
        return false
    }

    private func handleFinal(
        _ text: String,
        identity: StreamingSessionIdentity,
        isTerminal: Bool
    ) -> Bool {
        latestFinalOnlyValue = text
        let contentless = isContentless(text)
        if settings.autoInsert {
            deliverFinal(text, contentless: contentless, identity: identity)
        }
        if contentless {
            overlayMessage = "未识别到内容"
        }
        guard isTerminal else { return false }
        if contentless {
            publishCompletionFeedback(.emptyFinalPreservedPartial)
        }
        completeNormally(identity: identity)
        return true
    }

    private func deliverFinal(
        _ text: String,
        contentless: Bool,
        identity: StreamingSessionIdentity
    ) {
        if let cursorSession {
            try? cursorSession.handle(
                .final(contentless ? "" : text),
                generation: identity.generation
            )
        } else if let destination = finalOnlyDestination, !contentless {
            routeFinalOnly(text, destination: destination)
        } else if usesCurrentFocusFinalOutput, !contentless {
            routeCurrentFocusFinal(text)
        }
    }

    private func routeCurrentFocusFinal(_ text: String) {
        guard settings.autoInsert,
              !deliveredCurrentFocusFinal,
              !permissionManager.secureInputEnabled,
              !isContentless(text) else {
            return
        }
        guard TextInputSimulator.isSafeForAutomaticPaste(text) else {
            deliveredCurrentFocusFinal = true
            copyForManualRecovery(text)
            return
        }

        deliveredCurrentFocusFinal = true
        switch finalTextOutput.insertAtCurrentFocusOnce(text) {
        case .inserted, .securityRejected:
            break
        case .deliveryFailed, .destinationInvalid:
            copyForManualRecovery(text)
        }
    }

    private func handleTerminalEvent(
        _ event: StreamingRecognitionEvent,
        identity: StreamingSessionIdentity,
        message: String?,
        reportsError: Bool
    ) -> Bool {
        if let cursorSession {
            try? cursorSession.handle(event, generation: identity.generation)
        }
        Task { @MainActor [weak self] in
            await self?.terminateAbnormally(message: message, reportsError: reportsError)
        }
        return true
    }

    private func routeFinalOnly(_ text: String, destination: CursorDestinationToken) {
        guard currentSecurityIsSafe(for: destination) else { return }
        guard settings.autoInsert, !isContentless(text) else { return }
        guard TextInputSimulator.isSafeForAutomaticPaste(text) else {
            copyForManualRecovery(text)
            return
        }

        var validationCount = 0
        var outputPreflight: FinalOnlyDestinationValidation?
        let result = finalTextOutput.insertOnce(
            text,
            destination: destination
        ) { [self] in
            validationCount += 1
            let validation = validateFinalOnlyDestination(destination)
            if validationCount == 1 {
                outputPreflight = validation
            }
            return validation == .valid
        }
        handleFinalTextInsertionResult(
            result,
            text: text,
            outputPreflight: outputPreflight
        )
    }

    private func currentSecurityIsSafe(for destination: CursorDestinationToken) -> Bool {
        do {
            return try accessibilityClient.currentSecurityState(for: destination) == .safe
        } catch {
            return false
        }
    }

    private func validateFinalOnlyDestination(
        _ destination: CursorDestinationToken
    ) -> FinalOnlyDestinationValidation {
        guard currentSecurityIsSafe(for: destination) else {
            return .securityRejected
        }
        guard accessibilityClient.frontmostProcessIdentifier() == destination.processIdentifier else {
            return .destinationInvalid
        }
        do {
            let focusedElement = try accessibilityClient.focusedElement()
            return CFEqual(focusedElement, destination.element) ? .valid : .destinationInvalid
        } catch {
            return .destinationInvalid
        }
    }

    private func handleFinalTextInsertionResult(
        _ result: FinalTextInsertionResult,
        text: String,
        outputPreflight: FinalOnlyDestinationValidation?
    ) {
        guard result != .inserted, outputPreflight != .securityRejected else {
            return
        }
        copyForManualRecovery(text)
    }

    private func copyForManualRecovery(_ text: String) {
        finalTextOutput.copyForManualRecovery(text)
        publishCompletionFeedback(.manualRecoveryCopied)
    }

    private func beginSealing(identity: StreamingSessionIdentity) {
        guard isActive(identity), !sealStarted else { return }
        sealStarted = true
        stopMaxDurationTimer()
        status = .sealing
        overlayPresenter.update(status: .sealing)

        if settings.playSound, !stopSoundPlayed {
            stopSoundPlayed = true
            playSound(named: "stop")
        }

        sealingTask = Task { [weak self] in
            guard let self else { return }
            await self.audioRecorder.stopStreamingRecording(
                streamEstablished: self.activeIngress?.hasEmittedFullPacket == true
            )
        }
    }

    private func completeNormally(identity: StreamingSessionIdentity) {
        guard isActive(identity) else { return }
        let preservesCompletionFeedback = isCompletionFeedbackPresented
        invalidateActiveIdentityAndCursor(preserveCommittedCursorState: true)
        consumerTask = nil
        sealingTask = nil
        activeIngress = nil
        activeStreamingSession = nil
        finalOnlyDestination = nil
        usesCurrentFocusFinalOutput = false
        deliveredCurrentFocusFinal = false
        latestFinalOnlyValue = nil
        sealStarted = false
        acceptedPacket = false
        stopSoundPlayed = false
        stopMaxDurationTimer()
        if !preservesCompletionFeedback {
            hideOverlay()
        }
        status = .idle
        hotKeyService.resetToIdle()
    }

    private func terminateAbnormally(message: String?, reportsError: Bool) async {
        let session = activeStreamingSession
        let task = consumerTask

        invalidateActiveIdentityAndCursor()
        activeIngress?.fail(.cancelled)
        consumerTask = nil
        sealingTask?.cancel()
        sealingTask = nil
        clearInteractionReferences()
        stopMaxDurationTimer()
        hideOverlay()

        task?.cancel()
        audioRecorder.forceCleanup()
        await session?.cancel()

        if reportsError, let message {
            status = .error(message)
            hotKeyService.setError(message)
        } else {
            status = .idle
            hotKeyService.resetToIdle()
        }
    }

    private func invalidateActiveIdentityAndCursor(preserveCommittedCursorState: Bool = false) {
        activeSessionIdentity = nil
        if !preserveCommittedCursorState {
            cursorSession?.invalidate()
        }
        cursorSession = nil
    }

    private func clearInteractionReferences() {
        activeIngress = nil
        activeStreamingSession = nil
        finalOnlyDestination = nil
        usesCurrentFocusFinalOutput = false
        deliveredCurrentFocusFinal = false
        latestFinalOnlyValue = nil
        sealStarted = false
        acceptedPacket = false
        stopSoundPlayed = false
    }

    private func isActive(_ identity: StreamingSessionIdentity) -> Bool {
        activeSessionIdentity == identity
    }

    private func isContentless(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func publishCompletionFeedback(_ feedback: RecordingState) {
        status = feedback
        overlayMessage = feedback.text
        isCompletionFeedbackPresented = true
        overlayPresenter.presentCompletionFeedback(
            feedback,
            minimumVisibleDuration: completionFeedbackDuration
        )
    }

    /// Compatibility helper for tests and callers that still deliver a single
    /// final value. Production hot-key interactions never use whole-file recognition.
    func handleRecognitionResult(_ text: String) {
        guard !isContentless(text) else {
            logger.info("Recognition returned empty result")
            overlayMessage = "未识别到内容"
            status = .emptyFinalPreservedPartial
            return
        }
        overlayMessage = nil
        logger.info("Legacy recognition result retained without an unbound output destination")
    }

    private func handleAudioRecorderFailure(_ failure: RecordingFailure) {
        logger.error("Audio recorder failure: \(failure.localizedDescription)")
        if activeSessionIdentity != nil {
            Task { @MainActor [weak self] in
                await self?.terminateAbnormally(
                    message: failure.localizedDescription,
                    reportsError: true
                )
            }
        } else {
            audioRecorder.forceCleanup()
            stopMaxDurationTimer()
            hideOverlay()
            status = .error(failure.localizedDescription)
            hotKeyService.setError(failure.localizedDescription)
        }
    }

    private func handleMonitoringState(_ monitoringState: MonitoringState) {
        switch monitoringState {
        case .failed:
            logger.error("HotKey tap failed: \(String(describing: monitoringState))")
            isShowingHotKeyMonitoringError = true
            status = .error(hotKeyMonitoringErrorMessage)
        case .active:
            if isShowingHotKeyMonitoringError,
               status == .error(hotKeyMonitoringErrorMessage) {
                status = .idle
            }
            isShowingHotKeyMonitoringError = false
        case .stopped:
            break
        }
    }

    #if DEBUG
    func handleMonitoringStateForTesting(_ monitoringState: MonitoringState) {
        handleMonitoringState(monitoringState)
    }

    func handleMaxDurationReachedForTesting() {
        handleMaxDurationReached()
    }

    func handleTranscriptionErrorForTesting(_ error: Error) async {
        logger.error("Legacy recognition error: \(error.localizedDescription)")
        await terminateAbnormally(message: "识别失败", reportsError: true)
    }
    #endif

    func resetService() async {
        logger.info("Manual service reset requested")
        await terminateAbnormally(message: nil, reportsError: false)
        await FeishuAPIService.shared.resetState()
    }

    func handleSystemWillSleep() async {
        logger.info("Handling system will sleep")
        await terminateAbnormally(message: nil, reportsError: false)
        await FeishuAPIService.shared.resetStateForWake()
    }

    func handleSystemDidWake() async {
        logger.info("Handling system did wake")
        await terminateAbnormally(message: nil, reportsError: false)
        await FeishuAPIService.shared.resetStateForWake()
        hotKeyWakeRecovering.recoverAfterWake()
    }

    private func showOverlay(status: RecordingState) {
        isCompletionFeedbackPresented = false
        overlayPresenter.show(status: status)
    }

    private func hideOverlay() {
        isCompletionFeedbackPresented = false
        overlayPresenter.hide()
    }

    private func startMaxDurationTimer(identity: StreamingSessionIdentity) {
        maxDurationTimer?.invalidate()
        let timer = Timer(timeInterval: maxRecordingDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self?.isActive(identity) == true else { return }
                self?.handleMaxDurationReached()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        maxDurationTimer = timer
    }

    private func stopMaxDurationTimer() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
    }

    private func handleMaxDurationReached() {
        logger.warning("Max recording duration reached")
        guard activeSessionIdentity != nil else { return }
        hotKeyService.forceSealing()
    }

    private func setupErrorRecovery() {
        $status
            .debounce(for: .seconds(errorRecoveryDelay), scheduler: DispatchQueue.main)
            .sink { [weak self] status in
                if case .error = status {
                    logger.info("Auto-recovering from error state")
                    self?.status = .idle
                    self?.hotKeyService.resetToIdle()
                }
            }
            .store(in: &cancellables)
    }

    private func playSound(named name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }

    func saveSettings() {
        let oldLaunchAtLogin = AppSettings.load().launchAtLogin
        settings.save()
        if settings.launchAtLogin != oldLaunchAtLogin {
            LoginItemService.setEnabled(settings.launchAtLogin)
        }
    }

    func updateSettings(
        appId: String,
        appSecret: String,
        autoInsert: Bool,
        playSound: Bool,
        launchAtLogin: Bool
    ) {
        settings.appId = appId
        settings.appSecret = appSecret
        settings.autoInsert = autoInsert
        settings.playSound = playSound
        settings.launchAtLogin = launchAtLogin
        saveSettings()
    }

    func cleanup() {
        logger.info("MainViewModel cleanup called")
        invalidateActiveIdentityAndCursor()
        activeIngress?.fail(.cancelled)
        consumerTask?.cancel()
        consumerTask = nil
        sealingTask?.cancel()
        sealingTask = nil
        clearInteractionReferences()
        audioRecorder.forceCleanup()
        stopHotKeyMonitoring()
        stopMaxDurationTimer()
    }
}
