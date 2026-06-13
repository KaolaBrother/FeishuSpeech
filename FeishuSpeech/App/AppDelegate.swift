import AppKit
import Combine
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate {
    private enum WorkspaceLifecycleEvent {
        case willSleep
        case didWake
    }

    private var permissionCheckTimer: AnyCancellable?
    private var workspaceObserverTokens: [NSObjectProtocol] = []
    private var pendingWorkspaceLifecycleEvents: [WorkspaceLifecycleEvent] = []
    private weak var mainViewModel: MainViewModel?

    func setViewModel(_ viewModel: MainViewModel) {
        self.mainViewModel = viewModel
        replayPendingWorkspaceLifecycleEvents(to: viewModel)
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
                PermissionManager.shared.refreshMicrophoneStatus()
                PermissionManager.shared.refreshSecureInputStatus()
            }

        let settings = AppSettings.load()
        LoginItemService.setEnabled(settings.launchAtLogin)

        registerWorkspaceWakeObservers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Application terminating, cleaning up all resources")

        permissionCheckTimer?.cancel()
        permissionCheckTimer = nil

        mainViewModel?.cleanup()
        removeWorkspaceWakeObservers()

        HotKeyService.shared.stopMonitoring()

        logger.info("Cleanup completed")
    }

    private func registerWorkspaceWakeObservers() {
        guard workspaceObserverTokens.isEmpty else { return }

        let notificationCenter = NSWorkspace.shared.notificationCenter
        let willSleepToken = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleWorkspaceWillSleep(notification)
        }
        let didWakeToken = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleWorkspaceDidWake(notification)
        }

        workspaceObserverTokens = [willSleepToken, didWakeToken]
        logger.info("Registered workspace sleep/wake observers")
    }

    private func removeWorkspaceWakeObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        workspaceObserverTokens.forEach { notificationCenter.removeObserver($0) }
        workspaceObserverTokens.removeAll()
        logger.info("Removed workspace sleep/wake observers")
    }

    private func handleWorkspaceWillSleep(_ notification: Notification) {
        logger.info("Workspace will sleep")
        routeWorkspaceLifecycleEvent(.willSleep)
    }

    private func handleWorkspaceDidWake(_ notification: Notification) {
        logger.info("Workspace did wake")
        routeWorkspaceLifecycleEvent(.didWake)
    }

    private func routeWorkspaceLifecycleEvent(_ event: WorkspaceLifecycleEvent) {
        guard let mainViewModel else {
            pendingWorkspaceLifecycleEvents.append(event)
            logger.info("Queued workspace lifecycle event until view model is available")
            return
        }

        Task { @MainActor in
            await self.deliverWorkspaceLifecycleEvent(event, to: mainViewModel)
        }
    }

    private func replayPendingWorkspaceLifecycleEvents(to viewModel: MainViewModel) {
        guard !pendingWorkspaceLifecycleEvents.isEmpty else { return }

        let events = pendingWorkspaceLifecycleEvents
        pendingWorkspaceLifecycleEvents.removeAll()

        Task { @MainActor in
            for event in events {
                await self.deliverWorkspaceLifecycleEvent(event, to: viewModel)
            }
        }
    }

    @MainActor
    private func deliverWorkspaceLifecycleEvent(_ event: WorkspaceLifecycleEvent, to viewModel: MainViewModel) async {
        switch event {
        case .willSleep:
            await viewModel.handleSystemWillSleep()
        case .didWake:
            await viewModel.handleSystemDidWake()
        }
    }

    #if DEBUG
    var workspaceObserverCountForTesting: Int {
        workspaceObserverTokens.count
    }

    var pendingWorkspaceLifecycleEventCountForTesting: Int {
        pendingWorkspaceLifecycleEvents.count
    }

    func registerWorkspaceWakeObserversForTesting() {
        registerWorkspaceWakeObservers()
    }

    func removeWorkspaceWakeObserversForTesting() {
        removeWorkspaceWakeObservers()
    }

    func simulateWorkspaceWillSleepForTesting() {
        handleWorkspaceWillSleep(Notification(name: NSWorkspace.willSleepNotification))
    }

    func simulateWorkspaceDidWakeForTesting() {
        handleWorkspaceDidWake(Notification(name: NSWorkspace.didWakeNotification))
    }
    #endif
}
