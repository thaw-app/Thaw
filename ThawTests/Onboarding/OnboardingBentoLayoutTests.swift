//
//  OnboardingBentoLayoutTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// The welcome bento and its demos, drawn off screen at the window's size.
@Suite("Onboarding bento layout")
@MainActor
struct OnboardingBentoLayoutTests {
    private func layOut(_ view: some View, size: CGSize) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        return host
    }

    @Test("The bento fits the window it opens in, two cards a row")
    func bentoFitsTheWindow() {
        let host = layOut(OnboardingBentoView(finishesFlow: true) { _, _ in }, size: CGSize(width: 680, height: 680))
        #expect(host.fittingSize.height <= 700)
        #expect(host.fittingSize.width <= 700)
    }

    @Test("Every demo draws at a card's size, moving and still", arguments: BentoDemo.allCases)
    func demosDraw(demo: BentoDemo) {
        for phase in [0.0, 0.5, 1.0] {
            let host = layOut(BentoDemoContent(demo: demo, phase: phase), size: CGSize(width: 300, height: 120))
            #expect(host.frame.width == 300)
        }
    }

    @Test("An integration names its app under the icon")
    func integrationCard() {
        let card = IntegrationCard(appName: "Shortcuts", bundledAssetName: nil, fallbackSymbol: "square.2.layers.3d")
        let host = layOut(card, size: CGSize(width: 90, height: 60))
        #expect(host.fittingSize.height > 0)
    }
}
