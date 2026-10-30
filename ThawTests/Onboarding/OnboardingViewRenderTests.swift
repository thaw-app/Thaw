//
//  OnboardingViewRenderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

/// The onboarding screens drawn off screen at the onboarding window's size.
@MainActor
@Suite("Onboarding screens render", .serialized, .scratchDefaults)
struct OnboardingViewRenderTests {
    private static let windowSize = CGSize(width: 680, height: 680)

    private func render(_ view: some View, size: CGSize = windowSize) throws -> (OffscreenRender<AnyView>, Data) {
        let render = OffscreenRender(AnyView(view.frame(width: size.width, height: size.height)), size: size)
        return try (render, render.pixels())
    }

    @Test("The welcome screen draws something at the window's size")
    func welcomeDraws() throws {
        var continued = false
        let (render, pixels) = try render(OnboardingWelcomeView { continued = true })
        #expect(pixels.contains { $0 != 0 })
        #expect(render.host.fittingSize.height <= 700)
        #expect(!continued)
    }

    @Test("The onboarding flow opens on the welcome screen without numbering it")
    func flowOpensOnWelcome() throws {
        var finished = false
        let flow = ThawOnboardingView(skipsAccessStep: false) { _, _ in finished = true }
        let (render, pixels) = try render(flow)
        #expect(pixels.contains { $0 != 0 })
        #expect(render.host.fittingSize.height <= 700)
        #expect(!finished)
    }

    @Test("The bento is numbered as step one of two, and not numbered when it is the only step")
    func bentoStepNumbering() throws {
        func bento(skipsAccess: Bool) throws -> Data {
            try render(ThawOnboardingView(skipsAccessStep: skipsAccess, startingStep: .bento) { _, _ in }).1
        }
        let numbered = try bento(skipsAccess: false)
        let unnumbered = try bento(skipsAccess: true)
        #expect(numbered.contains { $0 != 0 })
        // The indicator sits along the top edge, above anything the bento changes for the last step.
        let top = numbered.count / 14
        #expect(numbered.prefix(top) != unnumbered.prefix(top), "only the two-step flow draws the indicator")
    }

    @Test("The access step opens numbered without finishing the flow")
    func accessStepDraws() throws {
        let appState = AppState()
        let permissions = appState.permissions
        defer { permissions.stopAllChecks() }
        var finished = false
        let flow = ThawOnboardingView(skipsAccessStep: false, startingStep: .access) { _, _ in finished = true }
        let alone = try render(
            ThawPermissionsView(mode: .onboarding, finishesFlow: true) {}.environment(permissions).environment(appState)
        ).1
        let (access, pixels) = try render(flow.environment(permissions).environment(appState))
        #expect(pixels.contains { $0 != 0 })
        // Below the step indicator, the flow draws exactly the permissions screen.
        let top = pixels.count / 8
        #expect(pixels.dropFirst(top) == alone.dropFirst(top))
        #expect(access.host.fittingSize.height <= 700)
        #expect(!finished)
    }

    @Test("The step indicator grows with the number of steps")
    func stepIndicator() {
        let one = OffscreenRender(OnboardingStepIndicator(step: 1, total: 1), size: CGSize(width: 200, height: 40))
        let three = OffscreenRender(OnboardingStepIndicator(step: 2, total: 3), size: CGSize(width: 200, height: 40))
        #expect(three.host.fittingSize.width > one.host.fittingSize.width)
    }

    @Test("The permissions step draws in both modes", arguments: [true, false])
    func permissionsViewDraws(onboarding: Bool) throws {
        let appState = AppState()
        let permissions = appState.permissions
        defer { permissions.stopAllChecks() }
        var continued = false
        let view = ThawPermissionsView(mode: onboarding ? .onboarding : .recovery, finishesFlow: onboarding) {
            continued = true
        }
        let size = Self.windowSize
        let render = OffscreenRender(
            AnyView(view.frame(width: size.width, height: size.height).environment(permissions).environment(appState)),
            size: size
        )
        let pixels = try render.pixels()
        #expect(pixels.contains { $0 != 0 })
        #expect(render.host.fittingSize.width > 0)
        #expect(!continued)
    }
}
