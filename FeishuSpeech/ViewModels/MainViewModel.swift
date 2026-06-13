import Foundation
import Combine
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "ViewModel")

let maxRecordingDuration: TimeInterval = 60.0
let errorRecoveryDelay: TimeInterval = 3.0
private let maxConsecutiveFailures = 3
private let hotKeyMonitoringErrorMessage = "热键不可用，请检查辅助功能权限"

@MainActor
class MainViewModel: ObservableObject {
    @Published var status: RecordingState = .idle
    @Published var settings: AppSettings = AppSettings.load()
    /// Transient message shown when speech recognition returns an empty result.
    /// Set to a non-nil string to trigger feedback; callers should observe this
    /// and clear it after display.  `nil` means no pending feedback.
    @Published var overlayMessage: String?

    private let hotKeyService = HotKeyService.shared
    private let audioRecorder: AudioRecorder
    private let permissionManager = PermissionManager.shared
    private let overlayController = OverlayWindowController.shared
    private var cancellables = Set<AnyCancellable>()
    // Dedicated cancellable for the $state subscription — assigned in
    // startHotKeyMonitoring() and nilled in stopHotKeyMonitoring().
    // Using a standalone optional (not stored in `cancellables`) ensures
    // at most one live $state subscriber exists at any time; reassigning
    // implicitly cancels any prior value (fixes subscription leak — issue #8).
    var stateCancellable: AnyCancellable?
    private var isMonitoring = false
    private var recordingStartTime: Date?
    private var maxDurationTimer: Timer?
    private var consecutiveFailureCount = 0
    private var isShowingHotKeyMonitoringError = false

    var statusText: String {
        status.text
    }

    init(audioRecorder: AudioRecorder = AudioRecorder()) {
        self.audioRecorder = audioRecorder
        logger.info("MainViewModel init")
        audioRecorder.forceCleanup()
        setupPermissionObserver()
        setupErrorRecovery()
    }

