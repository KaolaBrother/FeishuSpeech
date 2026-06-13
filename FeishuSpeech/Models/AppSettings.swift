import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "AppSettings")

struct AppSettings: Codable {
    var appId: String = ""
    var appSecret: String = ""
    var autoInsert: Bool = true
    var playSound: Bool = true
    var launchAtLogin: Bool = false
    private var credentialReadFailures = Set<CredentialAccount>()
    private var preserveLegacyCredentialsOnSave = false

    static let storageKey = "FeishuSpeechSettings"
    static var credentialStore: CredentialStoring = KeychainCredentialStore()

    static func load() -> AppSettings {
        let defaults = UserDefaults.standard
        let storedSettings = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(StoredSettings.self, from: $0) }
        let standaloneAppId = defaults.string(forKey: CredentialAccount.appId.rawValue) ?? ""
        let standaloneAppSecret = defaults.string(forKey: CredentialAccount.appSecret.rawValue) ?? ""

        var settings = storedSettings?.appSettings ?? AppSettings()
        let legacyAppId = legacyCredential(encodedValue: storedSettings?.appId, standaloneValue: standaloneAppId)
        let legacyAppSecret = legacyCredential(
            encodedValue: storedSettings?.appSecret,
            standaloneValue: standaloneAppSecret
        )
        let containsLegacyCredentials = storedSettings?.containsLegacyCredentials == true ||
            !standaloneAppId.isEmpty ||
            !standaloneAppSecret.isEmpty

        var migrationSucceeded = true
        if !legacyAppId.isEmpty {
            migrationSucceeded = saveCredential(legacyAppId, account: .appId) && migrationSucceeded
        }
        if !legacyAppSecret.isEmpty {
            migrationSucceeded = saveCredential(legacyAppSecret, account: .appSecret) && migrationSucceeded
        }

        switch loadCredential(account: .appId) {
        case .success(let value):
            settings.appId = value ?? legacyAppId
        case .failure:
            settings.appId = legacyAppId
            settings.credentialReadFailures.insert(.appId)
        }

        switch loadCredential(account: .appSecret) {
        case .success(let value):
            settings.appSecret = value ?? legacyAppSecret
        case .failure:
            settings.appSecret = legacyAppSecret
            settings.credentialReadFailures.insert(.appSecret)
        }

        settings.preserveLegacyCredentialsOnSave = containsLegacyCredentials &&
            (!migrationSucceeded || !settings.credentialReadFailures.isEmpty)

        if containsLegacyCredentials, migrationSucceeded, settings.credentialReadFailures.isEmpty {
            settings.savePreferences(to: defaults)
            removeLegacyStandaloneCredentials(from: defaults)
        }

        return settings
    }

    func save() {
        let defaults = UserDefaults.standard

        let appIdSaved = Self.saveCredential(
            appId,
            account: .appId,
            skipDeleteIfReadFailed: credentialReadFailures.contains(.appId)
        )
        let appSecretSaved = Self.saveCredential(
            appSecret,
            account: .appSecret,
            skipDeleteIfReadFailed: credentialReadFailures.contains(.appSecret)
        )

        if appIdSaved, appSecretSaved {
            Self.removeLegacyStandaloneCredentials(from: defaults)
        } else if preserveLegacyCredentialsOnSave {
            logger.warning("Skipping preference rewrite while legacy credential fallback is still needed")
            return
        }

        savePreferences(to: defaults)
    }

    private func savePreferences(to defaults: UserDefaults) {
        let storedSettings = StoredSettings(
            autoInsert: autoInsert,
            playSound: playSound,
            launchAtLogin: launchAtLogin
        )
        guard let data = try? JSONEncoder().encode(storedSettings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    var isConfigured: Bool {
        !appId.isEmpty && !appSecret.isEmpty
    }

    init(
        appId: String = "",
        appSecret: String = "",
        autoInsert: Bool = true,
        playSound: Bool = true,
        launchAtLogin: Bool = false
    ) {
        self.appId = appId
        self.appSecret = appSecret
        self.autoInsert = autoInsert
        self.playSound = playSound
        self.launchAtLogin = launchAtLogin
        self.preserveLegacyCredentialsOnSave = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appId = try container.decodeIfPresent(String.self, forKey: .appId) ?? ""
        appSecret = try container.decodeIfPresent(String.self, forKey: .appSecret) ?? ""
        autoInsert = try container.decodeIfPresent(Bool.self, forKey: .autoInsert) ?? true
        playSound = try container.decodeIfPresent(Bool.self, forKey: .playSound) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        credentialReadFailures = []
        preserveLegacyCredentialsOnSave = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(autoInsert, forKey: .autoInsert)
        try container.encode(playSound, forKey: .playSound)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
    }

    private static func loadCredential(account: CredentialAccount) -> CredentialLoadResult {
        do {
            return .success(try credentialStore.read(account: account))
        } catch {
            logger.error(
                """
                Failed to read credential for account \
                \(account.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)
                """
            )
            return .failure
        }
    }

    private static func saveCredential(
        _ value: String,
        account: CredentialAccount,
        skipDeleteIfReadFailed: Bool = false
    ) -> Bool {
        do {
            if value.isEmpty {
                if skipDeleteIfReadFailed {
                    logger.warning(
                        """
                        Skipping credential delete for account \
                        \(account.rawValue, privacy: .public) after a read failure
                        """
                    )
                    return false
                }
                try credentialStore.delete(account: account)
            } else {
                try credentialStore.save(value, account: account)
            }
            return true
        } catch {
            logger.error(
                """
                Failed to save credential for account \
                \(account.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)
                """
            )
            return false
        }
    }

    private static func legacyCredential(encodedValue: String?, standaloneValue: String) -> String {
        if !standaloneValue.isEmpty {
            return standaloneValue
        }
        return encodedValue ?? ""
    }

    private static func removeLegacyStandaloneCredentials(from defaults: UserDefaults) {
        defaults.removeObject(forKey: CredentialAccount.appId.rawValue)
        defaults.removeObject(forKey: CredentialAccount.appSecret.rawValue)
    }

    private enum CodingKeys: String, CodingKey {
        case appId
        case appSecret
        case autoInsert
        case playSound
        case launchAtLogin
    }
}

private enum CredentialLoadResult {
    case success(String?)
    case failure
}

private struct StoredSettings: Codable {
    var appId: String?
    var appSecret: String?
    var autoInsert: Bool
    var playSound: Bool
    var launchAtLogin: Bool

    init(autoInsert: Bool = true, playSound: Bool = true, launchAtLogin: Bool = false) {
        self.appId = nil
        self.appSecret = nil
        self.autoInsert = autoInsert
        self.playSound = playSound
        self.launchAtLogin = launchAtLogin
    }

    var appSettings: AppSettings {
        AppSettings(
            appId: appId ?? "",
            appSecret: appSecret ?? "",
            autoInsert: autoInsert,
            playSound: playSound,
            launchAtLogin: launchAtLogin
        )
    }

    var containsLegacyCredentials: Bool {
        appId != nil || appSecret != nil
    }
}
