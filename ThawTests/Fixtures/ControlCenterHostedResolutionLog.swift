//
//  ControlCenterHostedResolutionLog.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Verbatim SourcePIDCache "diag unresolved" lines captured from the field,
/// used by the strict-spatial-pass log-replay harness. Each line records, for
/// one menu bar window that was unresolved at the moment of capture, the CG
/// owner and the nearest AXExtrasMenuBar children (app, distance, enabled), so
/// the harness can replay which app the strict 1pt pass would bind the icon
/// to.
///
/// The two fixtures are the mutually-protective pair this area keeps
/// regressing on: Little Snitch (must NOT bind to Control Center, so it stays
/// an orphan for marker-pair) and The Clock (must bind to its own app). A fix
/// for either one has repeatedly broken the other, so both are pinned here.
enum ControlCenterHostedResolutionLog {
    /// Little Snitch agent icon, from thaw_2026-06-08_20-54-21.log (beta.15,
    /// commit 9a003611, macOS 26.5.1), line 3051. The icon (windowID 355,
    /// generic title Item-0, 116pt wide) is hosted by Control Center at the CG
    /// layer. The ONLY AX child within the strict 1pt tolerance is Control
    /// Center's OWN (distance 0.0, AXEnabled absent); the next candidate is
    /// 74pt away. Little Snitch publishes no extras-bar child of its own, so
    /// accepting Control Center's self-match misattributes it to
    /// com.apple.controlcenter and starves the marker-pair / provoke path.
    static let littleSnitch = """
    2026-06-08 20:57:54.289 [DEBUG] [SourcePIDCache] SourcePIDCache diag unresolved: windowID=355 title=Item-0 bounds=(889.0, 0.0, 116.0, 33.0) center=(947.0, 16.5) | cgOwner=com.apple.controlcenter:pid=648 ownerName=Control Center | closestAXFrame=(889.0, 0.0, 116.0, 33.0) in app=com.apple.controlcenter distance=0.0 closestAXEnabled=nil | nearest=[com.apple.controlcenter@0.0(enabled=nil), com.shortery-app.Shortery@74.0(enabled=true), org.languagetool.desktop@77.0(enabled=true)]
    """

    /// The Clock (com.fabriceleyne.theclock), from
    /// thaw_2026-06-03_09-44-18.copy.log (beta.14 diagnostic build 37dfb6a),
    /// line for windowID 6475. The icon also carries the generic title Item-0
    /// and is hosted by Control Center at the CG layer, but the matching
    /// distance-0 child is published by The Clock's OWN app (AXEnabled absent),
    /// so it must resolve to com.fabriceleyne.theclock. Crucially, Control
    /// Center publishes no competing child here: the nearest candidate after
    /// The Clock is 40pt away, and com.apple.controlcenter never appears in the
    /// candidate list.
    static let theClock = """
    2026-06-03 09:44:46.106 [DEBUG] [SourcePIDCache] SourcePIDCache diag unresolved: windowID=6475 title=Item-0 bounds=(-3725.0, 0.0, 46.0, 34.0) center=(-3702.0, 17.0) | cgOwner=com.apple.controlcenter:pid=701 ownerName=Control Center | closestAXFrame=(-3717.0, 6.0, 30.0, 22.0) in app=com.fabriceleyne.theclock distance=0.0 closestAXEnabled=nil | nearest=[com.fabriceleyne.theclock@0.0(enabled=nil), com.muesli.app@40.0(enabled=true), com.antiless.cleanclip.mac@74.0(enabled=true)]
    """
}