    private func setupPermissionObserver() {
        permissionManager.$allPermissionsGranted
            .removeDuplicates()
            .sink { [weak self] granted in
                logger.info("All permissions granted: \(granted)")
                if granted {
                    self?.startHotKeyMonitoring()
                } else {
                    self?.stopHotKeyMonitoring()
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
            .sink { [weak self] monState in
                logger.info("HotKey monitoringState changed: \(String(describing: monState))")
                self?.handleMonitoringState(monState)
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

    private func handleHotKeyState(_ state: HotKeyState) {
        switch state {
        case .idle:
            handleIdleState()
        case .pending:
            break
        case .recording:
            handleRecordingState()
        case .transcribing:
            handleTranscribingState()
        case .cancelled(let reason):
            handleCancelledState(reason: reason)
        case .error(let message):
            handleErrorState(message: message)
        }
    }

    private func handleIdleState() {
        hideOverlay()
        status = .idle
        stopMaxDurationTimer()
    }

    private func handleRecordingState() {
        guard canStartRecording() else { return }
        showOverlay()
        guard startRecordingInternal() else {
            hotKeyService.setError("无法启动录音")
            return
        }
        startMaxDurationTimer()
    }

    private func handleTranscribingState() {
        stopRecordingAndTranscribe()
    }

    private func handleCancelledState(reason: CancelReason) {
        logger.info("Recording cancelled: \(reason.description)")
        hideOverlay()
        audioRecorder.forceCleanup()
        status = .idle
        stopMaxDurationTimer()
    }

    private func handleErrorState(message: String) {
        logger.error("Error state: \(message)")
        hideOverlay()
        audioRecorder.forceCleanup()
        status = .error(message)
        stopMaxDurationTimer()
    }

    private func handleMonitoringState(_ monState: MonitoringState) {
        switch monState {
        case .failed:
            logger.error("HotKey tap failed: \(String(describing: monState))")
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
    func handleMonitoringStateForTesting(_ monState: MonitoringState) {
        handleMonitoringState(monState)
    }
    #endif

    private func canStartRecording() -> Bool {
        guard settings.isConfigured else {
            hotKeyService.setError("请先配置 App ID 和 Secret")
            return false
        }

        guard permissionManager.allPermissionsGranted else {
            hotKeyService.setError("请先授权所有权限")
            return false
        }

        guard AudioRecorder.hasInputDevice else {
            hotKeyService.setError("未检测到麦克风")
            return false
        }

        return true
    }

    private func startRecordingInternal() -> Bool {
        guard canStartRecording() else { return false }

        logger.info("Starting recording")
        status = .recording
        recordingStartTime = Date()

        let success = audioRecorder.startRecording()

        if !success {
            logger.error("AudioRecorder failed to start")
            return false
        }

        if settings.playSound {
            playSound(named: "start")
        }

        return true
    }

    private func stopRecordingAndTranscribe() {
        guard audioRecorder.isRecording else {
            logger.info("stopRecordingAndTranscribe called but not recording — ignoring")
            return
        }
        logger.info("Stopping recording")
        status = .transcribing
        stopMaxDurationTimer()

        let audioData = audioRecorder.stopRecording()
        logger.info("Audio data size: \(audioData.count) bytes")

        if settings.playSound {
            playSound(named: "stop")
        }

        hideOverlay()

        Task {
            await transcribeAudio(audioData)
        }
    }

    /// Handles a successful recognition result from the API.
    ///
    /// Extracted from `transcribeAudio` to allow direct unit testing of the
    /// empty-result feedback path without requiring a live API call.
    /// When `text` is empty or whitespace-only, `overlayMessage` is set to
    /// "未识别到内容" so the UI can display transient feedback (issue #14).
    func handleRecognitionResult(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            logger.info("Recognition returned empty result — showing feedback")
            overlayMessage = "未识别到内容"
        } else {
            if settings.autoInsert {
                TextInputSimulator.insertTextViaPasteboard(text)
            }
        }
    }

    private func transcribeAudio(_ audioData: Data) async {
        do {
            let text = try await withTimeout(seconds: 30) {
                try await FeishuAPIService.shared.recognizeSpeech(
                    audioData: audioData,
                    appId: self.settings.appId,
                    appSecret: self.settings.appSecret
                )
            }

            logger.info("Recognition result: \(text)")
            consecutiveFailureCount = 0

            handleRecognitionResult(text)

            status = .idle
            hotKeyService.resetToIdle()

        } catch {
            logger.error("Recognition error: \(error.localizedDescription)")
            consecutiveFailureCount += 1

            if consecutiveFailureCount >= maxConsecutiveFailures {
                logger.warning("Consecutive failures reached \(self.consecutiveFailureCount), auto-resetting service")
                await FeishuAPIService.shared.resetState()
                consecutiveFailureCount = 0
            }

            if hotKeyService.state.isActive {
                logger.info("Discarding stale transcription error - new session active")
                return
            }

            status = .error(error.localizedDescription)
            hotKeyService.setError(error.localizedDescription)
        }
    }

    func resetService() async {
        logger.info("Manual service reset requested")
        audioRecorder.forceCleanup()
        await FeishuAPIService.shared.resetState()
        consecutiveFailureCount = 0
        status = .idle
        hotKeyService.resetToIdle()
    }

    private func showOverlay() {
        overlayController.show()
    }

    private func hideOverlay() {
        overlayController.hide()
    }

    private func startMaxDurationTimer() {
        maxDurationTimer?.invalidate()
        let timer = Timer(timeInterval: maxRecordingDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleMaxDurationReached()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        maxDurationTimer = timer
    }

    private func stopMaxDurationTimer() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        recordingStartTime = nil
    }

    private func handleMaxDurationReached() {
        logger.warning("Max recording duration reached")
        guard audioRecorder.isRecording else { return }
        hotKeyService.forceTranscribing()
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

    func cleanup() {
        logger.info("MainViewModel cleanup called")
        audioRecorder.forceCleanup()
        stopHotKeyMonitoring()
        stopMaxDurationTimer()
    }
}

private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }

        guard let result = try await group.next() else {
            throw TimeoutError()
        }

        group.cancelAll()
        return result
    }
}

struct TimeoutError: LocalizedError {
    var errorDescription: String? {
        return "操作超时"
    }
}
