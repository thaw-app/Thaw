//
//  SearchIndex+Appearance.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

nonisolated extension SearchIndex {
    // MARK: Appearance Settings

    static let appearanceEntries: [SearchEntry] = [
        SearchEntry(
            id: "appearance.roundScreenCorners",
            title: "Round screen corners",
            descriptionText: String(localized: "Draws black over the corners of every display, so they look rounded."),
            pane: .menuBarAppearance,
            section: "Screen corners",
            keywords: ["corners", "rounded", "radius", "screen", "display"],
            property: .general("roundScreenCorners")
        ),
        SearchEntry(
            id: "appearance.isDynamic",
            title: "Use different settings for Light and Dark Mode",
            descriptionText: String(localized: "Edit Light and Dark separately. Switch modes below to customize each."),
            pane: .menuBarAppearance,
            keywords: ["dynamic", "light", "dark", "appearance", "mode"],
            property: nil
        ),
        SearchEntry(
            id: "appearance.background",
            title: "Background",
            descriptionText: String(localized: "Fills the menu bar behind or around a custom shape."),
            pane: .menuBarAppearance,
            section: "Background",
            keywords: ["background", "style", "solid", "gradient", "glass", "adaptive", "opacity", "shadow", "border"],
            property: nil
        ),
        SearchEntry(
            id: "appearance.shape",
            title: "Shape",
            descriptionText: nil,
            pane: .menuBarAppearance,
            section: "Shape",
            keywords: ["shape", "full", "split", "notch", "end cap", "margin", "inset"],
            property: nil
        ),
        SearchEntry(
            id: "appearance.isInset",
            title: "Inset on notched displays",
            descriptionText: String(localized: "Shrinks the shape slightly so it sits below the notch."),
            pane: .menuBarAppearance,
            section: "Shape",
            keywords: ["inset", "notch", "shape"],
            property: nil
        ),
        SearchEntry(
            id: "appearance.shapeFill",
            title: "Shape fill",
            descriptionText: String(localized: "Colors the area inside the shape."),
            pane: .menuBarAppearance,
            section: "Shape fill",
            keywords: ["tint", "fill", "style", "solid", "gradient", "glass", "adaptive", "opacity", "shadow", "border"],
            property: nil
        ),
        SearchEntry(
            id: "appearance.reset",
            title: "Reset Appearance",
            descriptionText: String(localized: "Restore the default menu bar appearance."),
            pane: .menuBarAppearance,
            keywords: ["reset", "appearance", "default"],
            property: nil
        ),
    ]
}
