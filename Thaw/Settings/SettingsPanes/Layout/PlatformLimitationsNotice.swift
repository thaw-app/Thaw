//
//  PlatformLimitationsNotice.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The Layout pane's standing note about what macOS 27 does not let Thaw do.
/// Opens on the first visit and leaves only its info button behind.
struct PlatformLimitationsNotice: View {
    /// Whether the user has already dismissed the open presentation. The
    /// caller persists it; the notice holds only its popover state.
    let isAcknowledged: Bool
    let onAcknowledge: () -> Void

    @State private var isShowingList = false

    var body: some View {
        if isAcknowledged {
            infoRow
        } else {
            firstVisitSection
        }
    }

    /// The card the pane opens with, once. The list is too long for a pill,
    /// so it takes a section of its own.
    private var firstVisitSection: some View {
        ThawSection {
            PlatformLimitationsList()

            HStack {
                Button("Got it") {
                    onAcknowledge()
                }
                .buttonStyle(.settingsGlass)
                Spacer()
            }
        }
    }

    /// What is left after the dismissal: the same list behind the info
    /// button, for anyone who needs to check it again.
    private var infoRow: some View {
        ThawSection(isBordered: false) {
            HStack {
                Button {
                    isShowingList = true
                } label: {
                    Label("Known macOS 27 limitations", systemImage: "info.circle")
                }
                .buttonStyle(.plain)
                .help("What macOS 27 does not let \(Constants.displayName) do yet")
                .popover(isPresented: $isShowingList, arrowEdge: .bottom) {
                    PlatformLimitationsList()
                        .frame(width: 420)
                        .padding(ThawSpacing.gutter)
                }
                Spacer()
            }
        }
    }
}

/// The list itself, shared by the first-visit card and the later popover.
private struct PlatformLimitationsList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.row) {
            VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                Label("Warning", systemImage: "exclamationmark.triangle.fill")
                    .font(ThawType.caption)
                    .foregroundStyle(.orange)
                Text("Known macOS 27 limitations")
                    .font(ThawType.heading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            limitation("**Several items from one app:** some apps’ menu bar items cannot be hidden independently with the current macOS 27 mechanism. An item assigned to Hidden can remain visible when another item from the same app is assigned to Visible. To hide them, put all of that app’s items in the same section.")

            limitation("**Apps that need their own update:** macOS 27 changed how menu bar items are published, and an app built against the older behavior can sit in the wrong place, refuse to hide, or show no icon. f.lux behaves this way today. The fix has to come from the app's own developer; \(Constants.displayName) cannot correct it from the outside. Check for an update to that app.")
        }
        .font(ThawType.body)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// One labeled line. The label is bolded through the string's own
    /// markdown so the whole line stays a single translatable unit.
    private func limitation(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.base) {
            Text("•")
                .foregroundStyle(ThawInk.supporting)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
