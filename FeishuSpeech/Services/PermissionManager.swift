import AppKit
import AVFoundation
import Carbon
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
    @Published var secureInputEnabled: Bool = false

    private var microphoneAuthorizationStatusProvider: () -> AVAuthorizationStatus = PermissionManager.liveMicrophoneAuthorizationStatus

    private init() {}
    
    func checkAllPermissions() async {
        logger.info("Checking all permissions...")
        isChecking = true
        
        accessibilityGranted = AXIsProcessTrusted()
        logger.info("Accessibility: \(self.accessibilityGranted)")
        
        microphoneGranted = await resolveMicrophonePermission(for: microphoneAuthorizationStatusProvider())
        logger.info("Microphone: \(self.microphoneGranted)")
        
        isChecking = false
        updateAllPermissionsGranted()
        
        if !accessibilityGranted {
            requestAccessibilityPermission()
        }
    }

    func refreshMicrophoneStatus() {
        microphoneGranted = microphoneGranted(for: microphoneAuthorizationStatusProvider())
        logger.info("Refreshed microphone status: \(self.microphoneGranted)")
        updateAllPermissionsGranted()
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

    private func resolveMicrophonePermission(for status: AVAuthorizationStatus) async -> Bool {
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await requestMicrophonePermission()
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func microphoneGranted(for status: AVAuthorizationStatus) -> Bool {
        switch status {
        case .authorized:
            return true
        case .notDetermined, .denied, .restricted:
            return false
        @unknown default:
            return false
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

    func refreshSecureInputStatus() {
        let current = IsSecureEventInputEnabled()
        if secureInputEnabled != current {
            secureInputEnabled = current
            logger.info("Secure keyboard input changed: \(current)")
        }
    }

    // MARK: - Test support

    /// Injects a synthetic `secureInputEnabled` value for unit testing only.
    /// This bypasses the live `IsSecureEventInputEnabled()` query so tests
    /// can exercise the Combine publisher without needing a real password field.
#if DEBUG
    func simulateSecureInputState(_ enabled: Bool) {
        secureInputEnabled = enabled
    }

    func setMicrophoneAuthorizationStatusProviderForTesting(_ provider: @escaping () -> AVAuthorizationStatus) {
        microphoneAuthorizationStatusProvider = provider
    }

    func resetMicrophoneAuthorizationStatusProviderForTesting() {
        microphoneAuthorizationStatusProvider = Self.liveMicrophoneAuthorizationStatus
    }

    func resetStateForTesting() {
        microphoneAuthorizationStatusProvider = Self.liveMicrophoneAuthorizationStatus
        accessibilityGranted = false
        microphoneGranted = false
        isChecking = true
        allPermissionsGranted = false
        secureInputEnabled = false
    }
#endif

    private func updateAllPermissionsGranted() {
        allPermissionsGranted = accessibilityGranted && microphoneGranted
    }

    private static func liveMicrophoneAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }
}
