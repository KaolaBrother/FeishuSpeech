import SwiftUI

@main
struct FeishuSpeechApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = MainViewModel()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.status.icon)
                    .foregroundStyle(viewModel.status.color)
                Text(viewModel.statusText)
            }
        }
        .menuBarExtraStyle(.menu)
        
        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
