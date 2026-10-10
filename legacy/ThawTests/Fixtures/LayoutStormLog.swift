//
//  LayoutStormLog.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// The menu bar shape captured in the #881 field log, at the moment the
/// storm started.
///
/// Single notched 14" MacBook Pro (1728×1117, notch 771…956, right boundary
/// 1538), macOS 26.6.
///
/// LM Studio had just launched at x=1066, left of Sound and Google Drive,
/// while the profile ordered it to their right: one item two slots off.
/// The old full sort trimmed only the correct prefix, so it dragged ten
/// items. See ``LayoutStormReplayTests``.
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
    /// The log prints the sequence after prefix trimming, so the three leading
    /// items are reconstructed from `visibleUIDs.count=13` and the ten-item tail.
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

    /// The ten items the old full sort dragged, in order.
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
    static let sectionMap: [String: String] = {
        var map = [String: String]()
        for uid in currentVisible {
            map[uid] = "visible"
        }
        for uid in currentHidden {
            map[uid] = "hidden"
        }
        return map
    }()
}
