//
//  IconResource.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A type that produces a view representing an icon.
enum IconResource: Hashable {
    /// A resource derived from a system symbol.
    case systemSymbol(_ name: String)

    /// A resource derived from an asset catalog.
    case assetCatalog(_ resource: ImageResource)

    /// The view produced by the resource.
    @ViewBuilder
    var view: some View {
        switch self {
        case .systemSymbol:
            // SF Symbols scale with the font environment - no .resizable()
            image
        case .assetCatalog:
            // Asset catalog images need explicit sizing
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
        }
    }

    /// The image produced by the resource.
    private var image: Image {
        switch self {
        case let .systemSymbol(name):
            Image(systemName: name)
        case let .assetCatalog(resource):
            Image(resource)
        }
    }
}
