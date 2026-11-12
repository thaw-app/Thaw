//
//  MenuBarItemIconChoices.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Observation

/// User-picked icons replace app-icon fallbacks, including Thaw Bar Only items and missing captures.
/// Store the image rather than its source so choices survive app moves and asset changes.
@MainActor
@Observable
final class MenuBarItemIconChoices {
    static let shared = MenuBarItemIconChoices()

    private static let defaultsKey = "MenuBarItemManager.iconChoices"

    /// About a menu bar glyph's height. An app's own image often reports its 2x pixel size
    /// as points, so every choice is drawn at this height whatever size it ships at.
    static let glyphHeight: CGFloat = 16

    static func glyphSize(for size: CGSize) -> CGSize {
        guard size.height > 0 else { return CGSize(width: glyphHeight, height: glyphHeight) }
        return CGSize(width: size.width * glyphHeight / size.height, height: glyphHeight)
    }

    private struct Stored: Codable {
        let png: Data
        let isTemplate: Bool
    }

    private var stored: [String: Stored]

    /// Bumped on every change, for surfaces that redraw on a single value.
    private(set) var revision = 0

    @ObservationIgnored private var images: [String: NSImage] = [:]

    /// Where choices are stored. Tests pass a scratch suite instead of the shared store.
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.defaultsKey)
        stored = data.flatMap { try? JSONDecoder().decode([String: Stored].self, from: $0) } ?? [:]
    }

    func image(for item: MenuBarItem) -> NSImage? {
        let key = item.canonicalIdentifier
        // Read before the image cache, so a SwiftUI caller observes a change.
        guard let entry = stored[key] else { return nil }
        if let image = images[key] {
            return image
        }
        guard let image = NSImage(data: entry.png) else { return nil }
        // Choices saved before glyphHeight kept their source size.
        image.size = Self.glyphSize(for: image.size)
        image.isTemplate = entry.isTemplate
        images[key] = image
        return image
    }

    func hasChoice(for item: MenuBarItem) -> Bool {
        stored[item.canonicalIdentifier] != nil
    }

    /// Saves image as the item's icon, or clears the choice when nil.
    func setImage(_ image: NSImage?, for item: MenuBarItem) {
        let key = item.canonicalIdentifier
        images[key] = nil
        if let image, let png = Self.pngData(for: image) {
            stored[key] = Stored(png: png, isTemplate: image.isTemplate)
        } else {
            stored[key] = nil
        }
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
        revision += 1
    }

    /// PNG at glyph size, at least 2x so it is sharp on a Retina display, and at most 3x:
    /// a picked file can be any size, and the PNG is kept in the defaults.
    static func pngData(for image: NSImage) -> Data? {
        let size = glyphSize(for: image.size)
        let pixelHeight = image.representations.map(\.pixelsHigh).max() ?? 0
        let scale = (CGFloat(pixelHeight) / size.height).clamped(to: 2 ... 3)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(Int((size.width * scale).rounded()), 1),
            pixelsHigh: max(Int((size.height * scale).rounded()), 1),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
