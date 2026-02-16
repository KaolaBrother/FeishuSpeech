import SwiftUI

struct PermissionView: View {
    @ObservedObject var permissionManager = PermissionManager.shared
    @State private var isRefreshing = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            
            Text("需要授权以下权限")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(
                    icon: "keyboard",
                    title: "辅助功能",
                    description: "用于监听 Fn 键",
                    isGranted: permissionManager.accessibilityGranted,
                    action: { permissionManager.openSystemSettings() }
                )
                
                PermissionRow(
                    icon: "mic.fill",
                    title: "麦克风",
                    description: "用于录制语音",
                    isGranted: permissionManager.microphoneGranted,
                    action: { permissionManager.openMicrophoneSettings() }
                )
            }
            .padding(.horizontal)
            
            Button("刷新状态") {
                Task {
                    isRefreshing = true
                    await permissionManager.checkAllPermissions()
                    isRefreshing = false
                }
            }
            .disabled(isRefreshing)
            
            if permissionManager.allPermissionsGranted {
                Label("所有权限已获得，可以开始使用", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isGranted ? .green : .orange)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("授权") {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}
