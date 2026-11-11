//
//  LayoutDashboardModel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import Observation

/// The Layout window's state: which bar it edits and whether the person is on it.
@MainActor
@Observable
final class LayoutDashboardModel {
    private(set) var pin: LayoutTargetPin

    /// The profile in use, shown beside the target. Read each time, so a Space that
    /// applies another profile renames the window while it is open.
    var profileName: String? {
        readProfileName()
    }

    /// The layout history the toolbar's Undo and Redo act on.
    let undo: LayoutUndoState

    /// The selection the bars and the item list share.
    let selection = LayoutSelectionModel(onMultiSelect: { FeatureTips.shared.noteMultiSelect() })

    /// The toolbar's filter for the item list.
    var filterText = ""

    /// A view behind the filter field, so the window can tell the filter from other fields.
    @ObservationIgnored weak var filterAnchor: NSView?

    /// Which sections the item list shows.
    var scope = LayoutItemListScope.all

    /// The right pane's tab.
    var sidePane = LayoutDashboardSidePane.Pane.item

    @ObservationIgnored private let readTarget: @MainActor () -> LayoutEditTarget
    @ObservationIgnored private let readProfileName: @MainActor () -> String?
    @ObservationIgnored private var cancellable: AnyCancellable?

    init(
        profileName: @escaping @MainActor () -> String? = { nil },
        undoManager: UndoManager = UndoManager(),
        readTarget: @escaping @MainActor () -> LayoutEditTarget,
        changes: some Publisher<Void, Never> = Empty<Void, Never>()
    ) {
        self.readTarget = readTarget
        readProfileName = profileName
        undo = LayoutUndoState(undoManager: undoManager)
        pin = LayoutTargetPin(readTarget())
        cancellable = changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
    }

    func refresh() {
        pin.observe(readTarget())
    }

    func retargetToCurrent() {
        pin.retargetToCurrent()
    }
}

extension LayoutDashboardModel {
    /// A model on the live menu bar, following Space and display changes.
    static func live(appState: AppState, displayInvalidations: some Publisher<Void, Never>) -> LayoutDashboardModel {
        LayoutDashboardModel(
            profileName: { activeProfileName(appState: appState) },
            undoManager: appState.layoutUndo,
            readTarget: { liveTarget(spaces: appState.spaceDirectory.spaces) },
            changes: DisplayEnvironment.spaceOrDisplayChanges(merging: displayInvalidations)
        )
    }

    /// The profile in use, or nil when profiles are off.
    static func activeProfileName(appState: AppState) -> String? {
        let profiles = appState.profileManager
        guard appState.profilesFeature.isOn, let id = profiles.activeProfileID else { return nil }
        return profiles.profiles.first { $0.id == id }?.name
    }

    /// The active menu bar's display and the Space showing on it.
    static func liveTarget(spaces: [Bridging.ManagedSpace]) -> LayoutEditTarget {
        let screen = NSScreen.activeMenuBarScreenOrMain
        let displayID = screen?.displayID ?? CGMainDisplayID()
        let spaceID = Bridging.getActiveSpaceID()
        let space = spaces.first { $0.spaceID == spaceID }
        return LayoutEditTarget(
            displayUUID: Bridging.getDisplayUUIDString(for: displayID),
            displayID: displayID,
            spaceKey: space?.persistentKey,
            displayName: screen?.localizedName ?? String(localized: "Display"),
            spaceName: SpaceLabels.label(ofSpaceID: spaceID, in: spaces, ownerName: SpaceLabels.liveOwnerName)
        )
    }
}
