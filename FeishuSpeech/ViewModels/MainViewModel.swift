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

private nonisolated final class StreamingOperationRaceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isSettled = false

    func claimSettlement() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isSettled else { return false }
        isSettled = true
        return true
    }
}

protocol HotKeyWakeRecovering: AnyObject {
    func recoverAfterWake()
}

extension HotKeyService: HotKeyWakeRecovering {}

@MainActor
class MainViewModel: ObservableObject {
    private struct ResponseOutputLedger {
        enum ReservationResult {
            case owned
            case historical(metrics: SnapshotMetrics)
            case staleGeneration
            case sealed
        }

        enum ClaimResult {
            case changed(snapshot: String, metrics: SnapshotMetrics)
            case duplicate(metrics: SnapshotMetrics)
            case staleGeneration
            case sealed
        }

        struct SnapshotMetrics {
            let decision: String
            let previousUTF16Count: Int
            let newUTF16Count: Int
            let commonPrefixUTF16Count: Int
            let previousCharacterCount: Int
            let newCharacterCount: Int
            let commonPrefixCharacterCount: Int
            let deleteCharacterCount: Int
            let insertUTF16Count: Int
            let insertCharacterCount: Int
        }

        private(set) var generation: UInt64?
        private(set) var latestSnapshot: String = ""
        private(set) var isAdmissionOpen = false

        private var ownedPacketIndices = Set<Int>()

        mutating func begin(generation: UInt64) {
            self.generation = generation
            latestSnapshot = ""
            ownedPacketIndices.removeAll(keepingCapacity: true)
            isAdmissionOpen = true
        }

        mutating func closeAdmission() {
            isAdmissionOpen = false
        }

        mutating func reset() {
            generation = nil
            latestSnapshot = ""
            ownedPacketIndices.removeAll(keepingCapacity: true)
            isAdmissionOpen = false
        }

        mutating func reserve(
            text: String,
            packetIndex: Int,
            generation: UInt64
        ) -> ReservationResult {
            guard generation == self.generation else { return .staleGeneration }
            guard isAdmissionOpen else { return .sealed }

            guard ownedPacketIndices.insert(packetIndex).inserted else {
                return .historical(metrics: snapshotMetrics(for: text))
            }
            return .owned
        }

        mutating func claim(text: String, generation: UInt64) -> ClaimResult {
            guard generation == self.generation else { return .staleGeneration }
            guard isAdmissionOpen else { return .sealed }

            let metrics = snapshotMetrics(for: text)
            guard text != latestSnapshot else { return .duplicate(metrics: metrics) }
            latestSnapshot = text
            return .changed(snapshot: text, metrics: metrics)
        }

        func metrics(for text: String) -> SnapshotMetrics {
            snapshotMetrics(for: text)
        }

        private func snapshotMetrics(for text: String) -> SnapshotMetrics {
            let previousCharacters = Array(latestSnapshot)
            let newCharacters = Array(text)
            let commonCount = zip(previousCharacters, newCharacters).prefix { $0 == $1 }.count
            let commonPrefix = String(newCharacters.prefix(commonCount))
            let inserted = String(newCharacters.dropFirst(commonCount))
            let decision: String
            if latestSnapshot.isEmpty {
                decision = "first"
            } else if text == latestSnapshot {
                decision = "duplicateSnapshot"
            } else if commonCount == previousCharacters.count {
                decision = "extension"
            } else if commonCount == newCharacters.count {
                decision = "shorter"
            } else {
                decision = "revision"
            }
            return SnapshotMetrics(
                decision: decision,
                previousUTF16Count: latestSnapshot.utf16.count,
                newUTF16Count: text.utf16.count,
                commonPrefixUTF16Count: commonPrefix.utf16.count,
                previousCharacterCount: previousCharacters.count,
                newCharacterCount: newCharacters.count,
                commonPrefixCharacterCount: commonCount,
                deleteCharacterCount: previousCharacters.count - commonCount,
                insertUTF16Count: inserted.utf16.count,
                insertCharacterCount: inserted.count
            )
        }
    }

    private struct ResponseReceiptContext {
        let identity: StreamingSessionIdentity
        let packetIndex: Int?
        let source: CurrentFocusHypothesisSource
        let eventKind: String
        let rawUTF16Count: Int
    }

    private struct ResponseReceipt {
        let context: ResponseReceiptContext
        let eligibility: String
        let ownership: String
        let metrics: ResponseOutputLedger.SnapshotMetrics?
        let outputRoute: String
        let outputOutcome: String
    }

    private struct ChangedSnapshotOutput {
        let route: String
        let outcome: String
        let shouldStop: Bool
    }

    private struct ProcessedPacketResult: Sendable {
        let event: StreamingRecognitionEvent
        let shouldStop: Bool
    }

    private enum ResponseEligibility {
        case eligible(packetIndex: Int)
        case ineligible(reason: String)
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
        case ready(any SpeechStreamingSession, attemptIdentifier: UInt64)
        case retry
        case stop
    }

    private enum WatchedOperationResult<Value: Sendable>: Sendable {
        case success(Value)
        case failure(StreamFailure)
    }

