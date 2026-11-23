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
    nonisolated enum LiveCaptureScope: String, Codable, Equatable, Sendable {
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
        /// What the page shown in the settings process needs; nothing while no such process runs.
        var settingsProcess = SettingsProcessCaptureDemand.none

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
            if settingsProcess.liveScope != .none {
                return settingsProcess.liveScope
            }
            return isThawBarPresented ? .thawBar : .none
        }

        /// The same snapshot with what the settings process's page needs.
        func including(_ settingsProcess: SettingsProcessCaptureDemand) -> NavigationStateSnapshot {
            var snapshot = self
            snapshot.settingsProcess = settingsProcess
            return snapshot
        }
    }

    // MARK: Live Refresh Backoff

    /// Consecutive changeless passes before the tick slows to its floor.
    nonisolated static let backoffFloorStreak = 5

    /// Sleep for one live-refresh tick: 2.5 s, or 4 s once the bar stops changing.
    ///
    /// Bar changes recapture on their own, so the tick only refreshes animated icons. Capturing
    /// about once a second kept macOS's screen-recording indicator on while Layout was open.
    /// A slower setting is kept.
    static nonisolated func backedOffTickMilliseconds(
        baseMilliseconds: Int,
        changelessStreak: Int
    ) -> Int {
        let floor = changelessStreak < backoffFloorStreak ? 2500 : 4000
        return max(baseMilliseconds, floor)
    }
}

/// What the page shown in the settings process needs captured. That process works it out from its own
/// window with the rules above; the app acts on it, because only the app reads the screen.
nonisolated struct SettingsProcessCaptureDemand: Codable, Equatable, Sendable {
    /// Whether the page reads the screen at all, as hasVisibleCaptureUI says of a page in the app.
    var consumesCapture = false
    /// The item pictures the page draws, whether or not its process is in front.
    var scope = MenuBarItemImageCache.LiveCaptureScope.none
    /// Whether the settings process is the frontmost app. Its pictures are only kept fresh while it is.
    var isFrontmost = false
    /// Whether the page draws item pictures at all, fresh or not. The app readies none until one does.
    var showsPictures = false
    /// Whether the page draws every item's picture whatever "Use app icons" says, as the item shortcut list does.
    var needsEveryPicture = false

    static let none = SettingsProcessCaptureDemand()

    /// The pictures to keep fresh now.
    var liveScope: MenuBarItemImageCache.LiveCaptureScope {
        isFrontmost ? scope : .none
    }

    /// The same demand with its process in front, to tell whether the page still draws the pictures.
    var asIfFrontmost: SettingsProcessCaptureDemand {
        var demand = self
        demand.isFrontmost = true
        return demand
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
