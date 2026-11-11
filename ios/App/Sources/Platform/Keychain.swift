import Foundation
import Security
import GymJournalCore

/// Связка ключей: здесь лежат адрес скрипта и ключ. В файлы приложения и в резервную копию
/// без шифрования они не попадают.
final class KeychainStorage: StateStorage {
    private let service: String

    init(service: String) {
        self.service = service
    }

    private func query(_ name: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
    }

    func data(for name: String) -> Data? {
        var request = query(name)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    func set(_ data: Data?, for name: String) -> Bool {
        let base = query(name)
        guard let data else {
            let status = SecItemDelete(base as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        // после первой разблокировки телефона: очередь должна уходить и тогда, когда экран погас
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        if status != errSecItemNotFound { return false }
        var item = base
        for (key, value) in attributes { item[key] = value }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
