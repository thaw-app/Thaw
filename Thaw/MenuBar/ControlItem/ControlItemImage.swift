//
//  ControlItemImage.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// MARK: - ControlItemImage

/// Resolves references lazily to keep settings small and follow system appearance; only data stores pixels.
/// - Important: Case names and unlabeled payloads encode the chosen icon; renaming either silently discards it on launch.
nonisolated enum ControlItemImage: Codable, Hashable {
    /// An image produced by drawing code in the app.
    case builtin(_ name: ImageBuiltinName)
    /// A system symbol image.
    case symbol(_ name: String)
    /// An image in an asset catalog.
    case catalog(_ name: String)
    /// An image stored as data.
    case data(_ data: Data)

    /// A landscape bounding box preserves wide icons rather than squeezing them into a square.
    static let maximumSize = CGSize(width: 25, height: 17)

    /// Resolves this image for display.
    @MainActor
    func nsImage(for appState: AppState) -> NSImage? {
        switch self {
        case let .builtin(name):
            switch name {
            case .chevronLarge: Drawn.Chevron.large
            case .chevronSmall: Drawn.Chevron.small
            }
        case let .symbol(name):
            NSImage(systemSymbolName: name, accessibilityDescription: nil)
                .map { image in
                    image.isTemplate = true
                    return image
                }
        case let .catalog(name):
            // Catalog art is authored at its own scale, so it is brought down
            // to the menu bar rather than trusted to fit.
            NSImage(named: name).flatMap(Self.scaledToFitMenuBar)
        case let .data(data):
            NSImage(data: data)
                .map { image in
                    // Tint custom images only when explicitly marked as templates, or photos become solid blocks.
                    image.isTemplate = appState.settings.customThawIconIsTemplate
                    return image
                }
        }
    }

    /// Fits proportionally using the larger ratio so only the constraining dimension reaches maximumSize.
    @MainActor
    static func scaledToFitMenuBar(_ image: NSImage) -> NSImage? {
        let ratio = max(
            image.size.width / maximumSize.width,
            image.size.height / maximumSize.height
        )
        let fittedSize = CGSize(
            width: image.size.width / ratio,
            height: image.size.height / ratio
        )
        return image.resized(to: fittedSize)
    }
}

// MARK: - ControlItemImage.ImageBuiltinName

nonisolated extension ControlItemImage {
    /// Names an image that the app draws for itself.
    ///
    /// - Important: These names are part of the encoded representation of a
    ///   ControlItemImage.
    enum ImageBuiltinName: Codable, Hashable {
        case chevronLarge
        case chevronSmall
    }
}

// MARK: - Drawn images

extension ControlItemImage {
    /// Stored statics draw once per launch, not on each appearance update.
    private enum Drawn {
        enum Chevron {
            static let large = stroked(size: CGSize(width: 12, height: 12), lineWidth: 2)

            static let small = stroked(size: CGSize(width: 9, height: 9), lineWidth: 2)

            /// Half-line-width insets prevent stroke clipping; black template strokes let AppKit recolor for menu bar appearance.
            private static func stroked(size: CGSize, lineWidth: CGFloat) -> NSImage {
                let image = NSImage(size: size, flipped: false) { bounds in
                    let insetBounds = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
                    let trailingX = (insetBounds.midX + insetBounds.maxX) / 2
                    let leadingX = (insetBounds.minX + insetBounds.midX) / 2

                    let path = NSBezierPath()
                    path.move(to: CGPoint(x: trailingX, y: insetBounds.maxY))
                    path.line(to: CGPoint(x: leadingX, y: insetBounds.midY))
                    path.line(to: CGPoint(x: trailingX, y: insetBounds.minY))
                    path.lineWidth = lineWidth
                    path.lineCapStyle = .butt

                    NSColor.black.setStroke()
                    path.stroke()
                    return true
                }
                image.isTemplate = true
                return image
            }
        }
    }
}
