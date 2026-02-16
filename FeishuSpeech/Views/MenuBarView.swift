import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var permissionManager = PermissionManager.shared
    
    var body: some View {
        Group {
            if permissionManager.isChecking {
                Text("检查权限中...")
                    .foregroundStyle(.secondary)
            } else if !permissionManager.allPermissionsGranted {
                Text("⚠️ 需要授权权限")
                    .foregroundStyle(.orange)
                
                Divider()
                
                if !permissionManager.accessibilityGranted {
                    Button("授权辅助功能") {
                        permissionManager.openSystemSettings()
                    }
                }
                
                if !permissionManager.microphoneGranted {
                    Button("授权麦克风") {
                        permissionManager.openMicrophoneSettings()
                    }
                }
                
                Button("刷新状态") {
                    Task {
                        await permissionManager.checkAllPermissions()
                    }
                }
            } else {
                Text(viewModel.status.text)
                    .foregroundStyle(viewModel.status.color)
                
                Divider()
                
                Text("按住 Fn 键开始录音")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            SettingsLink {
                Text("设置...")
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            Button("退出") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
