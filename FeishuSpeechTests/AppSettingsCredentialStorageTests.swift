import XCTest
@testable import FeishuSpeech

final class AppSettingsCredentialStorageTests: XCTestCase {

    private var credentialStore: FakeCredentialStore!
    private var keychainStore: KeychainCredentialStore!
    private let defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        credentialStore = FakeCredentialStore()
        keychainStore = KeychainCredentialStore(service: "Siji.FeishuSpeech.tests.\(UUID().uuidString)")
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
        keychainStore = nil
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
            launchAtLogin: true
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
