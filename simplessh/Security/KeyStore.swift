//
//  KeyStore.swift
//  simplessh
//
//  The seam between the app and wherever private keys live. Production uses
//  the Keychain (`KeychainManager`); the unit tests use an in-memory store.
//  Keys are addressed by the host's UUID string.
//

import SwiftUI

protocol KeyStore: AnyObject {
    /// Stores `key` under `identifier`, replacing any existing key.
    @discardableResult
    func storeSSHKey(_ key: String, for identifier: String, requireBiometric: Bool) -> Bool

    /// Returns the key stored under `identifier`, or nil if absent or if the
    /// store's own authentication (Face ID / passcode) failed.
    func retrieveSSHKey(for identifier: String) -> String?

    /// Removes the key under `identifier`. Succeeds when there was none.
    @discardableResult
    func deleteSSHKey(for identifier: String) -> Bool
}

extension KeychainManager: KeyStore {}

extension EnvironmentValues {
    /// The key store views read and write. Defaults to the Keychain; previews
    /// and tests inject their own.
    @Entry var keyStore: any KeyStore = KeychainManager.shared
}
