//
//  PrivateKeyParsingTests.swift
//  simplesshTests
//
//  Exercises SSHManager.parsePrivateKey with keys generated at test time (see
//  TestKeys). No private-key material is committed.
//

import Testing
import Foundation
import CryptoKit
import Citadel
@testable import simplessh

struct PrivateKeyParsingTests {

    /// The parser's failure reason, or nil when parsing succeeded.
    private func failureReason(_ text: String) -> String? {
        do {
            _ = try SSHManager.parsePrivateKey(text)
            return nil
        } catch let error as SSHManager.SSHError {
            if case .keyParsingFailed(let reason) = error { return reason }
            return error.errorDescription
        } catch {
            return String(describing: error)
        }
    }

    // MARK: - Accepted formats

    @Test func parsesOpenSSHEd25519() throws {
        let key = Curve25519.Signing.PrivateKey()
        let parsed = try SSHManager.parsePrivateKey(TestKeys.opensshEd25519(key))
        guard case .ed25519(let decoded) = parsed else {
            Issue.record("expected an Ed25519 key, got \(parsed)")
            return
        }
        #expect(decoded.rawRepresentation == key.rawRepresentation)
        #expect(decoded.publicKey.rawRepresentation == key.publicKey.rawRepresentation)
    }

    @Test func toleratesSurroundingWhitespaceAndCRLF() throws {
        let key = Curve25519.Signing.PrivateKey()
        let text = "\n  " + TestKeys.opensshEd25519(key, lineEnding: "\r\n") + "\n\n"
        let parsed = try SSHManager.parsePrivateKey(text)
        guard case .ed25519(let decoded) = parsed else {
            Issue.record("expected an Ed25519 key")
            return
        }
        #expect(decoded.rawRepresentation == key.rawRepresentation)
    }

    @Test func parsesOpenSSHRSA() throws {
        let rsa = try TestKeys.generateRSA()
        let parsed = try SSHManager.parsePrivateKey(TestKeys.opensshRSA(rsa))
        guard case .rsa(let decoded) = parsed else {
            Issue.record("expected an RSA key, got \(parsed)")
            return
        }
        let publicKey = try #require(decoded.publicKey as? Insecure.RSA.PublicKey)
        #expect(Array(publicKey.rawRepresentation) == TestKeys.mpint(rsa.e) + TestKeys.mpint(rsa.n))
        try expectSignatureRoundTrip(decoded)
    }

    @Test func parsesPEMPKCS1RSA() throws {
        let rsa = try TestKeys.generateRSA()
        let parsed = try SSHManager.parsePrivateKey(TestKeys.pkcs1RSA(rsa))
        guard case .rsa(let decoded) = parsed else {
            Issue.record("expected an RSA key, got \(parsed)")
            return
        }
        let publicKey = try #require(decoded.publicKey as? Insecure.RSA.PublicKey)
        #expect(Array(publicKey.rawRepresentation) == TestKeys.mpint(rsa.e) + TestKeys.mpint(rsa.n))
        try expectSignatureRoundTrip(decoded)
    }

    /// A signature made with the decoded private exponent must verify under
    /// the decoded public key; this is what proves `d` was read correctly.
    private func expectSignatureRoundTrip(_ key: Insecure.RSA.PrivateKey) throws {
        let message = Data("simplessh".utf8)
        let signature: Insecure.RSA.Signature = try key.signature(for: message)
        let publicKey = try #require(key.publicKey as? Insecure.RSA.PublicKey)
        #expect(publicKey.isValidSignature(signature, for: message))
        #expect(!publicKey.isValidSignature(signature, for: Data("tampered".utf8)))
    }

    // MARK: - Rejections

    @Test func rejectsEncryptedKey() {
        let reason = failureReason(TestKeys.opensshEncrypted())
        #expect(reason?.localizedCaseInsensitiveContains("encrypted") == true, "\(String(describing: reason))")
    }

    @Test func rejectsUnsupportedKeyTypeByName() {
        let reason = failureReason(TestKeys.opensshUnsupportedType("ecdsa-sha2-nistp256"))
        #expect(reason?.contains("ecdsa-sha2-nistp256") == true, "\(String(describing: reason))")
    }

    @Test func rejectsTruncatedKey() {
        let whole = TestKeys.payload(of: TestKeys.opensshEd25519(Curve25519.Signing.PrivateKey()))
        // Cut inside the private section (public blob intact) and inside the
        // public blob; both must throw rather than crash or return a key.
        for keep in [whole.count - 40, 40] {
            let cut = Array(whole.prefix(keep))
            let text = TestKeys.armour(cut, label: TestKeys.opensshLabel)
            #expect(failureReason(text) != nil, "kept \(keep) of \(whole.count) bytes")
        }
    }

    @Test func rejectsTinyPayloadWithoutCrashing() {
        // Three bytes of payload. The former marker scan indexed a negative
        // range here and crashed the app.
        let text = TestKeys.armour([0, 0, 0], label: TestKeys.opensshLabel)
        #expect(failureReason(text) != nil)
    }

    @Test func rejectsWrongMagic() {
        let bytes = Array("not-an-openssh-key-at-all-but-long-enough".utf8)
        let text = TestKeys.armour(bytes, label: TestKeys.opensshLabel)
        #expect(failureReason(text)?.contains("magic") == true)
    }

    @Test func rejectsInvalidBase64() {
        let text = TestKeys.armourRaw(body: "@@@@", label: TestKeys.opensshLabel)
        #expect(failureReason(text)?.contains("base64") == true)
    }

    @Test func rejectsMalformedPKCS1() {
        let text = TestKeys.armour([0, 0, 0], label: TestKeys.pkcs1Label)
        #expect(failureReason(text)?.contains("SEQUENCE") == true)
    }

    @Test(arguments: [
        "",
        "not a key",
        "ssh-ed25519 " + Data([0, 0, 0, 11] + Array("ssh-ed25519".utf8)).base64EncodedString() + " user@host",
        TestKeys.armour([0, 0, 0], label: "EC PRIVATE KEY"),        // PEM SEC1
        TestKeys.armour([0, 0, 0], label: "PRIVATE KEY"),           // PEM PKCS#8
    ])
    func rejectsUnsupportedFormats(_ text: String) {
        #expect(failureReason(text)?.contains("Unsupported key format") == true)
    }
}
