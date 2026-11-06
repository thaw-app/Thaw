//
//  ControlItemImageSet.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - ControlItemImageSet

/// Hidden and revealed icons are chosen and stored together because their directions or fills form a matched pair.
nonisolated struct ControlItemImageSet: Codable, Hashable, Identifiable {
    /// The icon the user picked.
    let name: Name

    /// Shown while the section is concealed.
    let hidden: ControlItemImage

    /// Shown while the section is revealed.
    let visible: ControlItemImage

    var id: Int {
        hashValue
    }

    init(name: Name, hidden: ControlItemImage, visible: ControlItemImage) {
        self.name = name
        self.hidden = hidden
        self.visible = visible
    }

    /// Creates a set that shows the same image in both states.
    init(name: Name, image: ControlItemImage) {
        self.init(name: name, hidden: image, visible: image)
    }
}

// MARK: - ControlItemImageSet.Name

nonisolated extension ControlItemImageSet {
    /// The identity of an icon, independent of the images that draw it.
    ///
    /// - Important: The raw values are persisted with the user's settings and
    ///   must not change.
    nonisolated enum Name: String, Codable, Hashable {
        case arrow = "Arrow"
        case chevron = "Chevron"
        case chevronDown = "Chevron (Down)"
        case door = "Door"
        case dot = "Dot"
        case ellipsis = "Ellipsis"
        case iceCube = "Ice Cube"
        case sunglasses = "Sunglasses"
        case custom = "Custom"

        /// The name as it should be shown to the user.
        var localized: LocalizedStringKey {
            switch self {
            case .arrow: "Arrow"
            case .chevron: "Chevron"
            case .chevronDown: "Chevron (Down)"
            case .door: "Door"
            case .dot: "Dot"
            case .ellipsis: "Ellipsis"
            case .iceCube: "Ice Cube"
            case .sunglasses: "Sunglasses"
            case .custom: "Custom"
            }
        }
    }
}

// MARK: - Built-in icons

nonisolated extension ControlItemImageSet {
    /// The icon a fresh install starts with.
    static let defaultThawIcon = ControlItemImageSet(
        name: .iceCube,
        hidden: .catalog("IceCubeStroke"),
        visible: .catalog("IceCubeFill")
    )

    /// The icons offered in settings, in the order they are presented.
    static let userSelectableThawIcons = [
        symbols(.arrow, hidden: "arrowshape.left.fill", visible: "arrowshape.right.fill"),
        symbols(.chevron, hidden: "chevron.left", visible: "chevron.right"),
        symbols(.chevronDown, hidden: "chevron.down", visible: "chevron.up"),
        symbols(.door, hidden: "door.left.hand.closed", visible: "door.left.hand.open"),
        catalog(.dot, hidden: "DotFill", visible: "DotStroke"),
        catalog(.ellipsis, hidden: "EllipsisFill", visible: "EllipsisStroke"),
        catalog(.iceCube, hidden: "IceCubeStroke", visible: "IceCubeFill"),
        symbols(.sunglasses, hidden: "sunglasses.fill", visible: "sunglasses"),
    ]

    /// An icon drawn from two SF Symbols.
    private static func symbols(_ name: Name, hidden: String, visible: String) -> ControlItemImageSet {
        ControlItemImageSet(name: name, hidden: .symbol(hidden), visible: .symbol(visible))
    }

    /// - Important: Names must match imageset folders in Assets.xcassets/ControlItemImages; unchecked mismatches yield no runtime icon.
    private static func catalog(_ name: Name, hidden: String, visible: String) -> ControlItemImageSet {
        ControlItemImageSet(name: name, hidden: .catalog(hidden), visible: .catalog(visible))
    }
}
