import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MainViewModel
    @AppStorage("appId") private var appId = ""
    @AppStorage("appSecret") private var appSecret = ""
    @AppStorage("autoInsert") private var autoInsert = true
    @AppStorage("playSound") private var playSound = true
    
    var body: some View {
        TabView {
            GeneralSettingsView(
                autoInsert: $autoInsert,
                playSound: $playSound
            )
            .tabItem {
                Label("通用", systemImage: "gearshape")
            }
            
            APISettingsView(
                appId: $appId,
                appSecret: $appSecret
            )
            .tabItem {
                Label("API 配置", systemImage: "key")
            }
        }
        .frame(width: 400, height: 300)
        .onDisappear {
            viewModel.settings.appId = appId
            viewModel.settings.appSecret = appSecret
            viewModel.settings.autoInsert = autoInsert
            viewModel.settings.playSound = playSound
            viewModel.saveSettings()
        }
        .onAppear {
            appId = viewModel.settings.appId
            appSecret = viewModel.settings.appSecret
            autoInsert = viewModel.settings.autoInsert
            playSound = viewModel.settings.playSound
        }
    }
}

struct GeneralSettingsView: View {
    @Binding var autoInsert: Bool
    @Binding var playSound: Bool
    
    var body: some View {
        Form {
            Section("录音") {
                Toggle("自动插入文字", isOn: $autoInsert)
                Toggle("播放提示音", isOn: $playSound)
            }
            
            Section("使用说明") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("• 按住 Fn 键开始录音")
                    Text("• 松开 Fn 键自动识别")
                    Text("• 识别结果将自动输入到当前光标位置")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct APISettingsView: View {
    @Binding var appId: String
    @Binding var appSecret: String
    
    var body: some View {
        Form {
            Section("飞书开放平台") {
                TextField("App ID", text: $appId)
                    .textFieldStyle(.roundedBorder)
                
                SecureField("App Secret", text: $appSecret)
                    .textFieldStyle(.roundedBorder)
            }
            
            Section {
                Link("前往飞书开放平台创建应用", destination: URL(string: "https://open.feishu.cn/app")!)
                    .font(.callout)
                
                Text("需要开通「语音识别」API 权限")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
