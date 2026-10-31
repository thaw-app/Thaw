//
//  OnboardingPiecesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import ThawUI

@MainActor
@Suite("Onboarding pieces")
struct OnboardingPiecesTests {
    private static func fittingSize(_ view: some View) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        return host.fittingSize
    }

    private static func button(_ title: String) -> some View {
        OnboardingPrimaryButton(action: {}, label: { Text(verbatim: title) })
    }

    @Test("A short title still gets the shared minimum size")
    func minimumSize() {
        let size = Self.fittingSize(Self.button("OK"))
        #expect(size.width >= 140)
        #expect(size.height >= 34)
    }

    @Test("A long title grows the button instead of clipping")
    func longTitleGrows() {
        let short = Self.fittingSize(Self.button("OK"))
        let long = Self.fittingSize(Self.button("Continue to the Next Step of Setup"))
        #expect(long.width > short.width)
    }

    @Test("A fact capsule keeps its height whatever its label")
    func capsuleHeight() {
        let short = OnboardingFactCapsule(symbol: "globe", label: Text(verbatim: "Hi"), spoken: Text(verbatim: "Hello"))
        let long = OnboardingFactCapsule(symbol: "globe", label: Text(verbatim: "A label far longer than any capsule in a row has room for"), spoken: Text(verbatim: "Hello"))
        #expect(Self.fittingSize(short).height == 30)
        #expect(Self.fittingSize(long.frame(width: 120)).height == 30)
    }

    @Test("A fact row stops at the width it is given")
    func factRowWidth() {
        let row = OnboardingFactRow(maxWidth: 200) {
            OnboardingFactCapsule(symbol: "globe", label: Text(verbatim: "Hi"), spoken: Text(verbatim: "Hello"))
            OnboardingFactCapsule(symbol: "lock", label: Text(verbatim: "Yo"), spoken: Text(verbatim: "Hello"))
        }
        #expect(Self.fittingSize(row).width <= 200)
    }

    @Test("An icon tile is as big as it is told, from a symbol or an image")
    func tileSide() {
        #expect(Self.fittingSize(OnboardingIconTile(symbol: "star")) == CGSize(width: 22, height: 22))
        #expect(Self.fittingSize(OnboardingIconTile(image: Image(systemName: "star"), tint: .red, side: 30)) == CGSize(width: 30, height: 30))
    }

    @Test("A permission card draws on either surface at the spacing it is given", arguments: [OnboardingCardSurface.flat, .glass])
    func permissionCard(surface: OnboardingCardSurface) {
        func card(spacing: CGFloat) -> some View {
            OnboardingPermissionCard(surface: surface, spacing: spacing, isGranted: false) {
                Text(verbatim: "Accessibility")
            } details: {
                Text(verbatim: "Reads the menu bar")
            } control: {
                Button(action: {}, label: { Text(verbatim: "Grant") })
            }
            .frame(width: 240)
        }
        let tight = Self.fittingSize(card(spacing: 2))
        let loose = Self.fittingSize(card(spacing: 20))
        #expect(tight.width == 240)
        #expect(loose.height > tight.height)
    }

    @Test("The welcome layout draws its parts at the window's size")
    func welcomeLayout() {
        let layout = OnboardingWelcomeLayout(continueTitle: Text(verbatim: "Next")) {
            // A step with nothing to do when it continues.
        } hero: {
            OnboardingIconTile(symbol: "star", side: 96)
        } copy: {
            OnboardingHeader(title: Text(verbatim: "Welcome"), message: Text(verbatim: "Glad you came"))
        } exit: {
            OnboardingQuietButton(title: Text(verbatim: "Leave"), help: Text(verbatim: "Leave now")) {}
        }
        let size = Self.fittingSize(layout.frame(width: 760, height: 600))
        #expect(size == CGSize(width: 760, height: 600))
    }

    @Test("A quiet exit has a key only when the app gives it one")
    func quietButtonShortcut() {
        let plain = OnboardingQuietButton(title: Text(verbatim: "Skip"), help: Text(verbatim: "Skip it")) {}
        let quit = OnboardingQuietButton(title: Text(verbatim: "Quit"), help: Text(verbatim: "Quit it"), shortcut: KeyboardShortcut("q")) {}
        #expect(plain.shortcut == nil)
        #expect(quit.shortcut == KeyboardShortcut("q"))
    }

    @Test("A step animation leaves the view's size alone")
    func stepAnimation() {
        let view = Text(verbatim: "Step").frame(width: 80, height: 20)
        #expect(Self.fittingSize(view.onboardingStepAnimation(value: 1)) == CGSize(width: 80, height: 20))
    }

    @Test("The background is a behind-window blend")
    func background() {
        let host = NSHostingView(rootView: VisualEffectBackground().frame(width: 40, height: 40))
        host.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        host.layoutSubtreeIfNeeded()
        func effects(in view: NSView) -> [NSVisualEffectView] {
            view.subviews.flatMap { subview in
                (subview as? NSVisualEffectView).map { [$0] } ?? effects(in: subview)
            }
        }
        let effect = effects(in: host).first
        #expect(effect?.blendingMode == .behindWindow)
        #expect(effect?.material == .hudWindow)
    }

    @Test("The background clears the window it joins, whenever it joins")
    func backgroundClearsWindow() {
        let host = NSHostingView(rootView: VisualEffectBackground().frame(width: 40, height: 40))
        host.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        host.layoutSubtreeIfNeeded()
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        #expect(window.isOpaque)
        window.contentView = host
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)
    }
}
