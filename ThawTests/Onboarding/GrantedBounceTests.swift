//
//  GrantedBounceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// A granted permission's checkmark appeared without any sign that something had just happened.
@MainActor
@Suite("Granted bounce")
struct GrantedBounceTests {
    @Test("The checkmark bounces once, and stays still under Reduce Motion")
    func bouncesUnlessReduced() {
        #expect(GrantedBounce.bounces(reduceMotion: false))
        #expect(!GrantedBounce.bounces(reduceMotion: true))
    }

    @Test("Content keeps its size with the bounce applied")
    func keepsLayout() {
        let plain = NSHostingView(rootView: Image(systemName: "checkmark.circle.fill"))
        let bounced = NSHostingView(rootView: Image(systemName: "checkmark.circle.fill").modifier(GrantedBounce()))
        #expect(plain.fittingSize == bounced.fittingSize)
    }
}
