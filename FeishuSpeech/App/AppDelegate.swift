import AppKit
import SwiftUI
import Combine
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate {
    private var permissionCheckTimer: AnyCancellable?
    private weak var mainViewModel: MainViewModel?
    
    func setViewModel(_ viewModel: MainViewModel) {
        self.mainViewModel = viewModel
    }
    
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
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Application terminating, cleaning up all resources")
        
        permissionCheckTimer?.cancel()
        permissionCheckTimer = nil
        
        mainViewModel?.cleanup()
        
        HotKeyService.shared.stopMonitoring()
        
        logger.info("Cleanup completed")
    }
}
