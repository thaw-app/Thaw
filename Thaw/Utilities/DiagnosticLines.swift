//
//  DiagnosticLines.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// The wording of log lines whose detail decides a diagnosis, kept out of the large types that write them.
nonisolated enum DiagnosticLines {
    /// A display can keep its ID while it moves or changes size, so the line names each one's frame.
    static func screensChanged(_ screens: [(id: CGDirectDisplayID, frame: CGRect, isMain: Bool)]) -> String {
        let described = screens.map { "\($0.id)=\($0.frame)\($0.isMain ? " main" : "")" }
        return "Screen parameters changed, \(screens.count) screen(s) connected: \(described.joined(separator: ", "))"
    }

    /// Why a reveal's boundary check found an item out of its section, with the frames it compared.
    static func boundaryRepair(
        item: String,
        itemX: CGFloat,
        section: String,
        hiddenDividerX: CGFloat,
        alwaysHiddenDividerX: CGFloat?,
        revealed: String
    ) -> String {
        "boundary repair: \(item) at x=\(itemX) is not in \(section) (hidden divider x=\(hiddenDividerX), " +
            "always hidden x=\(alwaysHiddenDividerX.map { "\($0)" } ?? "none"), revealed \(revealed))"
    }

    /// The tiles a Layout row built, naming those drawn without a picture, so a missing icon can be told from a blank one.
    static func layoutTiles(section: String, tiles: [(name: String, hasPicture: Bool)]) -> String {
        let blank = tiles.filter { !$0.hasPicture }.map(\.name)
        return "layout tiles (\(section)): \(tiles.count) [\(tiles.map(\.name).joined(separator: ", "))]; " +
            "no picture: [\(blank.joined(separator: ", "))]"
    }
}

@MainActor
extension DiagnosticLines {
    private static let layoutLog = DiagLog(category: "LayoutBarContainer")
    private static var lastLayoutTiles = [String: String]()

    static func screensChanged(_ screens: [NSScreen]) -> String {
        screensChanged(screens.map { (id: $0.displayID, frame: $0.frame, isMain: $0 == NSScreen.main) })
    }

    static func boundaryRepair(
        _ item: MenuBarItem,
        section: MenuBarSection.Name,
        controlItems: ControlItemPair,
        revealed: MenuBarSection.Name
    ) -> String {
        boundaryRepair(
            item: item.logString,
            itemX: item.bounds.midX,
            section: section.logString,
            hiddenDividerX: controlItems.hidden.bounds.midX,
            alwaysHiddenDividerX: controlItems.alwaysHidden?.bounds.midX,
            revealed: revealed.logString
        )
    }

    /// Logs a Layout row's tiles when they differ from the last time that row was logged.
    static func logLayoutTiles(section: MenuBarSection.Name, items: [MenuBarItem], imageCache: MenuBarItemImageCache) {
        let line = layoutTiles(
            section: section.logString,
            tiles: items.map { (name: $0.logString, hasPicture: imageCache.image(for: $0.tag) != nil) }
        )
        guard lastLayoutTiles[section.logString] != line else { return }
        lastLayoutTiles[section.logString] = line
        layoutLog.debug("\(line)")
    }
}
