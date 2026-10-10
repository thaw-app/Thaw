//
//  LayoutBar.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

struct LayoutBar: View {
    private struct Representable: NSViewRepresentable {
        let appState: AppState
        let section: MenuBarSection.Name

        func makeNSView(context _: Context) -> LayoutBarScrollView {
            LayoutBarScrollView(appState: appState, section: section)
        }

        func updateNSView(_: LayoutBarScrollView, context _: Context) {
            // LayoutBarScrollView observes shared state itself; this hook needs no updates.
        }
    }

    /// Whether the bar draws its own surface.
    enum Chrome {
        /// Self-contained sampled-color card with a hairline and shadow, used in the full Layout pane.
        case card
        /// Host-supplied surface lets FoldedMenuBar stack scrolling bars in one container.
        case bare
    }

    @Environment(AppState.self) var appState
    let imageCache: MenuBarItemImageCache

    let section: MenuBarSection.Name
    var chrome: Chrome = .card

    private var backgroundShape: some InsettableShape {
        RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous)
    }

    var body: some View {
        switch chrome {
        case .card: card
        case .bare: bare
        }
    }

    private var bare: some View {
        mainContent
            .frame(height: 48)
            .frame(maxWidth: .infinity)
    }

    private var card: some View {
        bare
            .menuBarItemContainer(appState: appState)
            .containerShape(backgroundShape)
            .clipShape(backgroundShape)
            .contentShape([.interaction, .focusEffect], backgroundShape)
            .overlay {
                backgroundShape
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
            }
            // Match ThawGlass card depth without glass material over the sampled menu bar color.
            .thawShadow(.raised)
    }

    private var mainContent: some View {
        // Concealed items may lack captures; keep placeholders draggable rather than hiding the interactive bar.
        Representable(appState: appState, section: section)
    }
}
