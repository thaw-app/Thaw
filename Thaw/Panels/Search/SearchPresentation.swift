//
//  SearchPresentation.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// MARK: - SearchPresentation

/// Which face MenuBarSearchPanel is wearing, and therefore how the search
/// panel opens.
///
/// There is one search panel and one shortcut; this is the user's choice of
/// how it arrives: where they last dragged it, centered like Spotlight, or
/// under the pointer in large type.
///
/// The properties below are the whole contract between the three. Behaviour
/// not listed here is shared and follows inspector, which is the default.
///
/// The raw values are storage, not display: they are written to
/// UserDefaults under Defaults.Key.menuBarSearchPresentation and must
/// not be renamed. localized is what the picker shows.
nonisolated enum SearchPresentation: String, CaseIterable, Identifiable {
    /// Opens where the user left it: the full inventory by section, inline
    /// rename, per-display frame memory, an action bar along the bottom, and
    /// a spotlight that follows the selection into the real menu bar.
    case inspector

    /// Opens centered, Spotlight-fashion, listing recents until the user
    /// types and then the ranked matches. No chrome, no memory, no editing.
    case launcher

    /// Opens at the pointer, listing the whole inventory in large type so
    /// items can be reached by scanning and clicking instead of by aiming at
    /// a twenty-pixel target in the top-right corner. Typing still filters,
    /// but reading, not typing, is the primary interaction.
    case assisted

    var id: String {
        rawValue
    }

    /// How the picker names this mode: where the panel appears, since that is
    /// the choice being made and the row sizes follow from it.
    var localized: LocalizedStringKey {
        switch self {
        case .inspector: "Where you left it"
        case .launcher: "Centered"
        case .assisted: "At the pointer"
        }
    }
}

// MARK: - Panel traits

extension SearchPresentation {
    /// Fixed size of the hosted content, and therefore of the panel.
    ///
    /// Both are fixed rather than resizable: the row list scrolls, and a
    /// resizable search panel is a window the user has to manage.
    var contentSize: CGSize {
        switch self {
        case .inspector: CGSize(width: 600, height: 400)
        case .launcher: CGSize(width: 620, height: 420)
        case .assisted: CGSize(width: 680, height: 560)
        }
    }

    /// Where the panel sits when it is shown.
    var placement: PanelPlacement {
        switch self {
        case .inspector: .remembered
        case .launcher: .centered
        case .assisted: .nearPointer
        }
    }

    /// Whether the panel remembers where it sat, per display.
    ///
    /// The inspector is dragged somewhere deliberate and expected to come back
    /// there. A launcher always opens in the same place, that is what makes it
    /// hittable without looking.
    var persistsFrame: Bool {
        switch self {
        case .inspector: true
        case .launcher, .assisted: false
        }
    }

    /// Whether the panel warms the item caches when it is shown.
    ///
    /// The inspector refreshes the image cache, because it renders a live
    /// preview of every row. The launcher
    /// deliberately rides on whatever the manager already has: it is on the
    /// hotkey path, and the refresh reaches code that can block.
    ///
    /// Stays keyed to the mode now that the mode is a preference. Choosing a
    /// launcher is choosing an instant open, and warming the caches for it
    /// anyway would take that back.
    var warmsCachesOnShow: Bool {
        switch self {
        case .inspector: true
        case .launcher, .assisted: false
        }
    }

    /// Whether the model samples the color behind the menu bar.
    ///
    /// Only the inspector's rows preview an item over that color; sampling it
    /// for the launcher would be a screen capture per showing for nothing.
    var samplesMenuBarColor: Bool {
        switch self {
        case .inspector: true
        case .launcher, .assisted: false
        }
    }

    /// Whether the selection lights its item up in the real menu bar.
    var spotlightsSelection: Bool {
        switch self {
        case .inspector: true
        case .launcher, .assisted: false
        }
    }

    /// Whether ⌘E starts an inline rename of the highlighted row.
    var allowsRename: Bool {
        switch self {
        case .inspector: true
        case .launcher, .assisted: false
        }
    }

    /// Whether the highlighted row can be organised from here: moved between
    /// sections, put into a group, taken to the pane it is arranged in.
    ///
    /// Tied to the same face as the rename, and for the same reason. The
    /// launchers exist to open something and get out of the way, and an action
    /// that leaves the menu bar rearranged after the panel is gone belongs to
    /// the surface the user opened in order to look at their menu bar.
    var allowsItemManagement: Bool {
        switch self {
        case .inspector: true
        case .launcher, .assisted: false
        }
    }

    /// Whether the "Remember last search" toggle applies.
    ///
    /// The toggle lives in the inspector's action bar, and the launcher has no
    /// action bar. It also has no use for the setting: a launcher that reopens
    /// mid-word is one the user has to clear before it is usable.
    var honorsKeepSearchToggle: Bool {
        switch self {
        case .inspector: true
        case .launcher, .assisted: false
        }
    }

