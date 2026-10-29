//
//  SettingsWindowBackgroundTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw

@Suite("Settings window background")
@MainActor
struct SettingsWindowBackgroundTests {
    @Test("Black replaces the dark look only and never pins the appearance")
    func colorFollowsTheScheme() {
        #expect(SettingsWindowBackground.black.color(in: .dark) == .black)
        #expect(SettingsWindowBackground.black.color(in: .light) == nil)
        #expect(SettingsWindowBackground.system.color(in: .dark) == nil)
    }

    @Test("The setting picks the background")
    func fromSetting() {
        #expect(SettingsWindowBackground(isBlack: true) == .black)
        #expect(SettingsWindowBackground(isBlack: false) == .system)
    }

    @Test("A black window fills black in dark mode, keeps its usual fill in light mode, and follows macOS")
    func applyToWindow() throws {
        let window = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false

        SettingsWindowBackground.black.apply(to: window)
        #expect(window.appearance == nil)
        #expect(try brightness(of: window.backgroundColor, in: .darkAqua) == 0)
        #expect(try brightness(of: window.backgroundColor, in: .aqua) > 0.5)

        SettingsWindowBackground.system.apply(to: window)
        #expect(window.appearance == nil)
        #expect(window.backgroundColor == .windowBackgroundColor)
    }

    @Test("A black window draws black behind its content in dark mode only")
    func drawsBlackInDarkModeOnly() throws {
        let dark = OffscreenRender(backgroundView(.dark), size: CGSize(width: 40, height: 40))
        #expect(isBlack(try dark.pixels()))
        let light = OffscreenRender(backgroundView(.light), size: CGSize(width: 40, height: 40))
        #expect(!isBlack(try light.pixels()))
    }

    @Test("A pane backdrop turns black on a black window in dark mode")
    func paneBackdrop() throws {
        let view = SettingsPaneBackdrop(material: .sidebar)
            .environment(\.settingsWindowBackground, .black)
            .environment(\.colorScheme, .dark)
            .frame(width: 40, height: 40)
        let render = OffscreenRender(view, size: CGSize(width: 40, height: 40))
        #expect(isBlack(try render.pixels()))
    }

    @Test("A pane backdrop keeps its material on the system background and in light mode")
    func paneBackdropMaterial() throws {
        for (background, scheme) in [(SettingsWindowBackground.system, ColorScheme.dark), (.black, .light)] {
            let view = SettingsPaneBackdrop(material: .sidebar)
                .environment(\.settingsWindowBackground, background)
                .environment(\.colorScheme, scheme)
                .frame(width: 40, height: 40)
            let render = OffscreenRender(view, size: CGSize(width: 40, height: 40))
            #expect(render.host.subviews.contains { containsEffectView($0) })
        }
    }

    private func backgroundView(_ scheme: ColorScheme) -> some View {
        Color.clear
            .settingsWindowBackground(.black)
            .environment(\.colorScheme, scheme)
            .frame(width: 40, height: 40)
    }

    private func brightness(of color: NSColor, in appearance: NSAppearance.Name) throws -> CGFloat {
        var resolved: NSColor?
        try #require(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        return try #require(resolved).brightnessComponent
    }

    /// RGBA: pure black is opaque with every color byte at zero.
    private func isBlack(_ pixels: Data) -> Bool {
        pixels.enumerated().allSatisfy { index, byte in index % 4 == 3 ? byte == 255 : byte == 0 }
    }

    private func containsEffectView(_ view: NSView) -> Bool {
        view is NSVisualEffectView || view.subviews.contains { containsEffectView($0) }
    }
}
