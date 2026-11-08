//
//  LayoutDashboardView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// The Layout window: a toolbar, the section bars and the refusal notice.
/// The bars keep their item menu, inspector, keyboard moves and multi-select.
struct LayoutDashboardView: View {
    let appState: AppState
    let model: LayoutDashboardModel

    var body: some View {
        VStack(spacing: 0) {
            LayoutDashboardToolbar(model: model)
            Divider()
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
            ScrollView([.horizontal, .vertical]) {
                FoldedMenuBar(itemManager: appState.itemManager, arrangement: .spaced)
                    .padding(ThawSpacing.gutter)
            }
            // The bars always show the live bar, so away from the target they only show it.
            .disabled(!model.pin.isEditable)
            .opacity(model.pin.isEditable ? 1 : 0.5)
            LayoutRefusalNotice()
                .padding(.horizontal, ThawSpacing.inset)
                .padding(.bottom, ThawSpacing.base)
        }
        .frame(minWidth: 640, minHeight: 360)
        .environment(appState)
    }
}

/// The window toolbar: target, filter, capture and undo.
private struct LayoutDashboardToolbar: View {
    let model: LayoutDashboardModel

    var body: some View {
        HStack(spacing: ThawSpacing.row) {
            VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                Text(LayoutDashboardText.title(profileName: model.profileName))
                    .font(ThawType.body.weight(.semibold))
                Text(LayoutDashboardText.target(model.pin.pinned))
                    .font(ThawType.caption)
                    .foregroundStyle(ThawInk.supporting)
            }
            .accessibilityElement(children: .combine)

            Menu {
                Button("Edit the Menu Bar You're On") { model.retargetToCurrent() }
                    .disabled(model.pin.isEditable)
            } label: {
                Label("Target", systemImage: "scope")
            }
            .fixedSize()
            .help("The display and Space this window edits.")

            Spacer(minLength: ThawSpacing.row)

            // A home for the item list's filter, which arrives with the list.
            TextField("Filter", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .disabled(true)

            HiddenItemCaptureButton()

            ThawActionGroup {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo.undo() }
                    .help(model.undo.undoTitle)
                    .disabled(!model.undo.canUndo)
                Button("Redo", systemImage: "arrow.uturn.forward") { model.undo.redo() }
                    .help(model.undo.redoTitle)
                    .disabled(!model.undo.canRedo)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.thawGrouped)
            .disabled(!model.pin.isEditable)
        }
        .padding(.horizontal, ThawSpacing.inset)
        .padding(.vertical, ThawSpacing.base)
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
