//
//  LittleSnitchOrphanLog.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// A trimmed, verbatim excerpt from a field-captured Thaw log used as the
/// first fixture for the profile-layout log-replay harness.
///
/// Source: thaw_2026-05-29_17-13-13.log (a ~23k-line capture reported by a
/// user whose Little Snitch agent kept moving on launch). Only the lines the
/// harness parses are retained, copied without modification:
///
///   - the Missing sourcePID warning that proves the Little Snitch agent icon
///     (windowID 64, namespaced com.apple.controlcenter:Item-0) had no
///     resolved source process for most of the session;
///   - one buggy applyProfileLayout cycle at 17:13:37 where the unresolved
///     orphan is the sole item routed through planUnmanagedPlacement and then
///     physically moved;
///   - one clean applyProfileLayout cycle at 18:01:11, after marker-pair
///     resolution renamed the same physical item to
///     at.obdev.littlesnitch.agent:Item-0, where nothing is unmanaged.
///
/// Thaw does not log the desired visible set (only desiredHidden / desiredAH),
/// which is why the harness reconstructs it; see the harness for how.
enum LittleSnitchOrphanLog {
    static let text = """
    2026-05-29 17:13:15.062 [WARNING] [MenuBarItemManager] Missing sourcePID for <com.apple.controlcenter:Item-0 (windowID: 64)>
    2026-05-29 17:13:37.430 [DEBUG] [MenuBarItemManager] applyProfileLayout: current visible section has 3 items: ["com.stonerl.Thaw:Thaw.ControlItem.Visible", "com.apple.controlcenter:Item-0", "com.rogueamoeba.soundsource:SSMainAppMenuIcon"]
    2026-05-29 17:13:37.430 [DEBUG] [MenuBarItemManager] applyProfileLayout: current hidden section has 5 items: ["com.microsoft.OneDrive-mac:Item-0", "app.updatest.Updatest:Item-0", "org.eduvpn.app:Item-0", "com.wireguard.macos:Item-0", "com.apple.systemuiserver:com.apple.menuextra.TimeMachine"]
    2026-05-29 17:13:37.431 [DEBUG] [MenuBarItemManager] applyProfileLayout: current always-hidden section has 7 items: ["com.governikus.ausweisapp2:Item-0", "pl.maketheweb.pixelsnap2:Item-0", "pl.maketheweb.cleanshotx:Item-0", "org.languagetool.desktop:Item-0", "com.DanPristupov.Fork:Item-0", "com.shortery-app.Shortery:Item-0", "de.fauler-apfel.CMD-Z:Item-0"]
    2026-05-29 17:13:37.433 [DEBUG] [MenuBarItemManager] Profile layout: planUnmanagedPlacement com.apple.controlcenter:Item-0 -> newItemAnchored(section=visible section, anchor=com.apple.controlcenter:Item-0, relation=leftOfAnchor)
    2026-05-29 17:13:37.433 [DEBUG] [MenuBarItemManager] Profile layout: 1 unmanaged item(s) placed via planUnmanagedPlacement
    2026-05-29 17:13:37.436 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: ahCtrlUID=com.stonerl.Thaw:Thaw.ControlItem.AlwaysHidden, crossSectionMoves=0, totalSectionMismatch=0
    2026-05-29 17:13:37.436 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: currentHidden=["app.updatest.Updatest:Item-0", "com.apple.systemuiserver:com.apple.menuextra.TimeMachine", "com.microsoft.OneDrive-mac:Item-0", "com.stonerl.Thaw:Thaw.ControlItem.AlwaysHidden", "com.wireguard.macos:Item-0", "org.eduvpn.app:Item-0"]
    2026-05-29 17:13:37.436 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: currentAH=["com.DanPristupov.Fork:Item-0", "com.governikus.ausweisapp2:Item-0", "com.shortery-app.Shortery:Item-0", "de.fauler-apfel.CMD-Z:Item-0", "org.languagetool.desktop:Item-0", "pl.maketheweb.cleanshotx:Item-0", "pl.maketheweb.pixelsnap2:Item-0"]
    2026-05-29 17:13:37.436 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: desiredHidden=["app.updatest.Updatest:Item-0", "com.apple.systemuiserver:com.apple.menuextra.TimeMachine", "com.microsoft.OneDrive-mac:Item-0", "com.wireguard.macos:Item-0", "org.eduvpn.app:Item-0"]
    2026-05-29 17:13:37.436 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: desiredAH=["com.DanPristupov.Fork:Item-0", "com.c-command.SpamSieve:com.c-command.spamsieve", "com.governikus.ausweisapp2:Item-0", "com.shortery-app.Shortery:Item-0", "de.fauler-apfel.CMD-Z:Item-0", "org.languagetool.desktop:Item-0", "pl.maketheweb.cleanshotx:Item-0", "pl.maketheweb.pixelsnap2:Item-0"]
    2026-05-29 17:13:37.536 [INFO] [MenuBarItemManager] Moving <com.apple.controlcenter:Item-0 (windowID: 64)> to right of <com.rogueamoeba.soundsource:SSMainAppMenuIcon (windowID: 51) (windowID: 51)> on display 1
    2026-05-29 17:59:54.647 [INFO] [SourcePIDCache] SourcePIDCache marker-pair resolution: windowID=5992 → PID 843 via marker windowID=6558 (title=at.obdev.littlesnitch.agent)
    2026-05-29 18:01:11.245 [DEBUG] [MenuBarItemManager] applyProfileLayout: current visible section has 3 items: ["com.stonerl.Thaw:Thaw.ControlItem.Visible", "com.rogueamoeba.soundsource:SSMainAppMenuIcon", "at.obdev.littlesnitch.agent:Item-0"]
    2026-05-29 18:01:11.246 [DEBUG] [MenuBarItemManager] applyProfileLayout: current hidden section has 5 items: ["com.microsoft.OneDrive-mac:Item-0", "app.updatest.Updatest:Item-0", "org.eduvpn.app:Item-0", "com.wireguard.macos:Item-0", "com.apple.systemuiserver:com.apple.menuextra.TimeMachine"]
    2026-05-29 18:01:11.246 [DEBUG] [MenuBarItemManager] applyProfileLayout: current always-hidden section has 7 items: ["com.governikus.ausweisapp2:Item-0", "pl.maketheweb.pixelsnap2:Item-0", "pl.maketheweb.cleanshotx:Item-0", "org.languagetool.desktop:Item-0", "com.DanPristupov.Fork:Item-0", "com.shortery-app.Shortery:Item-0", "de.fauler-apfel.CMD-Z:Item-0"]
    2026-05-29 18:01:11.247 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: ahCtrlUID=com.stonerl.Thaw:Thaw.ControlItem.AlwaysHidden, crossSectionMoves=0, totalSectionMismatch=0
    2026-05-29 18:01:11.247 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: currentHidden=["app.updatest.Updatest:Item-0", "com.apple.systemuiserver:com.apple.menuextra.TimeMachine", "com.microsoft.OneDrive-mac:Item-0", "com.stonerl.Thaw:Thaw.ControlItem.AlwaysHidden", "com.wireguard.macos:Item-0", "org.eduvpn.app:Item-0"]
    2026-05-29 18:01:11.247 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: currentAH=["com.DanPristupov.Fork:Item-0", "com.governikus.ausweisapp2:Item-0", "com.shortery-app.Shortery:Item-0", "de.fauler-apfel.CMD-Z:Item-0", "org.languagetool.desktop:Item-0", "pl.maketheweb.cleanshotx:Item-0", "pl.maketheweb.pixelsnap2:Item-0"]
    2026-05-29 18:01:11.247 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: desiredHidden=["app.updatest.Updatest:Item-0", "com.apple.systemuiserver:com.apple.menuextra.TimeMachine", "com.microsoft.OneDrive-mac:Item-0", "com.wireguard.macos:Item-0", "org.eduvpn.app:Item-0"]
    2026-05-29 18:01:11.247 [DEBUG] [MenuBarItemManager] Profile layout Phase 1: desiredAH=["com.DanPristupov.Fork:Item-0", "com.c-command.SpamSieve:com.c-command.spamsieve", "com.governikus.ausweisapp2:Item-0", "com.shortery-app.Shortery:Item-0", "de.fauler-apfel.CMD-Z:Item-0", "org.languagetool.desktop:Item-0", "pl.maketheweb.cleanshotx:Item-0", "pl.maketheweb.pixelsnap2:Item-0"]
    2026-05-29 18:01:11.255 [INFO] [MenuBarItemManager] Moving <com.rogueamoeba.soundsource:SSMainAppMenuIcon (windowID: 51) (windowID: 51)> to right of <at.obdev.littlesnitch.agent:Item-0 (windowID: 5992) (windowID: 5992)> on display 1
    """
}
