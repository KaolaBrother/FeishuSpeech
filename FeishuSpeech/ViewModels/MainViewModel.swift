import Foundation
import Combine
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "ViewModel")

let maxRecordingDuration: TimeInterval = 60.0
let errorRecoveryDelay: TimeInterval = 3.0

@MainActor
class MainViewModel: ObservableObject {
    @Published var status: RecordingState = .idle
    @Published var settings: AppSettings = AppSettings.load()
    
    private let hotKeyService = HotKeyService.shared
    private let audioRecorder = AudioRecorder()
    private let permissionManager = PermissionManager.shared
    private let overlayController = OverlayWindowController.shared
    private var cancellables = Set<AnyCancellable>()
    private var isMonitoring = false
    private var recordingStartTime: Date?
    private var maxDurationTimer: Timer?
    
    var statusText: String {
        status.text
    }
    
    init() {
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
    
    private func startHotKeyMonitoring() {
        guard !isMonitoring else { return }
        logger.info("Starting hot key monitoring with state machine")
        
        hotKeyService.$state
            .sink { [weak self] state in
                logger.info("HotKey state changed: \(String(describing: state))")
                self?.handleHotKeyState(state)
            }
            .store(in: &cancellables)
        
        hotKeyService.startMonitoring()
        isMonitoring = true
    }
    
    private func stopHotKeyMonitoring() {
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
        status = .idle
        stopMaxDurationTimer()
    }
    
    private func handleErrorState(message: String) {
        logger.error("Error state: \(message)")
        hideOverlay()
        status = .error(message)
        stopMaxDurationTimer()
    }
    
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
            
            if settings.autoInsert && !text.isEmpty {
                TextInputSimulator.insertTextViaPasteboard(text)
            }
            
            status = .idle
            hotKeyService.resetToIdle()
            
        } catch {
            logger.error("Recognition error: \(error.localizedDescription)")
            status = .error(error.localizedDescription)
            hotKeyService.setError(error.localizedDescription)
        }
    }
    
    private func showOverlay() {
        overlayController.show()
    }
    
    private func hideOverlay() {
        overlayController.hide()
    }
    
    private func startMaxDurationTimer() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maxRecordingDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleMaxDurationReached()
            }
        }
    }
    
    private func stopMaxDurationTimer() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        recordingStartTime = nil
    }
    
    private func handleMaxDurationReached() {
        logger.warning("Max recording duration reached")
        
        if audioRecorder.isRecording {
            stopRecordingAndTranscribe()
        }
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
        settings.save()
    }
    
    func cleanup() {
        logger.info("MainViewModel cleanup called")
        audioRecorder.forceCleanup()
        hotKeyService.stopMonitoring()
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
