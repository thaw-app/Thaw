//
//  ControlUIDs.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Shared boundary UIDs for placement and width planners; Hidden is required for a working layout.
/// Visible is nil without a chevron; Always Hidden is nil when that section is disabled.
public nonisolated struct ControlUIDs: Equatable {
    public let visible: String?
    public let hidden: String
    public let alwaysHidden: String?

    public init(visible: String?, hidden: String, alwaysHidden: String?) {
        self.visible = visible
        self.hidden = hidden
        self.alwaysHidden = alwaysHidden
    }
}
