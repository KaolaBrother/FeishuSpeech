import Foundation
import Security
import XCTest

@testable import FeishuSpeech

final class AppSettingsCredentialStorageTests: XCTestCase {

    private var credentialStore: FakeCredentialStore!
    private var keychainStore: KeychainCredentialStore!
    private var isolatedServiceName: String!
    private let defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        credentialStore = FakeCredentialStore()
        isolatedServiceName = "Siji.FeishuSpeech.tests.\(UUID().uuidString)"
        keychainStore = KeychainCredentialStore(service: isolatedServiceName)
        try? keychainStore.delete(account: .appId)
        try? keychainStore.delete(account: .appSecret)
        AppSettings.credentialStore = credentialStore
        defaults.removeObject(forKey: AppSettings.storageKey)
        defaults.removeObject(forKey: "appId")
        defaults.removeObject(forKey: "appSecret")
    }

    override func tearDown() {
        defaults.removeObject(forKey: AppSettings.storageKey)
        defaults.removeObject(forKey: "appId")
        defaults.removeObject(forKey: "appSecret")
        AppSettings.credentialStore = KeychainCredentialStore()
        try? keychainStore.delete(account: .appId)
        try? keychainStore.delete(account: .appSecret)
        if let isolatedServiceName {
            deleteGenericPasswords(service: isolatedServiceName)
        }
        keychainStore = nil
        isolatedServiceName = nil
        credentialStore = nil
        super.tearDown()
    }

    func test_load_migratesLegacyCredentialsToCredentialStoreAndScrubsDefaults() throws {
        let legacyData = Data("""
        {"appId":"legacy-app-id","appSecret":"legacy-app-secret","autoInsert":false,"playSound":false,"launchAtLogin":true}
        """.utf8)
        defaults.set(legacyData, forKey: AppSettings.storageKey)
        defaults.set("legacy-app-id", forKey: "appId")
        defaults.set("legacy-app-secret", forKey: "appSecret")

        let loaded = AppSettings.load()

        XCTAssertEqual(loaded.appId, "legacy-app-id")
        XCTAssertEqual(loaded.appSecret, "legacy-app-secret")
        XCTAssertFalse(loaded.autoInsert)
        XCTAssertFalse(loaded.playSound)
        XCTAssertTrue(loaded.launchAtLogin)
        XCTAssertEqual(try credentialStore.read(account: .appId), "legacy-app-id")
        XCTAssertEqual(try credentialStore.read(account: .appSecret), "legacy-app-secret")
        XCTAssertNil(defaults.string(forKey: "appId"))
        XCTAssertNil(defaults.string(forKey: "appSecret"))

        let scrubbedData = try XCTUnwrap(defaults.data(forKey: AppSettings.storageKey))
        let scrubbedJSON = try XCTUnwrap(String(data: scrubbedData, encoding: .utf8))
        XCTAssertFalse(scrubbedJSON.contains("legacy-app-id"))
        XCTAssertFalse(scrubbedJSON.contains("legacy-app-secret"))
        XCTAssertFalse(scrubbedJSON.contains("appId"))
        XCTAssertFalse(scrubbedJSON.contains("appSecret"))
    }

    func test_load_migratesStandaloneCredentialsWhenEncodedSettingsHasNoCredentials() throws {
        let legacyData = Data("""
        {"autoInsert":false,"playSound":true,"launchAtLogin":true}
        """.utf8)
        defaults.set(legacyData, forKey: AppSettings.storageKey)
        defaults.set("standalone-id", forKey: "appId")
        defaults.set("standalone-secret", forKey: "appSecret")

        let loaded = AppSettings.load()

        XCTAssertEqual(loaded.appId, "standalone-id")
        XCTAssertEqual(loaded.appSecret, "standalone-secret")
        XCTAssertFalse(loaded.autoInsert)
        XCTAssertTrue(loaded.playSound)
        XCTAssertTrue(loaded.launchAtLogin)
        XCTAssertEqual(try credentialStore.read(account: .appId), "standalone-id")
        XCTAssertEqual(try credentialStore.read(account: .appSecret), "standalone-secret")
        XCTAssertNil(defaults.string(forKey: "appId"))
        XCTAssertNil(defaults.string(forKey: "appSecret"))
    }

    func test_load_prefersStandaloneCredentialsWhenTheyDifferFromEncodedLegacyValues() throws {
        let legacyData = Data("""
        {"appId":"json-id","appSecret":"json-secret","autoInsert":true,"playSound":false,"launchAtLogin":false}
        """.utf8)
        defaults.set(legacyData, forKey: AppSettings.storageKey)
        defaults.set("newer-standalone-id", forKey: "appId")
        defaults.set("newer-standalone-secret", forKey: "appSecret")

        let loaded = AppSettings.load()

        XCTAssertEqual(loaded.appId, "newer-standalone-id")
        XCTAssertEqual(loaded.appSecret, "newer-standalone-secret")
        XCTAssertEqual(try credentialStore.read(account: .appId), "newer-standalone-id")
        XCTAssertEqual(try credentialStore.read(account: .appSecret), "newer-standalone-secret")
        XCTAssertNil(defaults.string(forKey: "appId"))
        XCTAssertNil(defaults.string(forKey: "appSecret"))
    }

    func test_load_keepsLegacyDefaultsWhenCredentialMigrationSaveFails() throws {
        let legacyData = Data("""
        {"appId":"legacy-id","appSecret":"legacy-secret","autoInsert":true,"playSound":true,"launchAtLogin":false}
        """.utf8)
        defaults.set(legacyData, forKey: AppSettings.storageKey)
        defaults.set("standalone-id", forKey: "appId")
        defaults.set("standalone-secret", forKey: "appSecret")
        credentialStore.saveErrors.insert(.appSecret)

        let loaded = AppSettings.load()

        XCTAssertEqual(loaded.appId, "standalone-id")
        XCTAssertEqual(loaded.appSecret, "standalone-secret")
        XCTAssertEqual(try credentialStore.read(account: .appId), "standalone-id")
        XCTAssertEqual(defaults.string(forKey: "appId"), "standalone-id")
        XCTAssertEqual(defaults.string(forKey: "appSecret"), "standalone-secret")

        let retainedData = try XCTUnwrap(defaults.data(forKey: AppSettings.storageKey))
        let retainedJSON = try XCTUnwrap(String(data: retainedData, encoding: .utf8))
        XCTAssertTrue(retainedJSON.contains("legacy-id"))
        XCTAssertTrue(retainedJSON.contains("legacy-secret"))
    }

    func test_saveAfterFailedEncodedMigrationKeepsLegacySettingsPayload() throws {
        let legacyData = Data("""
        {"appId":"legacy-id","appSecret":"legacy-secret","autoInsert":true,"playSound":false,"launchAtLogin":true}
        """.utf8)
        defaults.set(legacyData, forKey: AppSettings.storageKey)
        credentialStore.saveErrors.insert(.appSecret)

        var loaded = AppSettings.load()
        loaded.autoInsert = false
        loaded.save()

        let retainedData = try XCTUnwrap(defaults.data(forKey: AppSettings.storageKey))
        let retainedJSON = try XCTUnwrap(String(data: retainedData, encoding: .utf8))
        XCTAssertTrue(retainedJSON.contains("legacy-id"))
        XCTAssertTrue(retainedJSON.contains("legacy-secret"))
        XCTAssertTrue(retainedJSON.contains("appId"))
        XCTAssertTrue(retainedJSON.contains("appSecret"))
    }

    func test_save_writesCredentialsToCredentialStoreOnlyAndPreservesPreferences() throws {
        let settings = AppSettings(
            appId: "saved-app-id",
            appSecret: "saved-app-secret",
            autoInsert: false,
            playSound: true,
            launchAtLogin: true
        )

        settings.save()

        XCTAssertEqual(try credentialStore.read(account: .appId), "saved-app-id")
        XCTAssertEqual(try credentialStore.read(account: .appSecret), "saved-app-secret")

        let storedData = try XCTUnwrap(defaults.data(forKey: AppSettings.storageKey))
        let storedJSON = try XCTUnwrap(String(data: storedData, encoding: .utf8))
        XCTAssertFalse(storedJSON.contains("saved-app-id"))
        XCTAssertFalse(storedJSON.contains("saved-app-secret"))
        XCTAssertFalse(storedJSON.contains("appId"))
        XCTAssertFalse(storedJSON.contains("appSecret"))

        credentialStore.values[.appId] = "saved-app-id"
        credentialStore.values[.appSecret] = "saved-app-secret"

        let loaded = AppSettings.load()
        XCTAssertEqual(loaded.appId, "saved-app-id")
        XCTAssertEqual(loaded.appSecret, "saved-app-secret")
        XCTAssertFalse(loaded.autoInsert)
        XCTAssertTrue(loaded.playSound)
        XCTAssertTrue(loaded.launchAtLogin)
    }

    func test_codableEncodingOmitsCredentials() throws {
        let settings = AppSettings(
            appId: "encoded-app-id",
            appSecret: "encoded-app-secret",
            autoInsert: true,
            playSound: false,
            launchAtLogin: true,
            reviewBeforeInsert: true
        )

        let data = try JSONEncoder().encode(settings)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("encoded-app-id"))
        XCTAssertFalse(json.contains("encoded-app-secret"))
        XCTAssertFalse(json.contains("appId"))
        XCTAssertFalse(json.contains("appSecret"))
        XCTAssertTrue(json.contains("autoInsert"))
        XCTAssertTrue(json.contains("playSound"))
        XCTAssertTrue(json.contains("launchAtLogin"))
        XCTAssertTrue(json.contains("reviewBeforeInsert"))
    }

    func test_legacyStoredPayload_defaultsReviewBeforeInsertToTrue() {
        defaults.set(
            Data("{\"autoInsert\":false,\"playSound\":true,\"launchAtLogin\":true}".utf8),
            forKey: AppSettings.storageKey
        )

        let loaded = AppSettings.load()

        XCTAssertTrue(
            loaded.reviewBeforeInsert,
            "payloads written before issue #38 must opt into review-first instead of decoding as false"
        )
        XCTAssertFalse(loaded.autoInsert)
        XCTAssertTrue(loaded.playSound)
        XCTAssertTrue(loaded.launchAtLogin)
    }

    func test_reviewBeforeInsert_false_roundTrips_withoutChangingCompatibilityPreferences() {
        var settings = AppSettings(
            appId: "",
            appSecret: "",
            autoInsert: false,
            playSound: false,
            launchAtLogin: true,
            reviewBeforeInsert: false
        )

        settings.save()

        let storedData = defaults.data(forKey: AppSettings.storageKey)
        XCTAssertNotNil(storedData)
        XCTAssertTrue(
            String(data: storedData ?? Data(), encoding: .utf8)?.contains("reviewBeforeInsert") == true,
            "the explicit compatibility choice must be persisted"
        )

        let loaded = AppSettings.load()

        XCTAssertFalse(loaded.reviewBeforeInsert)
        XCTAssertFalse(loaded.autoInsert)
        XCTAssertFalse(loaded.playSound)
        XCTAssertTrue(loaded.launchAtLogin)
        settings = loaded
        settings.reviewBeforeInsert = true
        settings.save()
        XCTAssertTrue(AppSettings.load().reviewBeforeInsert)
    }

    func test_save_withBlankCredentialDeletesThatCredential() throws {
        credentialStore.values[.appId] = "existing-id"
        credentialStore.values[.appSecret] = "existing-secret"

        let settings = AppSettings(
            appId: "",
            appSecret: "rotated-secret",
            autoInsert: true,
            playSound: false,
            launchAtLogin: false
        )

        settings.save()

        XCTAssertNil(try credentialStore.read(account: .appId))
        XCTAssertEqual(try credentialStore.read(account: .appSecret), "rotated-secret")
        XCTAssertEqual(credentialStore.deletedAccounts, [.appId])

        let loaded = AppSettings.load()
        XCTAssertEqual(loaded.appId, "")
        XCTAssertEqual(loaded.appSecret, "rotated-secret")
        XCTAssertTrue(loaded.autoInsert)
        XCTAssertFalse(loaded.playSound)
        XCTAssertFalse(loaded.launchAtLogin)
    }

    func test_saveAfterCredentialReadFailureDoesNotDeleteExistingCredential() throws {
        credentialStore.values[.appId] = "existing-id"
        credentialStore.values[.appSecret] = "existing-secret"
        credentialStore.readErrors.insert(.appId)

        let loaded = AppSettings.load()
        loaded.save()

        XCTAssertEqual(credentialStore.values[.appId], "existing-id")
        XCTAssertEqual(credentialStore.values[.appSecret], "existing-secret")
        XCTAssertFalse(credentialStore.deletedAccounts.contains(.appId))
    }

    func test_keychainCredentialStore_saveReadAndDeleteUseIsolatedService() throws {
        do {
            try keychainStore.save("keychain-test-id", account: .appId)
            XCTAssertEqual(try keychainStore.read(account: .appId), "keychain-test-id")

            try keychainStore.save("", account: .appId)
            XCTAssertNil(try keychainStore.read(account: .appId))

            try keychainStore.delete(account: .appSecret)
        } catch KeychainCredentialStore.StoreError.unexpectedStatus(let status)
            where status == errSecMissingEntitlement || status == errSecInteractionNotAllowed {
            throw XCTSkip("Keychain is unavailable in this unit-test host: \(status)")
        }
    }

    func test_keychainCredentialStoreSource_usesLoginKeychainWithoutDataProtectionFlag() throws {
        let source = try productionSource(relativePath: "FeishuSpeech/Services/KeychainCredentialStore.swift")

        XCTAssertFalse(
            source.contains("kSecUseDataProtectionKeychain"),
            "issue #36: data-protection queries blanked existing login-keychain credentials (-34018)"
        )
    }

    func test_appDelegateDidFinishLaunching_doesNotLoadAppSettingsCredentials() throws {
        let source = try productionSource(relativePath: "FeishuSpeech/App/AppDelegate.swift")
        let method = try XCTUnwrap(
            methodBody(named: "applicationDidFinishLaunching", in: source),
            "AppDelegate.applicationDidFinishLaunching must exist"
        )

        XCTAssertFalse(
            method.contains("AppSettings.load"),
            "applicationDidFinishLaunching must not call AppSettings.load(); that opens the credential store and surfaces login-keychain ACL dialogs"
        )
        XCTAssertTrue(
            method.contains("launchAtLoginPreference"),
            "applicationDidFinishLaunching must apply launch-at-login from UserDefaults without reading credentials"
        )
        XCTAssertTrue(
            method.contains("LoginItemService.setEnabled"),
            "applicationDidFinishLaunching must still apply the launch-at-login preference"
        )
    }

    func test_appSettingsSource_declaresLaunchAtLoginPreferenceReader() throws {
        let source = try productionSource(relativePath: "FeishuSpeech/Models/AppSettings.swift")

        XCTAssertTrue(
            source.contains("func launchAtLoginPreference(from"),
            "AppSettings must expose launchAtLoginPreference(from:) so launch-at-login can be read without the credential store"
        )
    }

    func test_launchAtLoginPreference_readsEncodedPayloadWithoutTouchingCredentialStore() throws {
        let suiteName = "Siji.FeishuSpeech.tests.launchAtLogin.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }

        let inaccessible = InaccessibleCredentialStore()
        AppSettings.credentialStore = inaccessible

        suite.set(
            Data("""
            {"autoInsert":false,"playSound":false,"launchAtLogin":true}
            """.utf8),
            forKey: AppSettings.storageKey
        )
        XCTAssertTrue(AppSettings.launchAtLoginPreference(from: suite))
        XCTAssertEqual(inaccessible.readCount, 0, "launch-at-login preference must not read the credential store")
        XCTAssertEqual(inaccessible.saveCount, 0)
        XCTAssertEqual(inaccessible.deleteCount, 0)

        suite.set(
            Data("""
            {"autoInsert":true,"playSound":true,"launchAtLogin":false}
            """.utf8),
            forKey: AppSettings.storageKey
        )
        XCTAssertFalse(AppSettings.launchAtLoginPreference(from: suite))
        XCTAssertEqual(inaccessible.readCount, 0)
        XCTAssertEqual(inaccessible.saveCount, 0)
        XCTAssertEqual(inaccessible.deleteCount, 0)

        suite.removeObject(forKey: AppSettings.storageKey)
        XCTAssertFalse(AppSettings.launchAtLoginPreference(from: suite))
        XCTAssertEqual(inaccessible.readCount, 0)
        XCTAssertEqual(inaccessible.saveCount, 0)
        XCTAssertEqual(inaccessible.deleteCount, 0)
    }

    private func productionSource(relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func methodBody(named name: String, in source: String) -> String? {
        guard let nameRange = source.range(of: "func \(name)") else {
            return nil
        }
        guard let open = source[nameRange.upperBound...].firstIndex(of: "{") else {
            return nil
        }

        var depth = 0
        var index = open
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[open...index])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private func deleteGenericPasswords(service: String) {
        for account in [CredentialAccount.appId, CredentialAccount.appSecret] {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account.rawValue
            ]
            SecItemDelete(base as CFDictionary)
            var dataProtectionQuery = base
            dataProtectionQuery[kSecUseDataProtectionKeychain as String] = true
            SecItemDelete(dataProtectionQuery as CFDictionary)
        }
    }
}

