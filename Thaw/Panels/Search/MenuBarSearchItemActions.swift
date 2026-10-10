//
//  MenuBarSearchItemActions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

// MARK: - MenuBarSearchItemActions

/// The organising verbs the search panel offers on its highlighted row.
///
/// These are the layout editor's verbs, not a second set: every decision comes
/// from the same gate, so a move search refuses is a move the editor refuses
/// with the same message. Only the call sequence is duplicated, because the
/// editor's copy lives in an NSView drag handler that needs a drop point.
@MainActor
enum MenuBarSearchItemActions {
    /// Builds the actions menu for item, or nil when the app state cannot
    /// answer for it.
    ///
    /// openSettings is handed in rather than performed here because the
    /// panel has to come down before the settings window comes up, and only
    /// the panel knows that.
    static func menu(
        for item: MenuBarItem,
        appState: AppState,
        openSettings: @escaping @MainActor () -> Void
    ) -> NSMenu {
        let menu = NSMenu()

        let section = appState.menuBarManager.sectionController.section(for: item)
        if let built = LayoutBarItemMenu.menu(
            subject: .item(item),
            section: section,
            orderedItems: displayOrderedItems(in: section, appState: appState),
            appState: appState
        ) {
            // An NSMenuItem belongs to one menu at a time, so the editor's
            // entries are moved across, front first to keep their order.
            while let entry = built.items.first {
                built.removeItem(entry)
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        let settingsEntry = ClosureMenuItem(title: String(localized: "Open Layout Settings…")) {
            openSettings()
        }
        settingsEntry.keyEquivalent = "l"
        settingsEntry.keyEquivalentModifierMask = .command
        menu.addItem(settingsEntry)

        return menu
    }

    /// The sections a move can target, in the order their ⌘-number shortcuts
    /// are numbered. A section the user has switched off is not a destination,
    /// but it keeps its number so the remaining two never renumber under
    /// someone's fingers.
    static func moveDestinations(appState: AppState) -> [MenuBarSection.Name?] {
        MenuBarSection.Name.allCases.map { name in
            (appState.menuBarManager.section(withName: name)?.isEnabled ?? true) ? name : nil
        }
    }

    /// Assigns item, together with the group it belongs to when it has one,
    /// to section.
    ///
    /// The gate is the layout editor's gate, and so is the explanation when it
    /// closes: see postAssignmentRefusal(for:to:experimentalSystemItemHiding:appState:)
    /// for why the same refusal is worth two different sentences.
    static func move(_ item: MenuBarItem, to section: MenuBarSection.Name, appState: AppState) {
        let experimentalSystemItemHiding = appState.settings.advanced.enableExperimentalSystemItemHiding
        guard MenuBarBackendProvider.current.canAssign(
            item,
            to: section,
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ) else {
            postAssignmentRefusal(
                for: item,
                to: section,
                experimentalSystemItemHiding: experimentalSystemItemHiding,
                appState: appState
            )
            return
        }

        let controller = appState.menuBarManager.sectionController
        let sourceSection = controller.section(for: item)
        guard sourceSection != section else {
            return
        }

        let groupMembers = crossSectionGroupMembers(for: item, in: sourceSection, appState: appState)
        let members = groupMembers ?? [item]

        // The user chose this from a menu, so it moves in Manual too.
        ExplicitLayoutEdit.task {
            // Seat the weights in the destination band before the assertion
            // flips, or MenuBarAgent republishes the item on its old side of
            // the divider and the boundary repair drags it back seconds later.
            // See MenuBarItemManager.seatItemsForSectionTransition(_:to:commit:).
            await appState.itemManager.seatItemsForSectionTransition(members, to: section) {
                if let groupMembers {
                    // A group is indivisible, so one blocked member blocks all of
                    // them and the batch has to say so rather than half-apply.
                    if let refusal = appState.menuBarManager.setSection(
                        section,
                        items: groupMembers,
                        atomically: true
                    ) {
                        let sourceItems = appState.itemManager.managedItems(for: sourceSection)
                        appState.layoutFeedback.post(
                            LayoutBarFeedbackCenter.blockedGroupMove(
                                groupName: groupDisplayName(for: groupMembers, in: sourceItems, appState: appState),
                                section: section,
                                refusal: refusal
                            )
                        )
                        return
                    }
                } else {
                    // No setSectionOrder to go with it: a drop carries a position
                    // and this does not, so the item takes whatever place the
                    // destination's stored order gives it.
                    controller.setSection(section, item: item)
                }
            }

            await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
        }
    }

    /// Assigns several ungrouped items to section in one pass, for the
    /// Layout pane's suggestions. Items the section cannot take are skipped
    /// rather than refused one by one: a suggestion never offers them.
    static func move(_ items: [MenuBarItem], to section: MenuBarSection.Name, appState: AppState) {
        let experimentalSystemItemHiding = appState.settings.advanced.enableExperimentalSystemItemHiding
        let assignable = items.filter {
            MenuBarBackendProvider.current.canAssign($0, to: section, experimentalSystemItemHiding: experimentalSystemItemHiding)
        }
        guard !assignable.isEmpty else { return }
        ExplicitLayoutEdit.task {
            // Seated before the assertion flips, as for a single move.
            await appState.itemManager.seatItemsForSectionTransition(assignable, to: section) {
                _ = appState.menuBarManager.setSection(section, items: assignable)
            }
            await appState.itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
        }
    }

    /// Opens the pane the item's placement is edited in.
    static func openSettings(appState: AppState) {
        SettingsSearchNavigation.selectSidebarPane(.menuBarLayout, navigationState: appState.navigationState)
        appState.activate(withPolicy: .regular)
        appState.openWindow(.settings)
    }

    // MARK: Menu construction

    /// The section's name as a menu title. MenuBarSectionName.localized is
    /// a LocalizedStringKey for SwiftUI's benefit and an NSMenuItem needs a
    /// String, so the three keys are spelled again. They are the same keys,
    /// so the two surfaces still share one catalog entry each.
    static func title(for name: MenuBarSection.Name) -> String {
        switch name {
        case .visible: String(localized: "Visible")
        case .hidden: String(localized: "Hidden")
        case .alwaysHidden: String(localized: "Always Hidden")
        }
    }

    // MARK: Move policy

    /// Explains a refused move rather than letting it fail in silence.
    ///
    /// Asking the same question again with system item hiding switched on
    /// separates the two cases exactly: if the move would then be allowed, the
    /// refusal is a setting the user owns and the message names it. If it would
    /// be refused either way, the message says the item stays put instead of
    /// sending someone to a switch that would not have helped. The wording is
    /// the layout editor's, from LayoutBarFeedbackCenter.
    private static func postAssignmentRefusal(
        for item: MenuBarItem,
        to section: MenuBarSection.Name,
        experimentalSystemItemHiding: Bool,
        appState: AppState
    ) {
        let wouldBeAllowedWithSystemItemHiding = !experimentalSystemItemHiding
            && MenuBarBackendProvider.current.canAssign(
                item,
                to: section,
                experimentalSystemItemHiding: true
            )

        appState.layoutFeedback.post(
            wouldBeAllowedWithSystemItemHiding
                ? LayoutBarFeedbackCenter.systemItemHidingDisabled(
                    itemName: item.displayName,
                    section: section
                )
                : LayoutBarFeedbackCenter.itemCannotMove(
                    itemName: item.displayName,
                    section: section
                )
        )
    }

    /// The items that travel with item across a section boundary, or nil
    /// when it belongs to no group.
    ///
    /// "One section per group": the whole group moves together even when its
    /// members are not currently adjacent. Resolution goes through the shared
    /// resolver over display order, the same sequence the layout editor
    /// resolves against.
    private static func crossSectionGroupMembers(
        for item: MenuBarItem,
        in sourceSection: MenuBarSection.Name,
        appState: AppState
    ) -> [MenuBarItem]? {
        let sourceItems = displayOrderedItems(in: sourceSection, appState: appState)
        guard let group = appState.itemGroupManager.resolvedGroup(containing: item, in: sourceItems),
              group.count >= 2
        else {
            return nil
        }
        return group.memberIndices.compactMap { sourceItems.indices.contains($0) ? sourceItems[$0] : nil }
    }

    /// A user-facing name for the group these members belong to, for use in
    /// refusal copy.
    private static func groupDisplayName(
        for members: [MenuBarItem],
        in sourceItems: [MenuBarItem],
        appState: AppState
    ) -> String {
        guard let first = members.first,
              let group = appState.itemGroupManager.resolvedGroup(containing: first, in: sourceItems)
        else {
            return members.first?.displayName ?? ""
        }
        return appState.itemGroupManager.displayName(for: group, in: sourceItems)
    }

    private static func displayOrderedItems(
        in section: MenuBarSection.Name,
        appState: AppState
    ) -> [MenuBarItem] {
        let managed = appState.itemManager.managedItems(for: section)
        return appState.menuBarManager.sectionController.displayOrdered(managed, in: section)
    }
}
