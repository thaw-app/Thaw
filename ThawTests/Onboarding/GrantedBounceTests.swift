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
    @Test("The checkmark bounces for a grant made while it is shown, and stays still under Reduce Motion")
    func bouncesUnlessReduced() {
        #expect(GrantedBounce.bounces(justGranted: true, reduceMotion: false))
        #expect(!GrantedBounce.bounces(justGranted: true, reduceMotion: true))
    }

    @Test("A permission already granted when its card appears does not bounce")
    func staysStillWithoutAGrant() {
        #expect(!GrantedBounce.bounces(justGranted: false, reduceMotion: false))
        #expect(!GrantedBounce.bounces(justGranted: false, reduceMotion: true))
    }

    @Test("Content keeps its size with the bounce applied")
    func keepsLayout() {
        let plain = NSHostingView(rootView: Image(systemName: "checkmark.circle.fill"))
        let bounced = NSHostingView(rootView: Image(systemName: "checkmark.circle.fill").modifier(GrantedBounce(justGranted: true)))
        #expect(plain.fittingSize == bounced.fittingSize)
    }
}
