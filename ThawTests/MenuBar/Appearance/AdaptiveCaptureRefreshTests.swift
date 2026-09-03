//
//  AdaptiveCaptureRefreshTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers what an appearance configuration asks the menu bar manager to sample,
/// and what a change to it does to the running adaptive refresh.
///
/// The captures themselves need a window server and a real wallpaper, so what
/// is pinned here is the decision in front of them. The case that matters is a
/// move between two adaptive kinds: `.adaptive` and `.adaptiveGradient` are
/// both adaptive, yet only the gradient renders from a palette, so treating the
/// pair as one state leaves the bar on its average-color fallback until an
/// unrelated poll happens to fire.
@Suite("Adaptive capture refresh")
struct AdaptiveCaptureRefreshTests {
    private func requirements(
        tintKind: MenuBarTintKind = .noTint,
        backgroundKind: MenuBarBackgroundKind = .none,
        tintOpacity: Double = 0.2
    ) -> MenuBarManager.AdaptiveCaptureRequirements {
        var configuration = MenuBarAppearancePartialConfiguration.defaultConfiguration
        configuration.tintKind = tintKind
        configuration.backgroundKind = backgroundKind
        configuration.tintOpacity = tintOpacity
        return MenuBarManager.AdaptiveCaptureRequirements(configuration: configuration)
    }

    // MARK: - Requirements

    @Test("A static appearance samples nothing")
    func staticAppearanceSamplesNothing() {
        let staticAppearance = requirements(tintKind: .solid, backgroundKind: .gradient)

        #expect(!staticAppearance.needsAverageColor)
        #expect(!staticAppearance.needsPalette)
        #expect(!staticAppearance.isAdaptive)
    }

    @Test("An adaptive tint or background needs the average color alone")
    func adaptiveKindsNeedTheAverageColor() {
        let adaptiveTint = requirements(tintKind: .adaptive)
        let adaptiveBackground = requirements(backgroundKind: .adaptive)

        for adaptive in [adaptiveTint, adaptiveBackground] {
            #expect(adaptive.needsAverageColor)
            #expect(!adaptive.needsPalette)
            #expect(adaptive.isAdaptive)
        }
    }

    @Test("The adaptive gradient needs a palette on top of the average color")
    func adaptiveGradientNeedsAPalette() {
        let gradient = requirements(tintKind: .adaptiveGradient)

        #expect(gradient.needsAverageColor)
        #expect(gradient.needsPalette)
        #expect(gradient.isAdaptive)
    }

    // MARK: - Refresh Transitions

    @Test("Switching between the two adaptive tints captures right away")
    func switchingBetweenAdaptiveTintsCaptures() {
        let adaptive = requirements(tintKind: .adaptive)
        let gradient = requirements(tintKind: .adaptiveGradient)

        #expect(MenuBarManager.adaptiveRefreshAction(from: adaptive, to: gradient) == .recapture)
        #expect(MenuBarManager.adaptiveRefreshAction(from: gradient, to: adaptive) == .recapture)
    }

    @Test("An adaptive background gaining the gradient tint captures right away")
    func adaptiveBackgroundGainingTheGradientCaptures() {
        let background = requirements(backgroundKind: .adaptive)
        let backgroundWithGradient = requirements(tintKind: .adaptiveGradient, backgroundKind: .adaptive)

        #expect(
            MenuBarManager.adaptiveRefreshAction(from: background, to: backgroundWithGradient) == .recapture
        )
    }

    @Test("Turning an adaptive kind on starts the refresh")
    func turningAdaptiveOnStartsTheRefresh() {
        let solid = requirements(tintKind: .solid)

        #expect(MenuBarManager.adaptiveRefreshAction(from: solid, to: requirements(tintKind: .adaptive)) == .start)
        #expect(
            MenuBarManager.adaptiveRefreshAction(from: nil, to: requirements(tintKind: .adaptiveGradient)) == .start
        )
    }

    @Test("Turning every adaptive kind off stops the refresh")
    func turningAdaptiveOffStopsTheRefresh() {
        let gradient = requirements(tintKind: .adaptiveGradient)
        let solid = requirements(tintKind: .solid)

        #expect(MenuBarManager.adaptiveRefreshAction(from: gradient, to: solid) == .stop)
        // The first configuration seen is stopped rather than left alone, so a
        // refresh from an earlier observer never outlives it.
        #expect(MenuBarManager.adaptiveRefreshAction(from: nil, to: solid) == .stop)
    }

    @Test("An appearance change that samples the same thing leaves the refresh alone")
    func unrelatedChangeLeavesTheRefreshAlone() {
        let gradient = requirements(tintKind: .adaptiveGradient, tintOpacity: 0.2)
        let fainterGradient = requirements(tintKind: .adaptiveGradient, tintOpacity: 0.6)

        #expect(MenuBarManager.adaptiveRefreshAction(from: gradient, to: fainterGradient) == .unchanged)
    }
}
