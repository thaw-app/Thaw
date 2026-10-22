//
//  OnboardingPrimaryButtonTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("Onboarding primary button")
struct OnboardingPrimaryButtonTests {
    private static func fittingSize(title: String) -> CGSize {
        let host = NSHostingView(rootView: OnboardingPrimaryButton(action: {}, label: { Text(title) }))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        return host.fittingSize
    }

    @Test("A short title still gets the shared minimum size")
    func minimumSize() {
        let size = Self.fittingSize(title: "OK")
        #expect(size.width >= 140)
        #expect(size.height >= 34)
    }

    @Test("A long title grows the button instead of clipping")
    func longTitleGrows() {
        let short = Self.fittingSize(title: "OK")
        let long = Self.fittingSize(title: "Continue to the Next Step of Setup")
        #expect(long.width > short.width)
    }
}
