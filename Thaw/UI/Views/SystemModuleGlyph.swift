//
//  SystemModuleGlyph.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// The SF Symbol for a system module that has no picture, such as Bluetooth after Thaw
/// switched it off to hide it. Such a module is never drawn, so it can't be photographed.
enum SystemModuleGlyph {
    /// By catalog module name. Bluetooth and AirDrop exist only in macOS's private symbol set.
    private static let symbolNamesByModule: [String: String] = [
        "AirDrop": "airdrop",
        "Battery": "battery.100",
        "Bluetooth": "bluetooth",
        "Displays": "display",
        "FocusModes": "moon.fill",
        "Keyboard": "keyboard",
        "NowPlaying": "play.circle",
        "ScreenMirroring": "rectangle.on.rectangle",
        "Sound": "speaker.wave.2.fill",
        "Timer": "timer",
        "UserSwitcher": "person.crop.circle",
        "WiFi": "wifi",
    ]

    /// The symbol for the module an item title names, in any form the catalog accepts.
    static func symbolName(forItemTitle title: String) -> String? {
        SystemMenuBarModuleCatalog.moduleName(matching: title).flatMap { symbolNamesByModule[$0] }
    }

    /// The module's symbol as a template image, or nil when the title names no module or macOS
    /// no longer has the symbol.
    @MainActor
    static func image(forItemTitle title: String) -> NSImage? {
        guard let name = symbolName(forItemTitle: title) else { return nil }
        let image = privateSymbol(name) ?? NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    /// AppKit's private symbol loader, which also finds the public symbols.
    private static func privateSymbol(_ name: String) -> NSImage? {
        let selector = NSSelectorFromString("imageWithPrivateSystemSymbolName:accessibilityDescription:")
        guard NSImage.responds(to: selector), let implementation = NSImage.method(for: selector) else { return nil }
        typealias Loader = @convention(c) (AnyClass, Selector, NSString, NSString?) -> NSImage?
        return unsafeBitCast(implementation, to: Loader.self)(NSImage.self, selector, name as NSString, nil)
    }
}
