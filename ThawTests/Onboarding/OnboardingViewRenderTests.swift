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
import ThawUI

/// The onboarding screens drawn off screen at the onboarding window's size.
@MainActor
@Suite("Onboarding screens render", .serialized, .scratchDefaults)
struct OnboardingViewRenderTests {
    private static let windowSize = CGSize(
        width: ThawOnboardingWindowMetrics.width,
        height: 640
    )

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

    @Test("The onboarding flow opens on the welcome screen")
    func flowOpensOnWelcome() throws {
        var finished = false
        let flow = ThawOnboardingView(skipsAccessStep: false) { _ in finished = true }
        let (render, pixels) = try render(flow)
        #expect(pixels.contains { $0 != 0 })
        #expect(render.host.fittingSize.height <= 700)
        #expect(!finished)
    }

    @Test("The access step draws exactly the permissions screen without finishing the flow")
    func accessStepDraws() throws {
        let appState = AppState()
        let permissions = appState.permissions
        defer { permissions.stopAllChecks() }
        var finished = false
        let flow = ThawOnboardingView(skipsAccessStep: false, startingStep: .access) { _ in finished = true }
        let alone = try render(
            ThawPermissionsView(mode: .onboarding) {}.environment(permissions).environment(appState)
        ).1
        let (access, pixels) = try render(flow.environment(permissions).environment(appState))
        #expect(pixels.contains { $0 != 0 })
        #expect(pixels == alone)
        #expect(access.host.fittingSize.height <= 700)
        #expect(!finished)
    }

    @Test("The last page draws without finishing the flow")
    func donePageDraws() throws {
        let appState = AppState()
        var finished = false
        let flow = ThawOnboardingView(skipsAccessStep: true, startingStep: .done) { _ in finished = true }
        let (done, pixels) = try render(flow.environment(appState))
        #expect(pixels.contains { $0 != 0 })
        #expect(done.host.fittingSize.height <= 700)
        #expect(!finished)
    }

    @Test("The permissions step draws in both modes", arguments: [true, false])
    func permissionsViewDraws(onboarding: Bool) throws {
        let appState = AppState()
        let permissions = appState.permissions
        defer { permissions.stopAllChecks() }
        var continued = false
        let view = ThawPermissionsView(mode: onboarding ? .onboarding : .recovery) {
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

    @Test("The permissions window offers no Reduced mode while Accessibility is missing")
    func noReducedModeOffer() {
        let missing = OnboardingPreview.permissions()
        let granted = OnboardingPreview.permissions(granted: [.accessibility])
        defer {
            missing.stopAllChecks()
            granted.stopAllChecks()
        }
        #expect(fittingHeight(missing) == fittingHeight(granted), "no extra line above the footer")
    }

    private func fittingHeight(_ permissions: AppPermissions) -> CGFloat {
        let host = NSHostingView(rootView: ThawPermissionsView(mode: .onboarding, onContinue: {})
            .frame(width: ThawOnboardingWindowMetrics.width)
            .environment(permissions))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }
}
