//
//  MenuBarIconProvider.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Resolves menu bar icons from asset catalogs or SF Symbols,
/// independent of screen capture permissions.
enum MenuBarIconProvider {
    private static let diagLog = DiagLog(category: "MenuBarIconProvider")
    private static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
    private static let renderColorSpace = CGColorSpaceCreateDeviceRGB()

    // MARK: - Public API

    /// Returns a captured image for the given menu bar item, or `nil`
    /// if no icon can be resolved.
    @MainActor
    static func icon(for item: MenuBarItem, scale: CGFloat) -> MenuBarItemImageCache.CapturedImage? {
        // Path A: system items with known SF Symbol mappings.
        if let symbolName = systemSymbol(for: item.tag) {
            return renderSFSymbol(symbolName, scale: scale)
        }

        // Path B: third-party apps — extract from asset catalog or resources.
        guard let bundleURL = item.sourceApplication?.bundleURL ?? item.owningApplication?.bundleURL else {
            return nil
        }

        let hint = item.title
        guard let best = AssetCatalogReader.findBestIcon(in: bundleURL, hint: hint) else {
            return nil
        }

        guard let cgImage = renderNSImage(best.image, scale: scale) else {
            return nil
        }

        return MenuBarItemImageCache.CapturedImage(cgImage: cgImage, scale: scale)
    }

    // MARK: - System Item SF Symbol Mapping

    /// Maps known system menu bar item titles to SF Symbol names.
    private static let systemSymbolMap: [String: String] = [
        // Control Center items
        "WiFi": "wifi",
        "Bluetooth": "bluetooth",
        "Battery": "battery.100percent",
        "Sound": "speaker.wave.2.fill",
        "NowPlaying": "music.note",
        "Focus": "moon.fill",
        "Display": "sun.max.fill",
        "Clock": "clock",
        "FaceTime": "video.fill",
        "MusicRecognition": "shazam.logo.fill",
        "AudioVideoModule": "record.circle",
        "Hearing": "ear",
        "AirPlay": "airplayaudio",
        "UserSwitcher": "person.crop.circle",
        "AccessibilityShortcuts": "accessibility",
        "KeyboardBrightness": "light.max",
        "ScreenMirroring": "rectangle.on.rectangle",
        // SystemUIServer items
        "Siri": "mic.fill",
        // TimeMachine variants
        "com.apple.menuextra.TimeMachine": "clock.arrow.circlepath",
        "TimeMachineMenuExtra.TMMenuExtraHost": "clock.arrow.circlepath",
        "TimeMachine.TMMenuExtraHost": "clock.arrow.circlepath",
    ]

    /// Returns the SF Symbol name for a known system item, or `nil`.
    private static func systemSymbol(for tag: MenuBarItemTag) -> String? {
        guard tag.isSystemItem, !tag.isControlItem else {
            return nil
        }
        // BentoBox items (Control Center aggregates) don't have individual icons.
        if tag.isBentoBox {
            return nil
        }
        return systemSymbolMap[tag.title]
    }

    /// Renders an SF Symbol as a template CGImage suitable for menu bar display.
    private static func renderSFSymbol(_ name: String, scale: CGFloat) -> MenuBarItemImageCache.CapturedImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            diagLog.debug("SF Symbol '\(name)' not found")
            return nil
        }

        let configured = image.withSymbolConfiguration(symbolConfiguration) ?? image
        configured.isTemplate = true

        guard let cgImage = renderNSImage(configured, scale: scale) else {
            return nil
        }

        return MenuBarItemImageCache.CapturedImage(cgImage: cgImage, scale: scale)
    }

    // MARK: - Image Rendering

    /// Renders an NSImage to a CGImage at the given scale factor.
    private static func renderNSImage(_ image: NSImage, scale: CGFloat) -> CGImage? {
        let size = image.size
        let pixelWidth = Int(size.width * scale)
        let pixelHeight = Int(size.height * scale)

        guard pixelWidth > 0, pixelHeight > 0 else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: renderColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let nsGraphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsGraphicsContext

        let drawRect = NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage()
    }
}
