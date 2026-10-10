//
//  HiddenItemsSnippetIntents.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

// Use an interactive glyph snippet because names like "Item-3" do not identify menu bar items.
// Listing hidden items leaves the menu bar untouched; row buttons reveal them.

import AppIntents
import AppKit
import MenuBarModel
import SwiftUI

// MARK: - Row model

/// Resolve glyphs and names in the app, not in the re-evaluating snippet body.
/// Archived snippet views render outside the app and cannot access appState.imageCache.
struct HiddenMenuBarItemRow: Identifiable {
    /// MenuBarItem.uniqueIdentifier is the reveal key, stable across window-ID changes and app relaunches.
    let id: String
    /// The user's custom name if there is one, else the auto-detected one.
    let name: String
    /// The item as it draws in the bar, or its owner's app icon as a fallback.
    let glyph: Image?
    /// Point width of the glyph, so a wide item (a clock, a text status) is
    /// not squashed into an icon-sized box.
    let glyphWidth: CGFloat
}

// MARK: - Snippet view

/// System-rendered archived views cannot rely on Thaw's environment, materials, or ThawType fonts.
struct HiddenMenuBarItemsSnippetView: View {
    let rows: [HiddenMenuBarItemRow]
    /// Count beyond the capped list, which keeps the snippet glanceable.
    let overflowCount: Int
    /// Omit per-row buttons when the backend supports only whole-section reveal.
    let canRevealIndividually: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Hidden Menu Bar Items", systemImage: "menubar.dock.rectangle")
                .font(.headline)

            if rows.isEmpty {
                Text("Nothing is hidden right now.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows) { row in
                        itemRow(row)
                    }
                    if overflowCount > 0 {
                        Text("and \(overflowCount) more")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button(intent: RevealHiddenSectionIntent()) {
                    Label("Reveal All", systemImage: "eye")
                }
                Button(intent: ConcealHiddenSectionIntent()) {
                    Label("Hide", systemImage: "eye.slash")
                }
            }
            .font(.callout)
        }
        .padding(16)
        .frame(maxWidth: 360, alignment: .leading)
    }

    private func itemRow(_ row: HiddenMenuBarItemRow) -> some View {
        HStack(spacing: 10) {
            Group {
                if let glyph = row.glyph {
                    glyph
                } else {
                    // Match the search placeholder so missing captures and app icons do not collapse the row.
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: row.glyphWidth, height: Metrics.glyphHeight)

            Text(row.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            if canRevealIndividually {
                Button(intent: RevealMenuBarItemIntent(itemIdentifier: row.id)) {
                    Text("Show")
                }
                .font(.footnote)
            }
        }
    }

    private enum Metrics {
        /// The real bar's item height. Captures come out of the cache at bar
        /// scale, so matching it means no resampling.
        static let glyphHeight: CGFloat = 18
        /// Upper bound on a single glyph's drawn width. A status item that
        /// renders a long string would otherwise push the name off the row.
        static let maxGlyphWidth: CGFloat = 60
    }

    /// Clamps a capture's natural width into the row's budget.
    static func clampedGlyphWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, Metrics.glyphHeight), Metrics.maxGlyphWidth)
    }
}

// MARK: - The snippet itself

/// Presentation, button actions, and reloads rerun the snippet; only button intents mutate state.
/// Spotlight runs intents in the main app process, so AppState needs no XPC bridge.
struct HiddenMenuBarItemsSnippet: SnippetIntent {
    static nonisolated(unsafe) var title: LocalizedStringResource = "Hidden Menu Bar Items"

    /// Cap the card height; the count line covers remaining items.
    private static let rowLimit = 12

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        guard let appState = thawAppState() else {
            throw ThawIntentError.appNotReady
        }

        // Exclude chevrons, spacers, system clones, and transient Item-N entries from the user-facing count.
        let items = appState.itemManager
            .managedItems(for: .hidden)
            .filter(\.isUserActionable)

        let listed = items.prefix(Self.rowLimit)
        let rows = listed.map { item in
            HiddenMenuBarItemRow(
                id: item.uniqueIdentifier,
                name: MenuBarItemDisplayName.displayName(for: item),
                glyph: Self.glyph(for: item, appState: appState),
                glyphWidth: HiddenMenuBarItemsSnippetView.clampedGlyphWidth(
                    appState.imageCache.image(for: item.tag)?.pointSize.width ?? 18
                )
            )
        }

