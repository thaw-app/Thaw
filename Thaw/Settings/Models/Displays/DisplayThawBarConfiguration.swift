//
//  DisplayThawBarConfiguration.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Per-display configuration for the Thaw Bar.
nonisolated struct DisplayThawBarConfiguration: Codable, Equatable {
    /// Whether the Thaw Bar is enabled on this display.
    let useThawBar: Bool

    /// The location where the Thaw Bar appears on this display.
    let thawBarLocation: ThawBarLocation

    /// Whether to always show hidden menu bar items on this display.
    ///
    /// This setting is only applicable when useThawBar is false.
    let alwaysShowHiddenItems: Bool

    /// The layout mode for the Thaw Bar on this display.
    let thawBarLayout: ThawBarLayout

    /// The maximum number of items per row when the Thaw Bar is in grid layout.
    ///
    /// Valid range is 2 through 10.
    let gridColumns: Int

    /// The menu bar item spacing offset to apply when this display is the
    /// active menu bar display. Range is -16 to +16. The OS reads
    /// NSStatusItemSpacing as a single system-wide value, so this is the
    /// value that gets written + relaunched whenever this display becomes
    /// (or remains) the active menu bar display.
    let itemSpacingOffset: Double

    /// Default configuration (disabled, dynamic location, horizontal layout).
    static let defaultConfiguration = DisplayThawBarConfiguration(
        useThawBar: false,
        thawBarLocation: .dynamic,
        alwaysShowHiddenItems: false,
        thawBarLayout: .horizontal,
        gridColumns: 4,
        itemSpacingOffset: 0
    )

    func withUseThawBar(_ value: Bool) -> DisplayThawBarConfiguration {
        DisplayThawBarConfiguration(
            useThawBar: value,
            thawBarLocation: thawBarLocation,
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            thawBarLayout: thawBarLayout,
            gridColumns: gridColumns,
            itemSpacingOffset: itemSpacingOffset
        )
    }

    func withThawBarLocation(_ value: ThawBarLocation) -> DisplayThawBarConfiguration {
        DisplayThawBarConfiguration(
            useThawBar: useThawBar,
            thawBarLocation: value,
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            thawBarLayout: thawBarLayout,
            gridColumns: gridColumns,
            itemSpacingOffset: itemSpacingOffset
        )
    }

    func withAlwaysShowHiddenItems(_ value: Bool) -> DisplayThawBarConfiguration {
        DisplayThawBarConfiguration(
            useThawBar: useThawBar,
            thawBarLocation: thawBarLocation,
            alwaysShowHiddenItems: value,
            thawBarLayout: thawBarLayout,
            gridColumns: gridColumns,
            itemSpacingOffset: itemSpacingOffset
        )
    }

    func withThawBarLayout(_ value: ThawBarLayout) -> DisplayThawBarConfiguration {
        DisplayThawBarConfiguration(
            useThawBar: useThawBar,
            thawBarLocation: thawBarLocation,
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            thawBarLayout: value,
            gridColumns: gridColumns,
            itemSpacingOffset: itemSpacingOffset
        )
    }

    /// Values are clamped to the range 2 through 10.
    func withGridColumns(_ value: Int) -> DisplayThawBarConfiguration {
        DisplayThawBarConfiguration(
            useThawBar: useThawBar,
            thawBarLocation: thawBarLocation,
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            thawBarLayout: thawBarLayout,
            gridColumns: Swift.max(2, Swift.min(value, 10)),
            itemSpacingOffset: itemSpacingOffset
        )
    }

    /// Values are clamped to the range -16 through 16.
    func withItemSpacingOffset(_ value: Double) -> DisplayThawBarConfiguration {
        DisplayThawBarConfiguration(
            useThawBar: useThawBar,
            thawBarLocation: thawBarLocation,
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            thawBarLayout: thawBarLayout,
            gridColumns: gridColumns,
            itemSpacingOffset: Swift.max(-16, Swift.min(value, 16))
        )
    }

    /// Builds per-display configurations for all connected screens.
    @MainActor
    static func buildConfigurations(
        onlyOnNotched: Bool,
        location: ThawBarLocation
    ) -> [String: DisplayThawBarConfiguration] {
        var configs = [String: DisplayThawBarConfiguration]()
        for screen in NSScreen.managedScreens {
            guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else {
                continue
            }
            let enabled = onlyOnNotched ? screen.hasNotch : true
            configs[uuid] = DisplayThawBarConfiguration(
                useThawBar: enabled,
                thawBarLocation: location,
                alwaysShowHiddenItems: false,
                thawBarLayout: .horizontal,
                gridColumns: 4,
                itemSpacingOffset: 0
            )
        }
        return configs
    }
}

// MARK: - Backward-compatible decoding

nonisolated extension DisplayThawBarConfiguration {
    enum CodingKeys: String, CodingKey {
        // The Ice-era key strings are pinned: configurations already written
        // to disk use them, and changing them would silently drop settings.
        case useThawBar = "useIceBar"
        case thawBarLocation = "iceBarLocation"
        case alwaysShowHiddenItems
        case thawBarLayout = "iceBarLayout"
        case gridColumns
        case itemSpacingOffset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.useThawBar = try container.decode(Bool.self, forKey: .useThawBar)
        self.thawBarLocation = try container.decode(ThawBarLocation.self, forKey: .thawBarLocation)
        self.alwaysShowHiddenItems = try container.decode(Bool.self, forKey: .alwaysShowHiddenItems)
        self.thawBarLayout = try container.decodeIfPresent(ThawBarLayout.self, forKey: .thawBarLayout) ?? .horizontal
        let decodedGridColumns = try container.decodeIfPresent(Int.self, forKey: .gridColumns) ?? 4
        self.gridColumns = Swift.max(2, Swift.min(decodedGridColumns, 10))
        let decodedSpacing = try container.decodeIfPresent(Double.self, forKey: .itemSpacingOffset) ?? 0
        self.itemSpacingOffset = Swift.max(-16, Swift.min(decodedSpacing, 16))
    }
}
