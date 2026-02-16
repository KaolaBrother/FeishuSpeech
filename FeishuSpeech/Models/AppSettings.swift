import Foundation
import SwiftUI

struct AppSettings: Codable {
    var appId: String = ""
    var appSecret: String = ""
    var autoInsert: Bool = true
    var playSound: Bool = true
    
    static let storageKey = "FeishuSpeechSettings"
    
    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }
    
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
    
    var isConfigured: Bool {
        !appId.isEmpty && !appSecret.isEmpty
    }
}