    /// How the presentation names itself in diagnostics, so one log category
    /// still says which surface a line came from.
    var logLabel: String {
        switch self {
        case .inspector: "search panel"
        case .launcher: "item palette"
        case .assisted: "assisted palette"
        }
    }
}

// MARK: - PanelPlacement

/// Where a panel face positions itself when shown.
nonisolated enum PanelPlacement {
    /// Wherever the user last dragged it, per display.
    case remembered
    /// Centered on the screen, biased slightly above center.
    case centered
    /// Anchored to the pointer's current position, clamped to the screen.
    case nearPointer
}

// MARK: - Query field metrics

extension SearchPresentation {
    /// Type sizes and insets for the query field.
    ///
    /// The field is one view in one place; only its proportions differ. The
    /// inspector's is a control sitting on the panel, capsule, glass, a
    /// trailing gap that keeps it from reading as a full-width bar. The
    /// launcher's is the panel's headline, so it runs edge to edge in a lighter,
    /// larger face.
    struct QueryFieldMetrics {
        /// Face the query itself is typed in.
        let font: Font

        /// Inset around the field's contents.
        let padding: EdgeInsets

        /// Whether a trailing Spacer follows the text field, which stops the
        /// field from claiming the full width of the row.
        let hasTrailingSpacer: Bool

        /// Whether the field is drawn as its own glass capsule, inset from the
        /// panel's edges, rather than sitting flush in the panel's surface.
        let isCapsule: Bool
    }

    var queryFieldMetrics: QueryFieldMetrics {
        switch self {
        case .inspector:
            QueryFieldMetrics(
                font: .title2,
                padding: EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14),
                hasTrailingSpacer: true,
                isCapsule: true
            )
        case .launcher:
            QueryFieldMetrics(
                font: .title.weight(.light),
                padding: EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18),
                hasTrailingSpacer: false,
                isCapsule: false
            )
        case .assisted:
            // Deliberately off the app's type scale: enlarged, Dynamic-Type-
            // aware text is the feature here. .title3 scales with the
            // user's "Larger Text" setting instead of pinning at a fixed
            // point size.
            QueryFieldMetrics(
                font: .title3.weight(.light),
                padding: EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18),
                hasTrailingSpacer: false,
                isCapsule: false
            )
        }
    }
}

// MARK: - Palette row metrics

extension SearchPresentation {
    /// Icon size, type sizes and insets for one item row in a launcher list.
    ///
    /// Both launcher faces draw the same row, app icon, display name, and the
    /// owning app's name underneath when it says something the item's name
    /// doesn't, and only its proportions differ. They differ on purpose: the
    /// assisted face exists so that seeing and hitting a row stop being the
    /// hard part, so its numbers are a deliberately larger set rather than the
    /// launcher's nudged up, and they are the reason that face is shipped at
    /// all.
    struct RowMetrics {
        /// Edge length of the owning app's icon.
        let iconLength: CGFloat

        /// Gap between the icon and the text column.
        let iconSpacing: CGFloat

        /// Gap between the display name and the owner name below it.
        let textSpacing: CGFloat

        /// Face the display name is set in.
        let nameFont: Font

        /// Lines the display name may wrap to before it truncates.
        let nameLineLimit: Int

        /// Face the owner name is set in.
        let ownerFont: Font

        /// Inset around the row's contents.
        let padding: EdgeInsets

        /// Floor under the row's height. Zero leaves the row sized by its
        /// contents.
        let minHeight: CGFloat

        /// Whether VoiceOver reads the row as one element rather than walking
        /// the icon, the display name and the owner name separately.
        let combinesAccessibilityChildren: Bool
    }

    /// The launcher row's proportions, or nil for the face that draws no
    /// such row.
    ///
    /// The inspector is absent rather than sized: its row carries a live
    /// preview of the item as the menu bar draws it and hosts the inline
    /// rename field, so it is a different view, not this one at other
    /// numbers.
    var rowMetrics: RowMetrics? {
        switch self {
        case .inspector:
            nil
        case .launcher:
            RowMetrics(
                iconLength: 24,
                iconSpacing: 10,
                textSpacing: 1,
                nameFont: ThawType.body,
                nameLineLimit: 1,
                ownerFont: ThawType.caption,
                padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8),
                minHeight: 0,
                combinesAccessibilityChildren: false
            )
        case .assisted:
            // Deliberately off the app's type scale, for the same reason as
            // the query field above: .title3 and .body keep scaling with
            // the user's "Larger Text" setting where the app's own faces pin
            // at a fixed point size, and the 44pt floor is the HIG's smallest
            // comfortable target rather than a visual decision. A second line
            // for the name follows from the larger face, it is the size that
            // makes long names wrap.
            RowMetrics(
                iconLength: 32,
                iconSpacing: 14,
                textSpacing: 2,
                nameFont: .title3,
                nameLineLimit: 2,
                ownerFont: .body,
                padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12),
                minHeight: 44,
                combinesAccessibilityChildren: true
            )
        }
    }
}
