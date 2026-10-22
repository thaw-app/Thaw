//
//  MenuBarIconShade.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import ThawCapture
import ThawUI

/// The shade macOS drew the menu bar icons in, read from MenuBarAgent's hosting
/// window: every visible glyph on transparency, so the glyphs' own pixels say it.
nonisolated enum MenuBarIconShade: Equatable, Sendable {
    case light
    case dark

    /// Fewer glyph pixels than this is too little bar to judge.
    static let minimumGlyphPixels = 40

    /// The shade of the opaque pixels in image, or nil when there are too few.
    static func shade(of image: CGImage) -> MenuBarIconShade? {
        image.withPremultipliedRGBA8(maximumWidth: 1024) { bytes, _ in
            shade(ofPremultipliedRGBA: bytes)
        } ?? nil
    }

    /// The decision on raw premultiplied RGBA bytes: the mean luminance of the
    /// mostly opaque pixels, light above the midpoint.
    static func shade<Pixels: RandomAccessCollection<UInt8>>(
        ofPremultipliedRGBA pixels: Pixels
    ) -> MenuBarIconShade? where Pixels.Index == Int {
        var total = 0.0
        var count = 0
        for index in stride(from: pixels.startIndex, to: pixels.endIndex - 3, by: 4) where pixels[index + 3] > 128 {
            let alpha = Double(pixels[index + 3])
            let red = Double(pixels[index]) / alpha
            let green = Double(pixels[index + 1]) / alpha
            let blue = Double(pixels[index + 2]) / alpha
            total += 0.2126 * red + 0.7152 * green + 0.0722 * blue
            count += 1
        }
        guard count >= minimumGlyphPixels else { return nil }
        return total / Double(count) > 0.5 ? .light : .dark
    }

    /// The shade macOS gives icons on a bar of this luminance, for when the icons can't be read.
    static func estimated(barLuminance: Double) -> MenuBarIconShade {
        ForegroundContrast.prefersDarkContent(onLuminance: barLuminance) ? .dark : .light
    }

    /// Light glass under dark icons and dark glass under light ones.
    var matchingGlassAppearance: NSAppearance.Name {
        self == .dark ? .aqua : .darkAqua
    }

    /// Reads the icons on displayID's bar, through SkyLight when it can, so
    /// the recording indicator stays off. Nil without Screen Recording.
    @MainActor
    static func read(displayID: CGDirectDisplayID) async -> MenuBarIconShade? {
        let capture = await ScreenCapture.withOneshotCaptureTicket {
            await ScreenCapture.captureMenuBarHostingWindowAsync(displayID: displayID)
        }
        return capture.flatMap { shade(of: $0.image) }
    }
}