    private struct WatchedOperationContext: Sendable {
        let identity: StreamingSessionIdentity
        let attemptIdentifier: UInt64
        let operation: String
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
    private let overlayPresenter: RecordingOverlayPresenting
    private let currentFocusAppendSessionFactory: (any CurrentFocusProvisionalOutputSessionFactory)?
    private let streamingDrainPolicy: StreamingDrainPolicy
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
    private var usesCurrentFocusFinalOutput = false
    private var currentFocusAppendSession: (any CurrentFocusProvisionalOutputSession)?
    private var attemptedFirstPartialRebind = false
    private var attemptedUnboundAppendArm = false
    private var packetJournal: [Data] = []
    private var responseOutputLedger = ResponseOutputLedger()
    private var retryFailureStreak = 0
    private var nextAttemptIdentifier: UInt64 = 0
    private var activeAttemptIdentifier: UInt64?
    private var currentAttemptCancellationTask: Task<Void, Never>?
    private var retryAdmissionOpen = false
    private var streamingAttemptPhase = StreamingAttemptPhase.idle
    private var sessionCreationTask: Task<any SpeechStreamingSession, Error>?
    private var retrySleepTask: Task<Void, Error>?
    private var consumerTask: Task<Void, Never>?
    private var sealingTask: Task<Void, Never>?
    private var pendingRecorderBarrier: PendingRecorderBarrier?
    private var nextRecorderBarrierIdentifier: UInt64 = 0
    private var captureClosed = false
    private var postReleaseDrainDeadline: ContinuousClock.Instant?
    private var postReleaseDrainTask: Task<Void, Never>?
    private var acceptedPacket = false
    private var hasUsableHeldRecognition = false
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
        streamingDrainPolicy: StreamingDrainPolicy = StreamingDrainPolicy(),
        streamingRetryDelay: (@Sendable (Int) -> UInt64)? = nil,
        streamingRetrySleeper: (@Sendable (UInt64) async throws -> Void)? = nil
    ) {
        let resolvedAudioRecorder = audioRecorder ?? AudioRecorder()
        self.audioRecorder = resolvedAudioRecorder
        self.settings = settings ?? AppSettings.load()
        self.hotKeyWakeRecovering = hotKeyWakeRecovering ?? HotKeyService.shared
        self.streamingProvider = streamingProvider ?? FeishuAPIService.shared
        self.accessibilityClient = accessibilityClient ?? MacAccessibilityClient()
        self.overlayPresenter = overlayPresenter ?? OverlayWindowController.shared
        self.streamingDrainPolicy = streamingDrainPolicy
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
        captureClosed = false
        postReleaseDrainDeadline = nil
        postReleaseDrainTask?.cancel()
        postReleaseDrainTask = nil
        acceptedPacket = false
        hasUsableHeldRecognition = false
        stopSoundPlayed = false
        attemptedFirstPartialRebind = false
        attemptedUnboundAppendArm = false
        packetJournal.removeAll(keepingCapacity: true)
        responseOutputLedger.begin(generation: identity.generation)
        retryFailureStreak = 0
        nextAttemptIdentifier = 0
        activeAttemptIdentifier = nil
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
            configureUnboundCursorFallback(
                cursorSession: newCursorSession,
                identity: identity
            )
            return true
        }

