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
    enum SuccessClaim {
        case won
        case deadlineExpired
        case lost
    }

    private let lock = NSLock()
    private var isSettled = false

    func claimSettlement() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isSettled else { return false }
        isSettled = true
        return true
    }

    func claimSuccess(
        deadline: ContinuousClock.Instant?,
        now: @Sendable () -> ContinuousClock.Instant
    ) -> SuccessClaim {
        lock.lock()
        defer { lock.unlock() }
        guard !isSettled else { return .lost }
        if let deadline, now() >= deadline {
            isSettled = true
            return .deadlineExpired
        }
        isSettled = true
        return .won
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

    private struct ProcessedPacketResult: Sendable {
        let event: StreamingRecognitionEvent
        let shouldStop: Bool
    }

    private enum StreamingAttemptPhase {
        case idle
        case creatingSession
        case waitingToRetry
        case replayingJournal
        case consumingLiveAudio
        case finishing
    }

    private enum OutputPreservationState: Equatable {
        case none
        case committedSafe
        case deliveryUncertain
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

    private struct ReviewSurfaceAuthority {
        let identifier: UUID
        let generation: UInt64
        let destination: ReviewDestinationToken
        var draft: ReviewDraft?
        var revision: UInt64
        var readinessAttempt: UInt64
        var confirmationAttempt: UInt64
    }

    private struct ReviewDraft {
        var text: String
        let isPossiblyIncomplete: Bool
        var feedback: ReviewDraftFeedback?
    }

    @Published var status: RecordingState = .idle
    @Published var settings: AppSettings
    @Published var overlayMessage: String?
    @Published private(set) var transcriptionReviewState: TranscriptionReviewState = .idle
    @Published var reviewDraftText: String = "" {
        didSet {
            guard !projectingReviewDraft,
                  let authority = reviewSurfaceAuthority,
                  var draft = authority.draft,
                  !reviewConfirmationInFlight else { return }
            draft.text = reviewDraftText
            draft.feedback = nil
            var updatedAuthority = authority
            updatedAuthority.draft = draft
            updatedAuthority.revision &+= 1
            self.reviewSurfaceAuthority = updatedAuthority
            reviewSurfaceRevision &+= 1
            switch transcriptionReviewState {
            case .editable(_, let isPossiblyIncomplete, _):
                transcriptionReviewState = .editable(
                    draft: reviewDraftText,
                    isPossiblyIncomplete: isPossiblyIncomplete,
                    feedback: nil
                )
            case .editablePending(_, let isPossiblyIncomplete, let readiness, _):
                transcriptionReviewState = .editablePending(
                    draft: reviewDraftText,
                    isPossiblyIncomplete: isPossiblyIncomplete,
                    readiness: readiness,
                    feedback: nil
                )
            default:
                break
            }
        }
    }

    private let hotKeyService = HotKeyService.shared
    private let hotKeyWakeRecovering: HotKeyWakeRecovering
    private let audioRecorder: AudioRecorder
    private let streamingProvider: any SpeechStreamingSessionProviding
    private let overlayPresenter: RecordingOverlayPresenting
    private let reviewDestinationDelivery: ReviewDestinationDelivering
    private let reviewSurfacePresenter: ReviewSurfacePresenting
    private let streamingDrainPolicy: StreamingDrainPolicy
    private let streamingMonotonicNow: @Sendable () -> ContinuousClock.Instant
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
    private var holdPacketJournal = HoldPacketJournal()
    private var responseOutputLedger = ResponseOutputLedger()
    private var retryFailureStreak = 0
    private var nextAttemptIdentifier: UInt64 = 0
    private var activeAttemptIdentifier: UInt64?
    private var currentAttemptCancellationTask: Task<Void, Never>?
    private var retryAdmissionOpen = false
    private var streamingAttemptPhase = StreamingAttemptPhase.idle
    private var sessionCreationTask: Task<any SpeechStreamingSession, Error>?
    private var retrySleepTask: Task<Void, Error>?
    private var captureDrainTask: Task<Void, Never>?
    private var consumerTask: Task<Void, Never>?
    private var sealingTask: Task<Void, Never>?
    private var pendingRecorderBarrier: PendingRecorderBarrier?
    private var nextRecorderBarrierIdentifier: UInt64 = 0
    private var captureClosed = false
    private var postReleaseDrainDeadline: ContinuousClock.Instant?
    private var postReleaseDrainTask: Task<Void, Never>?
    private var acceptedPacket = false
    private var outputPreservationState = OutputPreservationState.none
    private var stopSoundPlayed = false
    private var isCompletionFeedbackPresented = false
    private var reviewSurfaceAuthority: ReviewSurfaceAuthority?
    private var reviewSurfaceRevision: UInt64 = 0
    private var reviewTerminalPending = false
    private var reviewDraftIsPossiblyIncomplete = false
    private var reviewConfirmationInFlight = false
    private var projectingReviewDraft = false
    private var reviewTransitionTask: Task<Void, Never>?
    private var reviewTransitionID: UUID?
    private var reviewReadOnlyPresentationTask: Task<Void, Never>?
    private var reviewDeliveryTask: Task<Void, Never>?

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
        reviewDestinationDelivery: ReviewDestinationDelivering? = nil,
        reviewSurfacePresenter: ReviewSurfacePresenting? = nil,
        currentFocusAppendSessionFactory: (any CurrentFocusProvisionalOutputSessionFactory)? = nil,
        streamingDrainPolicy: StreamingDrainPolicy = StreamingDrainPolicy(),
        streamingMonotonicNow: @escaping @Sendable () -> ContinuousClock.Instant = {
            ContinuousClock.now
        },
        streamingRetryDelay: (@Sendable (Int) -> UInt64)? = nil,
        streamingRetrySleeper: (@Sendable (UInt64) async throws -> Void)? = nil
    ) {
        let resolvedAudioRecorder = audioRecorder ?? AudioRecorder()
        self.audioRecorder = resolvedAudioRecorder
        self.settings = settings ?? AppSettings.load()
        self.hotKeyWakeRecovering = hotKeyWakeRecovering ?? HotKeyService.shared
        self.streamingProvider = streamingProvider ?? FeishuAPIService.shared
        self.overlayPresenter = overlayPresenter ?? OverlayWindowController.shared
        self.reviewDestinationDelivery = reviewDestinationDelivery ?? SystemReviewDestinationDelivery()
        self.reviewSurfacePresenter = reviewSurfacePresenter ?? ReviewWindowController.shared
        self.streamingDrainPolicy = streamingDrainPolicy
        self.streamingMonotonicNow = streamingMonotonicNow
        // Keep the legacy initializer labels source-compatible. Accepted
        // interactions never construct or select a direct-output owner.
        _ = accessibilityClient
        _ = finalTextOutput
        _ = currentFocusAppendSessionFactory
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
                    } else if self.reviewSurfaceAuthority != nil {
                        self.preserveReviewDraftAfterAmbientSecurityChange()
                    }
                }
            }
            .store(in: &cancellables)

        permissionManager.$secureInputEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard enabled, let self,
                      self.activeSessionIdentity != nil || self.reviewSurfaceAuthority != nil else {
                    return
                }
                logger.warning("Secure input activated during an active interaction")
                if self.activeSessionIdentity != nil {
                    self.invalidateActiveIdentityAndCursor()
                    Task { @MainActor [weak self] in
                        await self?.terminateAbnormally(
                            message: "安全输入已启用",
                            reportsError: true
                        )
                    }
                } else {
                    self.preserveReviewDraftAfterAmbientSecurityChange()
                }
            }
            .store(in: &cancellables)
    }

    private func preserveReviewDraftAfterAmbientSecurityChange() {
        guard var authority = reviewSurfaceAuthority,
              let existingDraft = authority.draft,
              !reviewConfirmationInFlight else {
            return
        }

        authority.draft = ReviewDraft(
            text: existingDraft.text,
            isPossiblyIncomplete: existingDraft.isPossiblyIncomplete,
            feedback: .securityRejected
        )
        reviewSurfaceAuthority = authority

        switch transcriptionReviewState {
        case .editable(let draft, let isPossiblyIncomplete, _):
            transcriptionReviewState = .editable(
                draft: draft,
                isPossiblyIncomplete: isPossiblyIncomplete,
                feedback: .securityRejected
            )
        case .editablePending(
            let draft,
            let isPossiblyIncomplete,
            let readiness,
            _
        ):
            let preservedReadiness: ReviewEditableReadinessState
            if case .preparing(let attempt) = readiness {
                reviewTransitionTask?.cancel()
                reviewTransitionTask = nil
                reviewTransitionID = nil
                preservedReadiness = .blocked(
                    attempt: attempt,
                    failure: .surfaceInvalidated
                )
            } else {
                preservedReadiness = readiness
            }
            transcriptionReviewState = .editablePending(
                draft: draft,
                isPossiblyIncomplete: isPossiblyIncomplete,
                readiness: preservedReadiness,
                feedback: .securityRejected
            )
        default:
            return
        }

        reviewSurfaceRevision &+= 1
        renderCurrentReviewDraftSurface()
    }

    private func renderCurrentReviewDraftSurface() {
        guard let authority = reviewSurfaceAuthority,
              authority.draft != nil else {
            return
        }
        switch transcriptionReviewState {
        case .editable, .editablePending:
            break
        case .idle, .streaming, .sealing, .confirming:
            return
        }

        let reviewID = authority.identifier
        var callbackRevision = reviewSurfaceRevision
        reviewSurfacePresenter.renderDraft(
            state: transcriptionReviewState,
            onDraftChange: { [weak self] changedDraft in
                guard let self,
                      self.reviewSurfaceRevision == callbackRevision else {
                    return
                }
                self.updateReviewDraft(changedDraft, reviewID: reviewID)
                callbackRevision = self.reviewSurfaceRevision
            },
            onConfirm: { [weak self] in
                self?.confirmReviewDraft(
                    reviewID: reviewID,
                    callbackRevision: callbackRevision
                )
            },
            onRetryReadiness: { [weak self] in
                self?.retryReviewReadiness(
                    reviewID: reviewID,
                    callbackRevision: callbackRevision
                )
            },
            onDiscard: { [weak self] in
                self?.discardReviewDraft(
                    reviewID: reviewID,
                    callbackRevision: callbackRevision
                )
            }
        )
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
            if reviewSurfaceAuthority != nil {
                stopMaxDurationTimer()
                return
            }
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
        if reviewSurfaceAuthority != nil {
            if activeSessionIdentity != nil {
                Task { @MainActor [weak self] in
                    await self?.terminateAbnormally(message: message, reportsError: true)
                }
            } else {
                revokeReviewAuthority()
                status = .error(message)
            }
            return
        }
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

    var journalCountForTesting: Int {
        holdPacketJournal.count
    }

    var holdPacketJournalForTesting: HoldPacketJournal {
        holdPacketJournal
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

        guard reviewSurfaceAuthority == nil else {
            logger.info("Ignoring streaming start while a review draft owns the interaction")
            hotKeyService.resetToIdle()
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
        outputPreservationState = .none
        stopSoundPlayed = false
        holdPacketJournal.cancelWaiters()
        holdPacketJournal = HoldPacketJournal()
        responseOutputLedger.begin(generation: identity.generation)
        retryFailureStreak = 0
        nextAttemptIdentifier = 0
        activeAttemptIdentifier = nil
        currentAttemptCancellationTask = nil
        retryAdmissionOpen = true
        streamingAttemptPhase = .idle
        sessionCreationTask = nil
        retrySleepTask = nil
        reviewSurfaceRevision &+= 1
        reviewTerminalPending = false
        reviewDraftIsPossiblyIncomplete = false
        reviewConfirmationInFlight = false
        projectingReviewDraft = false
        reviewTransitionTask?.cancel()
        reviewTransitionTask = nil
        reviewTransitionID = nil
        cancelReviewReadOnlyPresentation()
        reviewDeliveryTask?.cancel()
        reviewDeliveryTask = nil

        guard !permissionManager.secureInputEnabled else {
            failStartup(identity: identity, message: "安全输入框不支持语音输入")
            return
        }
        guard prepareReviewDestination(identity: identity) else { return }
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

        captureDrainTask = Task(priority: .userInitiated) { [weak self] in
            await self?.drainCapturedAudio(identity: identity, ingress: ingress)
        }
        consumerTask = Task(priority: .userInitiated) { [weak self] in
            await self?.consumeAudio(identity: identity)
        }

        if let authority = reviewSurfaceAuthority {
            renderReviewReadOnly(
                phase: .streaming,
                preview: "",
                authority: authority
            )
        }
    }

    private func prepareReviewDestination(identity: StreamingSessionIdentity) -> Bool {
        let captureResult = reviewDestinationDelivery.capture(
            generation: identity.generation
        )
        switch captureResult {
        case .rejected(.secureInput):
            failStartup(identity: identity, message: "安全输入框不支持语音输入")
            return false
        case .rejected(.destinationUnavailable):
            failStartup(identity: identity, message: "无法确认输入位置")
            return false
        case .captured(let destination):
            guard isValidReviewDestination(
                destination,
                generation: identity.generation
            ) else {
                failStartup(identity: identity, message: "无法确认输入位置")
                return false
            }

            let authority = ReviewSurfaceAuthority(
                identifier: UUID(),
                generation: identity.generation,
                destination: destination,
                draft: nil,
                revision: 0,
                readinessAttempt: 0,
                confirmationAttempt: 0
            )
            reviewSurfaceAuthority = authority
            transcriptionReviewState = .streaming(preview: "")
            status = .streaming
            return true
        }
    }

    private func isValidReviewDestination(
        _ destination: ReviewDestinationToken,
        generation: UInt64
    ) -> Bool {
        guard generation > 0,
              destination.generation == generation,
              destination.capturedSecurityState == .safe,
              destination.application.processIdentifier > 0,
              !destination.application.bundleIdentifier.isEmpty,
              !destination.application.executableURL.path.isEmpty,
              destination.application.launchDate.timeIntervalSinceReferenceDate.isFinite else {
            return false
        }
        switch destination.binding {
        case .exactCursor(let cursor):
            return cursor.generation == generation &&
                cursor.processIdentifier == destination.application.processIdentifier &&
                cursor.processIdentifier > 0 &&
                cursor.originalSelection.location >= 0 &&
                cursor.originalSelection.length >= 0 &&
                cursor.originalSelection.endLocation != nil
        case .applicationCurrentFocus:
            return true
        }
    }

    private func renderReviewReadOnly(
        phase: ReviewReadOnlyPhase,
        preview: String,
        authority: ReviewSurfaceAuthority? = nil
    ) {
        guard let currentAuthority = reviewSurfaceAuthority,
              currentAuthority.identifier == (authority ?? currentAuthority).identifier,
              !reviewTerminalPending else {
            return
        }
        switch transcriptionReviewState {
        case .streaming, .sealing:
            break
        default:
            return
        }

        reviewSurfaceRevision &+= 1
        let revision = reviewSurfaceRevision
        let reviewID = currentAuthority.identifier
        reviewReadOnlyPresentationTask?.cancel()
        reviewReadOnlyPresentationTask = Task { @MainActor [weak self] in
            // Keep the review surface on its own fire-and-forget lane. This yield gives
            // capture and recognition work a scheduling boundary and lets a newer
            // snapshot cancel a command that has not reached the presenter yet.
            await Task.yield()
            guard let self,
                  !Task.isCancelled,
                  self.reviewSurfaceAuthority?.identifier == reviewID,
                  self.reviewSurfaceRevision == revision,
                  !self.reviewTerminalPending else {
                return
            }
            switch self.transcriptionReviewState {
            case .streaming, .sealing:
                break
            default:
                return
            }
            self.reviewSurfacePresenter.renderReadOnly(phase: phase, preview: preview)
        }
    }

    private func cancelReviewReadOnlyPresentation() {
        reviewReadOnlyPresentationTask?.cancel()
        reviewReadOnlyPresentationTask = nil
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
        revokeReviewAuthority()
        activeIngress?.fail(.cancelled)
        holdPacketJournal.cancelWaiters()
        captureDrainTask?.cancel()
        captureDrainTask = nil
        consumerTask?.cancel()
        consumerTask = nil
        clearInteractionReferences()
        stopMaxDurationTimer()
        hideOverlay()
        status = .error(message)
        hotKeyService.setError(message)
    }

    private func drainCapturedAudio(
        identity: StreamingSessionIdentity,
        ingress: ByteBoundedAudioIngress
    ) async {
        var iterator = ingress.stream.makeAsyncIterator()
        do {
            while isActive(identity), !Task.isCancelled {
                let packet = try await iterator.next()
                guard isActive(identity), !Task.isCancelled else {
                    holdPacketJournal.cancelWaiters()
                    return
                }
                guard let packet else {
                    holdPacketJournal.markCaptureComplete()
                    return
                }
                holdPacketJournal.append(packet)
            }
            holdPacketJournal.cancelWaiters()
        } catch let ingressError as AudioIngressError {
            holdPacketJournal.cancelWaiters()
            logger.warning(
                """
                Capture drain ended without capture complete \
                generation=\(identity.generation, privacy: .public)
                """
            )
            guard isActive(identity) else { return }
            if case .ingressOverflow = ingressError {
                await terminateAbnormally(
                    message: RecordingFailure.ingressOverflow.localizedDescription,
                    reportsError: true
                )
            }
        } catch {
            holdPacketJournal.cancelWaiters()
            logger.warning(
                """
                Capture drain ended without capture complete \
                generation=\(identity.generation, privacy: .public)
                """
            )
        }
    }

    private func consumeAudio(
        identity: StreamingSessionIdentity
    ) async {
        while isActive(identity), !Task.isCancelled {
            switch await createStreamingSession(identity: identity) {
            case .retry:
                continue
            case .stop:
                return
            case .ready(let session, let attemptIdentifier):
                let shouldRetry = await runStreamingAttempt(
                    session,
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
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64
    ) async -> Bool {
        guard isCurrentAttempt(identity, attemptIdentifier), !Task.isCancelled else {
            await cancelCurrentAttemptOnce(session)
            return false
        }
        currentAttemptCancellationTask = nil
        activeStreamingSession = session
        let snapshotAtReady = holdPacketJournal.count
        var sent = 0

        do {
            while isCurrentAttempt(identity, attemptIdentifier), !Task.isCancelled {
                streamingAttemptPhase = sent < snapshotAtReady
                    ? .replayingJournal
                    : .consumingLiveAudio
                let wait = await holdPacketJournal.waitForPacket(atOrAfter: sent)
                guard isCurrentAttempt(identity, attemptIdentifier), !Task.isCancelled else {
                    await cancelCurrentAttemptOnce(session)
                    return false
                }
                switch wait {
                case let .packet(packetIndex, packet):
                    let source: CurrentFocusHypothesisSource = packetIndex < snapshotAtReady
                        ? .replayCatchUp
                        : .livePacket
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
                                context: (source: source, packetIndex: packetIndex)
                            )
                            return ProcessedPacketResult(event: event, shouldStop: shouldStop)
                        }
                    )
                    guard isCurrentAttempt(identity, attemptIdentifier), !Task.isCancelled else {
                        return false
                    }
                    if case .failed(let failure) = processed.event {
                        throw failure
                    }
                    sent += 1
                    if processed.shouldStop {
                        return false
                    }
                case .captureComplete:
                    return await finishConsumedAudio(
                        with: session,
                        identity: identity,
                        attemptIdentifier: attemptIdentifier
                    )
                case .cancelled:
                    await cancelCurrentAttemptOnce(session)
                    return false
                }
            }
            await cancelCurrentAttemptOnce(session)
            return false
        } catch {
            await cancelCurrentAttemptOnce(session)
            return await waitForRetryIfAdmitted(
                identity: identity,
                attemptIdentifier: attemptIdentifier,
                error: error
            )
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
                guard isRecoverable(
                    failure,
                    identity: identity,
                    attemptIdentifier: attemptIdentifier
                ) else {
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
            if isRecoverable(
                error,
                identity: identity,
                attemptIdentifier: attemptIdentifier
            ) {
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
        guard isRecoverable(
            error,
            identity: identity,
            attemptIdentifier: attemptIdentifier
        ) else {
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
        let remainingBudget = remainingDrainNanoseconds()
        guard remainingBudget != 0 else { return .failure(.timeout) }
        let timeoutNanoseconds = streamingDrainPolicy.operationTimeout(
            for: context.operation,
            remainingDrainNanoseconds: remainingBudget
        )
        let gate = StreamingOperationRaceGate()
        let monotonicNow = streamingMonotonicNow
        let (stream, continuation) = AsyncStream<WatchedOperationResult<AdmittedValue>>.makeStream()
        let task = Task<Value, Error>(priority: .high) {
            do {
                let value = try await body()
                let deadline = self.postReleaseDrainDeadline
                switch gate.claimSuccess(deadline: deadline, now: monotonicNow) {
                case .lost:
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
                case .deadlineExpired:
                    await onLateSuccess(value)
                    continuation.yield(.failure(.timeout))
                    continuation.finish()
                    return value
                case .won:
                    break
                }
                let admittedValue = await admitSuccess(value)
                continuation.yield(.success(admittedValue))
                continuation.finish()
                return value
            } catch {
                if gate.claimSettlement() {
                    continuation.yield(
                        .failure(
                            classifiedStreamFailure(
                                streamFailure(for: error),
                                identity: context.identity,
                                attemptIdentifier: context.attemptIdentifier
                            )
                        )
                    )
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
        let result = await withTaskCancellationHandler {
            await iterator.next()
        } onCancel: {
            if gate.claimSettlement() {
                continuation.finish()
            }
            task.cancel()
            timeout.cancel()
        }
        if case nil = result {
            _ = gate.claimSettlement()
        }
        task.cancel()
        timeout.cancel()
        return finalizeWatchedOperationResult(
            result,
            identity: context.identity,
            attemptIdentifier: context.attemptIdentifier
        )
    }

    private func finalizeWatchedOperationResult<AdmittedValue: Sendable>(
        _ result: WatchedOperationResult<AdmittedValue>?,
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64
    ) -> WatchedOperationResult<AdmittedValue> {
        if let result {
            return result
        }
        if retryAdmissionOpen, isCurrentAttempt(identity, attemptIdentifier) {
            return .failure(.timeout)
        }
        return .failure(.cancelled)
    }

    private func streamFailure(for error: Error) -> StreamFailure {
        if let failure = error as? StreamFailure {
            return failure
        }
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
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
        let remaining = streamingMonotonicNow().duration(to: postReleaseDrainDeadline)
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
            journalPackets=\(self.holdPacketJournal.count, privacy: .public) \
            retryStreak=\(self.retryFailureStreak, privacy: .public)
            """
        )
    }

    private func isRecoverable(
        _ error: Error,
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64
    ) -> Bool {
        if isAttemptScopedTransportCancel(
            error,
            identity: identity,
            attemptIdentifier: attemptIdentifier
        ) {
            return true
        }
        if let failure = error as? StreamFailure {
            return isRecoverable(
                failure,
                identity: identity,
                attemptIdentifier: attemptIdentifier
            )
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

    private func isRecoverable(
        _ failure: StreamFailure,
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64
    ) -> Bool {
        if isAttemptScopedTransportCancel(
            failure,
            identity: identity,
            attemptIdentifier: attemptIdentifier
        ) {
            return true
        }
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

    private func classifiedStreamFailure(
        _ failure: StreamFailure,
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64
    ) -> StreamFailure {
        if isAttemptScopedTransportCancel(
            failure,
            identity: identity,
            attemptIdentifier: attemptIdentifier
        ) {
            return .timeout
        }
        return failure
    }

    private func isAttemptScopedTransportCancel(
        _ error: Error,
        identity: StreamingSessionIdentity,
        attemptIdentifier: UInt64
    ) -> Bool {
        guard retryAdmissionOpen, isCurrentAttempt(identity, attemptIdentifier) else {
            return false
        }
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        if let failure = error as? StreamFailure, failure == .cancelled {
            return true
        }
        return false
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
        _ = eventKind
        _ = source
        return handleReviewSnapshot(
            text,
            identity: identity,
            packetIndex: packetIndex
        )
    }

    private func handleReviewSnapshot(
        _ text: String,
        identity: StreamingSessionIdentity,
        packetIndex: Int?
    ) -> Bool {
        guard isActive(identity),
              reviewSurfaceAuthority?.generation == identity.generation,
              !reviewTerminalPending else {
            return false
        }
        switch transcriptionReviewState {
        case .streaming, .sealing:
            break
        default:
            return false
        }

        if let packetIndex {
            guard responseOutputLedger.generation == identity.generation,
                  responseOutputLedger.isAdmissionOpen else {
                return false
            }
            switch responseOutputLedger.reserve(
                text: text,
                packetIndex: packetIndex,
                generation: identity.generation
            ) {
            case .owned:
                break
            case .historical, .staleGeneration, .sealed:
                return false
            }
        }

        // Empty/whitespace packets are acknowledged for replay ownership but do not
        // erase the latest usable opaque preview. Action-2 uses that preview as the
        // incomplete fallback when its authoritative final is contentless.
        guard !isContentless(text) else { return false }

        switch responseOutputLedger.claim(text: text, generation: identity.generation) {
        case .changed(let snapshot, _):
            let phase: ReviewReadOnlyPhase = captureClosed ? .sealing : .streaming
            transcriptionReviewState = phase == .streaming
                ? .streaming(preview: snapshot)
                : .sealing(preview: snapshot)
            renderReviewReadOnly(phase: phase, preview: snapshot)
        case .duplicate, .staleGeneration, .sealed:
            break
        }
        return false
    }

    private func handleFinal(
        _ text: String,
        identity: StreamingSessionIdentity,
        isTerminal: Bool,
        source: CurrentFocusHypothesisSource,
        packetIndex: Int?
    ) -> Bool {
        _ = source
        guard isTerminal else {
            return handleReviewSnapshot(
                text,
                identity: identity,
                packetIndex: packetIndex
            )
        }
        return handleReviewTerminal(text, identity: identity)
    }

    private func handleReviewTerminal(
        _ text: String,
        identity: StreamingSessionIdentity
    ) -> Bool {
        guard isActive(identity),
              reviewSurfaceAuthority?.generation == identity.generation,
              !reviewTerminalPending,
              captureClosed else {
            return true
        }
        switch transcriptionReviewState {
        case .streaming, .sealing:
            break
        default:
            return true
        }

        reviewTerminalPending = true
        cancelReviewReadOnlyPresentation()
        reviewSurfaceRevision &+= 1
        responseOutputLedger.closeAdmission()
        closeRetryAdmission()

        let finalIsContentless = isContentless(text)
        let latestSnapshot = responseOutputLedger.latestSnapshot
        let draft: String?
        let isPossiblyIncomplete: Bool
        if !finalIsContentless {
            draft = text
            isPossiblyIncomplete = false
        } else if !isContentless(latestSnapshot) {
            draft = latestSnapshot
            isPossiblyIncomplete = true
        } else {
            draft = nil
            isPossiblyIncomplete = false
        }

        guard let authority = reviewSurfaceAuthority else {
            return true
        }
        reviewDraftIsPossiblyIncomplete = isPossiblyIncomplete
        reviewDraftText = draft ?? ""
        let transitionID = UUID()
        reviewTransitionTask?.cancel()
        reviewTransitionID = transitionID
        reviewTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.awaitReviewRecorderBarrier(identity: identity) else {
                guard self.reviewTransitionID == transitionID else { return }
                self.reviewTransitionTask = nil
                self.reviewTransitionID = nil
                return
            }
            await self.finishReviewTransition(
                identity: identity,
                authority: authority,
                draft: draft,
                isPossiblyIncomplete: isPossiblyIncomplete,
                transitionID: transitionID
            )
        }
        return true
    }

    private func awaitReviewRecorderBarrier(identity: StreamingSessionIdentity) async -> Bool {
        guard isActive(identity) else { return false }
        if let barrier = pendingRecorderBarrier {
            await barrier.task.value
            guard isActive(identity) else { return false }
            _ = clearPendingRecorderBarrier(identifier: barrier.identifier)
        }
        return isActive(identity)
    }

    private func finishReviewTransition(
        identity: StreamingSessionIdentity,
        authority: ReviewSurfaceAuthority,
        draft: String?,
        isPossiblyIncomplete: Bool,
        transitionID: UUID
    ) async {
        guard isActive(identity),
              reviewSurfaceAuthority?.identifier == authority.identifier,
              reviewTerminalPending,
              reviewTransitionID == transitionID else {
            return
        }

        finishSpeechSessionForReview()

        guard let draft else {
            revokeReviewAuthority()
            return
        }

        if var updatedAuthority = reviewSurfaceAuthority {
            updatedAuthority.draft = ReviewDraft(
                text: draft,
                isPossiblyIncomplete: isPossiblyIncomplete,
                feedback: nil
            )
            updatedAuthority.revision &+= 1
            reviewSurfaceAuthority = updatedAuthority
        }
        setReviewDraftProjection(draft)
        reviewDraftIsPossiblyIncomplete = isPossiblyIncomplete
        reviewTerminalPending = false
        reviewSurfaceRevision &+= 1
        let reviewID = authority.identifier
        var draftCallbackRevision = reviewSurfaceRevision
        if var updatedAuthority = reviewSurfaceAuthority {
            updatedAuthority.readinessAttempt &+= 1
            updatedAuthority.revision &+= 1
            reviewSurfaceAuthority = updatedAuthority
        }
        let readinessAttempt = reviewSurfaceAuthority?.readinessAttempt ?? 0
        transcriptionReviewState = .editablePending(
            draft: draft,
            isPossiblyIncomplete: isPossiblyIncomplete,
            readiness: .preparing(attempt: readinessAttempt)
        )
        if let currentAuthority = reviewSurfaceAuthority {
            logReviewReadiness(
                event: "review_readiness_started",
                authority: currentAuthority,
                result: "started",
                predicate: nil
            )
        }
        let result = await renderEditableReviewSurface(
            onDraftChange: { [weak self] changedDraft in
                guard let self,
                      self.reviewSurfaceRevision == draftCallbackRevision else {
                    return
                }
                self.updateReviewDraft(changedDraft, reviewID: reviewID)
                draftCallbackRevision = self.reviewSurfaceRevision
            },
            onConfirm: { [weak self] in
                self?.confirmReviewDraft(
                    reviewID: reviewID,
                    callbackRevision: draftCallbackRevision
                )
            },
            onRetryReadiness: { [weak self] in
                self?.retryReviewReadiness(
                    reviewID: reviewID,
                    callbackRevision: draftCallbackRevision
                )
            },
            onDiscard: { [weak self] in
                self?.discardReviewDraft(
                    reviewID: reviewID,
                    callbackRevision: draftCallbackRevision
                )
            }
        )
        guard !Task.isCancelled,
              reviewSurfaceAuthority?.identifier == reviewID,
              reviewTransitionID == transitionID,
              let currentAuthority = reviewSurfaceAuthority,
              let currentDraft = currentAuthority.draft else {
            return
        }
        if let currentAuthority = reviewSurfaceAuthority {
            logReviewReadiness(
                result: result,
                authority: currentAuthority
            )
        }
        transcriptionReviewState = editableReviewState(
            for: result,
            draft: currentDraft,
            readinessAttempt: reviewSurfaceAuthority?.readinessAttempt ?? 0
        )
        reviewSurfacePresenter.renderDraft(
            state: transcriptionReviewState,
            onDraftChange: { [weak self] changedDraft in
                guard let self,
                      self.reviewSurfaceRevision == draftCallbackRevision else {
                    return
                }
                self.updateReviewDraft(changedDraft, reviewID: reviewID)
                draftCallbackRevision = self.reviewSurfaceRevision
            },
            onConfirm: { [weak self] in
                self?.confirmReviewDraft(
                    reviewID: reviewID,
                    callbackRevision: draftCallbackRevision
                )
            },
            onRetryReadiness: { [weak self] in
                self?.retryReviewReadiness(
                    reviewID: reviewID,
                    callbackRevision: draftCallbackRevision
                )
            },
            onDiscard: { [weak self] in
                self?.discardReviewDraft(
                    reviewID: reviewID,
                    callbackRevision: draftCallbackRevision
                )
            }
        )
        reviewTransitionTask = nil
        reviewTransitionID = nil
    }

    private func editableReviewState(
        for result: ReviewEditableTransitionResult,
        draft: ReviewDraft,
        readinessAttempt: UInt64
    ) -> TranscriptionReviewState {
        switch result {
        case .ready:
            return .editable(
                draft: draft.text,
                isPossiblyIncomplete: draft.isPossiblyIncomplete,
                feedback: draft.feedback
            )
        case .pending(let failure):
            return .editablePending(
                draft: draft.text,
                isPossiblyIncomplete: draft.isPossiblyIncomplete,
                readiness: .blocked(
                    attempt: readinessAttempt,
                    failure: failure
                ),
                feedback: draft.feedback
            )
        }
    }

    private func renderEditableReviewSurface(
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor () -> Void,
        onRetryReadiness: @escaping @MainActor () -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) async -> ReviewEditableTransitionResult {
        reviewSurfacePresenter.renderDraft(
            state: transcriptionReviewState,
            onDraftChange: onDraftChange,
            onConfirm: onConfirm,
            onRetryReadiness: onRetryReadiness,
            onDiscard: onDiscard
        )
        return await reviewSurfacePresenter.requestEditableReadiness()
    }

    private func updateReviewDraft(_ draft: String, reviewID: UUID) {
        guard var authority = reviewSurfaceAuthority,
              authority.identifier == reviewID,
              !reviewConfirmationInFlight,
              let existingDraft = authority.draft else {
            return
        }
        authority.draft = ReviewDraft(
            text: draft,
            isPossiblyIncomplete: existingDraft.isPossiblyIncomplete,
            feedback: nil
        )
        authority.revision &+= 1
        reviewSurfaceAuthority = authority
        reviewSurfaceRevision &+= 1
        setReviewDraftProjection(draft)
        switch transcriptionReviewState {
        case .editable(_, let isPossiblyIncomplete, _):
            transcriptionReviewState = .editable(
                draft: draft,
                isPossiblyIncomplete: isPossiblyIncomplete,
                feedback: nil
            )
        case .editablePending(_, let isPossiblyIncomplete, let readiness, _):
            transcriptionReviewState = .editablePending(
                draft: draft,
                isPossiblyIncomplete: isPossiblyIncomplete,
                readiness: readiness,
                feedback: nil
            )
        default:
            break
        }
    }

    private func setReviewDraftProjection(_ draft: String) {
        projectingReviewDraft = true
        reviewDraftText = draft
        projectingReviewDraft = false
    }

    private func retryReviewReadiness(
        reviewID: UUID,
        callbackRevision: UInt64? = nil
    ) {
        guard var authority = reviewSurfaceAuthority,
              authority.identifier == reviewID,
              callbackRevision.map({ $0 == reviewSurfaceRevision }) ?? true,
              let draft = authority.draft,
              case .editablePending = transcriptionReviewState,
              !reviewConfirmationInFlight else {
            return
        }

        authority.readinessAttempt &+= 1
        authority.revision &+= 1
        reviewSurfaceAuthority = authority
        reviewSurfaceRevision &+= 1
        transcriptionReviewState = .editablePending(
            draft: draft.text,
            isPossiblyIncomplete: draft.isPossiblyIncomplete,
            readiness: .preparing(attempt: authority.readinessAttempt),
            feedback: draft.feedback
        )
        logReviewReadiness(
            event: "review_readiness_started",
            authority: authority,
            result: "started",
            predicate: nil
        )
        var presentationRevision = reviewSurfaceRevision

        let transitionID = UUID()
        reviewTransitionID = transitionID
        reviewTransitionTask?.cancel()
        reviewTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.renderEditableReviewSurface(
                onDraftChange: { [weak self] changedDraft in
                    guard let self,
                          self.reviewSurfaceRevision == presentationRevision else {
                        return
                    }
                    self.updateReviewDraft(changedDraft, reviewID: reviewID)
                    presentationRevision = self.reviewSurfaceRevision
                },
                onConfirm: { [weak self] in
                    self?.confirmReviewDraft(
                        reviewID: reviewID,
                        callbackRevision: presentationRevision
                    )
                },
                onRetryReadiness: { [weak self] in
                    self?.retryReviewReadiness(
                        reviewID: reviewID,
                        callbackRevision: presentationRevision
                    )
                },
                onDiscard: { [weak self] in
                    self?.discardReviewDraft(
                        reviewID: reviewID,
                        callbackRevision: presentationRevision
                    )
                }
            )
            guard !Task.isCancelled,
                  self.reviewSurfaceAuthority?.identifier == reviewID,
                  self.reviewTransitionID == transitionID,
                  let currentDraft = self.reviewSurfaceAuthority?.draft else {
                return
            }

            if let currentAuthority = self.reviewSurfaceAuthority {
                self.logReviewReadiness(
                    result: result,
                    authority: currentAuthority
                )
            }

            switch result {
            case .ready:
                self.transcriptionReviewState = .editable(
                    draft: currentDraft.text,
                    isPossiblyIncomplete: currentDraft.isPossiblyIncomplete,
                    feedback: currentDraft.feedback
                )
                self.reviewSurfacePresenter.renderDraft(
                    state: self.transcriptionReviewState,
                    onDraftChange: { [weak self] changedDraft in
                        guard let self,
                              self.reviewSurfaceRevision == presentationRevision else {
                            return
                        }
                        self.updateReviewDraft(changedDraft, reviewID: reviewID)
                        presentationRevision = self.reviewSurfaceRevision
                    },
                    onConfirm: { [weak self] in
                        self?.confirmReviewDraft(
                            reviewID: reviewID,
                            callbackRevision: presentationRevision
                        )
                    },
                    onRetryReadiness: { [weak self] in
                        self?.retryReviewReadiness(
                            reviewID: reviewID,
                            callbackRevision: presentationRevision
                        )
                    },
                    onDiscard: { [weak self] in
                        self?.discardReviewDraft(
                            reviewID: reviewID,
                            callbackRevision: presentationRevision
                        )
                    }
                )
            case .pending(let failure):
                self.transcriptionReviewState = .editablePending(
                    draft: currentDraft.text,
                    isPossiblyIncomplete: currentDraft.isPossiblyIncomplete,
                    readiness: .blocked(
                        attempt: self.reviewSurfaceAuthority?.readinessAttempt ?? 0,
                        failure: failure
                    ),
                    feedback: currentDraft.feedback
                )
                self.reviewSurfacePresenter.renderDraft(
                    state: self.transcriptionReviewState,
                    onDraftChange: { [weak self] changedDraft in
                        guard let self,
                              self.reviewSurfaceRevision == presentationRevision else {
                            return
                        }
                        self.updateReviewDraft(changedDraft, reviewID: reviewID)
                        presentationRevision = self.reviewSurfaceRevision
                    },
                    onConfirm: { [weak self] in
                        self?.confirmReviewDraft(
                            reviewID: reviewID,
                            callbackRevision: presentationRevision
                        )
                    },
                    onRetryReadiness: { [weak self] in
                        self?.retryReviewReadiness(
                            reviewID: reviewID,
                            callbackRevision: presentationRevision
                        )
                    },
                    onDiscard: { [weak self] in
                        self?.discardReviewDraft(
                            reviewID: reviewID,
                            callbackRevision: presentationRevision
                        )
                    }
                )
            }
            self.reviewTransitionTask = nil
            self.reviewTransitionID = nil
        }
    }

    func confirmReviewDraft() {
        guard let reviewID = reviewSurfaceAuthority?.identifier else { return }
        confirmReviewDraft(reviewID: reviewID)
    }

    private func confirmReviewDraft(
        reviewID: UUID,
        callbackRevision: UInt64? = nil
    ) {
        guard var authority = reviewSurfaceAuthority,
              authority.identifier == reviewID,
              callbackRevision.map({ $0 == reviewSurfaceRevision }) ?? true,
              case .editable(_, let isPossiblyIncomplete, _) = transcriptionReviewState,
              let draft = authority.draft,
              !reviewConfirmationInFlight else {
            return
        }
        let frozenText = reviewDraftText
        guard !isContentless(frozenText) else { return }

        authority.draft = ReviewDraft(
            text: frozenText,
            isPossiblyIncomplete: isPossiblyIncomplete,
            feedback: nil
        )
        authority.confirmationAttempt &+= 1
        authority.revision &+= 1
        reviewSurfaceAuthority = authority
        let confirmationAttempt = authority.confirmationAttempt
        reviewConfirmationInFlight = true
        transcriptionReviewState = .confirming(
            draft: frozenText,
            isPossiblyIncomplete: draft.isPossiblyIncomplete
        )
        cancelReviewReadOnlyPresentation()
        reviewTransitionTask?.cancel()
        reviewTransitionTask = nil
        reviewTransitionID = nil
        reviewSurfaceRevision &+= 1
        reviewSurfacePresenter.renderDraft(
            state: transcriptionReviewState,
            onDraftChange: { _ in },
            onConfirm: {},
            onRetryReadiness: {},
            onDiscard: { [weak self] in
                self?.discardReviewDraft(reviewID: reviewID)
            }
        )

        let delivery = reviewDestinationDelivery
        reviewDeliveryTask = Task { @MainActor [weak self] in
            let result = await delivery.deliver(frozenText, to: authority.destination)
            self?.completeReviewDelivery(
                reviewID: reviewID,
                confirmationAttempt: confirmationAttempt,
                frozenText: frozenText,
                result: result
            )
        }
    }

    func discardReviewDraft() {
        guard let reviewID = reviewSurfaceAuthority?.identifier else { return }
        discardReviewDraft(reviewID: reviewID)
    }

    private func discardReviewDraft(
        reviewID: UUID,
        callbackRevision: UInt64? = nil
    ) {
        guard reviewSurfaceAuthority?.identifier == reviewID,
              callbackRevision.map({ $0 == reviewSurfaceRevision }) ?? true,
              isReviewDraftState else {
            return
        }
        revokeReviewAuthority()
        hotKeyService.resetToIdle()
    }

    private func completeReviewDelivery(
        reviewID: UUID,
        confirmationAttempt: UInt64,
        frozenText: String,
        result: ReviewDeliveryResult
    ) {
        guard reviewSurfaceAuthority?.identifier == reviewID,
              reviewSurfaceAuthority?.confirmationAttempt == confirmationAttempt,
              reviewConfirmationInFlight else {
            return
        }

        reviewDeliveryTask = nil
        switch result {
        case .inserted:
            revokeReviewAuthority()
        case .activationFailed, .identityChanged, .destinationInvalid,
             .securityRejected, .unsafeText, .deliveryFailed, .deliveryUncertain, .cancelled:
            guard var authority = reviewSurfaceAuthority,
                  authority.identifier == reviewID,
                  let draft = authority.draft else {
                return
            }
            let feedback = reviewFeedback(for: result)
            authority.draft = ReviewDraft(
                text: frozenText,
                isPossiblyIncomplete: draft.isPossiblyIncomplete,
                feedback: feedback
            )
            authority.revision &+= 1
            reviewSurfaceAuthority = authority
            reviewConfirmationInFlight = false
            setReviewDraftProjection(frozenText)
            reviewSurfaceRevision &+= 1
            hotKeyService.resetToIdle()
            transcriptionReviewState = .editablePending(
                draft: frozenText,
                isPossiblyIncomplete: draft.isPossiblyIncomplete,
                readiness: .preparing(attempt: authority.readinessAttempt),
                feedback: feedback
            )
            retryReviewReadiness(reviewID: reviewID)
            return
        }
        hotKeyService.resetToIdle()
    }

    private var isReviewDraftState: Bool {
        switch transcriptionReviewState {
        case .editable, .editablePending:
            return true
        case .idle, .streaming, .sealing, .confirming:
            return false
        }
    }

    private func reviewFeedback(for result: ReviewDeliveryResult) -> ReviewDraftFeedback {
        switch result {
        case .activationFailed:
            return .activationFailed
        case .identityChanged, .destinationInvalid:
            return .destinationChanged
        case .securityRejected:
            return .securityRejected
        case .unsafeText:
            return .unsafeText
        case .deliveryUncertain:
            return .deliveryUncertain
        case .cancelled:
            return .deliveryCancelled
        case .deliveryFailed:
            return .deliveryFailed
        case .inserted:
            return .deliveryFailed
        }
    }

    private func logReviewReadiness(
        result: ReviewEditableTransitionResult,
        authority: ReviewSurfaceAuthority
    ) {
        switch result {
        case .ready:
            logReviewReadiness(
                event: "review_readiness_ready",
                authority: authority,
                result: "ready",
                predicate: nil
            )
        case .pending(let failure):
            logReviewReadiness(
                event: failure.isCancellation
                    ? "review_readiness_cancelled"
                    : "review_readiness_pending",
                authority: authority,
                result: failure.telemetryResult,
                predicate: failure.telemetryPredicate
            )
        }
    }

    private func logReviewReadiness(
        event: String,
        authority: ReviewSurfaceAuthority,
        result: String,
        predicate: String?
    ) {
        let predicateName = predicate ?? "none"
        logger.info(
            "\(event, privacy: .public) generation=\(authority.generation, privacy: .public) attempt=\(authority.readinessAttempt, privacy: .public) result=\(result, privacy: .public) predicate=\(predicateName, privacy: .public)"
        )
    }

    private func finishSpeechSessionForReview() {
        cancelReviewReadOnlyPresentation()
        postReleaseDrainTask?.cancel()
        postReleaseDrainTask = nil
        postReleaseDrainDeadline = nil
        invalidateActiveIdentityAndCursor()
        captureDrainTask?.cancel()
        captureDrainTask = nil
        consumerTask?.cancel()
        consumerTask = nil
        sealingTask?.cancel()
        sealingTask = nil
        activeIngress = nil
        activeStreamingSession = nil
        holdPacketJournal.cancelWaiters()
        responseOutputLedger.reset()
        retryFailureStreak = 0
        activeAttemptIdentifier = nil
        nextAttemptIdentifier = 0
        currentAttemptCancellationTask = nil
        streamingAttemptPhase = .idle
        retryAdmissionOpen = false
        captureClosed = false
        acceptedPacket = false
        outputPreservationState = .none
        stopMaxDurationTimer()
        hideOverlay()
        status = .idle
        hotKeyService.resetToIdle()
    }

    private func revokeReviewAuthority() {
        let hadAuthority = reviewSurfaceAuthority != nil ||
            transcriptionReviewState != .idle
        cancelReviewReadOnlyPresentation()
        reviewSurfaceRevision &+= 1
        reviewTransitionID = nil
        reviewTransitionTask?.cancel()
        reviewTransitionTask = nil
        reviewDeliveryTask?.cancel()
        reviewDeliveryTask = nil
        reviewSurfaceAuthority = nil
        reviewTerminalPending = false
        reviewConfirmationInFlight = false
        reviewDraftIsPossiblyIncomplete = false
        setReviewDraftProjection("")
        transcriptionReviewState = .idle
        if hadAuthority {
            reviewSurfacePresenter.dismiss()
        }
    }

    private func handleTerminalEvent(
        _ event: StreamingRecognitionEvent,
        identity: StreamingSessionIdentity,
        message: String?,
        reportsError: Bool
    ) -> Bool {
        _ = event
        _ = identity
        Task { @MainActor [weak self] in
            await self?.terminateAbnormally(message: message, reportsError: reportsError)
        }
        return true
    }

    private func beginSealing(identity: StreamingSessionIdentity) {
        guard isActive(identity), !captureClosed else { return }
        captureClosed = true
        stopMaxDurationTimer()
        status = .sealing
        overlayPresenter.update(status: .sealing)
        if let authority = reviewSurfaceAuthority,
           !reviewTerminalPending {
            let preview = responseOutputLedger.latestSnapshot
            transcriptionReviewState = .sealing(preview: preview)
            renderReviewReadOnly(
                phase: .sealing,
                preview: preview,
                authority: authority
            )
        }
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
        postReleaseDrainDeadline = streamingMonotonicNow().advanced(
            by: .nanoseconds(Int64(timeout))
        )
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
        let preservationState = outputPreservationState
        let session = activeStreamingSession
        let consumer = consumerTask
        let captureDrain = captureDrainTask

        responseOutputLedger.closeAdmission()
        closeRetryAdmission()
        postReleaseDrainTask = nil
        postReleaseDrainDeadline = nil
        invalidateActiveIdentityAndCursor()
        revokeReviewAuthority()
        activeIngress?.fail(.cancelled)
        holdPacketJournal.cancelWaiters()
        captureDrainTask = nil
        consumerTask = nil
        sealingTask = nil
        pendingRecorderBarrier = nil
        clearInteractionReferences()
        stopMaxDurationTimer()
        captureDrain?.cancel()
        consumer?.cancel()
        hideOverlay()
        audioRecorder.forceCleanup()

        if let session {
            Task {
                await session.cancel()
            }
        }
        switch preservationState {
        case .committedSafe:
            publishCompletionFeedback(.emptyFinalPreservedPartial)
        case .deliveryUncertain:
            publishCompletionFeedback(.provisionalOutputPreserved)
        case .none:
            publishAbnormalTerminalState(
                message: streamingFailureErrorMessage,
                reportsError: true
            )
        }
        logger.warning(
            """
            Streaming drain expired generation=\(identity.generation, privacy: .public) \
            preservation=\(String(describing: preservationState), privacy: .public)
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
        invalidateActiveIdentityAndCursor()
        captureDrainTask = nil
        consumerTask = nil
        sealingTask = nil
        activeIngress = nil
        activeStreamingSession = nil
        holdPacketJournal.cancelWaiters()
        responseOutputLedger.reset()
        retryFailureStreak = 0
        activeAttemptIdentifier = nil
        nextAttemptIdentifier = 0
        currentAttemptCancellationTask = nil
        streamingAttemptPhase = .idle
        captureClosed = false
        acceptedPacket = false
        outputPreservationState = .none
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
        let captureDrain = captureDrainTask
        let barrier = pendingRecorderBarrier

        closeRetryAdmission()
        postReleaseDrainTask?.cancel()
        postReleaseDrainTask = nil
        postReleaseDrainDeadline = nil
        invalidateActiveIdentityAndCursor()
        revokeReviewAuthority()
        ingress?.fail(.cancelled)
        holdPacketJournal.cancelWaiters()
        captureDrainTask = nil
        consumerTask = nil
        sealingTask = nil
        clearInteractionReferences()
        stopMaxDurationTimer()
        captureDrain?.cancel()
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

    private func invalidateActiveIdentityAndCursor() {
        activeSessionIdentity = nil
    }

    private func clearInteractionReferences() {
        activeIngress = nil
        activeStreamingSession = nil
        holdPacketJournal.cancelWaiters()
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
        outputPreservationState = .none
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
        holdPacketJournal.cancelWaiters()
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
        if activeSessionIdentity != nil || reviewSurfaceAuthority != nil {
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
            if reviewSurfaceAuthority != nil {
                if activeSessionIdentity != nil {
                    Task { @MainActor [weak self] in
                        await self?.terminateAbnormally(
                            message: hotKeyMonitoringErrorMessage,
                            reportsError: true
                        )
                    }
                } else {
                    // A monitoring failure after capture has already yielded a
                    // draft is an ambient security/readiness change.  The
                    // draft remains the coordinator's authority until the
                    // user explicitly edits, retries, sends, or discards it.
                    preserveReviewDraftAfterAmbientSecurityChange()
                }
            }
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

    // The settings screen intentionally persists all six editable preferences in one call.
    // swiftlint:disable:next function_parameter_count
    func updateSettings(
        appId: String,
        appSecret: String,
        autoInsert: Bool,
        playSound: Bool,
        launchAtLogin: Bool,
        reviewBeforeInsert: Bool
    ) {
        settings.appId = appId
        settings.appSecret = appSecret
        settings.autoInsert = autoInsert
        settings.playSound = playSound
        settings.launchAtLogin = launchAtLogin
        settings.reviewBeforeInsert = reviewBeforeInsert
        saveSettings()
    }

    func cleanup() {
        logger.info("MainViewModel cleanup called")
        closeRetryAdmission()
        postReleaseDrainTask?.cancel()
        postReleaseDrainTask = nil
        postReleaseDrainDeadline = nil
        invalidateActiveIdentityAndCursor()
        revokeReviewAuthority()
        activeIngress?.fail(.cancelled)
        holdPacketJournal.cancelWaiters()
        captureDrainTask?.cancel()
        captureDrainTask = nil
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
