//
//  MenuBarGlassFinish.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// A surface's glass as it's drawn: the finish, and whether plain glass takes a tint.
nonisolated struct MenuBarGlassFinish: Hashable {
    var style: MenuBarGlassStyle
    /// Only plain glass reads this. Dynamic Glass always takes a tint, and the
    /// private finishes never do.
    var isTinted: Bool

    /// Whether the glass is drawn lighter, shaped to the surface, so that a tint
    /// color can show through.
    var usesTint: Bool {
        switch style {
        case .regular: isTinted
        case .dynamic: true
        case .solid, .edge, .sheer, .dim: false
        }
    }

    var usesShapeAwareSurface: Bool {
        usesTint
    }

    var usesDarkFade: Bool {
        style.usesDarkFade
    }

    var effectOpacity: Double {
        usesTint ? 0.45 : 1
    }

    var privateVariant: Int? {
        style.privateVariant
    }

    var followsIconShade: Bool {
        style.followsIconShade
    }

    var darkening: Double {
        style.darkening
    }

    @MainActor
    var nsGlassStyle: NSGlassEffectView.Style {
        switch style {
        case .regular: isTinted ? .clear : .regular
        case .solid, .dim: .regular
        case .dynamic, .edge, .sheer: .clear
        }
    }
}

// MARK: - Decoding

nonisolated extension MenuBarGlassFinish {
    /// The raw value older builds wrote for Liquid Glass, which is now plain glass with a tint.
    static let liquidGlassRawValue = 2

    /// Reads a surface's finish, including the forms older builds wrote. Clear
    /// (raw value 1) becomes plain glass and Liquid Glass (2) plain glass with a
    /// tint, drawn as before. Match System only ever chose Regular or Clear, so
    /// it becomes plain glass without a tint. A stored tint setting wins over
    /// what the raw value implies.
    static func decode<Key: CodingKey>(
        from stored: KeyedDecodingContainer<Key>,
        style styleKey: Key,
        isTinted tintKey: Key,
        legacyFollowsSystem followsSystemKey: Key,
        fallback: MenuBarGlassFinish
    ) throws -> MenuBarGlassFinish {
        let storedTint = try stored.decodeIfPresent(Bool.self, forKey: tintKey)
        guard let rawValue = try stored.decodeIfPresent(Int.self, forKey: styleKey) else {
            return MenuBarGlassFinish(style: fallback.style, isTinted: storedTint ?? fallback.isTinted)
        }
        if try stored.decodeIfPresent(Bool.self, forKey: followsSystemKey) == true {
            return MenuBarGlassFinish(style: .regular, isTinted: false)
        }
        return MenuBarGlassFinish(
            style: MenuBarGlassStyle(storedRawValue: rawValue),
            isTinted: storedTint ?? (rawValue == liquidGlassRawValue)
        )
    }

    /// Reads the background's and the shape fill's finish under the keys the
    /// menu bar's look and the Thaw Bar's own look both store them with.
    static func decodeSurfaces<Key: CodingKey>(
        from stored: KeyedDecodingContainer<Key>,
        fallback: MenuBarAppearancePartialConfiguration
    ) throws -> (background: MenuBarGlassFinish, tint: MenuBarGlassFinish) {
        func key(_ name: String) -> Key {
            guard let key = Key(stringValue: name) else {
                preconditionFailure("\(Key.self) has no key named \(name)")
            }
            return key
        }
        func finish(_ surface: String, fallback: MenuBarGlassFinish) throws -> MenuBarGlassFinish {
            try decode(
                from: stored,
                style: key(surface + "GlassStyle"),
                isTinted: key(surface + "GlassIsTinted"),
                legacyFollowsSystem: key(surface + "GlassFollowsSystem"),
                fallback: fallback
            )
        }
        return try (
            finish("background", fallback: fallback.backgroundGlassFinish),
            finish("tint", fallback: fallback.tintGlassFinish)
        )
    }
}

nonisolated extension MenuBarGlassStyle: Codable {
    /// The finish for a stored raw value. Clear, Liquid Glass and values from
    /// newer builds read as plain glass rather than failing the whole appearance.
    init(storedRawValue rawValue: Int) {
        self = Self(rawValue: rawValue) ?? .regular
    }

    init(from decoder: any Decoder) throws {
        try self.init(storedRawValue: decoder.singleValueContainer().decode(Int.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
