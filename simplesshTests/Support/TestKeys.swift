//
//  TestKeys.swift
//  simplesshTests
//
//  Builds private-key text in the formats the app accepts.
//
//  Every key is generated while the test runs and discarded afterwards. Nothing
//  in this file is, or may ever become, stored key material: the repository's
//  pre-push gate rejects committed PEM blocks, and these helpers exist so the
//  tests never need one.
//

import Foundation
import CryptoKit
import Security

enum TestKeys {

    // MARK: - SSH wire encoding (RFC 4251)

    static func uint32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    /// `string`: uint32 length followed by the bytes.
    static func sshString(_ bytes: [UInt8]) -> [UInt8] { uint32(UInt32(bytes.count)) + bytes }
    static func sshString(_ text: String) -> [UInt8] { sshString(Array(text.utf8)) }

    /// `mpint` of a positive magnitude: leading zeros dropped, a 0x00 byte
    /// prepended when the top bit is set so the value stays positive.
    static func mpint(_ magnitude: [UInt8]) -> [UInt8] {
        var m = Array(magnitude.drop(while: { $0 == 0 }))
        if let first = m.first, first & 0x80 != 0 { m.insert(0, at: 0) }
        return sshString(m)
    }

    // MARK: - PEM armour

    static func armour(_ der: [UInt8], label: String, lineEnding: String = "\n") -> String {
        let body = Data(der)
            .base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
            .replacingOccurrences(of: "\n", with: lineEnding)
        return "-----BEGIN \(label)-----\(lineEnding)\(body)\(lineEnding)-----END \(label)-----\(lineEnding)"
    }

    /// Armour with a verbatim body (for fixtures that are not valid base64).
    static func armourRaw(body: String, label: String) -> String {
        "-----BEGIN \(label)-----\n\(body)\n-----END \(label)-----\n"
    }

    static let opensshLabel = "OPENSSH PRIVATE KEY"
    static let pkcs1Label = "RSA PRIVATE KEY"

    /// Decodes the base64 body of an armoured key back to bytes.
    static func payload(of armoured: String) -> [UInt8] {
        let body = armoured
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            .joined()
        return Array(Data(base64Encoded: body)!)
    }

    // MARK: - openssh-key-v1 container

    /// Wraps a public blob and the private-section fields in an unencrypted
    /// openssh-key-v1 container: matching check integers, comment, and 1..n
    /// padding to the 8-byte block size of cipher "none".
    static func opensshContainer(publicBlob: [UInt8],
                                 privateFields: [UInt8],
                                 comment: String = "simplessh-test") -> [UInt8] {
        let check = uint32(0x5F5F5F5F)
        var privateSection = check + check + privateFields + sshString(comment)
        var pad: UInt8 = 1
        while privateSection.count % 8 != 0 { privateSection.append(pad); pad += 1 }
        return Array("openssh-key-v1\0".utf8)
            + sshString("none") + sshString("none") + sshString([])
            + uint32(1)
            + sshString(publicBlob)
            + sshString(privateSection)
    }

    /// An unencrypted OpenSSH Ed25519 private key for `key`.
    static func opensshEd25519(_ key: Curve25519.Signing.PrivateKey,
                               comment: String = "simplessh-test",
                               lineEnding: String = "\n") -> String {
        let pub = Array(key.publicKey.rawRepresentation)
        let seed = Array(key.rawRepresentation)
        let publicBlob = sshString("ssh-ed25519") + sshString(pub)
        let fields = sshString("ssh-ed25519") + sshString(pub) + sshString(seed + pub)
        let container = opensshContainer(publicBlob: publicBlob, privateFields: fields, comment: comment)
        return armour(container, label: opensshLabel, lineEnding: lineEnding)
    }

    /// An unencrypted OpenSSH RSA private key for `rsa`.
    static func opensshRSA(_ rsa: RSAComponents, comment: String = "simplessh-test") -> String {
        let publicBlob = sshString("ssh-rsa") + mpint(rsa.e) + mpint(rsa.n)
        let fields = sshString("ssh-rsa")
            + mpint(rsa.n) + mpint(rsa.e) + mpint(rsa.d)
            + mpint(rsa.qinv) + mpint(rsa.p) + mpint(rsa.q)
        let container = opensshContainer(publicBlob: publicBlob, privateFields: fields, comment: comment)
        return armour(container, label: opensshLabel)
    }

