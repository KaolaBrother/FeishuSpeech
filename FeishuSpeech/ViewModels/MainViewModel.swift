import AppKit
import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "ViewModel")

let maxRecordingDuration: TimeInterval = 60.0
let errorRecoveryDelay: TimeInterval = 3.0
private let hotKeyMonitoringErrorMessage = "热键不可用，请检查辅助功能权限"
private let completionFeedbackDuration: TimeInterval = 2.0
private let streamingSecurityErrorMessage = "安全输入框不支持语音输入"
private let streamingFailureErrorMessage = "流式识别失败"
private let streamingIngressConfiguration = AudioIngressConfiguration(
    packetByteCount: 6_400,
    minimumTailByteCount: 3_200,
    maximumBufferedByteCount: 1_920_000
)

protocol HotKeyWakeRecovering: AnyObject {
    func recoverAfterWake()
}

extension HotKeyService: HotKeyWakeRecovering {}

@MainActor
class MainViewModel: ObservableObject {
    private enum AppendManualRecoveryEligibility {
        case unavailable
        case capturedZeroPost
    }

    private enum StreamingAttemptPhase {
        case idle
        case creatingSession
        case waitingToRetry
        case replayingJournal
        case consumingLiveAudio
        case finishing
    }

    private enum SessionCreationOutcome {
        case ready(any SpeechStreamingSession)
        case retry
        case stop
    }

