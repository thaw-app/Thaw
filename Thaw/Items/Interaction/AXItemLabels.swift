//
//  AXItemLabels.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

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
