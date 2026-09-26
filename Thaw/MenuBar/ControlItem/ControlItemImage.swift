//
//  ControlItemImage.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// A Codable image for a control item.
nonisolated enum ControlItemImage: Codable, Hashable {
    /// An image created from drawing code built into the app.
    case builtin(_ name: ImageBuiltinName)
    case symbol(_ name: String)
    /// An image in an asset catalog.
    case catalog(_ name: String)
    case data(_ data: Data)

    /// A Cocoa representation of this image.
    @MainActor
    func nsImage(for appState: AppState) -> NSImage? {
        nsImage(customIceIconIsTemplate: appState.settings.general.customIceIconIsTemplate)
    }

    /// Takes only the template flag instead of the app state, so it can be
    /// tested without an AppState.
    @MainActor
    func nsImage(customIceIconIsTemplate: Bool) -> NSImage? {
        switch self {
        case let .builtin(name):
            return switch name {
            case .chevronLarge: StaticBuiltins.Chevron.large
            case .chevronSmall: StaticBuiltins.Chevron.small
            }
        case let .symbol(name):
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            image?.isTemplate = true
            return image
        case let .catalog(name):
            guard let originalImage = NSImage(named: name) else {
                return nil
            }
            let originalWidth = originalImage.size.width
            let originalHeight = originalImage.size.height
            let ratio = max(originalWidth / 25, originalHeight / 17)
            let newSize = CGSize(width: originalWidth / ratio, height: originalHeight / ratio)
            return originalImage.resized(to: newSize)
        case let .data(data):
            let image = NSImage(data: data)
            image?.isTemplate = customIceIconIsTemplate
            return image
        }
    }
}

nonisolated extension ControlItemImage {
    /// A name for an image that is created from drawing code in the app.
    enum ImageBuiltinName: Codable, Hashable {
        case chevronLarge
        case chevronSmall
    }
}

extension ControlItemImage {
    /// Cached so ``nsImage(for:)`` doesn't redraw on every call.
    private enum StaticBuiltins {
        enum Chevron {
            private static func chevron(size: CGSize, lineWidth: CGFloat) -> NSImage {
                let image = NSImage(size: size, flipped: false) { bounds in
                    let insetBounds = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
                    let path = NSBezierPath()
                    path.move(to: CGPoint(x: (insetBounds.midX + insetBounds.maxX) / 2, y: insetBounds.maxY))
                    path.line(to: CGPoint(x: (insetBounds.minX + insetBounds.midX) / 2, y: insetBounds.midY))
                    path.line(to: CGPoint(x: (insetBounds.midX + insetBounds.maxX) / 2, y: insetBounds.minY))
                    path.lineWidth = lineWidth
                    path.lineCapStyle = .butt
                    NSColor.black.setStroke()
                    path.stroke()
                    return true
                }
                image.isTemplate = true
                return image
            }

            static let large = chevron(size: CGSize(width: 12, height: 12), lineWidth: 2)

            static let small = chevron(size: CGSize(width: 9, height: 9), lineWidth: 2)
        }
    }
}
