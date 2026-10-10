//
//  PermissionViews.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// MARK: - PermissionLabel

/// A permission's icon, name, and requirement badge.
///
/// Every surface that offers a permission names it the same way, down to the
/// badge wording. Only the type scale differs: onboarding sets its own so the
/// cards read as headings, while a settings row inherits the form's.
struct PermissionLabel: View {
    /// Where the requirement badge sits.
    enum BadgePlacement {
        /// Directly after the title, so the two read as one phrase.
        case adjacent
        /// At the trailing edge of the available width.
        case trailing
        /// On its own line under the title. The card layout uses this: a
        /// narrow column turns a trailing badge into a long gap between the
        /// name and the tag, and an adjacent one crowds a heading that
        /// already wraps.
        case below
    }

    let permission: Permission

    /// The title's font, or nil to inherit from the surrounding view.
    var titleFont: Font?

    var badgePlacement: BadgePlacement = .adjacent

    var body: some View {
        HStack(alignment: badgePlacement == .below ? .top : .center, spacing: 8) {
            Image(systemName: permission.iconName)
                .foregroundStyle(permission.iconColor)

            if badgePlacement == .below {
                VStack(alignment: .leading, spacing: 4) {
                    title
                    badge
                }
            } else {
                title

                if badgePlacement == .trailing {
                    Spacer()
                }

                badge
            }
        }
    }

    private var title: some View {
        Text(permission.title)
            .font(titleFont)
    }

    @ViewBuilder
    private var badge: some View {
        if !permission.isRequired {
            ThawBadge("Optional")
        }
    }
}

// MARK: - PermissionStatusControl

/// A permission's state and the one control that changes it.
///
/// Granted is deliberately not a disabled button. A control that cannot be
/// pressed still reads as something the user is meant to press, and the whole
/// point of this state is that there is nothing left to do.
struct PermissionStatusControl: View {
    /// How much room the control should take.
    enum Layout {
        /// Sits at the trailing edge of a settings row at the form's own scale.
        case inline
        /// Fills its container as a card's call to action.
        case filled
    }

    let permission: Permission
    var layout: Layout = .inline

    var body: some View {
        switch layout {
        case .inline:
            if permission.hasPermission {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button(requestTitle, action: request)
            }
        case .filled:
            if permission.hasPermission {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(ThawType.detail.weight(.medium))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            } else {
                Button(action: request) {
                    Text(requestTitle)
                        .font(ThawType.detail.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.glass)
            }
        }
    }

    /// After a declined prompt macOS will not ask again, so the control leads to System Settings.
    private var offersSettings: Bool {
        permission.wasDeclined && permission.hasSettingsPane
    }

    private var requestTitle: LocalizedStringKey {
        offersSettings ? "Open System Settings" : "Grant Access"
    }

    private func request() {
        if offersSettings {
            permission.openSettingsPane()
        } else {
            permission.performRequest()
        }
    }
}