        return .result(
            view: HiddenMenuBarItemsSnippetView(
                rows: Array(rows),
                overflowCount: max(0, items.count - listed.count),
                canRevealIndividually: appState.menuBarManager.sectionController.isOperational
            )
        )
    }

    /// Prefer a capture, then the owner's app icon to identify concealed items that were never captured.
    @MainActor
    private static func glyph(for item: MenuBarItem, appState: AppState) -> Image? {
        if let capture = appState.imageCache.image(for: item.tag),
           let trimmed = capture.horizontallyTrimmedCGImage
        {
            return Image(decorative: trimmed, scale: capture.scale)
        }
        guard let icon = OverflowFallbackIcon.preferredImage(for: item, appState: appState) else {
            return nil
        }
        return Image(nsImage: icon)
            .resizable()
    }
}

// MARK: - Discoverable entry point

/// Asking what is hidden presents the snippet without changing the hidden section.
/// Only this intent is discoverable; button intents stay out of the Shortcuts action list.
struct ShowHiddenItemsIntent: AppIntent {
    static nonisolated(unsafe) var title: LocalizedStringResource = "Show Hidden Menu Bar Items"
    static nonisolated(unsafe) var description: IntentDescription? = IntentDescription(
        "List the menu bar items Thaw is currently hiding, and reveal any of them.",
        categoryName: "Menu Bar"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        .result(snippetIntent: HiddenMenuBarItemsSnippet())
    }
}

// MARK: - Snippet button actions

/// Uses the thaw://reveal-item path to reveal in place without a synthetic drag or whole-section flash, then conceal after a menu-aware delay.
/// Do not click: the menu could open behind Spotlight; this is also the macOS 27 Thaw Bar click fallback.
struct RevealMenuBarItemIntent: AppIntent {
    static nonisolated(unsafe) var title: LocalizedStringResource = "Reveal Menu Bar Item"
    /// Hidden from Shortcuts: its parameter is an opaque item identifier that
    /// only the snippet knows how to supply.
    static var isDiscoverable: Bool {
        false
    }

    @Parameter(title: "Item Identifier")
    var itemIdentifier: String

    init() {}

    init(itemIdentifier: String) {
        self.itemIdentifier = itemIdentifier
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appState = thawAppState() else {
            throw ThawIntentError.appNotReady
        }

        let controller = appState.menuBarManager.sectionController
        if controller.isOperational {
            controller.revealItemTemporarily(itemIdentifier)
            controller.scheduleTemporaryItemConceal(itemIdentifier)
        } else {
            // Fall back to whole-section reveal when per-item reveal is unavailable.
            appState.menuBarManager.section(withName: .hidden)?.show()
        }

        // Reveal makes the list stale; ask the system to rebuild the snippet.
        HiddenMenuBarItemsSnippet.reload()
        return .result()
    }
}

/// Reveals the whole hidden section, as the chevron does.
struct RevealHiddenSectionIntent: AppIntent {
    static nonisolated(unsafe) var title: LocalizedStringResource = "Reveal Hidden Menu Bar Section"
    static var isDiscoverable: Bool {
        false
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appState = thawAppState() else {
            throw ThawIntentError.appNotReady
        }
        guard let section = appState.menuBarManager.section(withName: .hidden) else {
            return .result()
        }
        section.show()
        // Explicit reveal must not disappear on the next pointer movement.
        appState.menuBarManager.showOnHoverAllowed = false
        HiddenMenuBarItemsSnippet.reload()
        return .result()
    }
}

struct ConcealHiddenSectionIntent: AppIntent {
    static nonisolated(unsafe) var title: LocalizedStringResource = "Hide Menu Bar Section"
    static var isDiscoverable: Bool {
        false
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appState = thawAppState() else {
            throw ThawIntentError.appNotReady
        }
        appState.menuBarManager.section(withName: .hidden)?.hide()
        HiddenMenuBarItemsSnippet.reload()
        return .result()
    }
}
