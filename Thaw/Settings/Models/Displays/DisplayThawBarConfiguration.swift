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
    private(set) var useThawBar: Bool

    /// The location where the Thaw Bar appears on this display.
    private(set) var thawBarLocation: ThawBarLocation

    /// Whether to always show hidden menu bar items on this display.
    ///
    /// This setting is only applicable when useThawBar is false.
    private(set) var alwaysShowHiddenItems: Bool

    /// The layout mode for the Thaw Bar on this display.
    private(set) var thawBarLayout: ThawBarLayout

    /// The maximum number of items per row when the Thaw Bar is in grid layout.
    ///
    /// Valid range is 2 through 10.
    private(set) var gridColumns: Int

    /// The menu bar item spacing offset to apply when this display is the
    /// active menu bar display. Range is -16 to +16. The OS reads
    /// NSStatusItemSpacing as a single system-wide value, so this is the
    /// value that gets written + relaunched whenever this display becomes
    /// (or remains) the active menu bar display.
    private(set) var itemSpacingOffset: Double

    /// How large the Thaw Bar draws items on this display; 1 is the menu bar's
    /// size. See ThawBarItemSize for the range.
    private(set) var thawBarItemScale: Double

    /// Whether only Always Hidden opens in the Thaw Bar on this display, as in
    /// Thaw 2: reaching it inline would also open Hidden. Ignored while useThawBar is on.
    var useThawBarForAlwaysHidden = false

    /// Default configuration (disabled, dynamic location, horizontal layout).
    static let defaultConfiguration = DisplayThawBarConfiguration(
        useThawBar: false,
        thawBarLocation: .dynamic,
        alwaysShowHiddenItems: false,
        thawBarLayout: .horizontal,
        gridColumns: 4,
        itemSpacingOffset: 0,
        thawBarItemScale: ThawBarItemSize.defaultScale,
        useThawBarForAlwaysHidden: false
    )

    func withUseThawBar(_ value: Bool) -> DisplayThawBarConfiguration {
        with { $0.useThawBar = value }
    }

    func withThawBarLocation(_ value: ThawBarLocation) -> DisplayThawBarConfiguration {
        with { $0.thawBarLocation = value }
    }

    func withAlwaysShowHiddenItems(_ value: Bool) -> DisplayThawBarConfiguration {
        with { $0.alwaysShowHiddenItems = value }
    }

    func withThawBarLayout(_ value: ThawBarLayout) -> DisplayThawBarConfiguration {
        with { $0.thawBarLayout = value }
    }

    /// Values are clamped to the range 2 through 10.
    func withGridColumns(_ value: Int) -> DisplayThawBarConfiguration {
        with { $0.gridColumns = Swift.max(2, Swift.min(value, 10)) }
    }

    /// Values are clamped to the range -16 through 16.
    func withItemSpacingOffset(_ value: Double) -> DisplayThawBarConfiguration {
        with { $0.itemSpacingOffset = Swift.max(-16, Swift.min(value, 16)) }
    }

    /// Values are clamped to ThawBarItemSize.scaleRange.
    func withThawBarItemScale(_ value: Double) -> DisplayThawBarConfiguration {
        with { $0.thawBarItemScale = ThawBarItemSize.clampedScale(value) }
    }

    func withUseThawBarForAlwaysHidden(_ value: Bool) -> DisplayThawBarConfiguration {
        with { $0.useThawBarForAlwaysHidden = value }
    }

    /// A copy with one change applied, so a new field never has to be threaded through every builder.
    private func with(_ change: (inout DisplayThawBarConfiguration) -> Void) -> DisplayThawBarConfiguration {
        var copy = self
        change(&copy)
        return copy
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
            configs[uuid] = defaultConfiguration.withUseThawBar(enabled).withThawBarLocation(location)
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
        case thawBarItemScale
        case useThawBarForAlwaysHidden
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
        let decodedItemScale = try container.decodeIfPresent(Double.self, forKey: .thawBarItemScale) ?? ThawBarItemSize.defaultScale
        self.thawBarItemScale = ThawBarItemSize.clampedScale(decodedItemScale)
        // Thaw 2 wrote this key; reading it again restores the choice for configurations Thaw 3 hasn't rewritten.
        self.useThawBarForAlwaysHidden = try container.decodeIfPresent(Bool.self, forKey: .useThawBarForAlwaysHidden) ?? false
    }
}
