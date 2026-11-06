//
//  AXItemLabels.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms

/// The accessibility strings one extras-bar child published, from which
/// MenuBarItemAXProvider derives its identity.
///
/// The child fields come from one level down, for apps that publish their
/// identity on the button rather than on the item.
nonisolated struct AXItemLabels {
    var identifier: String?
    var childIdentifier: String?
    var accessibilityDescription: String?
    var childDescription: String?
    var axTitle: String?
}

nonisolated extension AXItemLabels {
    /// Labels from a child's attributes and its already-read descendants.
    init(attributes: AXHelpers.MenuBarChildAttributes, descendants: [AXHelpers.MenuBarChildAttributes]) {
        let child = Self.childLabels(in: descendants)
        self.init(
            identifier: attributes.identifier,
            childIdentifier: child.identifier,
            accessibilityDescription: attributes.accessibilityDescription,
            childDescription: child.description,
            axTitle: attributes.title
        )
    }

    /// The first stable identifier and the first description among descendants.
    static func childLabels(
        in descendants: [AXHelpers.MenuBarChildAttributes]
    ) -> (identifier: String?, description: String?) {
        (
            descendants.firstNonNil { MenuBarItemAXProvider.stableAXIdentifier($0.identifier?.nonEmpty) },
            descendants.firstNonNil { $0.accessibilityDescription?.nonEmpty }
        )
    }

    /// The values identity is keyed on: blank strings and launch-specific
    /// identifiers drop out, and the item's own value wins over its child's.
    var resolved: (identifier: String?, accessibilityDescription: String?, axTitle: String?) {
        (
            MenuBarItemAXProvider.stableAXIdentifier(identifier?.nonEmpty)
                ?? MenuBarItemAXProvider.stableAXIdentifier(childIdentifier?.nonEmpty),
            accessibilityDescription?.nonEmpty ?? childDescription?.nonEmpty,
            axTitle?.nonEmpty
        )
    }
}
