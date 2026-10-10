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

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.defaultsKey)
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
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        revision += 1
    }

    /// PNG from the image's largest representation, so a 2x asset stays sharp.
    private static func pngData(for image: NSImage) -> Data? {
        let pixelHeight = image.representations.map(\.pixelsHigh).max() ?? 0
        let scale = max(CGFloat(pixelHeight) / max(image.size.height, 1), 1)
        var rect = CGRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = image.size
        return rep.representation(using: .png, properties: [:])
    }
}
