//
//  LayoutStormLog.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// The menu bar shape captured in the #881 field log, at the moment the
/// storm started.
///
/// Reporter: single notched 14" MacBook Pro (1728×1117, notch 771…956,
/// right boundary 1538), macOS 26.6 build 25G72, Thaw 2.0.0-rc.2 (48),
/// log `thaw_2026-08-05_04-41-41.log` cycle `04:46:26`.
///
/// LM Studio had just launched. Its item attached at x=1066 — left of Sound
/// (x≈1106) and Google Drive (x=1142) — while the saved profile ordered it
/// to their right. One item, displaced by two slots, near the front of the
/// row.
///
/// The deleted full-sort path trimmed its replay by the longest correctly
/// ordered *prefix*, so that one displacement invalidated everything after
/// it and the log records `Profile layout (full sort): 10 item(s)` followed
/// by ten sequential drags over 4.1 seconds. See
/// ``LayoutStormReplayTests`` for what the surviving planner does instead.
enum LayoutStormLog {
    /// Visible section, left to right, as logged by
    /// `applyProfileLayout: current visible section` at 04:46:26.721.
    static let currentVisible = [
        "com.apple.controlcenter:FocusModes",
        "ai.elementlabs.lmstudio:Item-0",
        "com.apple.controlcenter:Sound",
        "com.google.drivefs:Item-0",
        "com.adobe.acc.AdobeCreativeCloud:Item-0",
        "com.displaylink.DisplayLinkUserAgent:Item-0",
        "com.stonerl.Thaw:Thaw.ControlItem.Visible",
        "com.if.Amphetamine:Amphetamine",
        "com.ameba.TRex:Item-1",
        "com.apple.TextInputMenuAgent:Item-0",
        "com.apple.controlcenter:UserSwitcher",
        "com.apple.controlcenter:WiFi",
        "com.apple.controlcenter:Battery",
    ]

    /// Hidden section, left to right, as logged at 04:46:26.722.
    static let currentHidden = [
        "org.tabby:Item-0",
        "com.electron.dockerdesktop:Item-0",
        "com.apple.systemuiserver:com.apple.menuextra.TimeMachine",
    ]

    /// The desired visible order.
    ///
    /// The log prints the full-sort sequence *after* prefix trimming, so the
    /// three leading items are reconstructed: `visibleUIDs.count=13` on the
    /// `Notch overflow budget` line fixes the length, and a trim of 7 (three
    /// hidden items, the hidden control item, and three visible ones) is the
    /// only split that yields the ten-item tail the log does print.
    static let desiredVisible = [
        "com.apple.controlcenter:FocusModes",
        "com.apple.controlcenter:Sound",
        "com.google.drivefs:Item-0",
        "ai.elementlabs.lmstudio:Item-0",
        "com.adobe.acc.AdobeCreativeCloud:Item-0",
        "com.displaylink.DisplayLinkUserAgent:Item-0",
        "com.stonerl.Thaw:Thaw.ControlItem.Visible",
        "com.if.Amphetamine:Amphetamine",
        "com.ameba.TRex:Item-1",
        "com.apple.TextInputMenuAgent:Item-0",
        "com.apple.controlcenter:UserSwitcher",
        "com.apple.controlcenter:WiFi",
        "com.apple.controlcenter:Battery",
    ]

    /// The ten items the deleted full-sort path dragged, in the order it
    /// dragged them, transcribed from the `Profile layout (full sort):
    /// <uid> → .leftOfItem(CC)` lines between 04:46:26.734 and 04:46:30.380.
    static let fullSortDraggedItems = [
        "ai.elementlabs.lmstudio:Item-0",
        "com.adobe.acc.AdobeCreativeCloud:Item-0",
        "com.displaylink.DisplayLinkUserAgent:Item-0",
        "com.stonerl.Thaw:Thaw.ControlItem.Visible",
        "com.if.Amphetamine:Amphetamine",
        "com.ameba.TRex:Item-1",
        "com.apple.TextInputMenuAgent:Item-0",
        "com.apple.controlcenter:UserSwitcher",
        "com.apple.controlcenter:WiFi",
        "com.apple.controlcenter:Battery",
    ]

    /// Section map for every UID in the cycle.
    static var sectionMap: [String: String] {
        var map = [String: String]()
        for uid in currentVisible { map[uid] = "visible" }
        for uid in currentHidden { map[uid] = "hidden" }
        return map
    }
}