        if let rejectionMessage = configureCursorCapability(
            capability,
            cursorSession: newCursorSession,
            identity: identity
        ) {
            failStartup(identity: identity, message: rejectionMessage)
            return false
        }
        return true
    }

    private func configureCursorCapability(
        _ capability: CursorCapabilityResult,
        cursorSession newCursorSession: CursorTextSession,
        identity: StreamingSessionIdentity
    ) -> String? {
        switch capability {
        case .rejected(.secureTarget):
            return "安全输入框不支持语音输入"
        case .rejected(.accessibilityUnavailable):
            configureUnboundCursorFallback(
                cursorSession: newCursorSession,
                identity: identity
            )
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

    private func configureUnboundCursorFallback(
        cursorSession newCursorSession: CursorTextSession,
        identity: StreamingSessionIdentity
    ) {
        newCursorSession.invalidate()
        cursorSession = nil
        usesCurrentFocusFinalOutput = settings.autoInsert
        if settings.autoInsert {
            attemptedUnboundAppendArm = true
            armCurrentFocusAppendSession(identity: identity)
            usesCurrentFocusFinalOutput = true
        }
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
            switch await createStreamingSession(identity: identity) {
            case .retry:
                continue
            case .stop:
                return
            case .ready(let session, let attemptIdentifier):
                let shouldRetry = await runStreamingAttempt(
                    session,
                    iterator: &iterator,
                    identity: identity,
                    attemptIdentifier: attemptIdentifier
                )
                guard shouldRetry else { return }
            }
        }
    }

    private func createStreamingSession(
        identity: StreamingSessionIdentity
    ) async -> SessionCreationOutcome {
        guard isActive(identity), retryAdmissionOpen else {
            return .stop
        }

        nextAttemptIdentifier &+= 1
        let attemptIdentifier = nextAttemptIdentifier
        activeAttemptIdentifier = attemptIdentifier
        currentAttemptCancellationTask = nil
        streamingAttemptPhase = .creatingSession
        logStreamingLifecycle(
            identity: identity,
            attemptIdentifier: attemptIdentifier,
            phase: "factoryStarted"
        )
        let appId = settings.appId
        let appSecret = settings.appSecret
        let provider = streamingProvider
        let result = await performWatchedOperation(
            context: WatchedOperationContext(
                identity: identity,
                attemptIdentifier: attemptIdentifier,
                operation: "factory"
            ),
            onTaskCreated: { [weak self] task in
                self?.sessionCreationTask = task
            },
            onLateSuccess: { session in
                await session.cancel()
            },
            admitSuccess: { session in session },
            body: {
                try await provider.makeStreamingSession(
                    appId: appId,
                    appSecret: appSecret
                )
            }
        )
        sessionCreationTask = nil
        guard isCurrentAttempt(identity, attemptIdentifier), retryAdmissionOpen else {
            if case .success(let session) = result {
                await session.cancel()
            }
            return .stop
        }

        switch result {
        case .success(let session):
            streamingAttemptPhase = .idle
            logStreamingLifecycle(
                identity: identity,
                attemptIdentifier: attemptIdentifier,
                phase: "factoryReady"
            )
            return .ready(session, attemptIdentifier: attemptIdentifier)
        case .failure(let failure):
            return await waitForRetryIfAdmitted(
                identity: identity,
                attemptIdentifier: attemptIdentifier,
                error: failure
            ) ? .retry : .stop
        }
    }

    private func runStreamingAttempt(
        _ session: any SpeechStreamingSession,
        iterator: inout AsyncThrowingStream<Data, Error>.Iterator,
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64
    ) async -> Bool {
        guard isCurrentAttempt(identity, attemptIdentifier), !Task.isCancelled else {
            await cancelCurrentAttemptOnce(session)
            return false
        }
        currentAttemptCancellationTask = nil
        activeStreamingSession = session

        do {
            streamingAttemptPhase = packetJournal.isEmpty ? .consumingLiveAudio : .replayingJournal
            try await replayJournal(
                with: session,
                identity: identity,
                attemptIdentifier: attemptIdentifier
            )
            streamingAttemptPhase = .consumingLiveAudio
            let receivedTerminalEvent = try await consumePackets(
                iterator: &iterator,
                with: session,
                identity: identity,
                attemptIdentifier: attemptIdentifier
            )
            guard isCurrentAttempt(identity, attemptIdentifier), !Task.isCancelled else { return false }
            guard !receivedTerminalEvent else { return false }
            return await finishConsumedAudio(
                with: session,
                identity: identity,
                attemptIdentifier: attemptIdentifier
            )
        } catch {
            await cancelCurrentAttemptOnce(session)
            return await waitForRetryIfAdmitted(
                identity: identity,
                attemptIdentifier: attemptIdentifier,
                error: error
            )
        }
    }

    private func consumePackets(
        iterator: inout AsyncThrowingStream<Data, Error>.Iterator,
        with session: any SpeechStreamingSession,
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64
    ) async throws -> Bool {
        while let packet = try await iterator.next() {
            guard isCurrentAttempt(identity, attemptIdentifier), !Task.isCancelled else { return true }
            packetJournal.append(packet)
            let packetIndex = packetJournal.index(before: packetJournal.endIndex)
            let processed = try await performSessionOperation(
                identity: identity,
                attemptIdentifier: attemptIdentifier,
                operation: "packet",
                body: {
                    try await session.sendAudioPacket(packet)
                },
                admitSuccess: { event in
                    let shouldStop = self.processPacketOperationEvent(
                        event,
                        identity: identity,
                        attemptIdentifier: attemptIdentifier,
                        context: (source: .livePacket, packetIndex: packetIndex)
                    )
                    return ProcessedPacketResult(event: event, shouldStop: shouldStop)
                }
            )
            guard isCurrentAttempt(identity, attemptIdentifier), !Task.isCancelled else { return true }
            if case .failed(let failure) = processed.event {
                throw failure
            }
            if processed.shouldStop {
                return true
            }
        }
        return false
    }

    private func replayJournal(
        with session: any SpeechStreamingSession,
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64
    ) async throws {
        guard !packetJournal.isEmpty else { return }

        for (packetIndex, packet) in packetJournal.enumerated() {
            guard isCurrentAttempt(identity, attemptIdentifier), !Task.isCancelled else {
                throw CancellationError()
            }
            let processed = try await performSessionOperation(
                identity: identity,
                attemptIdentifier: attemptIdentifier,
                operation: "packet",
                body: {
                    try await session.sendAudioPacket(packet)
                },
                admitSuccess: { event in
                    let shouldStop = self.processPacketOperationEvent(
                        event,
                        identity: identity,
                        attemptIdentifier: attemptIdentifier,
                        context: (source: .replayCatchUp, packetIndex: packetIndex)
                    )
                    return ProcessedPacketResult(event: event, shouldStop: shouldStop)
                }
            )
            if case .failed(let failure) = processed.event {
                throw failure
            }
            if processed.shouldStop { return }
        }
    }

    private func finishConsumedAudio(
        with session: any SpeechStreamingSession,
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64
    ) async -> Bool {
        streamingAttemptPhase = .finishing
        guard captureClosed else {
            await terminateAbnormally(message: "音频流意外结束", reportsError: true)
            return false
        }

        do {
            let event = try await performSessionOperation(
                identity: identity,
                attemptIdentifier: attemptIdentifier,
                operation: "finish",
                body: {
                    try await session.finish()
                },
                admitSuccess: { event in
                    self.processTerminalOperationEvent(
                        event,
                        identity: identity,
                        attemptIdentifier: attemptIdentifier
                    )
                    return event
                }
            )
            guard isCurrentAttempt(identity, attemptIdentifier), !Task.isCancelled else { return false }
            if case .failed(let failure) = event {
                guard isRecoverable(failure) else {
                    await handleStreamingFailure(identity: identity, error: failure)
                    return false
                }
                await cancelCurrentAttemptOnce(session)
                return await waitForRetryIfAdmitted(
                    identity: identity,
                    attemptIdentifier: attemptIdentifier,
                    error: failure
                )
            }
            return false
        } catch {
            if isRecoverable(error) {
                await cancelCurrentAttemptOnce(session)
                return await waitForRetryIfAdmitted(
                    identity: identity,
                    attemptIdentifier: attemptIdentifier,
                    error: error
                )
            } else {
                await handleStreamingFailure(identity: identity, error: error)
                return false
            }
        }
    }

    private func waitForRetryIfAdmitted(
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64,
        error: Error
    ) async -> Bool {
        guard isRecoverable(error) else {
            await handleStreamingFailure(identity: identity, error: error)
            return false
        }
        guard isCurrentAttempt(identity, attemptIdentifier), !Task.isCancelled else { return false }
        guard retryAdmissionOpen else { return false }
        if remainingDrainNanoseconds() == 0 {
            await expirePostReleaseDrain(identity: identity)
            return false
        }

        retryFailureStreak += 1
        let requestedDelay = streamingRetryDelay(retryFailureStreak)
        let delay = streamingDrainPolicy.retryDelay(
            requestedDelay,
            remainingDrainNanoseconds: remainingDrainNanoseconds()
        )
        logger.warning(
            """
            Streaming recoverable failure generation=\(identity.generation, privacy: .public) \
            attempt=\(attemptIdentifier, privacy: .public) \
            retryStreak=\(self.retryFailureStreak, privacy: .public) \
            delayMilliseconds=\(delay / 1_000_000, privacy: .public)
            """
        )
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
            return false
        }
        retrySleepTask = nil
        guard isCurrentAttempt(identity, attemptIdentifier), !Task.isCancelled, retryAdmissionOpen else {
            return false
        }
        if remainingDrainNanoseconds() == 0 {
            await expirePostReleaseDrain(identity: identity)
            return false
        }
        streamingAttemptPhase = .idle
        return true
    }

    private func performSessionOperation<Value: Sendable, AdmittedValue: Sendable>(
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64,
        operation: String,
        body: @escaping @Sendable () async throws -> Value,
        admitSuccess: @escaping @MainActor (Value) -> AdmittedValue
    ) async throws -> AdmittedValue {
        let result = await performWatchedOperation(
            context: WatchedOperationContext(
                identity: identity,
                attemptIdentifier: attemptIdentifier,
                operation: operation
            ),
            onTaskCreated: { _ in },
            onLateSuccess: { _ in },
            admitSuccess: admitSuccess,
            body: body
        )
        guard isCurrentAttempt(identity, attemptIdentifier), retryAdmissionOpen else {
            throw StreamFailure.cancelled
        }
        switch result {
        case .success(let value):
            return value
        case .failure(let failure):
            if failure == .timeout {
                logger.warning(
                    """
                    Streaming operation timed out generation=\(identity.generation, privacy: .public) \
                    attempt=\(attemptIdentifier, privacy: .public) \
                    operation=\(operation, privacy: .public)
                    """
                )
            }
            throw failure
        }
    }

    private func processPacketOperationEvent(
        _ event: StreamingRecognitionEvent,
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64,
        context: (source: CurrentFocusHypothesisSource, packetIndex: Int)
    ) -> Bool {
        guard isCurrentAttempt(identity, attemptIdentifier), !Task.isCancelled else { return true }
        if case .failed = event {
            return false
        }
        recordPacketAcknowledgement(identity: identity, attemptIdentifier: attemptIdentifier)
        return handleStreamingEvent(
            event,
            identity: identity,
            isTerminal: false,
            source: context.source,
            packetIndex: context.packetIndex
        )
    }

    private func processTerminalOperationEvent(
        _ event: StreamingRecognitionEvent,
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64
    ) {
        guard isCurrentAttempt(identity, attemptIdentifier), !Task.isCancelled else { return }
        if case .failed = event {
            return
        }
        _ = handleStreamingEvent(event, identity: identity, isTerminal: true)
    }

    private func performWatchedOperation<Value: Sendable, AdmittedValue: Sendable>(
        context: WatchedOperationContext,
        onTaskCreated: (Task<Value, Error>) -> Void,
        onLateSuccess: @escaping @Sendable (Value) async -> Void,
        admitSuccess: @escaping @MainActor (Value) -> AdmittedValue,
        body: @escaping @Sendable () async throws -> Value
    ) async -> WatchedOperationResult<AdmittedValue> {
        let timeoutNanoseconds = streamingDrainPolicy.operationTimeout(
            remainingDrainNanoseconds: remainingDrainNanoseconds()
        )
        let gate = StreamingOperationRaceGate()
        let (stream, continuation) = AsyncStream<WatchedOperationResult<AdmittedValue>>.makeStream()
        let task = Task<Value, Error>(priority: .high) {
            do {
                let value = try await body()
                guard gate.claimSettlement() else {
                    await onLateSuccess(value)
                    logger.info(
                        """
                        Streaming late completion suppressed \
                        generation=\(context.identity.generation, privacy: .public) \
                        attempt=\(context.attemptIdentifier, privacy: .public) \
                        operation=\(context.operation, privacy: .public)
                        """
                    )
                    return value
                }
                let admittedValue = await admitSuccess(value)
                continuation.yield(.success(admittedValue))
                continuation.finish()
                return value
            } catch {
                if gate.claimSettlement() {
                    continuation.yield(.failure(streamFailure(for: error)))
                    continuation.finish()
                }
                throw error
            }
        }
        onTaskCreated(task)
        let timeout = Task {
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }
            if gate.claimSettlement() {
                continuation.yield(.failure(.timeout))
                continuation.finish()
            }
        }
        var iterator = stream.makeAsyncIterator()
        let result = await iterator.next() ?? .failure(.cancelled)
        task.cancel()
        timeout.cancel()
        return result
    }

    private func streamFailure(for error: Error) -> StreamFailure {
        if let failure = error as? StreamFailure {
            return failure
        }
        if error is CancellationError {
            return .cancelled
        }
        guard let apiError = error as? FeishuAPIService.APIError else {
            return .malformedResponse
        }
        switch apiError {
        case .httpError(let status):
            return .httpStatus(status)
        case .timeout:
            return .timeout
        case .networkUnavailable, .connectionFailed, .networkError:
            return .network
        case .authFailed, .authenticationUnavailable:
            return .authentication
        case .invalidResponse, .recognitionFailed, .unknown:
            return .malformedResponse
        }
    }

    private func recordPacketAcknowledgement(
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64
    ) {
        guard isCurrentAttempt(identity, attemptIdentifier) else { return }
        acceptedPacket = true
        retryFailureStreak = 0
        logStreamingLifecycle(
            identity: identity,
            attemptIdentifier: attemptIdentifier,
            phase: "packetAcknowledged"
        )
    }

    private func remainingDrainNanoseconds() -> UInt64? {
        guard let postReleaseDrainDeadline else { return nil }
        let remaining = ContinuousClock.now.duration(to: postReleaseDrainDeadline)
        guard remaining > .zero else { return 0 }
        let components = remaining.components
        let seconds = UInt64(max(components.seconds, 0))
        let nanoseconds = UInt64(max(components.attoseconds, 0) / 1_000_000_000)
        return seconds.multipliedReportingOverflow(by: 1_000_000_000).partialValue + nanoseconds
    }

    private func isCurrentAttempt(
        _ identity: StreamingSessionIdentity,
        _ attemptIdentifier: UInt64
    ) -> Bool {
        isActive(identity) && activeAttemptIdentifier == attemptIdentifier
    }

    private func logStreamingLifecycle(
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64,
        phase: String
    ) {
        logger.info(
            """
            Streaming lifecycle generation=\(identity.generation, privacy: .public) \
            attempt=\(attemptIdentifier, privacy: .public) \
            phase=\(phase, privacy: .public) captureClosed=\(self.captureClosed, privacy: .public) \
            journalPackets=\(self.packetJournal.count, privacy: .public) \
            retryStreak=\(self.retryFailureStreak, privacy: .public)
            """
        )
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

    private func interpretAppendFinalOutcome(
        _ outcome: CurrentFocusAppendFinalOutcome,
        identity: StreamingSessionIdentity
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
            return true
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
        if let failure = error as? StreamFailure, failure == .authentication {
            return "认证失败，请检查应用凭据"
        }
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
        source: CurrentFocusHypothesisSource = .livePacket,
        packetIndex: Int? = nil
    ) -> Bool {
        guard isActive(identity) else { return true }

        switch event {
        case .partial(let text):
            return handlePacketResponse(
                text,
                eventKind: "partial",
                identity: identity,
                source: source,
                packetIndex: packetIndex
            )

        case .final(let text):
            return handleFinal(
                text,
                identity: identity,
                isTerminal: isTerminal,
                source: source,
                packetIndex: packetIndex
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

    private func handlePacketResponse(
        _ text: String,
        eventKind: String,
        identity: StreamingSessionIdentity,
        source: CurrentFocusHypothesisSource,
        packetIndex: Int?
    ) -> Bool {
        let context = ResponseReceiptContext(
            identity: identity,
            packetIndex: packetIndex,
            source: source,
            eventKind: eventKind,
            rawUTF16Count: text.utf16.count
        )
        recordUsableRecognitionIfEligible(text, packetIndex: context.packetIndex)
        guard reservePacketIndex(
            text: text,
            context: context,
            generation: identity.generation
        ) else {
            return false
        }

        if let rejection = classifySnapshotForAllRoutes(text) {
            logReservedIneligibleResponse(context, eligibility: rejection)
            return false
        }
        guard prepareContinuousOutputIfNeeded(identity: identity) else { return true }
        guard cursorSession != nil || currentFocusAppendSession != nil else {
            logIneligibleResponse(context, eligibility: "noContinuousOwner")
            return false
        }
        if let rejection = classifySnapshotForActiveRoute(text) {
            logReservedIneligibleResponse(context, eligibility: rejection)
            return false
        }

        switch responseOutputLedger.claim(text: text, generation: identity.generation) {
        case .changed(let snapshot, let metrics):
            let output = offerChangedSnapshot(snapshot, identity: identity, source: source)
            logResponseReceipt(ResponseReceipt(
                context: ResponseReceiptContext(
                    identity: context.identity,
                    packetIndex: context.packetIndex,
                    source: context.source,
                    eventKind: context.eventKind,
                    rawUTF16Count: metrics.newUTF16Count
                ),
                eligibility: "eligible",
                ownership: "ownedResponse",
                metrics: metrics,
                outputRoute: output.route,
                outputOutcome: output.outcome
            ))
            return output.shouldStop

        case .duplicate(let metrics):
            logResponseReceipt(ResponseReceipt(
                context: context,
                eligibility: "eligible",
                ownership: "ownedResponse",
                metrics: metrics,
                outputRoute: "none",
                outputOutcome: "notOffered"
            ))
            return false

        case .staleGeneration:
            logIneligibleResponse(context, eligibility: "staleGeneration")
            return false

        case .sealed:
            logIneligibleResponse(context, eligibility: "sealed")
            return false
        }
    }

    private func reservePacketIndex(
        text: String,
        context: ResponseReceiptContext,
        generation: UInt64
    ) -> Bool {
        let packetIndex: Int
        switch classifyPacketAdmission(context: context) {
        case .eligible(let eligibleIndex):
            packetIndex = eligibleIndex
        case .ineligible(let reason):
            logIneligibleResponse(context, eligibility: reason)
            return false
        }

        switch responseOutputLedger.reserve(
            text: text,
            packetIndex: packetIndex,
            generation: generation
        ) {
        case .owned:
            return true
        case .historical(let metrics):
            logHistoricalResponse(context, metrics: metrics)
        case .staleGeneration:
            logIneligibleResponse(context, eligibility: "staleGeneration")
        case .sealed:
            logIneligibleResponse(context, eligibility: "sealed")
        }
        return false
    }

    private func logHistoricalResponse(
        _ context: ResponseReceiptContext,
        metrics: ResponseOutputLedger.SnapshotMetrics
    ) {
        logResponseReceipt(ResponseReceipt(
            context: context,
            eligibility: "eligible",
            ownership: "historicalReplaySuppressed",
            metrics: metrics,
            outputRoute: "none",
            outputOutcome: "notOffered"
        ))
    }

    private func logReservedIneligibleResponse(
        _ context: ResponseReceiptContext,
        eligibility: String
    ) {
        logResponseReceipt(ResponseReceipt(
            context: context,
            eligibility: eligibility,
            ownership: "ownedPacketIndex",
            metrics: nil,
            outputRoute: "none",
            outputOutcome: "snapshotNotAdmitted"
        ))
    }

    private func offerChangedSnapshot(
        _ snapshot: String,
        identity: StreamingSessionIdentity,
        source: CurrentFocusHypothesisSource
    ) -> ChangedSnapshotOutput {
        if let cursorSession {
            try? cursorSession.handle(.partial(snapshot), generation: identity.generation)
            return ChangedSnapshotOutput(
                route: "verifiedAX",
                outcome: "offered",
                shouldStop: false
            )
        }
        guard let currentFocusAppendSession else {
            return ChangedSnapshotOutput(
                route: "none",
                outcome: "ownerUnavailable",
                shouldStop: false
            )
        }
        let outcome = currentFocusAppendSession.applyOpaqueHypothesis(
            snapshot,
            generation: identity.generation,
            source: source
        )
        return ChangedSnapshotOutput(
            route: "currentFocusKeyboard",
            outcome: String(describing: outcome),
            shouldStop: interpretAppendApplyOutcome(outcome, identity: identity)
        )
    }

    private func recordUsableRecognitionIfEligible(_ text: String, packetIndex: Int?) {
        guard packetIndex != nil,
              responseOutputLedger.isAdmissionOpen,
              !isContentless(text) else {
            return
        }
        hasUsableHeldRecognition = true
    }

    private func classifyPacketAdmission(
        context: ResponseReceiptContext
    ) -> ResponseEligibility {
        guard responseOutputLedger.isAdmissionOpen else {
            return .ineligible(reason: "sealed")
        }
        guard settings.autoInsert else { return .ineligible(reason: "outputDisabled") }
        guard let packetIndex = context.packetIndex else {
            return .ineligible(reason: "missingJournalIndex")
        }
        return .eligible(packetIndex: packetIndex)
    }

    private func classifySnapshotForActiveRoute(_ text: String) -> String? {
        let isSafe = if cursorSession != nil {
            TextInputSimulator.isSafeForAutomaticKeyboardText(text)
        } else {
            TextInputSimulator.isSafeForAutomaticKeyboardEventText(text)
        }
        guard isSafe else { return "unsafeText" }
        return nil
    }

    private func classifySnapshotForAllRoutes(_ text: String) -> String? {
        guard !isContentless(text) else { return "contentless" }
        guard TextInputSimulator.isSafeForAutomaticKeyboardText(text) else { return "unsafeText" }
        return nil
    }

    private func handleFinal(
        _ text: String,
        identity: StreamingSessionIdentity,
        isTerminal: Bool,
        source: CurrentFocusHypothesisSource,
        packetIndex: Int?
    ) -> Bool {
        guard isTerminal else {
            return handlePacketResponse(
                text,
                eventKind: "final",
                identity: identity,
                source: source,
                packetIndex: packetIndex
            )
        }

        let context = ResponseReceiptContext(
            identity: identity,
            packetIndex: nil,
            source: source,
            eventKind: "terminal",
            rawUTF16Count: text.utf16.count
        )
        guard responseOutputLedger.isAdmissionOpen else {
            logIneligibleResponse(context, eligibility: "sealed")
            return true
        }

        let finalText: String?
        let terminalEligibility: String
        if let rejection = classifySnapshotForAllRoutes(text) {
            finalText = nil
            terminalEligibility = rejection
        } else if let rejection = classifySnapshotForActiveRoute(text) {
            finalText = nil
            terminalEligibility = rejection
        } else {
            finalText = text
            terminalEligibility = "eligible"
            hasUsableHeldRecognition = true
        }
        let metrics = finalText.map(responseOutputLedger.metrics(for:))
        let finalization = finalizeExistingOutputOwner(
            identity: identity,
            finalText: finalText
        )
        responseOutputLedger.closeAdmission()
        logResponseReceipt(ResponseReceipt(
            context: context,
            eligibility: terminalEligibility,
            ownership: finalText == nil ? "notOwned" : "terminalAuthority",
            metrics: metrics,
            outputRoute: cursorSession == nil ? "currentFocusKeyboard" : "verifiedAX",
            outputOutcome: finalization.outcome
        ))
        guard finalization.mayCompleteNormally else { return true }
        if finalText == nil, !hasUsableHeldRecognition {
            overlayMessage = "未识别到内容"
        }
        if isContentless(text), !isCompletionFeedbackPresented {
            publishCompletionFeedback(.emptyFinalPreservedPartial)
        }
        Task { @MainActor [weak self] in
            await self?.completeNormally(identity: identity)
        }
        return true
    }

    private func finalizeExistingOutputOwner(
        identity: StreamingSessionIdentity,
        finalText: String? = nil
    ) -> (mayCompleteNormally: Bool, outcome: String) {
        let latestSnapshot = responseOutputLedger.latestSnapshot
        if let cursorSession {
            if let finalText {
                try? cursorSession.handle(.final(finalText), generation: identity.generation)
                return (true, "authoritativeFinalOffered")
            }
            try? cursorSession.handle(.cancelled, generation: identity.generation)
            return (true, "cursorPreservedWithoutFinal")
        }
        guard let currentFocusAppendSession else { return (true, "noOwner") }
        let outcome = currentFocusAppendSession.finalize(
            finalText: finalText,
            lastAcceptedText: latestSnapshot.isEmpty ? nil : latestSnapshot,
            generation: identity.generation
        )
        return (
            interpretAppendFinalOutcome(outcome, identity: identity),
            String(describing: outcome)
        )
    }

    private func logIneligibleResponse(_ context: ResponseReceiptContext, eligibility: String) {
        logResponseReceipt(ResponseReceipt(
            context: context,
            eligibility: eligibility,
            ownership: "notOwned",
            metrics: nil,
            outputRoute: "none",
            outputOutcome: eligibility == "sealed" ? "sealedSuppressed" : "notOffered"
        ))
    }

    private func logResponseReceipt(_ receipt: ResponseReceipt) {
        let sourceName: String
        switch receipt.context.source {
        case .livePacket:
            sourceName = receipt.context.eventKind == "terminal" ? "terminal" : "live"
        case .replayCatchUp:
            sourceName = "replay"
        }
        let packetIndexValue = receipt.context.packetIndex ?? -1
        let metrics = receipt.metrics
        let decision = receipt.ownership == "historicalReplaySuppressed"
            ? "suppressed"
            : metrics?.decision ?? "suppressed"
        logger.info(
            """
            Streaming response receipt generation=\(receipt.context.identity.generation, privacy: .public) \
            attempt=\(self.activeAttemptIdentifier ?? 0, privacy: .public) \
            packetIndex=\(packetIndexValue, privacy: .public) \
            source=\(sourceName, privacy: .public) event=\(receipt.context.eventKind, privacy: .public) \
            eligibility=\(receipt.eligibility, privacy: .public) \
            ownership=\(receipt.ownership, privacy: .public) \
            decision=\(decision, privacy: .public) \
            previousUTF16=\(metrics?.previousUTF16Count ?? 0, privacy: .public) \
            newUTF16=\(receipt.context.rawUTF16Count, privacy: .public) \
            commonUTF16=\(metrics?.commonPrefixUTF16Count ?? 0, privacy: .public) \
            previousCharacters=\(metrics?.previousCharacterCount ?? 0, privacy: .public) \
            newCharacters=\(metrics?.newCharacterCount ?? 0, privacy: .public) \
            commonCharacters=\(metrics?.commonPrefixCharacterCount ?? 0, privacy: .public) \
            backspaces=\(metrics?.deleteCharacterCount ?? 0, privacy: .public) \
            insertionUTF16=\(metrics?.insertUTF16Count ?? 0, privacy: .public) \
            insertionCharacters=\(metrics?.insertCharacterCount ?? 0, privacy: .public) \
            route=\(receipt.outputRoute, privacy: .public) \
            transaction=\(receipt.outputOutcome, privacy: .public)
            """
        )
    }

    private func prepareContinuousOutputIfNeeded(identity: StreamingSessionIdentity) -> Bool {
        guard usesCurrentFocusFinalOutput,
              cursorSession == nil,
              !attemptedFirstPartialRebind,
              !captureClosed else {
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
            if currentFocusAppendSession == nil, !attemptedUnboundAppendArm {
                armCurrentFocusAppendSession(identity: identity)
            }
            return true
        }

        switch capability {
        case .live:
            currentFocusAppendSession?.invalidate()
            currentFocusAppendSession = nil
            cursorSession = reboundSession
            usesCurrentFocusFinalOutput = false
            logger.info("Bound an AX cursor destination on the first streaming hypothesis")
        case .finalOnly(let token):
            reboundSession.invalidate()
            usesCurrentFocusFinalOutput = false
            if currentFocusAppendSession != nil || armCapturedCurrentFocusAppendSession(
                identity: identity,
                destination: token
            ) {
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
            if currentFocusAppendSession == nil, !attemptedUnboundAppendArm {
                armCurrentFocusAppendSession(identity: identity)
            }
        }
        return true
    }

    private func armCurrentFocusAppendSession(identity: StreamingSessionIdentity) {
        guard let appendSession = currentFocusAppendSessionFactory?.makeSession(
            generation: identity.generation
        ) else {
            logger.info("Continuous current-focus output is unavailable; no response output owner was armed")
            return
        }
        currentFocusAppendSession = appendSession
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
            logger.info("Captured continuous output is unavailable; no response output owner was armed")
            return false
        }
        currentFocusAppendSession = appendSession
        usesCurrentFocusFinalOutput = false
        logger.info("Armed captured continuous append output")
        return true
    }

    private func interpretAppendApplyOutcome(
        _ outcome: CurrentFocusAppendOutcome,
        identity: StreamingSessionIdentity
    ) -> Bool {
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

    private func handleTerminalEvent(
        _ event: StreamingRecognitionEvent,
        identity: StreamingSessionIdentity,
        message: String?,
        reportsError: Bool
    ) -> Bool {
        if captureClosed {
            guard finalizeExistingOutputOwner(identity: identity).mayCompleteNormally else { return true }
        } else if let cursorSession {
            try? cursorSession.handle(event, generation: identity.generation)
        }
        Task { @MainActor [weak self] in
            await self?.terminateAbnormally(message: message, reportsError: reportsError)
        }
        return true
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

    private func beginSealing(identity: StreamingSessionIdentity) {
        guard isActive(identity), !captureClosed else { return }
        captureClosed = true
        stopMaxDurationTimer()
        status = .sealing
        overlayPresenter.update(status: .sealing)
        logStreamingLifecycle(
            identity: identity,
            attemptIdentifier: activeAttemptIdentifier ?? 0,
            phase: "releaseRequested"
        )

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
        pendingRecorderBarrier = barrier
        sealingTask = Task { @MainActor [weak self] in
            await barrierTask.value
            guard let self, self.isActive(identity) else { return }
            _ = self.clearPendingRecorderBarrier(identifier: barrier.identifier)
            self.armPostReleaseDrainDeadlineIfNeeded(identity: identity)
        }
    }

    private func awaitSealingBarrier(identity: StreamingSessionIdentity) async -> Bool {
        guard isActive(identity) else { return false }
        let barrier = pendingRecorderBarrier
        if let barrier {
            await barrier.task.value
            guard isActive(identity) else { return false }
            guard clearPendingRecorderBarrier(identifier: barrier.identifier) else {
                return isActive(identity)
            }
        }
        armPostReleaseDrainDeadlineIfNeeded(identity: identity)
        return isActive(identity)
    }

    private func armPostReleaseDrainDeadlineIfNeeded(identity: StreamingSessionIdentity) {
        guard isActive(identity), captureClosed, postReleaseDrainDeadline == nil else { return }
        let timeout = streamingDrainPolicy.postReleaseDrainTimeoutNanoseconds
        postReleaseDrainDeadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeout)))
        logStreamingLifecycle(
            identity: identity,
            attemptIdentifier: activeAttemptIdentifier ?? 0,
            phase: "recorderBarrierComplete"
        )
        postReleaseDrainTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeout)
            } catch {
                return
            }
            await self?.expirePostReleaseDrain(identity: identity)
        }
    }

    private func expirePostReleaseDrain(identity: StreamingSessionIdentity) async {
        guard isActive(identity), captureClosed else { return }
        let preservesUsableOutput = hasUsableHeldRecognition
        let session = activeStreamingSession
        let consumer = consumerTask

        responseOutputLedger.closeAdmission()
        closeRetryAdmission()
        postReleaseDrainTask = nil
        postReleaseDrainDeadline = nil
        invalidateActiveIdentityAndCursor()
        activeIngress?.fail(.cancelled)
        consumerTask = nil
        sealingTask = nil
        pendingRecorderBarrier = nil
        clearInteractionReferences()
        stopMaxDurationTimer()
        consumer?.cancel()
        hideOverlay()
        audioRecorder.forceCleanup()

        if let session {
            Task {
                await session.cancel()
            }
        }
        if preservesUsableOutput {
            publishCompletionFeedback(.emptyFinalPreservedPartial)
        } else {
            publishAbnormalTerminalState(
                message: streamingFailureErrorMessage,
                reportsError: true
            )
        }
        logger.warning(
            """
            Streaming drain expired generation=\(identity.generation, privacy: .public) \
            preservedUsableOutput=\(preservesUsableOutput, privacy: .public)
            """
        )
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
        responseOutputLedger.closeAdmission()
        closeRetryAdmission()
        postReleaseDrainTask?.cancel()
        postReleaseDrainTask = nil
        postReleaseDrainDeadline = nil
        invalidateActiveIdentityAndCursor(preserveCommittedCursorState: true)
        consumerTask = nil
        sealingTask = nil
        activeIngress = nil
        activeStreamingSession = nil
        usesCurrentFocusFinalOutput = false
        attemptedFirstPartialRebind = false
        attemptedUnboundAppendArm = false
        packetJournal.removeAll(keepingCapacity: true)
        responseOutputLedger.reset()
        retryFailureStreak = 0
        activeAttemptIdentifier = nil
        nextAttemptIdentifier = 0
        currentAttemptCancellationTask = nil
        streamingAttemptPhase = .idle
        captureClosed = false
        acceptedPacket = false
        hasUsableHeldRecognition = false
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
        postReleaseDrainTask?.cancel()
        postReleaseDrainTask = nil
        postReleaseDrainDeadline = nil
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
        usesCurrentFocusFinalOutput = false
        attemptedFirstPartialRebind = false
        attemptedUnboundAppendArm = false
        packetJournal.removeAll(keepingCapacity: true)
        responseOutputLedger.reset()
        retryFailureStreak = 0
        activeAttemptIdentifier = nil
        nextAttemptIdentifier = 0
        retryAdmissionOpen = false
        streamingAttemptPhase = .idle
        sessionCreationTask = nil
        retrySleepTask = nil
        captureClosed = false
        acceptedPacket = false
        hasUsableHeldRecognition = false
        stopSoundPlayed = false
    }

    private func isActive(_ identity: StreamingSessionIdentity) -> Bool {
        activeSessionIdentity == identity
    }

    private func isContentless(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        postReleaseDrainTask?.cancel()
        postReleaseDrainTask = nil
        postReleaseDrainDeadline = nil
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
