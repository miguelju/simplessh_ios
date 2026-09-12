//
//  SSHManagerTests.swift
//  simplesshTests
//
//  SSHManager with an injected key store and render theme. No real server:
//  the connect tests stop at key retrieval, key parsing, or a refused TCP
//  connection to localhost.
//

import Testing
import Foundation
import SwiftUI
import CryptoKit
@testable import simplessh

struct SSHManagerTests {

    private let theme = TerminalRenderTheme(foreground: .white, background: .black,
                                            font: .system(size: 12), boldFont: .system(size: 12).bold())

    private func host(port: Int = 22) -> SSHConnection {
        SSHConnection(name: "test", serverIP: "127.0.0.1", username: "nobody", port: port, requiresBiometric: false)
    }

    private func connectError(_ manager: SSHManager, _ connection: SSHConnection,
                              _ store: KeyStore) async -> SSHManager.SSHError? {
        do {
            try await manager.connect(to: connection, keyStore: store)
            return nil
        } catch let error as SSHManager.SSHError {
            return error
        } catch {
            Issue.record("unexpected error type: \(error)")
            return nil
        }
    }

    // MARK: - Key store seam

    @Test func connectFailsWhenTheStoreHasNoKey() async {
        let manager = SSHManager(renderTheme: theme)
        let store = InMemoryKeyStore()
        let error = await connectError(manager, host(), store)
        guard case .keyParsingFailed(let reason)? = error else {
            Issue.record("expected keyParsingFailed, got \(String(describing: error))")
            return
        }
        #expect(reason.contains("No key found"))
        #expect(manager.statusMessage == "Failed to retrieve SSH key")
        #expect(!manager.isConnected)
        #expect(manager.lastError != nil)
    }

    @Test func connectFailsWhenTheStoredKeyIsInvalid() async {
        let manager = SSHManager(renderTheme: theme)
        let store = InMemoryKeyStore()
        let connection = host()
        store.storeSSHKey("not a key", for: connection.id.uuidString, requireBiometric: false)
        let error = await connectError(manager, connection, store)
        guard case .keyParsingFailed(let reason)? = error else {
            Issue.record("expected keyParsingFailed, got \(String(describing: error))")
            return
        }
        #expect(reason.contains("Unsupported key format"))
        #expect(manager.statusMessage == "Invalid SSH key format")
    }

    @Test func connectReadsTheKeyFromTheInjectedStoreAndReachesTheTransport() async {
        // Port 1 on localhost has no listener, so a valid key gets the manager
        // past retrieval and parsing to a refused TCP connection.
        let manager = SSHManager(renderTheme: theme)
        let store = InMemoryKeyStore()
        let connection = host(port: 1)
        store.storeSSHKey(TestKeys.opensshEd25519(Curve25519.Signing.PrivateKey()),
                          for: connection.id.uuidString, requireBiometric: false)
        let error = await connectError(manager, connection, store)
        guard case .connectionFailed? = error else {
            Issue.record("expected connectionFailed, got \(String(describing: error))")
            return
        }
        #expect(manager.statusMessage == "Connection failed")
        #expect(!manager.isConnected)
    }

    // MARK: - Render theme seam

    @Test func changingTheRenderThemeReRendersWithTheNewFonts() async throws {
        let manager = SSHManager(renderTheme: theme)
        manager.terminal.feed("prompt$ ")
        var bigger = theme
        bigger.font = .system(size: 20)
        bigger.boldFont = .system(size: 20).bold()
        let before = manager.outputVersion
        manager.renderTheme = bigger
        try await Task.sleep(for: .milliseconds(50))   // one coalesced render hop
        #expect(manager.outputVersion == before + 1)
        #expect(manager.renderedScreen.runs.first?.font == bigger.font)
        #expect(String(manager.renderedScreen.characters) == "prompt$")
    }

    @Test func settingAnEqualThemeDoesNotRender() async throws {
        let manager = SSHManager(renderTheme: theme)
        let before = manager.outputVersion
        manager.renderTheme = theme
        try await Task.sleep(for: .milliseconds(50))
        #expect(manager.outputVersion == before)
    }
}
