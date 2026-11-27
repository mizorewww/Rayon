//
//  SecretStore.swift
//  RayonModule
//
//  Passwords, private keys and tokens, kept in the system keychain (the data
//  protection keychain, the one iOS has) instead of the database, which only
//  names them. Items stay on this device: what syncs travels in CloudKit's
//  encrypted fields.
//

import Foundation
import Security

public struct SecretStore: Sendable {
    public struct Failure: LocalizedError {
        public let status: OSStatus

        public var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return String(localized: "The keychain refused the request: \(message)", bundle: .module)
        }
    }

    public static let shared = SecretStore(service: "me.mizorewww.rayon.secrets")

    public let service: String
    /// Tests: accounts the keychain refuses, as it does while the device
    /// is locked before its first unlock.
    var refusedAccounts: Set<String> = []

    public init(service: String) {
        self.service = service
    }

    private func checkAccess(_ account: String) throws {
        if refusedAccounts.contains(account) { throw Failure(status: errSecInteractionNotAllowed) }
    }

    public func data(for account: String) throws -> Data? {
        try checkAccess(account)
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = perform { SecItemCopyMatching(merged(query, $0) as CFDictionary, &result) }
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw Failure(status: status)
        }
    }

    /// Nil removes the item.
    public func set(_ data: Data?, for account: String) throws {
        guard let data else { return try remove(account) }
        try checkAccess(account)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = perform { SecItemUpdate(merged(query, $0) as CFDictionary, attributes as CFDictionary) }
        if status == errSecItemNotFound {
            status = perform { SecItemAdd(merged(merged(query, $0), attributes) as CFDictionary, nil) }
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    public func remove(_ account: String) throws {
        try checkAccess(account)
        let status = perform { SecItemDelete(merged(baseQuery(account: account), $0) as CFDictionary) }
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }

    /// Every item of the service.
    public func removeAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = perform { SecItemDelete(merged(query, $0) as CFDictionary) }
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }

    public func value<T: Decodable>(_: T.Type, for account: String) throws -> T? {
        try data(for: account).map { try JSONDecoder().decode(T.self, from: $0) }
    }

    public func setValue(_ value: (some Encodable)?, for account: String) throws {
        try set(value.map { try JSONEncoder().encode($0) }, for: account)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func merged(_ lhs: [String: Any], _ rhs: [String: Any]) -> [String: Any] {
        lhs.merging(rhs) { _, new in new }
    }

    /// Runs a keychain call against the data protection keychain. A Mac
    /// build signed without an application identifier (ad hoc, or a test
    /// runner) has no access to it, and gets inconsistent answers from it
    /// (writes refused, reads "not found"); that build keeps its items in the
    /// login keychain instead.
    private func perform(_ call: ([String: Any]) -> OSStatus) -> OSStatus {
        #if os(macOS)
            guard Self.hasApplicationIdentifier else { return call([:]) }
        #endif
        return call([kSecUseDataProtectionKeychain as String: true])
    }

    #if os(macOS)
        private static let hasApplicationIdentifier: Bool = {
            guard let task = SecTaskCreateFromSelf(nil) else { return false }
            return SecTaskCopyValueForEntitlement(task, "com.apple.application-identifier" as CFString, nil) != nil
        }()
    #endif
}
