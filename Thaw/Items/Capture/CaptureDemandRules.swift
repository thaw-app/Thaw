//
//  CaptureDemandRules.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

extension MenuBarItemImageCache {
    // MARK: Capture Invalidation

    /// Cache state that requires a new capture. Position is left out because AX
    /// jitter would otherwise drive a capture feedback loop.
    nonisolated struct CaptureInvalidationKey: Equatable {
        let displayID: CGDirectDisplayID?
        let entries: [Entry]
    }

    static nonisolated func captureInvalidationKey(
        _ cache: MenuBarItemManager.ItemCache
    ) -> CaptureInvalidationKey {
        let entries = MenuBarSection.Name.allCases.flatMap { section in
            cache[section].map { item in
                CaptureInvalidationKey.Entry(
                    section: section.rawValue,
                    identifier: item.uniqueIdentifier,
                    windowID: item.windowID,
                    width: item.bounds.width,
                    height: item.bounds.height,
                    isOnScreen: item.isOnScreen
                )
            }
        }.sorted()
        return CaptureInvalidationKey(displayID: cache.displayID, entries: entries)
    }

    // MARK: Live Capture Scope

    /// One demand decision drives loop lifetime, periodic capture, and event-driven refresh.
    nonisolated enum LiveCaptureScope: Equatable, Sendable {
        case none
        case visible
        case allSections
        case thawBar

        func sections(thawBarSection: MenuBarSection.Name?) -> [MenuBarSection.Name] {
            switch self {
            case .none: []
            case .visible: [.visible]
            case .allSections: MenuBarSection.Name.allCases
            case .thawBar: thawBarSection.map { [$0] } ?? []
            }
        }
    }

    /// Snapshot of navigation state read in a single MainActor hop.
    struct NavigationStateSnapshot {
        let isThawBarPresented: Bool
        let isSearchPresented: Bool
        let isAppFrontmost: Bool
        let isSettingsPresented: Bool
        let settingsNavigationIdentifier: SettingsNavigationIdentifier?
        let isItemHotkeyListExpanded: Bool
        /// Simple Mode has no sidebar, so the identifier above never names its
        /// pane and cannot answer for it.
        let isSimpleModeSettings: Bool

        var liveCaptureScope: LiveCaptureScope {
            if isSearchPresented {
                return .visible
            }
            if isAppFrontmost, isSettingsPresented {
                if isSimpleModeSettings {
                    return .allSections
                }
                switch settingsNavigationIdentifier {
                case .menuBarLayout, .thawBar:
                    return .allSections
                case .hotkeys where isItemHotkeyListExpanded:
                    return .allSections
                default:
                    break
                }
            }
            return isThawBarPresented ? .thawBar : .none
        }
    }

    // MARK: Live Refresh Backoff

    /// Consecutive changeless passes before the tick interval starts backing
    /// off, and the streak at which it reaches the 1 Hz floor.
    private static let backoffGraceTicks = 5
    static let backoffFloorStreak = 60

    /// Sleep for one live-refresh tick.
    ///
    /// SCK one-shot captures are the dominant transient memory cost and most
    /// ticks change nothing, so changeless passes back off to at most 333 ms,
    /// then 1 Hz. Any change resets the streak to the slider's rate.
    static nonisolated func backedOffTickMilliseconds(
        baseMilliseconds: Int,
        changelessStreak: Int
    ) -> Int {
        let base = max(1, baseMilliseconds)
        switch changelessStreak {
        case ..<backoffGraceTicks:
            return base
        case ..<backoffFloorStreak:
            return max(base, min(333, base * 3))
        default:
            return max(base, 1000)
        }
    }
}

extension MenuBarItemImageCache.CaptureInvalidationKey {
    /// One item as the key sees it. Declared here rather than inside the key
    /// so it sits one level deep.
    nonisolated struct Entry: Equatable, Comparable {
        let section: String
        let identifier: String
        let windowID: CGWindowID
        let width: CGFloat
        let height: CGFloat
        let isOnScreen: Bool

        static func < (lhs: Entry, rhs: Entry) -> Bool {
            if lhs.section != rhs.section {
                return lhs.section < rhs.section
            }
            if lhs.identifier != rhs.identifier {
                return lhs.identifier < rhs.identifier
            }
            return lhs.windowID < rhs.windowID
        }
    }
}
