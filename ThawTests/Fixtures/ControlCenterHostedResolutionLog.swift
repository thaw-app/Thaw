//
//  ControlCenterHostedResolutionLog.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Verbatim SourcePIDCache "diag unresolved" field lines: the CG owner and
/// nearest AXExtrasMenuBar children (app, distance, enabled) of one
/// unresolved window.
///
/// Little Snitch must not bind to Control Center; The Clock must bind to its
/// own app. A fix for either has repeatedly broken the other.
enum ControlCenterHostedResolutionLog {
    /// Little Snitch agent icon (macOS 26.5.1), hosted by Control Center. The
    /// only AX child within 1pt is Control Center's own; Little Snitch
    /// publishes none, so accepting it starves the marker-pair path.
    static let littleSnitch = """
    2026-06-08 20:57:54.289 [DEBUG] [SourcePIDCache] SourcePIDCache diag unresolved: windowID=355 title=Item-0 bounds=(889.0, 0.0, 116.0, 33.0) center=(947.0, 16.5) | cgOwner=com.apple.controlcenter:pid=648 ownerName=Control Center | closestAXFrame=(889.0, 0.0, 116.0, 33.0) in app=com.apple.controlcenter distance=0.0 closestAXEnabled=nil | nearest=[com.apple.controlcenter@0.0(enabled=nil), com.shortery-app.Shortery@74.0(enabled=true), org.languagetool.desktop@77.0(enabled=true)]
    """

    /// The Clock, also titled Item-0 and hosted by Control Center, but the
    /// distance-0 child is its own app's and Control Center publishes no
    /// competing child.
    static let theClock = """
    2026-06-03 09:44:46.106 [DEBUG] [SourcePIDCache] SourcePIDCache diag unresolved: windowID=6475 title=Item-0 bounds=(-3725.0, 0.0, 46.0, 34.0) center=(-3702.0, 17.0) | cgOwner=com.apple.controlcenter:pid=701 ownerName=Control Center | closestAXFrame=(-3717.0, 6.0, 30.0, 22.0) in app=com.fabriceleyne.theclock distance=0.0 closestAXEnabled=nil | nearest=[com.fabriceleyne.theclock@0.0(enabled=nil), com.muesli.app@40.0(enabled=true), com.antiless.cleanclip.mac@74.0(enabled=true)]
    """
}