    private struct PendingRecorderBarrier {
        let identifier: UInt64
        let task: Task<Void, Never>
    }

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
    private let currentFocusAppendSessionFactory: (any CurrentFocusProvisionalOutputSessionFactory)?
    private let streamingRetryDelay: @Sendable (Int) -> UInt64
    private let streamingRetrySleeper: @Sendable (UInt64) async throws -> Void
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
    private var currentFocusAppendSession: (any CurrentFocusProvisionalOutputSession)?
    private var appendManualRecoveryEligibility = AppendManualRecoveryEligibility.unavailable
    private var attemptedFirstPartialRebind = false
    private var packetJournal: [Data] = []
    private var retryOrdinal = 0
    private var currentAttemptCancellationTask: Task<Void, Never>?
    private var retryAdmissionOpen = false
    private var streamingAttemptPhase = StreamingAttemptPhase.idle
    private var sessionCreationTask: Task<any SpeechStreamingSession, Error>?
    private var retrySleepTask: Task<Void, Error>?
    private var consumerTask: Task<Void, Never>?
    private var sealingTask: Task<Void, Never>?
    private var pendingRecorderBarrier: PendingRecorderBarrier?
    private var nextRecorderBarrierIdentifier: UInt64 = 0
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
        overlayPresenter: RecordingOverlayPresenting? = nil,
        currentFocusAppendSessionFactory: (any CurrentFocusProvisionalOutputSessionFactory)? = nil,
        streamingRetryDelay: (@Sendable (Int) -> UInt64)? = nil,
        streamingRetrySleeper: (@Sendable (UInt64) async throws -> Void)? = nil
    ) {
        let resolvedAudioRecorder = audioRecorder ?? AudioRecorder()
        self.audioRecorder = resolvedAudioRecorder
        self.settings = settings ?? AppSettings.load()
        self.hotKeyWakeRecovering = hotKeyWakeRecovering ?? HotKeyService.shared
        self.streamingProvider = streamingProvider ?? FeishuAPIService.shared
        self.accessibilityClient = accessibilityClient ?? MacAccessibilityClient()
        self.finalTextOutput = finalTextOutput ?? SystemFinalTextOutput()
        self.overlayPresenter = overlayPresenter ?? OverlayWindowController.shared
        if let currentFocusAppendSessionFactory {
            self.currentFocusAppendSessionFactory = currentFocusAppendSessionFactory
        } else if audioRecorder == nil,
                  streamingProvider == nil,
                  accessibilityClient == nil,
                  finalTextOutput == nil,
                  overlayPresenter == nil {
            self.currentFocusAppendSessionFactory = SystemCurrentFocusProvisionalOutputSessionFactory()
        } else {
            self.currentFocusAppendSessionFactory = nil
        }
        let retryPolicy = StreamingRetryPolicy()
        self.streamingRetryDelay = streamingRetryDelay ?? { ordinal in
            retryPolicy.delayNanoseconds(forRetryOrdinal: ordinal)
        }
        self.streamingRetrySleeper = streamingRetrySleeper ?? { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
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
            if activeSessionIdentity == nil, pendingRecorderBarrier == nil {
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
            handleHotKeyError(message)
        case .recording, .transcribing:
            logger.warning("Ignoring retired whole-file hot-key state")
        }
        _ = startsTranscriptionTask
    }

    private func handleHotKeyError(_ message: String) {
        guard activeSessionIdentity != nil else {
            guard pendingRecorderBarrier == nil else { return }
            if status != .error(message) {
                hideOverlay()
                status = .error(message)
            }
            return
        }
        Task { @MainActor [weak self] in
            await self?.terminateAbnormally(message: message, reportsError: true)
        }
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
        guard activeSessionIdentity == nil, pendingRecorderBarrier == nil else {
            logger.info("Ignoring streaming start while another generation or recorder barrier is active")
            return
        }

        activeSessionIdentity = identity
        isCompletionFeedbackPresented = false
        overlayMessage = nil
        sealStarted = false
        acceptedPacket = false
        stopSoundPlayed = false
        attemptedFirstPartialRebind = false
        appendManualRecoveryEligibility = .unavailable
        packetJournal.removeAll(keepingCapacity: true)
        retryOrdinal = 0
        currentAttemptCancellationTask = nil
        retryAdmissionOpen = true
        streamingAttemptPhase = .idle
        sessionCreationTask = nil
        retrySleepTask = nil

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
        let ingress = ByteBoundedAudioIngress(
            configuration: streamingIngressConfiguration,
            retainsDeliveredPacketsForReplay: true
        )
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
                if armCapturedCurrentFocusAppendSession(
                    identity: StreamingSessionIdentity(generation: token.generation),
                    destination: token
                ) {
                    status = .streaming
                } else {
                    status = .finalOnly
                }
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
        closeRetryAdmission()
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
        var iterator = ingress.stream.makeAsyncIterator()

        while isActive(identity), !Task.isCancelled {
            if sealStarted {
                await completeAfterRecoverableRelease(identity: identity)
                return
            }

            switch await createStreamingSession(identity: identity) {
            case .retry:
                continue
            case .stop:
                if isActive(identity), sealStarted {
                    await completeAfterRecoverableRelease(identity: identity)
                }
                return
            case .ready(let session):
                guard await runStreamingAttempt(
                    session,
                    iterator: &iterator,
                    identity: identity
                ) else { return }
            }
        }
    }

    private func createStreamingSession(
        identity: StreamingSessionIdentity
    ) async -> SessionCreationOutcome {
        guard isActive(identity), retryAdmissionOpen, !sealStarted else {
            return .stop
        }

        currentAttemptCancellationTask = nil
        streamingAttemptPhase = .creatingSession
        let appId = settings.appId
        let appSecret = settings.appSecret
        let provider = streamingProvider
        let creationTask = Task<any SpeechStreamingSession, Error> {
            try await provider.makeStreamingSession(
                appId: appId,
                appSecret: appSecret
            )
        }
        sessionCreationTask = creationTask

        do {
            let session = try await creationTask.value
            sessionCreationTask = nil
            guard isActive(identity), retryAdmissionOpen, !sealStarted else {
                await session.cancel()
                return .stop
            }
            streamingAttemptPhase = .idle
            return .ready(session)
        } catch is CancellationError {
            sessionCreationTask = nil
            return .stop
        } catch {
            sessionCreationTask = nil
            return await waitForRetryIfAdmitted(identity: identity, error: error) ? .retry : .stop
        }
    }

    private func runStreamingAttempt(
        _ session: any SpeechStreamingSession,
        iterator: inout AsyncThrowingStream<Data, Error>.Iterator,
        identity: StreamingSessionIdentity
    ) async -> Bool {
        guard isActive(identity), !Task.isCancelled, !sealStarted else {
            await cancelCurrentAttemptOnce(session)
            if isActive(identity), sealStarted {
                await completeAfterRecoverableRelease(identity: identity)
            }
            return false
        }
        currentAttemptCancellationTask = nil
        activeStreamingSession = session

        do {
            streamingAttemptPhase = packetJournal.isEmpty ? .consumingLiveAudio : .replayingJournal
            try await replayJournal(with: session, identity: identity)
            streamingAttemptPhase = .consumingLiveAudio
            let receivedTerminalEvent = try await consumePackets(
                iterator: &iterator,
                with: session,
                identity: identity
            )
            guard isActive(identity), !Task.isCancelled else { return false }
            guard !receivedTerminalEvent else { return false }
            await finishConsumedAudio(with: session, identity: identity)
            return false
        } catch {
            await cancelCurrentAttemptOnce(session)
            if isStreamingCancellation(error), isActive(identity), sealStarted {
                await completeAfterRecoverableRelease(identity: identity)
                return false
            }
            return await waitForRetryIfAdmitted(identity: identity, error: error)
        }
    }

    private func consumePackets(
        iterator: inout AsyncThrowingStream<Data, Error>.Iterator,
        with session: any SpeechStreamingSession,
        identity: StreamingSessionIdentity
    ) async throws -> Bool {
        while let packet = try await iterator.next() {
            guard isActive(identity), !Task.isCancelled else { return true }
            packetJournal.append(packet)
            let event = try await session.sendAudioPacket(packet)
            guard isActive(identity), !Task.isCancelled else { return true }
            acceptedPacket = true
            if case .failed(let failure) = event {
                throw failure
            }
            if handleStreamingEvent(event, identity: identity, isTerminal: false) {
                return true
            }
        }
        return false
    }

    private func replayJournal(
        with session: any SpeechStreamingSession,
        identity: StreamingSessionIdentity
    ) async throws {
        guard !packetJournal.isEmpty else { return }
        var catchUpEvent: StreamingRecognitionEvent?

        for packet in packetJournal {
            guard isActive(identity), !Task.isCancelled, !sealStarted else {
                throw CancellationError()
            }
            let event = try await session.sendAudioPacket(packet)
            if case .failed(let failure) = event {
                throw failure
            }
            acceptedPacket = true
            if isUsableHypothesis(event) {
                catchUpEvent = event
            }
        }

        guard let catchUpEvent,
              isActive(identity),
              !Task.isCancelled,
              !sealStarted else {
            return
        }
        _ = handleStreamingEvent(
            catchUpEvent,
            identity: identity,
            isTerminal: false,
            source: .replayCatchUp
        )
    }

    private func finishConsumedAudio(
        with session: any SpeechStreamingSession,
        identity: StreamingSessionIdentity
    ) async {
        streamingAttemptPhase = .finishing
        guard sealStarted else {
            await terminateAbnormally(message: "音频流意外结束", reportsError: true)
            return
        }

        guard acceptedPacket else {
            await cancelCurrentAttemptOnce(session)
            guard isActive(identity), !Task.isCancelled else { return }
            publishCompletionFeedback(.emptyFinalPreservedPartial)
            await completeNormally(identity: identity)
            return
        }

        do {
            let event = try await session.finish()
            guard isActive(identity), !Task.isCancelled else { return }
            if case .failed(let failure) = event, isRecoverable(failure) {
                await cancelCurrentAttemptOnce(session)
                guard isActive(identity) else { return }
                await completeAfterRecoverableRelease(identity: identity)
                return
            }
            _ = handleStreamingEvent(event, identity: identity, isTerminal: true)
        } catch {
            if isRecoverable(error) {
                await cancelCurrentAttemptOnce(session)
                guard isActive(identity) else { return }
                await completeAfterRecoverableRelease(identity: identity)
            } else {
                await handleStreamingFailure(identity: identity, error: error)
            }
        }
    }

    private func waitForRetryIfAdmitted(
        identity: StreamingSessionIdentity,
        error: Error
    ) async -> Bool {
        guard isRecoverable(error) else {
            await handleStreamingFailure(identity: identity, error: error)
            return false
        }
        guard isActive(identity), !Task.isCancelled else { return false }
        guard !sealStarted else {
            await completeAfterRecoverableRelease(identity: identity)
            return false
        }
        guard retryAdmissionOpen else { return false }

        retryOrdinal += 1
        let delay = streamingRetryDelay(retryOrdinal)
        logger.warning("Streaming attempt failed recoverably; retry ordinal \(self.retryOrdinal)")
        streamingAttemptPhase = .waitingToRetry
        let sleeper = streamingRetrySleeper
        let sleepTask = Task<Void, Error> {
            try await sleeper(delay)
        }
        retrySleepTask = sleepTask
        do {
            try await sleepTask.value
        } catch {
            retrySleepTask = nil
            if isActive(identity), sealStarted {
                await completeAfterRecoverableRelease(identity: identity)
            }
            return false
        }
        retrySleepTask = nil
        guard isActive(identity), !Task.isCancelled, retryAdmissionOpen, !sealStarted else {
            if isActive(identity), sealStarted {
                await completeAfterRecoverableRelease(identity: identity)
            }
            return false
        }
        streamingAttemptPhase = .idle
        return true
    }

    private func isRecoverable(_ error: Error) -> Bool {
        if let failure = error as? StreamFailure {
            return isRecoverable(failure)
        }
        guard let apiError = error as? FeishuAPIService.APIError else {
            return false
        }
        switch apiError {
        case .httpError(let code):
            return code == 408 || code == 425 || code == 429 || (500...599).contains(code)
        case .timeout, .networkUnavailable, .connectionFailed, .networkError:
            return true
        case .authenticationUnavailable, .invalidResponse, .recognitionFailed,
             .unknown, .authFailed:
            return false
        }
    }

    private func isRecoverable(_ failure: StreamFailure) -> Bool {
        switch failure {
        case .network, .timeout:
            return true
        case .httpStatus(let code):
            return code == 408 || code == 425 || code == 429 || (500...599).contains(code)
        case .backend(let code):
            return code == 10024
        case .invalidRequest, .authentication, .malformedResponse,
             .responseIdentityMismatch, .cancelled:
            return false
        }
    }

    private func completeAfterRecoverableRelease(identity: StreamingSessionIdentity) async {
        guard await awaitSealingBarrier(identity: identity) else { return }
        guard let retainedText = retainedStreamingHypothesis else {
            if !acceptedPacket, retryOrdinal == 0 {
                // Releasing while the very first transport is still being created is
                // an ordinary user cancellation, not a failed recognition attempt.
                await completeNormally(identity: identity)
            } else {
                await terminateAbnormally(
                    message: streamingFailureErrorMessage,
                    reportsError: true
                )
            }
            return
        }

        if let currentFocusAppendSession {
            await completeAppendRecovery(
                currentFocusAppendSession,
                retainedText: retainedText,
                identity: identity
            )
            return
        }

        routeRetainedRecoveryOutput(retainedText)
        await completeNormally(identity: identity)
    }

    private var retainedStreamingHypothesis: String? {
        guard let latestFinalOnlyValue, !isContentless(latestFinalOnlyValue) else {
            return nil
        }
        return latestFinalOnlyValue
    }

    private func completeAppendRecovery(
        _ appendSession: any CurrentFocusProvisionalOutputSession,
        retainedText: String,
        identity: StreamingSessionIdentity
    ) async {
        let outcome = appendSession.finalize(
            finalText: nil,
            lastAcceptedText: retainedText,
            generation: identity.generation
        )
        switch outcome {
        case .exactCommitted, .suffixCommitted, .staleGeneration:
            await completeNormally(identity: identity)
        case .preservedDivergence, .preservedDestinationLoss, .deliveryUncertain:
            publishCompletionFeedback(.provisionalOutputPreserved)
            await completeNormally(identity: identity)
        case .preservedSecurityRejection:
            await terminateAbnormally(
                message: streamingSecurityErrorMessage,
                reportsError: true
            )
        case .noUsableText:
            if recoverUnsafeCapturedTextIfEligible() {
                await completeNormally(identity: identity)
            } else {
                await terminateAbnormally(
                    message: streamingFailureErrorMessage,
                    reportsError: true
                )
            }
        }
    }

    private func routeRetainedRecoveryOutput(_ retainedText: String) {
        if let destination = finalOnlyDestination {
            routeFinalOnly(retainedText, destination: destination)
        } else if usesCurrentFocusFinalOutput {
            routeCurrentFocusFinal(retainedText)
        } else if cursorSession != nil, settings.autoInsert {
            publishCompletionFeedback(.provisionalOutputPreserved)
        }
    }

    private func interpretAppendFinalOutcome(
        _ outcome: CurrentFocusAppendFinalOutcome,
        identity: StreamingSessionIdentity,
        followsSealedRecoverableFailure: Bool
    ) -> Bool {
        switch outcome {
        case .exactCommitted, .suffixCommitted, .staleGeneration:
            return true
        case .preservedDivergence, .preservedDestinationLoss, .deliveryUncertain:
            publishCompletionFeedback(.provisionalOutputPreserved)
            return true
        case .preservedSecurityRejection:
            scheduleStreamingTermination(
                identity: identity,
                message: streamingSecurityErrorMessage
            )
            return false
        case .noUsableText:
            if recoverUnsafeCapturedTextIfEligible() {
                return true
            }
            guard followsSealedRecoverableFailure else { return true }
            scheduleStreamingTermination(
                identity: identity,
                message: streamingFailureErrorMessage
            )
            return false
        }
    }

    private func cancelCurrentAttemptOnce(_ session: any SpeechStreamingSession) async {
        if let currentAttemptCancellationTask {
            await currentAttemptCancellationTask.value
            return
        }

        activeStreamingSession = nil
        let cancellationTask = Task {
            await session.cancel()
        }
        currentAttemptCancellationTask = cancellationTask
        await cancellationTask.value
    }

    private func isStreamingCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        guard let failure = error as? StreamFailure else { return false }
        if case .cancelled = failure {
            return true
        }
        return false
    }

    private func handleStreamingFailure(
        identity: StreamingSessionIdentity,
        error: Error? = nil
    ) async {
        guard isActive(identity), !Task.isCancelled else { return }
        if let cursorSession {
            try? cursorSession.handle(.failed(.network), generation: identity.generation)
        }
        await terminateAbnormally(
            message: streamingFailureMessage(for: error),
            reportsError: true
        )
    }

    private func streamingFailureMessage(for error: Error?) -> String {
        guard let apiError = error as? FeishuAPIService.APIError else {
            return "流式识别失败"
        }
        if case .authFailed = apiError {
            return "认证失败，请检查应用凭据"
        }
        return "流式识别失败"
    }

    @discardableResult
    private func handleStreamingEvent(
        _ event: StreamingRecognitionEvent,
        identity: StreamingSessionIdentity,
        isTerminal: Bool,
        source: CurrentFocusHypothesisSource = .livePacket
    ) -> Bool {
        guard isActive(identity) else { return true }

        switch event {
        case .partial(let text):
            return handlePartial(text, identity: identity, source: source)

        case .final(let text):
            return handleFinal(
                text,
                identity: identity,
                isTerminal: isTerminal,
                source: source
            )

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
        identity: StreamingSessionIdentity,
        source: CurrentFocusHypothesisSource
    ) -> Bool {
        guard !isContentless(text) else { return false }
        latestFinalOnlyValue = text
        guard !sealStarted else { return false }
        guard settings.autoInsert else { return false }
        guard prepareContinuousOutputIfNeeded(identity: identity) else { return true }
        if let cursorSession {
            try? cursorSession.handle(.partial(text), generation: identity.generation)
        } else if let currentFocusAppendSession {
            let outcome = currentFocusAppendSession.applyOpaqueHypothesis(
                text,
                generation: identity.generation,
                source: source
            )
            return interpretAppendApplyOutcome(outcome, identity: identity)
        }
        return false
    }

    private func handleFinal(
        _ text: String,
        identity: StreamingSessionIdentity,
        isTerminal: Bool,
        source: CurrentFocusHypothesisSource
    ) -> Bool {
        let contentless = isContentless(text)
        if !contentless {
            latestFinalOnlyValue = text
        }
        guard isTerminal || !sealStarted else { return false }
        var mayCompleteNormally = true
        if settings.autoInsert {
            mayCompleteNormally = deliverFinal(
                text,
                contentless: contentless,
                identity: identity,
                isTerminal: isTerminal,
                source: source
            )
        }
        guard mayCompleteNormally else { return true }
        if contentless {
            overlayMessage = "未识别到内容"
        }
        guard isTerminal else { return false }
        if contentless, !isCompletionFeedbackPresented {
            publishCompletionFeedback(.emptyFinalPreservedPartial)
        }
        Task { @MainActor [weak self] in
            await self?.completeNormally(identity: identity)
        }
        return true
    }

    private func deliverFinal(
        _ text: String,
        contentless: Bool,
        identity: StreamingSessionIdentity,
        isTerminal: Bool,
        source: CurrentFocusHypothesisSource
    ) -> Bool {
        if let cursorSession {
            try? cursorSession.handle(
                .final(contentless ? "" : text),
                generation: identity.generation
            )
        } else if let currentFocusAppendSession {
            if isTerminal {
                let outcome = currentFocusAppendSession.finalize(
                    finalText: text,
                    lastAcceptedText: latestFinalOnlyValue,
                    generation: identity.generation
                )
                return interpretAppendFinalOutcome(
                    outcome,
                    identity: identity,
                    followsSealedRecoverableFailure: false
                )
            } else if !contentless {
                let outcome = currentFocusAppendSession.applyOpaqueHypothesis(
                    text,
                    generation: identity.generation,
                    source: source
                )
                return !interpretAppendApplyOutcome(outcome, identity: identity)
            }
        } else if let destination = finalOnlyDestination,
                  let candidate = contentless ? latestFinalOnlyValue : Optional(text),
                  !isContentless(candidate) {
            routeFinalOnly(candidate, destination: destination)
        } else if usesCurrentFocusFinalOutput,
                  let candidate = contentless ? latestFinalOnlyValue : Optional(text),
                  !isContentless(candidate) {
            routeCurrentFocusFinal(candidate)
        }
        return true
    }

    private func prepareContinuousOutputIfNeeded(identity: StreamingSessionIdentity) -> Bool {
        guard usesCurrentFocusFinalOutput,
              cursorSession == nil,
              currentFocusAppendSession == nil,
              !attemptedFirstPartialRebind else {
            return true
        }
        attemptedFirstPartialRebind = true

        let reboundSession = CursorTextSession(
            generation: identity.generation,
            accessibilityClient: accessibilityClient
        )
        let capability: CursorCapabilityResult
        do {
            capability = try reboundSession.begin()
        } catch {
            reboundSession.invalidate()
            armCurrentFocusAppendSession(identity: identity)
            return true
        }

        switch capability {
        case .live:
            cursorSession = reboundSession
            usesCurrentFocusFinalOutput = false
            logger.info("Bound an AX cursor destination on the first streaming hypothesis")
        case .finalOnly(let token):
            reboundSession.invalidate()
            finalOnlyDestination = token
            usesCurrentFocusFinalOutput = false
            if armCapturedCurrentFocusAppendSession(identity: identity, destination: token) {
                status = .streaming
                overlayPresenter.update(status: .streaming)
                logger.info("Armed captured continuous output on the first streaming hypothesis")
            } else {
                status = .finalOnly
                overlayPresenter.update(status: .finalOnly)
                logger.info("Captured a final-only AX destination on the first streaming hypothesis")
            }
        case .rejected(.secureTarget):
            reboundSession.invalidate()
            usesCurrentFocusFinalOutput = false
            scheduleStreamingTermination(
                identity: identity,
                message: streamingSecurityErrorMessage
            )
            return false
        case .rejected(.accessibilityUnavailable):
            reboundSession.invalidate()
            armCurrentFocusAppendSession(identity: identity)
        }
        return true
    }

    private func armCurrentFocusAppendSession(identity: StreamingSessionIdentity) {
        guard let appendSession = currentFocusAppendSessionFactory?.makeSession(
            generation: identity.generation
        ) else {
            logger.info("Continuous current-focus output is unavailable; retaining final-only fallback")
            return
        }
        currentFocusAppendSession = appendSession
        appendManualRecoveryEligibility = .unavailable
        usesCurrentFocusFinalOutput = false
        logger.info("Armed continuous current-focus append output")
    }

    private func armCapturedCurrentFocusAppendSession(
        identity: StreamingSessionIdentity,
        destination: CursorDestinationToken
    ) -> Bool {
        guard let appendSession = currentFocusAppendSessionFactory?.makeSession(
            generation: identity.generation,
            boundProcessIdentifier: destination.processIdentifier,
            validateBoundDestination: { [weak self] in
                guard let self else { return .destinationChanged }
                return self.validateFinalOnlyDestination(destination)
            }
        ) else {
            logger.info("Captured continuous output is unavailable; retaining final-only fallback")
            return false
        }
        currentFocusAppendSession = appendSession
        appendManualRecoveryEligibility = .capturedZeroPost
        usesCurrentFocusFinalOutput = false
        logger.info("Armed captured continuous append output")
        return true
    }

    private func interpretAppendApplyOutcome(
        _ outcome: CurrentFocusAppendOutcome,
        identity: StreamingSessionIdentity
    ) -> Bool {
        switch outcome {
        case .contentless, .unsafeTextSuppressed:
            break
        case .insertedFirst, .appendedSuffix, .duplicate, .revisionSuppressed,
             .destinationChanged, .securityRejected, .deliveryUncertain, .staleGeneration:
            appendManualRecoveryEligibility = .unavailable
        }
        switch outcome {
        case .securityRejected:
            scheduleStreamingTermination(
                identity: identity,
                message: streamingSecurityErrorMessage
            )
            return true
        case .insertedFirst, .appendedSuffix, .duplicate, .revisionSuppressed,
             .contentless, .unsafeTextSuppressed, .destinationChanged,
             .deliveryUncertain, .staleGeneration:
            return false
        }
    }

    private func recoverUnsafeCapturedTextIfEligible() -> Bool {
        guard appendManualRecoveryEligibility == .capturedZeroPost,
              let retainedText = latestFinalOnlyValue,
              !isContentless(retainedText),
              !TextInputSimulator.isSafeForAutomaticPaste(retainedText) else {
            return false
        }
        appendManualRecoveryEligibility = .unavailable
        guard let destination = finalOnlyDestination,
              validateFinalOnlyDestination(destination) == .valid else {
            return false
        }
        copyForManualRecovery(retainedText)
        return true
    }

    private func scheduleStreamingTermination(
        identity: StreamingSessionIdentity,
        message: String
    ) {
        guard isActive(identity) else { return }
        retryAdmissionOpen = false
        Task { @MainActor [weak self] in
            guard let self, self.isActive(identity) else { return }
            await self.terminateAbnormally(message: message, reportsError: true)
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
        var outputPreflight: CurrentFocusBoundDestinationValidation?
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
    ) -> CurrentFocusBoundDestinationValidation {
        if let currentFocusAppendSessionFactory,
           currentFocusAppendSessionFactory.validateCapturedDestinationSecurity() != .valid {
            return .securityRejected
        }
        guard currentSecurityIsSafe(for: destination) else {
            return .securityRejected
        }
        guard accessibilityClient.frontmostProcessIdentifier() == destination.processIdentifier else {
            return .destinationChanged
        }
        do {
            let focusedElement = try accessibilityClient.focusedElement()
            return CFEqual(focusedElement, destination.element) ? .valid : .destinationChanged
        } catch {
            return .destinationChanged
        }
    }

    private func handleFinalTextInsertionResult(
        _ result: FinalTextInsertionResult,
        text: String,
        outputPreflight: CurrentFocusBoundDestinationValidation?
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
        let interruptedPhase = streamingAttemptPhase
        let interruptedSession = activeStreamingSession
        sealStarted = true
        closeRetryAdmission()
        stopMaxDurationTimer()
        status = .sealing
        overlayPresenter.update(status: .sealing)

        if settings.playSound, !stopSoundPlayed {
            stopSoundPlayed = true
            playSound(named: "stop")
        }

        let streamEstablished = activeIngress?.hasEmittedFullPacket == true
        let recorder = audioRecorder
        let barrierTask = Task {
            await recorder.stopStreamingRecording(streamEstablished: streamEstablished)
        }
        nextRecorderBarrierIdentifier &+= 1
        let barrier = PendingRecorderBarrier(
            identifier: nextRecorderBarrierIdentifier,
            task: barrierTask
        )
        sealingTask = barrierTask
        pendingRecorderBarrier = barrier

        switch interruptedPhase {
        case .creatingSession, .waitingToRetry:
            Task { @MainActor [weak self] in
                await self?.completeAfterRecoverableRelease(identity: identity)
            }
        case .replayingJournal:
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let interruptedSession {
                    await self.cancelCurrentAttemptOnce(interruptedSession)
                }
                await self.completeAfterRecoverableRelease(identity: identity)
            }
        case .idle, .consumingLiveAudio, .finishing:
            break
        }
    }

    private func awaitSealingBarrier(identity: StreamingSessionIdentity) async -> Bool {
        guard isActive(identity) else { return false }
        let barrier = pendingRecorderBarrier
        if let barrier {
            await barrier.task.value
            guard isActive(identity) else { return false }
            guard clearPendingRecorderBarrier(identifier: barrier.identifier) else {
                return false
            }
        }
        return isActive(identity)
    }

    @discardableResult
    private func clearPendingRecorderBarrier(identifier: UInt64) -> Bool {
        guard pendingRecorderBarrier?.identifier == identifier else { return false }
        pendingRecorderBarrier = nil
        return true
    }

    private func completeNormally(identity: StreamingSessionIdentity) async {
        guard await awaitSealingBarrier(identity: identity) else { return }
        let preservesCompletionFeedback = isCompletionFeedbackPresented
        closeRetryAdmission()
        invalidateActiveIdentityAndCursor(preserveCommittedCursorState: true)
        consumerTask = nil
        sealingTask = nil
        activeIngress = nil
        activeStreamingSession = nil
        finalOnlyDestination = nil
        usesCurrentFocusFinalOutput = false
        deliveredCurrentFocusFinal = false
        latestFinalOnlyValue = nil
        attemptedFirstPartialRebind = false
        appendManualRecoveryEligibility = .unavailable
        packetJournal.removeAll(keepingCapacity: true)
        retryOrdinal = 0
        currentAttemptCancellationTask = nil
        streamingAttemptPhase = .idle
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
        let ingress = activeIngress
        let session = activeStreamingSession
        let existingCancellationTask = currentAttemptCancellationTask
        let consumer = consumerTask
        let barrier = pendingRecorderBarrier

        closeRetryAdmission()
        invalidateActiveIdentityAndCursor()
        ingress?.fail(.cancelled)
        consumerTask = nil
        sealingTask = nil
        clearInteractionReferences()
        stopMaxDurationTimer()
        consumer?.cancel()
        hideOverlay()
        audioRecorder.forceCleanup()
        if barrier == nil {
            publishAbnormalTerminalState(message: message, reportsError: reportsError)
        }

        if let session {
            await cancelCurrentAttemptOnce(session)
        } else if let existingCancellationTask {
            await existingCancellationTask.value
        }

        if let barrier {
            await barrier.task.value
            guard clearPendingRecorderBarrier(identifier: barrier.identifier) else {
                return
            }
            publishAbnormalTerminalState(message: message, reportsError: reportsError)
        }
    }

    private func publishAbnormalTerminalState(message: String?, reportsError: Bool) {
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
            currentFocusAppendSession?.invalidate()
        }
        cursorSession = nil
        currentFocusAppendSession = nil
    }

    private func clearInteractionReferences() {
        activeIngress = nil
        activeStreamingSession = nil
        finalOnlyDestination = nil
        usesCurrentFocusFinalOutput = false
        deliveredCurrentFocusFinal = false
        latestFinalOnlyValue = nil
        attemptedFirstPartialRebind = false
        appendManualRecoveryEligibility = .unavailable
        packetJournal.removeAll(keepingCapacity: true)
        retryOrdinal = 0
        retryAdmissionOpen = false
        streamingAttemptPhase = .idle
        sessionCreationTask = nil
        retrySleepTask = nil
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

    private func isUsableHypothesis(_ event: StreamingRecognitionEvent) -> Bool {
        switch event {
        case .partial(let text), .final(let text):
            return !isContentless(text)
        case .failed, .cancelled:
            return false
        }
    }

    private func closeRetryAdmission() {
        retryAdmissionOpen = false
        sessionCreationTask?.cancel()
        sessionCreationTask = nil
        retrySleepTask?.cancel()
        retrySleepTask = nil
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
        } else if pendingRecorderBarrier != nil {
            logger.info("Ignoring recorder failure while abnormal sealing cleanup owns the barrier")
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
        closeRetryAdmission()
        invalidateActiveIdentityAndCursor()
        activeIngress?.fail(.cancelled)
        consumerTask?.cancel()
        consumerTask = nil
        sealingTask?.cancel()
        sealingTask = nil
        pendingRecorderBarrier?.task.cancel()
        pendingRecorderBarrier = nil
        clearInteractionReferences()
        audioRecorder.forceCleanup()
        stopHotKeyMonitoring()
        stopMaxDurationTimer()
    }
}
