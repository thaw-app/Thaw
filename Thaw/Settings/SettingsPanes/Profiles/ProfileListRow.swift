//
//  ProfileListRow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// One profile in the Profiles list, drawn like a sidebar row.
struct ProfileListRow<Actions: View>: View {
    let profile: ProfileMetadata
    let isSelected: Bool
    let showsFocus: Bool
    let isActive: Bool
    let isApplying: Bool
    let isEditing: Bool
    @Binding var editingName: String
    let select: () -> Void
    let apply: () -> Void
    let commitRename: () -> Void
    @ViewBuilder let actions: () -> Actions

    private static var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ThawRadius.row, style: .continuous)
    }

    var body: some View {
        HStack(spacing: ThawSpacing.inset) {
            if isEditing {
                TextField("Profile name", text: $editingName, onCommit: commitRename)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Button("Done", action: commitRename)
                    .buttonStyle(.settingsGlass)
            } else {
                Button(action: select) {
                    label
                }
                .buttonStyle(.plain)

                if isActive {
                    Text("Active")
                        .foregroundStyle(ThawInk.supporting)
                } else {
                    Button("Apply", action: apply)
                        .buttonStyle(.settingsGlass)
                        .disabled(isApplying)
                }

                MoreActionsMenu(label: "More profile actions", content: actions)
            }
        }
        .padding(.horizontal, ThawSpacing.row)
        .frame(minHeight: 36)
        .thawSelectedFill(isSelected, in: Self.rowShape)
        .contentShape(Self.rowShape)
        .thawSelectionCue(isSelected: isSelected, in: Self.rowShape)
        .thawFocusRing(isSelected && showsFocus, in: Self.rowShape)
    }

    private var label: some View {
        HStack(spacing: ThawSpacing.inset) {
            Text(profile.name)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Text(AutomationSummary.switches(of: profile))
                .foregroundStyle(ThawInk.supporting)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
