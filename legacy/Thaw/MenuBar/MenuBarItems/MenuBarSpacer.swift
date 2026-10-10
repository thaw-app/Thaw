//
//  MenuBarSpacer.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

// MARK: - MenuBarSpacer

/// One user-created spacer item.
nonisolated struct MenuBarSpacer: Codable, Identifiable, Equatable {
    /// The narrowest useful spacer; anything below reads as a normal gap.
    static let minWidth: CGFloat = 8
    /// Wide enough to push items past a notch without being a footgun.
    static let maxWidth: CGFloat = 300
    /// A visible, obviously-intentional default gap.
    static let defaultWidth: CGFloat = 40

    let id: UUID
    var width: CGFloat
    /// Optional fill; `nil` renders the spacer as a fully transparent gap.
    var color: IceColor?

    init(id: UUID = UUID(), width: CGFloat = Self.defaultWidth, color: IceColor? = nil) {
        self.id = id
        self.width = width.clamped(to: Self.minWidth ... Self.maxWidth)
        self.color = color
    }

    /// Decodes through the memberwise initializer so the clamp applies to
    /// persisted widths too. A synthesized `init(from:)` assigns `width`
    /// directly, and a downgrade from a build with a larger `maxWidth` reads
    /// back a value wide enough to push other items off the bar.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            width: container.decode(CGFloat.self, forKey: .width),
            color: container.decodeIfPresent(IceColor.self, forKey: .color)
        )
    }
}
