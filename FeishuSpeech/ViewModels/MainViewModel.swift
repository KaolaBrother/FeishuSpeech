import Foundation
import Combine
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "ViewModel")

@MainActor
class MainViewModel: ObservableObject {
    @Published var status: RecordingState = .idle
    @Published var settings: AppSettings = AppSettings.load()
    
    private let hotKeyService = HotKeyService.shared
    private let audioRecorder = AudioRecorder()
    private let permissionManager = PermissionManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var isMonitoring = false
    
    var statusText: String {
        status.text
    }
    
    init() {
        logger.info("MainViewModel init")
        setupPermissionObserver()
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
        logger.info("Starting hot key monitoring")
        
        hotKeyService.$isFnKeyPressed
            .removeDuplicates()
            .sink { [weak self] isPressed in
                logger.info("Fn key pressed changed: \(isPressed)")
                self?.handleFnKeyState(isPressed: isPressed)
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
    
    private func handleFnKeyState(isPressed: Bool) {
        guard permissionManager.allPermissionsGranted else { return }
        
        let recording = self.audioRecorder.isRecording
        logger.info("handleFnKeyState: \(isPressed), isRecording: \(recording)")
        
        if isPressed && !recording {
            startRecording()
        } else if !isPressed && recording {
            stopAndTranscribe()
        }
    }
    
    private func startRecording() {
        guard settings.isConfigured else {
            logger.warning("Settings not configured")
            status = .error("请先配置 App ID 和 Secret")
            return
        }
        
        guard permissionManager.allPermissionsGranted else {
            logger.warning("Permissions not granted")
            status = .error("请先授权所有权限")
            return
        }
        
        logger.info("Starting recording")
        status = .recording
        audioRecorder.startRecording()
        
        if settings.playSound {
            playSound(named: "start")
        }
    }
    
    private func stopAndTranscribe() {
        logger.info("Stopping recording")
        status = .transcribing
        
        let audioData = audioRecorder.stopRecording()
        logger.info("Audio data size: \(audioData.count) bytes")
        
        if settings.playSound {
            playSound(named: "stop")
        }
        
        Task {
            do {
                let text = try await FeishuAPIService.shared.recognizeSpeech(
                    audioData: audioData,
                    appId: settings.appId,
                    appSecret: settings.appSecret
                )
                
                logger.info("Recognition result: \(text)")
                
                if settings.autoInsert && !text.isEmpty {
                    TextInputSimulator.insertTextViaPasteboard(text)
                }
                
                status = .idle
            } catch {
                logger.error("Recognition error: \(error.localizedDescription)")
                status = .error(error.localizedDescription)
            }
        }
    }
    
    private func playSound(named name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
    
    func saveSettings() {
        settings.save()
    }
}
