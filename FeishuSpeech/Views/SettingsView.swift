import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var appId = ""
    @State private var appSecret = ""
    @State private var playSound = true
    @State private var launchAtLogin = false

    var body: some View {
        TabView {
            GeneralSettingsView(
                launchAtLogin: $launchAtLogin,
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
            viewModel.updateSettings(
                appId: appId,
                appSecret: appSecret,
                autoInsert: viewModel.settings.autoInsert,
                playSound: playSound,
                launchAtLogin: launchAtLogin,
                reviewBeforeInsert: viewModel.settings.reviewBeforeInsert
            )
        }
        .onAppear {
            loadSettings()
        }
    }

    private func loadSettings() {
        appId = viewModel.settings.appId
        appSecret = viewModel.settings.appSecret
        playSound = viewModel.settings.playSound
        launchAtLogin = viewModel.settings.launchAtLogin
    }
}

struct GeneralSettingsView: View {
    @Binding var launchAtLogin: Bool
    @Binding var playSound: Bool

    var body: some View {
        Form {
            Section("通用") {
                Toggle("开机启动", isOn: $launchAtLogin)
            }

            Section("录音") {
                Text("每次语音交互都会打开预览；点击发送或按回车后才输入。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Toggle("播放提示音", isOn: $playSound)
            }

            Section("使用说明") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("按住 Fn 键开始录音")
                    Text("松开 Fn 键自动识别")
                    Text("编辑预览后点击发送或按回车发送到原始光标位置")
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
