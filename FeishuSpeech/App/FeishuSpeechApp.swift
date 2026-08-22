import Foundation
import SwiftUI

@main
struct FeishuSpeechApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel: MainViewModel

    init() {
        #if DEBUG
        let settings = Self.isUnitTestHost ? AppSettings() : nil
        #else
        let settings: AppSettings? = nil
        #endif
        _viewModel = StateObject(wrappedValue: MainViewModel(settings: settings))
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
                .onAppear {
                    appDelegate.setViewModel(viewModel)
                }
        } label: {
            // Icon-only: icon+status text is wide enough to land in the MacBook
            // notch and vanish from the visible extra strip.
            Image(systemName: viewModel.status.icon)
                .foregroundStyle(viewModel.status.color)
        }
        .menuBarExtraStyle(.menu)
        
        Settings {
            SettingsView(viewModel: viewModel)
        }
    }

    #if DEBUG
    private static var isUnitTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }
    #endif
}
