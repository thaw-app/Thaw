//
//  NewItemsPlacement.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// Placement is shared with the layout engine; its default stays in the app because it reads app preferences.
public struct NewItemsPlacement: Codable, Equatable, Sendable {
    public enum Relation: String, Codable, Sendable {
        case leftOfAnchor
        case rightOfAnchor
        case sectionDefault
    }

    public let sectionKey: String
    public let anchorIdentifier: String?
    public let relation: Relation

    public init(sectionKey: String, anchorIdentifier: String?, relation: Relation) {
        self.sectionKey = sectionKey
        self.anchorIdentifier = anchorIdentifier
        self.relation = relation
    }
}
