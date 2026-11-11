//
//  SearchLauncherLook.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The search panel's glass, tint, border and shadow: the menu bar's own, as
/// Floe draws its launcher when it follows Thaw.
nonisolated extension SharedAppearance {
    /// Maps the menu bar's look onto the launcher's. A part the bar has in a
    /// kind the launcher cannot draw stays as base has it.
    func launcherLook(over base: LauncherLook = LauncherLook()) -> LauncherLook {
        var look = base
        look.hasShadow = hasShadow
        look.border = border.map { border in
            LauncherBorder(
                color: border.color.map(StoredColor.init) ?? LauncherBorder().color,
                width: max(0, border.width)
            )
        }
        // The launcher has one glass and one tint: each takes the bar's tint
        // first and its background otherwise.
        let glass = tint.launcherGlass(keeping: base.glass) ?? background.launcherGlass(keeping: base.glass)
        if let glass {
            look.glass = glass
        }
        let paint = tint.launcherPaint(keeping: base.tint)
        switch paint == .nothing ? background.launcherPaint(keeping: base.tint) : paint {
        case let .tint(tint):
            look.tint = tint
        case .nothing:
            look.tint.kind = .none
        case .unmirrored:
            break
        }
        // The bar's tint replaces a coloured glass of the launcher's own.
        if glass == nil {
            look.glass.isColored = false
        }
        return look
    }
}

private nonisolated extension SharedAppearance.Fill {
    enum Paint: Equatable {
        case tint(LauncherTint)
        /// No tint from this fill: it is off, or it is a glass.
        case nothing
        /// A kind the launcher cannot draw, or one missing its colours.
        case unmirrored
    }

    func launcherPaint(keeping base: LauncherTint) -> Paint {
        var tint = base
        tint.opacity = opacity.clamped(to: 0 ... 1)
        switch kind {
        case "none", "glass":
            return .nothing
        case "solid":
            guard let color else { return .unmirrored }
            tint.kind = .solid
            tint.solid = StoredColor(color)
        case "gradient":
            let ordered = (stops ?? []).sorted { $0.location < $1.location }
            guard let first = ordered.first, let last = ordered.last else { return .unmirrored }
            tint.kind = .gradient
            tint.gradient = LauncherGradient(start: StoredColor(first.color), end: StoredColor(last.color), angle: angle ?? 90)
        default:
            return .unmirrored
        }
        return .tint(tint)
    }

    /// The bar's glass styles carry the launcher's names.
    func launcherGlass(keeping base: LauncherGlass) -> LauncherGlass? {
        guard kind == "glass", let style = glassStyle.flatMap(LauncherGlassStyle.init(rawValue:)) else {
            return nil
        }
        return LauncherGlass(
            style: style,
            isColored: glassIsColored ?? false,
            color: color.map(StoredColor.init) ?? base.color,
            opacity: opacity.clamped(to: 0 ... 1)
        )
    }
}

private nonisolated extension StoredColor {
    init(_ color: SharedAppearance.Color) {
        self.init()
        red = color.red.clamped(to: 0 ... 1)
        green = color.green.clamped(to: 0 ... 1)
        blue = color.blue.clamped(to: 0 ... 1)
        opacity = color.alpha.clamped(to: 0 ... 1)
    }
}

@MainActor
extension AppState {
    /// The search panel's look for the menu bar's current appearance.
    var searchLauncherLook: LauncherLook {
        let configuration = appearanceManager.effectiveConfiguration
        return SharedAppearance(
            configuration: configuration.current,
            shapeKind: configuration.shapeKind,
            hasRoundedShape: configuration.hasRoundedShape,
            isDark: SystemAppearance.current == .dark
        ).launcherLook()
    }
}
