//
//  ParkedDividerLog.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// The two menu bar shapes the #899 field log alternated between while the
/// boundary move storm ran.
///
/// Single notched MacBook Pro (`screen.maxX=2056`, notch `918…1138`, right
/// boundary 1985), macOS 26.6.1.
///
/// The log never converges: hidden membership alternates 4 → 0 → 4 and
/// `hiddenBoundaryMismatch` 5 → 9 → 5. Every pass burns all eight attempts
/// dragging `H_ctrl` next to coconutBattery, and the per-item pass flips the
/// membership back.
///
/// The two states fail for different reasons, so #881's anchor filter alone
/// does not close the loop:
///
/// - ``anchorParked``: both the anchor and the divider sit in the parked
///   zone. `planHiddenDividerAnchor` rejects the anchor, so no drag is
///   planned. Covered by ``ParkedAnchorTests``.
/// - ``anchorOnScreen``: the anchor is back on the bar at `minX=1050`, so it
///   survives the anchor filter, but `H_ctrl` is still parked at
///   `minX=-3950`. The drag point is on screen and the owner accepts the
///   events, yet AppKit snaps the divider back on mouse-up and the attempt
///   reports "events succeeded but item not at destination".
enum ParkedDividerLog {
    /// Only `maxX` is logged; the height just has to contain the item
    /// centers at `y=19.5`.
    static let display = CGRect(x: 0, y: 0, width: 2056, height: 1329)

    static let screenFrames = [display]

    /// Menu bar item height as logged by `captureWindowsImageSCK`.
    private static let itemHeight: CGFloat = 39

    /// Builds an item rect at `minX` with the log's vertical geometry.
    static func bounds(minX: CGFloat, width: CGFloat = 24) -> CGRect {
        CGRect(x: minX, y: 0, width: width, height: itemHeight)
    }

    // MARK: - Odd passes: anchor parked

    /// `Move points` for the first attempt of passes 2, 6, 10 and 14:
    /// `targetMinX=-3950.0 itemMinX=-3869.0`. Both operands are parked.
    enum AnchorParked {
        static let anchorMinX: CGFloat = -3950
        static let hiddenDividerMinX: CGFloat = -3869
    }

    // MARK: - Even passes: anchor on screen, divider parked

    /// `Move points` for the first attempt of passes 4, 8 and 12:
    /// `targetMinX=1050.0 itemMinX=-3950.0`. The anchor is back on the bar;
    /// the divider is not.
    enum AnchorOnScreen {
        static let anchorMinX: CGFloat = 1050
        static let hiddenDividerMinX: CGFloat = -3950
    }

    // MARK: - Section membership

    /// Hidden section on the odd passes, as logged by
    /// `applyProfileLayout: current hidden section has 4 items`.
    static let hiddenWhenAnchorParked = [
        "com.coconut-flavour.coconutBattery-Menu:Item-0",
        "org.herf.Flux:Item-0",
        "com.hegenberg.BetterTouchTool:BetterTouchTool",
        "com.ohanaware.sleepAidRG2:testItem",
    ]

    /// Hidden section on the even passes: the per-item pass evacuated it into
    /// visible, and the save was skipped for zero width.
    static let hiddenWhenAnchorOnScreen: [String] = []

    /// The anchor `planHiddenDividerAnchor` picked on every pass, and the
    /// first entry of the profile's desired hidden order.
    static let anchorUID = "com.coconut-flavour.coconutBattery-Menu:Item-0"

    /// The divider being dragged.
    static let hiddenDividerUID = "com.stonerl.Thaw:Thaw.ControlItem.Hidden"

    /// `hiddenBoundaryMismatch` per pass, in order. Never reaches zero.
    static let mismatchPerPass = [5, 9, 5, 9, 5, 9, 5]
}
