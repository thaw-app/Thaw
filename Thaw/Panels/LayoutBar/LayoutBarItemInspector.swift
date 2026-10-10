//
//  LayoutBarItemInspector.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit
import SwiftUI
import ThawUI

// MARK: - LayoutBarItemInspector

/// The item view holds the real icon's spotlight while the inspector is open, even after hover exit.
/// Properties live here; neighbor-affecting actions and group editing live in LayoutBarItemMenu.
struct LayoutBarItemInspector: View {
    private enum Metrics {
        static let width: CGFloat = 268
        static let glyphHeight: CGFloat = 22
        static let maxGlyphWidth: CGFloat = 96
    }

    /// Snapshot captured on open; the container freezes view updates while the popover is up.
    let item: MenuBarItem

    /// The section whose bar the item was clicked in.
    let section: MenuBarSection.Name

    /// Shared with LayoutBarItemMenu so position and group lookups agree.
    let orderedItems: [MenuBarItem]

    let appState: AppState

    /// Open the full item menu rather than flattening its submenus into this popover.
    let onShowAllActions: () -> Void

    /// Commit on submit and dismissal so clicking away does not lose a rename.
    @State private var draftName: String

    /// MenuBarItemAlertReveals has no observable projection; keep a local copy and write through.
    @State private var revealsOnIconChange: Bool

    @FocusState private var isNameFocused: Bool

    init(
        item: MenuBarItem,
        section: MenuBarSection.Name,
        orderedItems: [MenuBarItem],
        appState: AppState,
        onShowAllActions: @escaping () -> Void
    ) {
        self.item = item
        self.section = section
        self.orderedItems = orderedItems
        self.appState = appState
        self.onShowAllActions = onShowAllActions
        _draftName = State(initialValue: item.customName ?? "")
        _revealsOnIconChange = State(
            initialValue: MenuBarItemAlertReveals.contains(item.tag.tagIdentifier)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.inset) {
            header
            Divider()
            nameField
            Divider()
            facts
            Divider()
            actions
        }
        .padding(14)
        .frame(width: Metrics.width)
        .onDisappear(perform: commitName)
    }

    // MARK: Header

    /// Match LayoutBarItemView's captured glyph and app-icon fallback.
    private var header: some View {
        HStack(spacing: 9) {
            if let glyph = glyphImage {
                // Already sized in points; resizable would lose the ideal size and stretch across the popover.
                Image(nsImage: glyph)
                    .frame(height: Metrics.glyphHeight)
            } else {
                Image(systemName: "menubar.rectangle")
                    .foregroundStyle(.secondary)
                    .frame(height: Metrics.glyphHeight)
            }

            VStack(alignment: .leading, spacing: 1) {
                // Memoize process resolution because rename keystrokes re-evaluate this body.
                Text(MenuBarItemDisplayName.displayName(for: item))
                    .font(ThawType.heading)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let owner = ownerName {
                    Text(owner)
                        .font(ThawType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Rename

    /// Share MenuBarItem.customName with search rename; its windowID-free keys survive restarts.
    /// MenuBarItemDisplayName reads custom names each call, so no cache invalidation is needed.
    private var nameField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Name")
                .font(ThawType.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: ThawSpacing.compact) {
                TextField(item.autoDetectedName, text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit(commitName)

                Button {
                    draftName = ""
                    commitName()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .padding(ThawSpacing.tight)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .thawRowHover(in: Circle())
                .disabled(item.customName == nil && draftName.isEmpty)
                .help("Restore the name macOS reports for this item")
                .accessibilityLabel("Restore the name macOS reports for this item")
            }
        }
        .onAppear {
            // Focus the name field so renaming needs only a glyph click, typing, and Return.
            isNameFocused = true
        }
    }

    // MARK: Facts

    /// Show section, position, and width on the item; the strip alone cannot expose these layout costs.
    private var facts: some View {
        VStack(alignment: .leading, spacing: 5) {
            fact("Section", section.displayString)
            if let position {
                fact("Position", "\(position) of \(orderedItems.count)")
            }
            fact("Width", "\(Int(item.bounds.width.rounded())) pt")
            if RuntimeModuleController.isGovernable(itemIdentifier: item.uniqueIdentifier) {
                // Warn before changing the System Settings toggle, the only way macOS lets these modules hide.
                Text("Hiding this turns off its switch in System Settings \(Constants.menuArrow) Menu Bar. \(Constants.displayName) turns it back on when you move it to Visible or quit.")
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ThawSpacing.tight)
            }
        }
    }

    private func fact(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: ThawSpacing.base) {
            Text(label)
                .font(ThawType.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(ThawType.metric)
        }
    }

    // MARK: Actions

    /// Share the menu's alert-reveal setter; other actions remain in the full menu.
    private var actions: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.base) {
            Toggle("Reveal when its icon changes", isOn: $revealsOnIconChange)
                .font(ThawType.body)
                .onChange(of: revealsOnIconChange) { _, isOn in
                    MenuBarItemAlertReveals.setEnabled(isOn, for: item.tag.tagIdentifier)
                }

            Divider()

            // Offset hover padding to keep the title aligned with the toggle.
            Button(action: onShowAllActions) {
                Text("All Actions…")
                    .padding(.horizontal, ThawSpacing.tight)
                    .padding(.vertical, ThawSpacing.hairline)
                    .contentShape(RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous))
            }
            .thawRowHover()
            .padding(.horizontal, -ThawSpacing.tight)
            .help("Show grouping and other actions for this item.")
        }
        .buttonStyle(.plain)
        .font(ThawType.body)
    }

    // MARK: Derived values

    /// Captures already have point sizes; fit large app-icon fallbacks to header height before rendering.
    private var glyphImage: NSImage? {
        if let capture = appState.imageCache.image(for: item.tag) {
            let size = CGSize(
                width: min(capture.pointSize.width, Metrics.maxGlyphWidth),
                height: capture.pointSize.height
            )
            return NSImage(cgImage: capture.cgImage, size: size)
        }
        guard let icon = OverflowFallbackIcon.preferredImage(for: item, appState: appState) else {
            return nil
        }
        let fitted = icon.copy() as? NSImage ?? icon
        fitted.size = CGSize(width: Metrics.glyphHeight, height: Metrics.glyphHeight)
        return fitted
    }

    /// Share launcher subtitles, suppressing owner names that repeat the item name.
    private var ownerName: String? {
        MenuBarItemDisplayName.subtitle(for: item)
    }

    private var position: Int? {
        orderedItems.firstIndex { $0.tag == item.tag }.map { $0 + 1 }
    }

    private func commitName() {
        var item = item
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        // Empty or whitespace-only names remove the entry, matching the revert button.
        guard item.customName != (trimmed.isEmpty ? nil : trimmed) else {
            return
        }
        item.customName = trimmed.isEmpty ? nil : trimmed
    }
}
