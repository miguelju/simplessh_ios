//
//  CIRedCheck.swift
//  simplesshTests
//
//  Temporary. Proves the CI workflow turns red on a failing test (roadmap B3
//  acceptance criterion). The next commit deletes this file.
//

import Testing

struct CIRedCheck {
    @Test func deliberateFailure() {
        #expect(Bool(false), "deliberate B3 red check — this file must not survive the PR")
    }
}
