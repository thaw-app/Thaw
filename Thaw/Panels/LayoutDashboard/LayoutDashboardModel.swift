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

    /// The profile in use when the window opened, shown beside the target.
    private(set) var profileName: String?

    /// The layout history the toolbar's Undo and Redo act on.
    let undo: LayoutUndoState

    /// The selection the bars and the item list share.
    let selection = LayoutSelectionModel(onMultiSelect: { FeatureTips.shared.noteMultiSelect() })

    /// The toolbar's filter for the item list.
    var filterText = ""

    @ObservationIgnored private let readTarget: @MainActor () -> LayoutEditTarget
    @ObservationIgnored private var cancellable: AnyCancellable?

    init(
        profileName: String? = nil,
        undoManager: UndoManager = UndoManager(),
        readTarget: @escaping @MainActor () -> LayoutEditTarget,
        changes: some Publisher<Void, Never> = Empty<Void, Never>()
    ) {
        self.readTarget = readTarget
        self.profileName = profileName
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
        let profiles = appState.profileManager
        let profileName = appState.profilesFeature.isOn
            ? profiles.activeProfileID.flatMap { id in profiles.profiles.first { $0.id == id }?.name }
            : nil
        return LayoutDashboardModel(
            profileName: profileName,
            undoManager: appState.layoutUndo,
            readTarget: { liveTarget(spaces: appState.spaceDirectory.spaces) },
            changes: DisplayEnvironment.spaceOrDisplayChanges(merging: displayInvalidations)
        )
    }

    /// The active menu bar's display and the Space showing on it.
    static func liveTarget(spaces: [Bridging.ManagedSpace]) -> LayoutEditTarget {
        let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main
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
