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

    private static func key(for item: MenuBarItem) -> String {
        MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
    }

    func image(for item: MenuBarItem) -> NSImage? {
        let key = Self.key(for: item)
        // Read before the image cache, so a SwiftUI caller observes a change.
        guard let entry = stored[key] else { return nil }
        if let image = images[key] {
            return image
        }
        guard let image = NSImage(data: entry.png) else { return nil }
        image.isTemplate = entry.isTemplate
        images[key] = image
        return image
    }

    func hasChoice(for item: MenuBarItem) -> Bool {
        stored[Self.key(for: item)] != nil
    }

    /// Saves image as the item's icon, or clears the choice when nil.
    func setImage(_ image: NSImage?, for item: MenuBarItem) {
        let key = Self.key(for: item)
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

    /// PNG at the image's largest representation's scale, so a 2x asset stays sharp, but drawn
    /// at no more than 3x: a picked file can be any size, and the PNG is kept in the defaults.
    private static func pngData(for image: NSImage) -> Data? {
        let pixelHeight = image.representations.map(\.pixelsHigh).max() ?? 0
        let scale = min(max(CGFloat(pixelHeight) / max(image.size.height, 1), 1), 3)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(Int((image.size.width * scale).rounded()), 1),
            pixelsHigh: max(Int((image.size.height * scale).rounded()), 1),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
