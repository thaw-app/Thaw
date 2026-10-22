//
//  MenuBarPrivateGlassTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
struct MenuBarPrivateGlassTests {
    @Test
    func `each experimental finish names its private variant, and the public styles name none`() {
        #expect(MenuBarGlassStyle.solid.privateVariant == 6)
        #expect(MenuBarGlassStyle.edge.privateVariant == 11)
        #expect(MenuBarGlassStyle.sheer.privateVariant == 15)
        #expect(MenuBarGlassStyle.dim.privateVariant == 18)
        #expect(!MenuBarGlassStyle.solid.followsIconShade, "Invert turns bright when dark and would hide light icons")
        #expect(MenuBarGlassStyle.edge.followsIconShade)
        for style in [MenuBarGlassStyle.regular, .clear, .liquid, .dynamic] {
            #expect(style.privateVariant == nil)
            #expect(!style.isExperimental)
        }
        #expect(MenuBarGlassStyle.allCases.filter(\.isExperimental).allSatisfy { MenuBarPrivateGlass.safeVariants.contains($0.privateVariant ?? -1) })
    }

    @Test
    func `a finish is set, read back, and cleared again`() {
        let view = NSGlassEffectView()
        #expect(MenuBarPrivateGlass.apply(11, to: view))
        #expect((view.value(forKey: MenuBarPrivateGlass.variantKey) as? NSNumber)?.intValue == 11)
        #expect(MenuBarPrivateGlass.apply(nil, to: view))
        #expect((view.value(forKey: MenuBarPrivateGlass.variantKey) as? NSNumber)?.intValue == 0)
    }

    @Test
    func `a value outside the probed range is never set`() {
        let view = NSGlassEffectView()
        #expect(!MenuBarPrivateGlass.apply(22, to: view))
        #expect(!MenuBarPrivateGlass.apply(-1, to: view))
        #expect((view.value(forKey: MenuBarPrivateGlass.variantKey) as? NSNumber)?.intValue == 0)
        #expect(MenuBarPrivateGlass.apply(15, to: view))
        #expect(!MenuBarPrivateGlass.apply(22, to: view))
        #expect((view.value(forKey: MenuBarPrivateGlass.variantKey) as? NSNumber)?.intValue == 0, "A refused value takes the earlier finish off")
    }

    @Test
    func `the glass is light under dark icons and dark under light ones`() {
        #expect(MenuBarIconShade.estimated(barLuminance: 0.9).matchingGlassAppearance == .aqua)
        #expect(MenuBarIconShade.estimated(barLuminance: 0.02).matchingGlassAppearance == .darkAqua)
    }

    @Test
    func `Floe is told the nearest public style for a finish`() {
        #expect(MenuBarGlassStyle.solid.nsGlassStyle == .regular)
        #expect(MenuBarGlassStyle.sheer.nsGlassStyle == .clear)
    }

    @Test
    func `without the private setter only the default can be set`() {
        let view = SetterlessGlass()
        #expect(MenuBarPrivateGlass.apply(nil, to: view))
        #expect(!MenuBarPrivateGlass.apply(11, to: view))
    }

    @Test
    func `a finish that does not stick falls back to the public style`() {
        let view = StubbornGlass()
        #expect(!MenuBarPrivateGlass.apply(11, to: view))
        #expect((view.value(forKey: MenuBarPrivateGlass.variantKey) as? NSNumber)?.intValue == 0)
    }
}

/// Glass from a system without the private setter.
private final class SetterlessGlass: NSGlassEffectView {
    override func responds(to selector: Selector?) -> Bool {
        selector == NSSelectorFromString("set\(MenuBarPrivateGlass.variantKey):") ? false : super.responds(to: selector)
    }
}

/// Glass that takes the setter but keeps its default finish.
private final class StubbornGlass: NSGlassEffectView {
    override func setValue(_ value: Any?, forKey key: String) {
        guard key != MenuBarPrivateGlass.variantKey || (value as? NSNumber)?.intValue == 0 else { return }
        super.setValue(value, forKey: key)
    }
}
