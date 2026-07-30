//
//  ControlItemImageSet.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A named set of images that are used by control items.
///
/// An image set contains images for a control item in both the hidden and visible states.
struct ControlItemImageSet: Codable, Hashable, Identifiable {
    enum Name: String, Codable, Hashable {
        case arrow = "Arrow"
        case chevron = "Chevron"
        case chevronDown = "Chevron (Down)"
        case door = "Door"
        case dot = "Dot"
        case ellipsis = "Ellipsis"
        case iceCube = "Ice Cube"
        case sunglasses = "Sunglasses"
        case custom = "Custom"

        /// Localized string key representation.
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

    let name: Name
    let hidden: ControlItemImage
    let visible: ControlItemImage

    var id: Int {
        hashValue
    }

    init(name: Name, hidden: ControlItemImage, visible: ControlItemImage) {
        self.name = name
        self.hidden = hidden
        self.visible = visible
    }

    init(name: Name, image: ControlItemImage) {
        self.init(name: name, hidden: image, visible: image)
    }
}

extension ControlItemImageSet {
    /// The default image set for the Ice icon.
    static let defaultIceIcon = ControlItemImageSet(
        name: .iceCube,
        hidden: .catalog("IceCubeStroke"),
        visible: .catalog("IceCubeFill")
    )

    /// The image sets that the user can choose to display in the Ice icon.
    static let userSelectableIceIcons = [
        ControlItemImageSet(
            name: .arrow,
            hidden: .symbol("arrowshape.left.fill"),
            visible: .symbol("arrowshape.right.fill")
        ),
        ControlItemImageSet(
            name: .chevron,
            hidden: .symbol("chevron.left"),
            visible: .symbol("chevron.right")
        ),
        ControlItemImageSet(
            name: .chevronDown,
            hidden: .symbol("chevron.down"),
            visible: .symbol("chevron.up")
        ),
        ControlItemImageSet(
            name: .door,
            hidden: .symbol("door.left.hand.closed"),
            visible: .symbol("door.left.hand.open")
        ),
        ControlItemImageSet(
            name: .dot,
            hidden: .catalog("DotFill"),
            visible: .catalog("DotStroke")
        ),
        ControlItemImageSet(
            name: .ellipsis,
            hidden: .catalog("EllipsisFill"),
            visible: .catalog("EllipsisStroke")
        ),
        ControlItemImageSet(
            name: .iceCube,
            hidden: .catalog("IceCubeStroke"),
            visible: .catalog("IceCubeFill")
        ),
        ControlItemImageSet(
            name: .sunglasses,
            hidden: .symbol("sunglasses.fill"),
            visible: .symbol("sunglasses")
        ),
    ]
}
