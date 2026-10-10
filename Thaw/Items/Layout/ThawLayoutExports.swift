//
//  ThawLayoutExports.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@_exported import ThawLayout

extension NewItemsPlacement {
    /// The app owns the default because it reads an app default for the section.
    static var defaultValue: NewItemsPlacement {
        NewItemsPlacement(
            sectionKey: Defaults.DefaultValue.newItemsSection,
            anchorIdentifier: nil,
            relation: .sectionDefault
        )
    }
}
