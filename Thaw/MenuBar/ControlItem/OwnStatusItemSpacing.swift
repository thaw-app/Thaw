//
//  OwnStatusItemSpacing.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Keeps Thaw's collapsed dividers from leaving a blank: macOS adds its item spacing to every status item, a zero-length one too.
/// Thaw lays its own items out with no spacing and puts the room back around the ones it shows.
@MainActor
enum OwnStatusItemSpacing {
    static let spacingKey = "NSStatusItemSpacing"

    /// What macOS uses when the spacing was never set.
    static let systemDefault = 16

    /// Whether this process lays its status items out with no spacing.
    private(set) static var isInstalled = false

    /// Sets the spacing to zero for this process alone. AppKit reads it once, when the first
    /// status item is made, so this runs before the app starts.
    static func install(defaults: UserDefaults = .standard) {
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(withNoSpacing(arguments), forName: UserDefaults.argumentDomain)
        isInstalled = true
    }

    /// The launch arguments with the spacing set to zero. They outrank the user's own setting,
    /// and nothing is written to disk.
    static func withNoSpacing(_ arguments: [String: Any]) -> [String: Any] {
        arguments.merging([spacingKey: 0]) { _, zero in zero }
    }

    /// The room macOS would have added to an item: the user's menu bar spacing.
    static var padding: CGFloat {
        padding(isInstalled: isInstalled, systemSpacing: SystemSpacingStore.current.read(spacingKey))
    }

    /// Nothing while macOS still adds the spacing itself; otherwise the spacing, or its default when it was never set.
    static func padding(isInstalled: Bool, systemSpacing: Int?) -> CGFloat {
        isInstalled ? CGFloat(systemSpacing ?? systemDefault) : 0
    }

    /// The length of a collapsed divider. One point, not none: a window with no width reads as an
    /// item that never landed, and two dividers at one position have no order.
    static var collapsedDividerLength: CGFloat {
        collapsedDividerLength(isInstalled: isInstalled)
    }

    static func collapsedDividerLength(isInstalled: Bool) -> CGFloat {
        isInstalled ? 1 : 0
    }

    /// A fixed length with the missing spacing added, for an item that is not sized to an image.
    static func padded(length: CGFloat, by padding: CGFloat = padding) -> CGFloat {
        length + padding
    }

    /// The image with the missing spacing as clear margins left and right, so an item sized to
    /// its image is as wide as macOS would have made it. The same image gives the same result.
    static func padded(_ image: NSImage?, by padding: CGFloat = padding) -> NSImage? {
        guard let image, padding > 0 else { return image }
        if let made = paddedImages.object(forKey: image), made.padding == padding {
            return made.image
        }
        let size = NSSize(width: image.size.width + padding, height: image.size.height)
        let wide = NSImage(size: size, flipped: false) { bounds in
            image.draw(in: NSRect(x: padding / 2, y: 0, width: image.size.width, height: bounds.height))
            return true
        }
        wide.isTemplate = image.isTemplate
        wide.accessibilityDescription = image.accessibilityDescription
        paddedImages.setObject(Padded(image: wide, padding: padding), forKey: image)
        return wide
    }

    /// A padded image and the padding it was made with.
    private final class Padded {
        let image: NSImage
        let padding: CGFloat

        init(image: NSImage, padding: CGFloat) {
            self.image = image
            self.padding = padding
        }
    }

    /// Each image's padded copy, kept while the image lives, so redrawing an item assigns the same object.
    private static let paddedImages = NSMapTable<NSImage, Padded>.weakToStrongObjects()
}
