//
//  ThawHUDPlacement.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import SwiftUI

/// Where along the top of a display a ThawHUD capsule sits.
///
/// Confirmations do not need this: they answer a gesture the user just made
/// and are already being looked for, so the center is the right place and the
/// only place. Announcements do. The recording watch's banners arrive
/// unrequested and land on a display the user may not be facing, and the
/// center of a wide display is also where the thing being worked on usually
/// is, the one spot a banner is most likely to be in the way of.
nonisolated enum ThawHUDPlacement: String, CaseIterable, Hashable {
    /// Under the left end of the menu bar, past the application menus.
    case leading
    /// Under the middle of the menu bar. What every HUD caller gets unless it
    /// asks otherwise.
    case center
    /// Under the right end of the menu bar, nearest the status items the
    /// camera and microphone indicators appear in themselves.
    case trailing

    /// How far the off-center cases stay clear of the screen's edge, where a
    /// rounded display corner would otherwise clip the capsule.
    static let edgeInset: CGFloat = 16

    /// The capsule's left edge for a capsule width wide on screenFrame.
    ///
    /// Pure math over the frame, so all three cases are decidable without a
    /// display attached.
    func originX(screenFrame: CGRect, width: CGFloat) -> CGFloat {
        switch self {
        case .leading:
            screenFrame.minX + Self.edgeInset
        case .center:
            screenFrame.midX - width / 2
        case .trailing:
            screenFrame.maxX - width - Self.edgeInset
        }
    }

    /// The picker's label for this case.
    var localized: LocalizedStringKey {
        switch self {
        case .leading: "Top left"
        case .center: "Top center"
        case .trailing: "Top right"
        }
    }
}
