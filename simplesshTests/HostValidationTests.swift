//
//  HostValidationTests.swift
//  simplesshTests
//

import Testing
@testable import simplessh

struct HostValidationTests {

    @Test(arguments: [
        "192.168.1.1", "10.0.0.254", "0.0.0.0", "255.255.255.255",
        "::1", "fe80::1", "2001:db8::1", "::ffff:192.0.2.1",
        "localhost", "pve", "gibbs.mjhomelab.dev", "my-host.example.com",
        "a.b.c.d.e", "host1", "1host.example.com", "xn--bcher-kva.example",
    ])
    func acceptsValidHosts(_ host: String) {
        #expect(AddConnectionView.isValidHost(host))
    }

    @Test(arguments: [
        "", " ", "host name", "user@host", "host_name",
        "172.20..20.222",      // the double-dot typo the message warns about
        "172.20.20.",          // empty last octet
        ".172.20.20.222",      // leading dot
        "172.20.20",           // three octets
        "1.2.3.4.5",           // five octets
        "256.1.1.1",           // octet out of range
        "1.2.3.-1",            // label starting with a hyphen
        "host..name", "-host.com", "host-.com",
        "1.2.3.4:22",          // port belongs in its own field
        "[::1]", ":::",
        String(repeating: "a", count: 64) + ".com",                          // label over 63
        Array(repeating: "abcdefghij", count: 25).joined(separator: ".") + ".abcd",  // 254 chars
    ])
    func rejectsInvalidHosts(_ host: String) {
        #expect(!AddConnectionView.isValidHost(host))
    }
}
