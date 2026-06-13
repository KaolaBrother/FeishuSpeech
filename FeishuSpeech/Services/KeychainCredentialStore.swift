import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "KeychainCredentialStore")

enum CredentialAccount: String {
    case appId
    case appSecret
}

protocol CredentialStoring {
    func read(account: CredentialAccount) throws -> String?
    func save(_ value: String, account: CredentialAccount) throws
    func delete(account: CredentialAccount) throws
}

struct KeychainCredentialStore: CredentialStoring {
    enum StoreError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                return "Keychain operation failed with status \(status)"
            case .invalidData:
                return "Keychain item data is not valid UTF-8"
            }
        }
    }

    private let service: String

    init(service: String = "Siji.FeishuSpeech.credentials") {
        self.service = service
    }

    func read(account: CredentialAccount) throws -> String? {
        var query = baseQuery(account: account, failAuthenticationUI: true)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw StoreError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw StoreError.invalidData
        }

        return value
    }

    func save(_ value: String, account: CredentialAccount) throws {
        guard !value.isEmpty else {
            try delete(account: account)
            return
        }

        let data = Data(value.utf8)
        let status = SecItemUpdate(
            baseQuery(account: account, failAuthenticationUI: true) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            try add(data, account: account)
        default:
            throw StoreError.unexpectedStatus(status)
        }
    }

    func delete(account: CredentialAccount) throws {
        let status = SecItemDelete(
            baseQuery(account: account, failAuthenticationUI: true) as CFDictionary
        )

        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw StoreError.unexpectedStatus(status)
        }
    }

    private func add(_ data: Data, account: CredentialAccount) throws {
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                baseQuery(account: account, failAuthenticationUI: true) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw StoreError.unexpectedStatus(updateStatus)
            }
        default:
            throw StoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: CredentialAccount, failAuthenticationUI: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
        if failAuthenticationUI {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        return query
    }
}
