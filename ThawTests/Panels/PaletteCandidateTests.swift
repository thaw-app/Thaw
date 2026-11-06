//
//  PaletteCandidateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// The palette matches three fields per item where MenuBarSearchPanel
/// matches one, so these cover which fields reach the matcher at all.
@Suite("Palette candidate properties")
struct PaletteCandidateTests {
    /// The AX provider mints Item-<n> for children that publish no title.
    /// Every one of them fuzzy-matches the query "item", so they must not
    /// reach the matcher.
    @Test("Placeholder identity keys are not matchable")
    func placeholderKeysDropped() {
        #expect(PaletteCandidate.matchableIdentityKey("com.example.app:Item-0") == nil)
        #expect(PaletteCandidate.matchableIdentityKey("com.example.app:Item-12") == nil)
        #expect(PaletteCandidate.matchableIdentityKey("Item-3") == nil)
    }

    @Test("Real identity keys stay matchable")
    func realKeysKept() {
        #expect(PaletteCandidate.matchableIdentityKey("com.example.app:Battery") != nil)
        // "Item-" with a non-numeric tail is a real title, not a placeholder.
        #expect(PaletteCandidate.matchableIdentityKey("com.example.app:Item-Tracker") != nil)
        #expect(PaletteCandidate.matchableIdentityKey("com.example.app:Items") != nil)
    }

    @Test("An empty key is not matchable")
    func emptyKeyDropped() {
        #expect(PaletteCandidate.matchableIdentityKey("") == nil)
    }
}