private final class InaccessibleCredentialStore: CredentialStoring {
    enum AccessError: Error {
        case forced
    }

    private(set) var readCount = 0
    private(set) var saveCount = 0
    private(set) var deleteCount = 0

    func read(account: CredentialAccount) throws -> String? {
        readCount += 1
        _ = account
        throw AccessError.forced
    }

    func save(_ value: String, account: CredentialAccount) throws {
        saveCount += 1
        _ = (value, account)
        throw AccessError.forced
    }

    func delete(account: CredentialAccount) throws {
        deleteCount += 1
        _ = account
        throw AccessError.forced
    }
}

private final class FakeCredentialStore: CredentialStoring {
    enum FakeError: Error {
        case forced
    }

    var values: [CredentialAccount: String] = [:]
    var readErrors: Set<CredentialAccount> = []
    var saveErrors: Set<CredentialAccount> = []
    var deleteErrors: Set<CredentialAccount> = []
    private(set) var deletedAccounts: [CredentialAccount] = []

    func read(account: CredentialAccount) throws -> String? {
        if readErrors.contains(account) {
            throw FakeError.forced
        }
        return values[account]
    }

    func save(_ value: String, account: CredentialAccount) throws {
        if saveErrors.contains(account) {
            throw FakeError.forced
        }
        if value.isEmpty {
            try delete(account: account)
        } else {
            values[account] = value
        }
    }

    func delete(account: CredentialAccount) throws {
        if deleteErrors.contains(account) {
            throw FakeError.forced
        }
        values.removeValue(forKey: account)
        deletedAccounts.append(account)
    }
}
