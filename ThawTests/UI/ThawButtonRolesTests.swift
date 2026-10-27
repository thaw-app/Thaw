//
//  ThawButtonRolesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("Button roles")
struct ThawButtonRolesTests {
    private func fittingSize(of view: some View) -> NSSize {
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    @Test("Each role draws a button with room for its label")
    func rolesRender() {
        let primary = fittingSize(of: Button("Continue") {}.buttonStyle(.thawPrimary))
        let secondary = fittingSize(of: Button("Continue") {}.buttonStyle(.thawSecondary))
        let inline = fittingSize(of: Button("Continue") {}.buttonStyle(.thawInline))

        for size in [primary, secondary, inline] {
            #expect(size.width > 0 && size.height > 0)
        }
    }

    @Test("A secondary action is padded wider than an inline one")
    func secondaryIsPadded() {
        let secondary = fittingSize(of: Button("Continue") {}.buttonStyle(.thawSecondary))
        let inline = fittingSize(of: Button("Continue") {}.buttonStyle(.thawInline))

        #expect(secondary.width > inline.width)
    }

    @Test("A destructive button renders in the primary role")
    func destructivePrimaryRenders() {
        let view = Button("Delete", role: .destructive) {}.buttonStyle(.thawPrimary)

        #expect(fittingSize(of: view).width > 0)
    }
}
