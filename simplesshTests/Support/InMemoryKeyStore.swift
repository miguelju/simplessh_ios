//
//  InMemoryKeyStore.swift
//  simplesshTests
//
//  A `KeyStore` that keeps keys in a dictionary for the duration of a test.
//

@testable import simplessh

final class InMemoryKeyStore: KeyStore {
    private(set) var keys: [String: String] = [:]
    private(set) var biometricFlags: [String: Bool] = [:]

    @discardableResult
    func storeSSHKey(_ key: String, for identifier: String, requireBiometric: Bool) -> Bool {
        keys[identifier] = key
        biometricFlags[identifier] = requireBiometric
        return true
    }

    func retrieveSSHKey(for identifier: String) -> String? {
        keys[identifier]
    }

    @discardableResult
    func deleteSSHKey(for identifier: String) -> Bool {
        keys.removeValue(forKey: identifier)
        biometricFlags.removeValue(forKey: identifier)
        return true
    }
}
