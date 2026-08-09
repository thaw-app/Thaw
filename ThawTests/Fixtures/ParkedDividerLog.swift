//
//  ParkedDividerLog.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics

/// The two menu bar shapes the #899 field log alternated between while the
/// boundary move storm ran.
///
/// Reporter: single notched MacBook Pro (`screen.maxX=2056`, notch
/// `918…1138`, right boundary 1985), macOS 26.6.1 build 25G76, Thaw
/// 2.0.0-rc.2.1 (49) commit `54345d40`, log `thaw_2026-08-09_18-14-12.log`.
///
/// The log covers 22 seconds and never converges. `Profile re-sort` fires
/// seven times, and the hidden section's membership alternates 4 → 0 → 4
/// with `hiddenBoundaryMismatch` alternating 5 → 9 → 5. Every pass tries to
/// drag `H_ctrl` next to coconutBattery, every pass burns all eight attempts
/// on `EventError.cannotComplete`, and the per-item pass that follows flips
/// the membership back so the next re-sort has the same work to do. It ends
/// only because the reporter killed the app.
///
/// The two states fail for different reasons, which is why #881's anchor
/// filter alone does not close the loop:
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
    /// The reporter's display. Only `maxX` is quoted in the log; the height
    /// is whatever contains a menu bar item's center, which every item in
    /// the log has at `y=19.5` (bounds `y=0`, `height=39`).
    static let display = CGRect(x: 0, y: 0, width: 2056, height: 1329)

    static let screenFrames = [display]

    /// Menu bar item height as logged by `captureWindowsImageSCK`.
    private static let itemHeight: CGFloat = 39

    /// Builds a menu bar item rect at the given `minX`, matching the log's
    /// vertical geometry.
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
    /// visible, so only the always-hidden divider is left between the
    /// dividers. The log records `hidden section has 0 items` alongside
    /// `Skipping saveSectionOrder; hidden section has zero width`.
    static let hiddenWhenAnchorOnScreen: [String] = []

    /// The anchor `planHiddenDividerAnchor` picked on every pass, and the
    /// first entry of the profile's desired hidden order.
    static let anchorUID = "com.coconut-flavour.coconutBattery-Menu:Item-0"

    /// The divider being dragged.
    static let hiddenDividerUID = "com.stonerl.Thaw:Thaw.ControlItem.Hidden"

    /// `hiddenBoundaryMismatch` per pass, in order. Never reaches zero.
    static let mismatchPerPass = [5, 9, 5, 9, 5, 9, 5]
}
