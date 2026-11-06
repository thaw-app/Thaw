//
//  LayoutBarVisibilityLimit.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Why macOS keeps an icon out of the section its Layout tile is in.
enum LayoutBarVisibilityLimit: Equatable {
    /// The hiding restriction allows apps by registered bundle, so an icon
    /// whose process has none stays hidden while any other icon is hidden.
    case cannotShow
    /// The hiding restriction keeps nine of Apple's items by name. A Control Center item the user
    /// pinned, such as Home, is not one of them, so it leaves the bar while any icon is hidden.
    case pinnedModuleCannotShow
    /// Native app hiding found no Control Center switch that governs the app,
    /// so its icon stays on the bar.
    case cannotHide

    var explanation: String {
        switch self {
        case .cannotShow:
            String(localized: "macOS hides this icon while other icons are hidden because its app has no registered identity.")
        case .pinnedModuleCannotShow:
            String(localized: "macOS takes pinned Control Center items like this one off the menu bar while other icons are hidden. It comes back when you show them.")
        case .cannotHide:
            String(localized: "macOS won't let \(Constants.displayName) switch this app off, so its icon stays on the bar.")
        }
    }

    /// - Parameters:
    ///   - ownerHasRegisteredBundle: Whether the running owner has a registered
    ///     bundle identifier; nil when the owner is not running.
    ///   - ownerBundleID: The owner's bundle identifier, else its tag namespace.
    ///   - hidesOtherIcons: Whether any icon is assigned to a hidden section.
    ///   - isPinnedControlCenterModule: Whether the icon is a Control Center item the user pinned.
    static func limit(
        section: MenuBarSectionName,
        ownerHasRegisteredBundle: Bool?,
        ownerBundleID: String,
        nativeAppHidingActive: Bool,
        hidesOtherIcons: Bool,
        untrackedBundleIDs: Set<String>,
        isPinnedControlCenterModule: Bool = false
    ) -> Self? {
        if section == .visible {
            if isPinnedControlCenterModule {
                return !nativeAppHidingActive && hidesOtherIcons ? .pinnedModuleCannotShow : nil
            }
            return !nativeAppHidingActive && hidesOtherIcons && ownerHasRegisteredBundle == false ? .cannotShow : nil
        }
        return nativeAppHidingActive && untrackedBundleIDs.contains(ownerBundleID) ? .cannotHide : nil
    }

    @MainActor
    static func limit(for item: MenuBarItem, in section: MenuBarSectionName, appState: AppState) -> Self? {
        let menuBarManager = appState.menuBarManager
        let owner = item.sourceApplication
        return limit(
            section: section,
            ownerHasRegisteredBundle: owner.map { $0.bundleIdentifier != nil },
            ownerBundleID: owner?.bundleIdentifier ?? item.tag.namespace.description,
            nativeAppHidingActive: menuBarManager.nativeAppHidingExperiment.isActive,
            hidesOtherIcons: menuBarManager.sectionController.sectionAssignment.values.contains { $0 != .visible },
            untrackedBundleIDs: menuBarManager.nativeUntrackedBundleIDs,
            isPinnedControlCenterModule: item.tag.namespace.isMenuBarHostingNamespace
                && SystemMenuBarModuleCatalog.pinnedModuleName(inTitle: item.tag.title) != nil
        )
    }
}
