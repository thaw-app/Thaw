//
//  SearchLauncherLookTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw
import ThawUI

/// The search panel follows the menu bar's look, as Floe does when it follows Thaw.
@Suite("Search panel look")
struct SearchLauncherLookTests {
    private func look(_ configure: (inout MenuBarAppearancePartialConfiguration) -> Void) -> LauncherLook {
        var configuration = MenuBarAppearancePartialConfiguration.defaultConfiguration
        configure(&configuration)
        return SharedAppearance(configuration: configuration, shapeKind: .full, hasRoundedShape: true, isDark: true).launcherLook()
    }

    @Test("A plain bar leaves the launcher's own glass, with no tint, border or shadow")
    func plainBar() {
        let look = look { configuration in
            configuration.tintKind = .noTint
            configuration.backgroundKind = .none
            configuration.hasBorder = false
            configuration.hasShadow = false
        }
        #expect(look.glass.style == .regular)
        #expect(look.tint.kind == .none)
        #expect(look.border == nil)
        #expect(!look.hasShadow)
    }

    @Test("The bar's Dynamic Glass, border and shadow carry over")
    func dynamicGlass() {
        let look = look { configuration in
            configuration.tintKind = .glass
            configuration.tintGlassFinish = MenuBarGlassFinish(style: .dynamic, isTinted: false)
            configuration.hasBorder = true
            configuration.borderWidth = 2
            configuration.hasShadow = true
        }
        #expect(look.glass.style == .dynamic)
        #expect(look.tint.kind == .none, "a glass is not a tint")
        #expect(look.border?.width == 2)
        #expect(look.hasShadow)
    }

    @Test("A solid tint becomes the launcher's tint, at its opacity")
    func solidTint() {
        let look = look { configuration in
            configuration.tintKind = .solid
            configuration.tintColor = CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)
            configuration.tintOpacity = 0.4
        }
        #expect(look.tint.kind == .solid)
        #expect(look.tint.opacity == 0.4)
        #expect(look.tint.solid.red == 1)
        #expect(look.tint.backgroundStyle != nil)
    }

    @Test("A gradient takes its outermost stops and its angle")
    func gradientTint() {
        let look = look { configuration in
            configuration.tintKind = .gradient
            configuration.tintGradient = ThawGradient(stops: [
                .stop(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), location: 0),
                .stop(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1), location: 0.5),
                .stop(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), location: 1),
            ])
        }
        #expect(look.tint.kind == .gradient)
        #expect(look.tint.gradient.start.red == 1)
        #expect(look.tint.gradient.end.blue == 1)
    }

    @Test("An adaptive tint has no colour to copy, so the launcher keeps its own")
    func adaptiveTintIsNotCopied() {
        let look = look { configuration in
            configuration.tintKind = .adaptive
            configuration.backgroundKind = .none
        }
        #expect(look.tint == LauncherTint())
    }
}