    /// A PEM PKCS#1 `RSA PRIVATE KEY` for `rsa`.
    static func pkcs1RSA(_ rsa: RSAComponents) -> String {
        armour(rsa.der, label: pkcs1Label)
    }

    /// A well-formed container whose public blob names an algorithm the app
    /// does not support. The key bytes are placeholders; only the name matters.
    static func opensshUnsupportedType(_ name: String = "ecdsa-sha2-nistp256") -> String {
        let point = [UInt8](repeating: 0x04, count: 65)
        let publicBlob = sshString(name) + sshString("nistp256") + sshString(point)
        let fields = publicBlob + mpint([UInt8](repeating: 0x07, count: 32))
        let container = opensshContainer(publicBlob: publicBlob, privateFields: fields)
        return armour(container, label: opensshLabel)
    }

    /// Looks like a passphrase-protected key: cipher aes256-ctr, KDF bcrypt,
    /// and a private section of bytes that do not decrypt to matching check
    /// integers without the passphrase.
    static func opensshEncrypted() -> String {
        let key = Curve25519.Signing.PrivateKey()
        let publicBlob = sshString("ssh-ed25519") + sshString(Array(key.publicKey.rawRepresentation))
        let kdfOptions = sshString([UInt8](repeating: 0xA5, count: 16)) + uint32(16)
        var privateSection = [UInt8](repeating: 0x42, count: 160)
        privateSection.replaceSubrange(0..<8, with: [1, 2, 3, 4, 5, 6, 7, 8])   // check0 != check1
        let container = Array("openssh-key-v1\0".utf8)
            + sshString("aes256-ctr") + sshString("bcrypt") + sshString(kdfOptions)
            + uint32(1)
            + sshString(publicBlob)
            + sshString(privateSection)
        return armour(container, label: opensshLabel)
    }

    // MARK: - RSA generation

    /// The integers of a PKCS#1 `RSAPrivateKey`, plus its DER encoding.
    struct RSAComponents {
        let der: [UInt8]
        let n: [UInt8], e: [UInt8], d: [UInt8]
        let p: [UInt8], q: [UInt8]
        let dp: [UInt8], dq: [UInt8], qinv: [UInt8]
    }

    enum GenerationFailure: Error { case keygen(String), export, der }

    /// Generates an RSA key with the Security framework and reads its PKCS#1
    /// components with an independent DER walker (not the app's).
    static func generateRSA(bits: Int = 2048) throws -> RSAComponents {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: bits,
            kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: false],
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw GenerationFailure.keygen(String(describing: error?.takeRetainedValue()))
        }
        guard let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw GenerationFailure.export
        }
        let der = Array(data)
        var reader = DERReader(der)
        try reader.enterSequence()
        var ints: [[UInt8]] = []
        for _ in 0..<9 { ints.append(try reader.integer()) }   // version, n, e, d, p, q, dp, dq, qinv
        return RSAComponents(der: der,
                             n: ints[1], e: ints[2], d: ints[3],
                             p: ints[4], q: ints[5],
                             dp: ints[6], dq: ints[7], qinv: ints[8])
    }

    private struct DERReader {
        let bytes: [UInt8]
        var offset = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func byte() throws -> UInt8 {
            guard offset < bytes.count else { throw GenerationFailure.der }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func length() throws -> Int {
            let first = try byte()
            if first < 0x80 { return Int(first) }
            var value = 0
            for _ in 0..<Int(first & 0x7F) { value = (value << 8) | Int(try byte()) }
            return value
        }

        mutating func enterSequence() throws {
            guard try byte() == 0x30 else { throw GenerationFailure.der }
            _ = try length()
        }

        /// Unsigned magnitude of the next INTEGER, leading zeros stripped.
        mutating func integer() throws -> [UInt8] {
            guard try byte() == 0x02 else { throw GenerationFailure.der }
            let count = try length()
            guard offset + count <= bytes.count else { throw GenerationFailure.der }
            let value = Array(bytes[offset..<(offset + count)])
            offset += count
            return Array(value.drop(while: { $0 == 0 }))
        }
    }
}
