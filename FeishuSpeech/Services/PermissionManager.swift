import AppKit
import AVFoundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "Permission")

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var accessibilityGranted = false
    @Published var microphoneGranted = false
    @Published var isChecking = true
    @Published var allPermissionsGranted = false
    
    private init() {}
    
    func checkAllPermissions() async {
        logger.info("Checking all permissions...")
        isChecking = true
        
        accessibilityGranted = AXIsProcessTrusted()
        logger.info("Accessibility: \(self.accessibilityGranted)")
        
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .authorized:
            microphoneGranted = true
        case .notDetermined:
            microphoneGranted = await requestMicrophonePermission()
        case .denied, .restricted:
            microphoneGranted = false
        @unknown default:
            microphoneGranted = false
        }
        logger.info("Microphone: \(self.microphoneGranted)")
        
        isChecking = false
        updateAllPermissionsGranted()
        
        if !accessibilityGranted {
            requestAccessibilityPermission()
        }
    }
    
    private func requestMicrophonePermission() async -> Bool {
        logger.info("Requesting microphone permission...")
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                logger.info("Microphone permission result: \(granted)")
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func requestAccessibilityPermission() {
        logger.info("Requesting accessibility permission...")
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    
    func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
    
    func refreshAccessibilityStatus() {
        accessibilityGranted = AXIsProcessTrusted()
        logger.info("Refreshed accessibility status: \(self.accessibilityGranted)")
        updateAllPermissionsGranted()
    }
    
    private func updateAllPermissionsGranted() {
        allPermissionsGranted = accessibilityGranted && microphoneGranted
    }
}
