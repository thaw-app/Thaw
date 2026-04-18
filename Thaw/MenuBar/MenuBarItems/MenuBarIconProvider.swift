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

    /// Weak reference to the app state, set during image cache setup.
    @MainActor
    static weak var appState: AppState?

    // MARK: - Public API

    /// Returns a captured image for the given menu bar item, or `nil`
    /// if no icon can be resolved. The image is rendered at the item's
    /// actual bounds size to preserve menu bar spacing in the layout pane.
    @MainActor
    static func icon(for item: MenuBarItem, scale: CGFloat) -> MenuBarItemImageCache.CapturedImage? {
        let canvasSize = item.bounds.size

        // Path A: Thaw's own control items — render the configured icon.
        if item.tag.isControlItem, let appState = MenuBarIconProvider.appState {
            return renderThawControlItem(item, appState: appState, canvasSize: canvasSize, scale: scale)
        }

        // Path B: system items with known SF Symbol or named image mappings.
        if let systemImage = systemIcon(for: item.tag, canvasSize: canvasSize, scale: scale) {
            return systemImage
        }

        // Path C: third-party apps — extract from asset catalog or resources.
        guard let bundleURL = item.sourceApplication?.bundleURL ?? item.owningApplication?.bundleURL else {
            return nil
        }

        guard let best = AssetCatalogReader.findBestIcon(in: bundleURL) else {
            return nil
        }

        let forceMono = best.name.hasPrefix("mono:")

        guard let cgImage = renderNSImage(best.image, canvasSize: canvasSize, scale: scale, forceMono: forceMono) else {
            return nil
        }

        return MenuBarItemImageCache.CapturedImage(cgImage: cgImage, scale: scale)
    }

    // MARK: - System Item SF Symbol Mapping

    /// Maps known system menu bar item titles to SF Symbol names.
    /// Internal for testing.
    static let systemSymbolMap: [String: String] = [
        // Control Center items (titles from com.apple.controlcenter)
        "WiFi": "wifi",
        "Battery": "battery.100percent",
        "Sound": "speaker.wave.2.fill",
        "NowPlaying": "music.note",
        "FocusModes": "moon.fill",
        "Focus": "moon.fill",
        "Display": "sun.max.fill",
        // Clock is handled separately as rendered text.
        "FaceTime": "video.fill",
        "MusicRecognition": "shazam.logo.fill",
        "AudioVideoModule": "record.circle",
        "Hearing": "ear",
        "AirPlay": "airplayaudio",
        "UserSwitcher": "person.crop.circle",
        "AccessibilityShortcuts": "accessibility",
        "KeyboardBrightness": "light.max",
        "ScreenMirroring": "rectangle.on.rectangle",
        "StageManager": "rectangle.3.group",
        // SystemUIServer items
        "Siri": "mic.fill",
        // TimeMachine variants
        "com.apple.menuextra.TimeMachine": "clock.arrow.circlepath",
        "TimeMachineMenuExtra.TMMenuExtraHost": "clock.arrow.circlepath",
        "TimeMachine.TMMenuExtraHost": "clock.arrow.circlepath",
        // VPN
        "com.apple.menuextra.vpn": "lock.shield",
        // Volume / input
        "com.apple.menuextra.audio": "speaker.wave.2.fill",
        "com.apple.menuextra.audiosettings": "speaker.wave.2.fill",
    ]

    /// Maps system item titles to AppKit named images (for icons without
    /// an SF Symbol equivalent, e.g. Bluetooth).
    /// Internal for testing.
    static let systemNamedImageMap: [String: String] = [
        "Bluetooth": "NSBluetoothTemplate",
    ]

    /// Returns a resolved system icon for a known system item, or `nil`.
    private static func systemIcon(for tag: MenuBarItemTag, canvasSize: CGSize, scale: CGFloat) -> MenuBarItemImageCache.CapturedImage? {
        guard tag.isSystemItem, !tag.isControlItem else {
            return nil
        }

        // BentoBox is the Control Center aggregate icon.
        if tag.isBentoBox {
            return renderSFSymbol("switch.2", canvasSize: canvasSize, scale: scale)
        }

        // Clock: render the current date/time as text to match the menu bar.
        if tag.title == "Clock" {
            return renderClockText(canvasSize: canvasSize, scale: scale)
        }

        // Try SF Symbol first.
        if let symbolName = systemSymbolMap[tag.title] {
            return renderSFSymbol(symbolName, canvasSize: canvasSize, scale: scale)
        }

        // Fall back to named system images.
        if let namedImage = systemNamedImageMap[tag.title],
           let image = NSImage(named: NSImage.Name(namedImage))
        {
            image.isTemplate = true
            guard let cgImage = renderNSImage(image, canvasSize: canvasSize, scale: scale) else {
                return nil
            }
            return MenuBarItemImageCache.CapturedImage(cgImage: cgImage, scale: scale)
        }

        return nil
    }

    /// Target height for Thaw's own control item icons. Smaller than
    /// ``iconHeight`` so the chevron matches its actual menu bar size.
    private static let thawIconHeight: CGFloat = 12

    /// Renders Thaw's own control item icon using the user's configured icon.
    @MainActor
    private static func renderThawControlItem(
        _: MenuBarItem,
        appState: AppState,
        canvasSize: CGSize,
        scale: CGFloat
    ) -> MenuBarItemImageCache.CapturedImage? {
        let icon = appState.settings.general.iceIcon
        // Use the "hidden" variant (the icon shown when the section is collapsed,
        // which is the default resting state).
        guard let image = icon.hidden.nsImage(for: appState) else {
            return nil
        }
        image.isTemplate = true

        // Render at the icon's natural size (capped at thawIconHeight)
        // rather than the standard iconHeight, so the chevron isn't
        // scaled up larger than it appears in the actual menu bar.
        guard let cgImage = renderNSImage(
            image,
            canvasSize: canvasSize,
            scale: scale,
            maxIconHeight: min(thawIconHeight, image.size.height)
        ) else {
            return nil
        }
        return MenuBarItemImageCache.CapturedImage(cgImage: cgImage, scale: scale)
    }

    /// Renders the current date/time as white text, matching the menu bar clock.
    private static func renderClockText(canvasSize: CGSize, scale: CGFloat) -> MenuBarItemImageCache.CapturedImage? {
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "EEE d MMM h:mm a",
            options: 0,
            locale: .current
        )
        let text = formatter.string(from: Date())

        let font = NSFont.menuBarFont(ofSize: 0)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]

        let textSize = (text as NSString).size(withAttributes: attrs)
        let pixelW = Int(ceil(textSize.width + 4) * scale)
        let pixelH = Int(canvasSize.height * scale)

        guard pixelW > 0, pixelH > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: renderColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Scale the context so NSString.draw works in points, not pixels.
        let nsGraphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsGraphicsContext
        context.scaleBy(x: scale, y: scale)

        let pointH = canvasSize.height
        let drawX: CGFloat = 2
        let drawY = (pointH - textSize.height) / 2
        (text as NSString).draw(
            at: NSPoint(x: drawX, y: drawY),
            withAttributes: attrs
        )

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else { return nil }
        return MenuBarItemImageCache.CapturedImage(cgImage: cgImage, scale: scale)
    }

    /// Renders an SF Symbol as a template CGImage suitable for menu bar display.
    private static func renderSFSymbol(_ name: String, canvasSize: CGSize, scale: CGFloat) -> MenuBarItemImageCache.CapturedImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            diagLog.debug("SF Symbol '\(name)' not found")
            return nil
        }

        let configured = image.withSymbolConfiguration(symbolConfiguration) ?? image
        configured.isTemplate = true

        guard let cgImage = renderNSImage(configured, canvasSize: canvasSize, scale: scale) else {
            return nil
        }

        return MenuBarItemImageCache.CapturedImage(cgImage: cgImage, scale: scale)
    }

    // MARK: - Image Rendering

    /// Target height for all icons in the layout pane and Ice Bar.
    private static let iconHeight: CGFloat = 18

    /// Renders an NSImage to a CGImage, centered within the given canvas
    /// size. The icon is scaled to ``iconHeight`` (or the provided override)
    /// while preserving its aspect ratio. Template images are tinted white
    /// to match the dark menu bar.
    private static func renderNSImage(_ image: NSImage, canvasSize: CGSize, scale: CGFloat, maxIconHeight: CGFloat? = nil, forceMono: Bool = false) -> CGImage? {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return nil
        }

        // Determine the icon's rendered size.
        let aspect = image.size.width / max(image.size.height, 1)
        let targetH: CGFloat = maxIconHeight ?? iconHeight
        let maxH = min(targetH, canvasSize.height)
        let iconH = maxH * scale
        let iconW = iconH * aspect

        // Fit the canvas width to the icon rather than using the full
        // item bounds. Apps that render multiple icons in a single status
        // item (e.g. Alter shows 3 icons side-by-side) have wide item
        // bounds, but our single replacement icon would be dwarfed with
        // large gaps on either side without this.
        let padding: CGFloat = 16 * scale
        let fittedW = iconW + padding
        let canvasPixelW = Int(min(fittedW, canvasSize.width * scale))
        let canvasPixelH = Int(canvasSize.height * scale)

        guard canvasPixelW > 0, canvasPixelH > 0 else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: canvasPixelW,
            height: canvasPixelH,
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

        // Center the icon within the canvas.
        let iconRect = NSRect(
            x: (CGFloat(canvasPixelW) - iconW) / 2,
            y: (CGFloat(canvasPixelH) - iconH) / 2,
            width: iconW,
            height: iconH
        )

        image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        if image.isTemplate {
            // Template images render as black by default. Tint white
            // to match the dark menu bar.
            context.setBlendMode(.sourceIn)
            context.setFillColor(CGColor.white)
            context.fill(CGRect(x: 0, y: 0, width: canvasPixelW, height: canvasPixelH))
        }

        NSGraphicsContext.restoreGraphicsState()

        guard var cgImage = context.makeImage() else { return nil }

        if forceMono {
            // Convert colored icon to menu-bar-style white: use each
            // pixel's luminance as the alpha for a white pixel. Bright
            // colored areas become opaque white, dark areas become
            // transparent, preserving shading and depth.
            cgImage = luminanceToWhiteAlpha(cgImage) ?? cgImage
        }

        return cgImage
    }

    /// Converts a CGImage to white pixels with luminance-based alpha.
    /// Each pixel's brightness becomes the opacity of a white pixel.
    private static func luminanceToWhiteAlpha(_ source: CGImage) -> CGImage? {
        let w = source.width
        let h = source.height
        let bytesPerRow = w * 4

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: renderColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let data = ctx.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        for i in 0 ..< (w * h) {
            let offset = i * 4
            let r = Float(pixels[offset])
            let g = Float(pixels[offset + 1])
            let b = Float(pixels[offset + 2])
            let a = Float(pixels[offset + 3])

            // Rec. 601 luminance.
            let lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            let newAlpha = UInt8(min(lum * a, 255))

            pixels[offset] = 255 // R
            pixels[offset + 1] = 255 // G
            pixels[offset + 2] = 255 // B
            pixels[offset + 3] = newAlpha
        }

        return ctx.makeImage()
    }
}
