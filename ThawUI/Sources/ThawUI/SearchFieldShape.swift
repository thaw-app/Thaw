//
//  SearchFieldShape.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI

/// The outline of the launcher's search field, as the three choices it had before SearchFieldCorners.
/// Settings that sync still carry it, for older copies of an app on another Mac.
public nonisolated enum SearchFieldShape: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The corners the rest of the panel's controls have.
    case rounded
    /// Ends rounded off into half circles.
    case capsule
    case square

    public var id: String {
        rawValue
    }

    public func cornerRadius(height: CGFloat) -> CGFloat {
        SearchFieldCorners(self).cornerRadius(height: height)
    }

    /// Standing alone the field is a piece of the panel, so rounded takes the panel's corner and not a control's.
    public func fieldPieceRadius(height: CGFloat) -> CGFloat {
        SearchFieldCorners(self).fieldPieceRadius(height: height)
    }

    /// The piece under a separate field, and a panel in one piece beside it: only square squares it.
    public var panelPieceRadius: CGFloat {
        SearchFieldCorners(self).panelPieceRadius
    }

    /// A continuous corner as large as half the height leaves a nick, so a capsule's is circular.
    public var pieceCornerStyle: RoundedCornerStyle {
        SearchFieldCorners(self).pieceCornerStyle
    }

    /// The outline itself. A capsule is its own shape, since the field's height is not known where this is asked.
    public var outline: SearchFieldOutline {
        SearchFieldCorners(self).outline
    }
}

/// One shape type for every outline, so the glass that draws the field takes any of them.
public nonisolated struct SearchFieldOutline: InsettableShape {
    public let corners: SearchFieldCorners
    public var inset: CGFloat = 0

    public var shape: SearchFieldShape {
        corners.nearestShape
    }

    public func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let radius = max(min(corners.cornerRadius(height: rect.height), rect.height / 2, rect.width / 2), 0)
        return Path(roundedRect: rect, cornerRadius: radius, style: corners.pieceCornerStyle)
    }

    public func inset(by amount: CGFloat) -> SearchFieldOutline {
        SearchFieldOutline(corners: corners, inset: inset + amount)
    }
}

extension EnvironmentValues {
    /// Read by the search field, set by the launcher from the setting: the field itself knows nothing of settings.
    @Entry public var searchFieldCorners = SearchFieldCorners.rounded
    /// The same value by its nearest shape, for a caller that still sets one.
    public var searchFieldShape: SearchFieldShape {
        get { searchFieldCorners.nearestShape }
        set { searchFieldCorners = SearchFieldCorners(newValue) }
    }

    /// The same for the beam around the field.
    @Entry public var searchFieldBeam: SearchFieldBeam = .off
    @Entry public var searchFieldBeamFrameRate = 60.0
}
