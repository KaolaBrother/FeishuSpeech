import AppKit
import SwiftUI
import Combine
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate {
    private var permissionCheckTimer: AnyCancellable?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        Task {
            await PermissionManager.shared.checkAllPermissions()
        }
        
        permissionCheckTimer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                PermissionManager.shared.refreshAccessibilityStatus()
            }
    }
}
