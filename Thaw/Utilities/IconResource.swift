//
//  IconResource.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A type that produces a view representing an icon.
enum IconResource: Hashable {
    case systemSymbol(_ name: String)

    case assetCatalog(_ resource: ImageResource)

    /// The view produced by the resource.
    @ViewBuilder
    var view: some View {
        switch self {
        case .systemSymbol:
            // SF Symbols scale with the font environment, so no .resizable().
            image
        case .assetCatalog:
            // Asset catalog images need explicit sizing
            image
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        }
    }

    /// The image produced by the resource, for callers that size the
    /// glyph themselves (SettingsPaneIconTile).
    var image: Image {
        switch self {
        case let .systemSymbol(name):
            Image(systemName: name)
        case let .assetCatalog(resource):
            Image(resource)
        }
    }
}
