//
//  LayoutItemEditor.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI

/// The Layout window's editor for the selected item, built from the bars' own actions.
struct LayoutItemEditor: View {
    @Environment(AppState.self) private var appState
    let selection: LayoutSelectionModel

    var body: some View {
        switch LayoutItemEditorContent.make(selectedIDs: selection.orderedItemIDs, itemCache: appState.itemManager.itemCache) {
        case .empty:
            ThawEmptyState(
                systemImage: "cursorarrow.click",
                title: "No item selected",
                caption: "Select an item in the list or the bars to edit it."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .single(item, section):
            ThawForm(readingWidth: .full) {
                LayoutSingleItemEditor(item: item, section: section, selection: selection)
            }
            // A fresh editor per item, so a draft name never carries over.
            .id(item.uniqueIdentifier)
        case let .several(count, section):
            ThawForm(readingWidth: .full) {
                ThawSection("\(count) items selected") {
                    LayoutSectionPicker(section: section, selection: selection, isLocked: false)
                }
            }
        }
    }
}

/// Visible, Hidden or Always Hidden for the selection, through the bars' move path.
struct LayoutSectionPicker: View {
    @Environment(AppState.self) private var appState
    let section: MenuBarSectionName?
    let selection: LayoutSelectionModel
    let isLocked: Bool

    var body: some View {
        let destinations = MenuBarSearchItemActions.moveDestinations(appState: appState).compactMap(\.self)
        ThawPicker("Section", selection: Binding(get: { section }, set: { target in
            guard let target, target != section else { return }
            LayoutItemVisibility.moveSelection(to: target, selection: selection, appState: appState)
        })) {
            ForEach(destinations, id: \.self) { name in
                Text(name.localizedName).tag(Optional(name))
            }
        }
        .disabled(isLocked)
    }
}

/// One item's name, icon, section, group, shortcut and app.
private struct LayoutSingleItemEditor: View {
    @Environment(AppState.self) private var appState
    let item: MenuBarItem
    let section: MenuBarSectionName
    let selection: LayoutSelectionModel

    /// Committed on Return and when the editor goes away, as in the bars' inspector.
    @State private var draftName: String
    /// MenuBarItemAlertReveals isn't observable, so keep a copy and write through.
    @State private var revealsOnIconChange: Bool

    init(item: MenuBarItem, section: MenuBarSectionName, selection: LayoutSelectionModel) {
        self.item = item
        self.section = section
        self.selection = selection
        _draftName = State(initialValue: item.customName ?? "")
        _revealsOnIconChange = State(initialValue: MenuBarItemAlertReveals.contains(item.tag.tagIdentifier))
    }

    var body: some View {
        let lock = LayoutItemVisibility.lockReason(
            for: item,
            in: section,
            experimentalSystemItemHiding: appState.settings.layout.enableExperimentalSystemItemHiding
        )
        ThawSection("Name and icon") {
            LabeledContent("Name") {
                TextField("Name", text: $draftName, prompt: Text(item.autoDetectedName))
                    .labelsHidden()
                    .onSubmit(commitName)
            }
            LabeledContent("Icon") {
                Button("Choose…") { ItemIconPicker.present(for: item, appState: appState) }
            }
        }
        ThawSection("Section and group") {
            LayoutSectionPicker(section: section, selection: selection, isLocked: lock != nil)
                .help(lock ?? "")
            LayoutItemGroupRow(item: item, section: section)
        }
        ThawSection("Shortcut and behavior") {
            LabeledContent("Shortcut") {
                if let hotkey = appState.menuBarManager.itemHotkeys[item.uniqueIdentifier] {
                    HotkeyRecorder(hotkey: hotkey) { EmptyView() }
                } else {
                    Text("Available while its app runs")
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Show when its icon changes", isOn: $revealsOnIconChange)
                .onChange(of: revealsOnIconChange) { _, isOn in
                    MenuBarItemAlertReveals.setEnabled(isOn, for: item.tag.tagIdentifier)
                }
        }
        LayoutItemAppSection(details: LayoutItemAppDetails(item: item))
            .onDisappear(perform: commitName)
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        LayoutEditUndo.rename(item, to: trimmed.isEmpty ? nil : trimmed, undoManager: appState.layoutUndo)
    }
}

/// The item's group, with the bars' group menu to change it.
private struct LayoutItemGroupRow: View {
    @Environment(AppState.self) private var appState
    let item: MenuBarItem
    let section: MenuBarSectionName

    var body: some View {
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let ordered = LayoutDisplayedItems.items(in: section, appState: appState, runningApplications: running)
        let manager = appState.itemGroupManager
        let group = LayoutBarItemMenu.group(of: item, in: manager.resolvedGroups(for: ordered), orderedItems: ordered)
        LabeledContent("Group") {
            HStack(spacing: ThawSpacing.base) {
                Text(group.map { manager.displayName(for: $0, in: ordered) } ?? String(localized: "None"))
                    .foregroundStyle(.secondary)
                LayoutMenuButton(title: String(localized: "Edit")) {
                    LayoutBarItemMenu.groupMenu(for: item, section: section, orderedItems: ordered, appState: appState)
                }
                .fixedSize()
            }
        }
    }
}

/// The owning app: its name, whether it runs, and where to find it.
private struct LayoutItemAppSection: View {
    let details: LayoutItemAppDetails

    var body: some View {
        ThawSection("App") {
            if details.isPartOfMacOS {
                LabeledContent("App", value: String(localized: "Part of macOS"))
            } else {
                LabeledContent {
                    Text(details.isRunning ? "Running" : "Not running")
                        .foregroundStyle(.secondary)
                } label: {
                    Label {
                        Text(verbatim: details.name ?? String(localized: "Unknown app"))
                    } icon: {
                        if let url = details.url {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                    }
                }
                if let url = details.url {
                    ThawActionGroup {
                        Button("Open App") {
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                        }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    .buttonStyle(.thawGrouped)
                }
            }
        }
    }
}

/// A push button that opens an NSMenu, since SwiftUI can't host the bars' menus.
struct LayoutMenuButton: NSViewRepresentable {
    let title: String
    let makeMenu: @MainActor () -> NSMenu?

    func makeNSView(context _: Context) -> MenuButton {
        let button = MenuButton(title: title, target: nil, action: nil)
        button.bezelStyle = .push
        button.controlSize = .small
        button.target = button
        button.action = #selector(MenuButton.openMenu)
        button.makeMenu = makeMenu
        return button
    }

    func updateNSView(_ button: MenuButton, context _: Context) {
        button.title = title
        button.makeMenu = makeMenu
    }

    final class MenuButton: NSButton {
        var makeMenu: (@MainActor () -> NSMenu?)?

        @objc func openMenu() {
            guard let menu = makeMenu?() else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY + 4), in: self)
        }
    }
}
