//
//  LayoutDashboardView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI

/// The Layout window: a toolbar, the section bars and the refusal notice.
/// The bars keep their item menu, inspector, keyboard moves and multi-select.
struct LayoutDashboardView: View {
    let appState: AppState
    let model: LayoutDashboardModel

    private var enabledSectionCount: Int {
        MenuBarSectionName.allCases.count { appState.menuBarManager.section(withName: $0)?.isEnabled == true }
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if case let .elsewhere(current) = model.pin.state {
                SettingsWarningPill(
                    title: "Not the menu bar you're editing",
                    message: "\(LayoutDashboardText.elsewhere(pinned: model.pin.pinned, current: current))",
                    systemImage: "rectangle.on.rectangle.slash",
                    actionTitle: "Edit This One",
                    action: { model.retargetToCurrent() }
                )
                .padding(ThawSpacing.inset)
            }
            // The bars across the window, sized to their sections; the list and the tabs take the rest.
            VStack(spacing: 0) {
                ThawForm(readingWidth: .full) {
                    LayoutBarsSection(itemManager: appState.itemManager, selection: model.selection, isInLayoutWindow: true)
                }
                .frame(height: LayoutDashboardMetrics.barsHeight(sections: enabledSectionCount))
                Divider()
                HSplitView {
                    LayoutItemListPane(selection: model.selection, query: $model.filterText)
                        .frame(minWidth: LayoutDashboardMetrics.listMinWidth, idealWidth: LayoutDashboardMetrics.listIdealWidth)
                    ThawForm(readingWidth: .full) {
                        LayoutDetailTabs(
                            itemManager: appState.itemManager,
                            canArrangeLayout: !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults,
                            isHidingUnavailable: false,
                            includesOptions: false
                        )
                    }
                    .frame(minWidth: LayoutDashboardMetrics.tabsMinWidth)
                }
            }
            // The bars always show the live bar, so away from the target they only show it.
            .disabled(!model.pin.isEditable)
            .opacity(model.pin.isEditable ? 1 : 0.5)
            LayoutRefusalNotice()
                .padding(.horizontal, ThawSpacing.inset)
                .padding(.bottom, ThawSpacing.base)
        }
        .frame(minWidth: LayoutDashboardMetrics.windowMinSize.width, minHeight: LayoutDashboardMetrics.windowMinSize.height)
        .navigationTitle("Layout")
        .navigationSubtitle(LayoutDashboardText.title(profileName: model.profileName))
        .toolbar { LayoutDashboardToolbar(model: model) }
        .environment(appState)
    }
}

/// The window toolbar: what it edits, then capture and undo.
private struct LayoutDashboardToolbar: ToolbarContent {
    let model: LayoutDashboardModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Menu {
                Button("Edit the Menu Bar You're On") { model.retargetToCurrent() }
                    .disabled(model.pin.isEditable)
            } label: {
                Label(LayoutDashboardText.target(model.pin.pinned), systemImage: "scope")
                    .labelStyle(.titleAndIcon)
            }
            .help("The display and Space this window edits.")
        }
        ToolbarItem(placement: .primaryAction) {
            HiddenItemCaptureButton()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Undo", systemImage: "arrow.uturn.backward") { model.undo.undo() }
                .help(model.undo.undoTitle)
                .disabled(!model.pin.isEditable || !model.undo.canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward") { model.undo.redo() }
                .help(model.undo.redoTitle)
                .disabled(!model.pin.isEditable || !model.undo.canRedo)
        }
    }
}

/// The window's text, kept apart so tests can read it.
enum LayoutDashboardText {
    static func title(profileName: String?) -> String {
        if let profileName {
            return String(localized: "Editing \(profileName)")
        }
        return String(localized: "Editing the current layout")
    }

    /// "Desktop 13, Studio Display", or the display alone before its Space is known.
    static func target(_ target: LayoutEditTarget) -> String {
        guard let spaceName = target.spaceName else {
            return target.displayName
        }
        return String(localized: "\(spaceName), \(target.displayName)", comment: "A Space and the display it is on.")
    }

    static func elsewhere(pinned: LayoutEditTarget, current: LayoutEditTarget) -> String {
        let here = place(current, comparedWith: pinned)
        let there = place(pinned, comparedWith: current)
        return String(localized: "You're on \(here). Switch back to \(there), or edit this one instead.")
    }

    /// The Space's name when the two differ by Space, otherwise the display's.
    private static func place(_ target: LayoutEditTarget, comparedWith other: LayoutEditTarget) -> String {
        if let name = target.spaceName, target.spaceKey != other.spaceKey {
            return name
        }
        return target.displayName
    }
}
