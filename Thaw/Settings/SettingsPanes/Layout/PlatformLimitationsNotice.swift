//
//  PlatformLimitationsNotice.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// What macOS 27 does not let Thaw do, behind an info button in the Hiding section,
/// next to the choice it mostly bears on.
struct PlatformLimitationsNotice: View {
    @State private var isShowingList = false

    var body: some View {
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

/// The list the info button opens.
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

            limitation("**Apple’s own items:** with the Standard hiding method, macOS hides Focus, AirDrop, Now Playing, Fast User Switching, Live Activities and the camera indicator whenever any other item is hidden, and never hides Time Machine or the Input menu. Choose the Native hiding method to keep them on the menu bar, or turn on Replace Control Center items in the Apple’s Items tab to put \(Constants.displayName) icons in their place, which you can move and hide.")
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
