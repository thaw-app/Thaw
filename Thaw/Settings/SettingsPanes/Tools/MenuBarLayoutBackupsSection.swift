//
//  MenuBarLayoutBackupsSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import PlatformRuntimeKit
import SwiftUI
import ThawUI

/// The backup browser on Settings → Tools.
///
/// Restoring puts every file back itself rather than leaving the user with a
/// plist in Finder, and snapshots what it overwrites first, so it is not a
/// one-way door.
struct MenuBarLayoutBackupsSection: View {
    @Environment(AppState.self) private var appState

    /// Bumped by the pane when a reset writes a backup, so the list reloads
    /// without the section having to watch the folder.
    let refreshToken: Int

    @State private var backups: [MenuBarLayoutBackups.Backup] = []
    @State private var previewedBackup: MenuBarLayoutBackups.Backup?
    @State private var pendingRestore: MenuBarLayoutBackups.Backup?
    @State private var pendingDelete: MenuBarLayoutBackups.Backup?
    @State private var isWorking = false
    @State private var awaitsRelaunch = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        ThawSection {
            Text("Layout backups")
        } content: {
            if backups.isEmpty {
                Text("No backups yet. \(Constants.displayName) saves one before it resets saved item positions, and again before it restores one.")
                    .font(ThawType.detail)
                    .foregroundStyle(ThawInk.supporting)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(backups) { backup in
                    row(for: backup)
                        .contextMenu {
                            Button("Restore…") {
                                pendingRestore = backup
                            }
                            Divider()
                            Button("Delete…", role: .destructive) {
                                pendingDelete = backup
                            }
                        }
                }

                Button("Show Backups in Finder") {
                    NSWorkspace.shared.open(MenuBarLayoutBackups.directory())
                }
                .buttonStyle(.settingsGlass)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if awaitsRelaunch {
                SettingsWarningPill(
                    title: "Relaunch to finish",
                    message: "\(Constants.displayName) read the old positions at launch and does not re-read them while running.",
                    systemImage: "arrow.clockwise.circle.fill",
                    tint: .blue,
                    actionTitle: "Relaunch",
                    action: { appState.restartSelf() }
                )
            }

            if isLayoutTableUnreadable {
                SettingsWarningPill(
                    title: "Backups can't include macOS's saved menu bar layout",
                    message: "macOS keeps it in a protected folder, so a backup holds only the older preference files beside it. Grant Menu Bar Layout Access on the Privacy page to back up and restore the whole layout.",
                    systemImage: "lock.circle.fill",
                    tint: .orange
                )
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(ThawType.detail)
                    .foregroundStyle(ThawInk.supporting)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } footer: {
            Text("A backup holds macOS's saved menu bar layout and the per-Mac preference files a positions reset deletes. It does not hold \(Constants.displayName)'s own settings, profiles, or which section an item is in.")
        }
        .disabled(isWorking)
        .task(id: refreshToken) {
            backups = await MenuBarLayoutBackups.list()
        }
        .confirmationDialog(
            "Restore this layout backup?",
            item: $pendingRestore,
            titleVisibility: .visible
        ) { backup in
            Button("Restore") {
                Task { await restore(backup) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The saved positions in this backup replace the ones in use now. \(Constants.displayName) backs up the current positions first, so you can restore your way back. The menu bar restarts, and \(Constants.displayName) has to relaunch afterward.")
        }
        .confirmationDialog(
            "Delete this backup?",
            item: $pendingDelete,
            titleVisibility: .visible
        ) { backup in
            Button("Delete", role: .destructive) {
                Task { await delete(backup) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The saved positions in it are gone for good. This does not change your current menu bar.")
        }
        .errorAlert("Couldn’t restore backup", message: $errorMessage, role: .cancel)
    }

    // MARK: - Rows

    private func row(for backup: MenuBarLayoutBackups.Backup) -> some View {
        HStack(spacing: ThawSpacing.inset) {
            VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                HStack(spacing: ThawSpacing.compact) {
                    Text(backup.created.formatted(date: .abbreviated, time: .shortened))
                        .font(ThawType.body.weight(.semibold))
                    if !backup.includesLiveTable {
                        ThawBadge("Partial", tone: .tinted(.orange))
                            .help("This backup does not include macOS's current saved menu bar layout.")
                    }
                }
                Text(summary(for: backup))
                    .font(ThawType.metric)
                    .foregroundStyle(ThawInk.supporting)
            }

            Spacer()

            Button {
                previewedBackup = backup
            } label: {
                Image(systemName: "eye")
            }
            .buttonStyle(.settingsGlass)
            .help("Show the item positions this backup holds")
            .accessibilityLabel("Show the item positions this backup holds")
            .disabled(backup.entries.isEmpty)
            .popover(
                isPresented: Binding(
                    get: { previewedBackup == backup },
                    set: { isPresented in
                        if !isPresented {
                            previewedBackup = nil
                        }
                    }
                ),
                arrowEdge: .bottom
            ) {
                preview(for: backup)
            }

            Button("Restore…") {
                pendingRestore = backup
            }
            .buttonStyle(.settingsGlass)

            MoreActionsMenu(label: "More backup actions") {
                Button("Delete…", role: .destructive) {
                    pendingDelete = backup
                }
            }
        }
    }

    private func preview(for backup: MenuBarLayoutBackups.Backup) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                Text("Saved positions, in menu bar order")
                    .font(ThawType.caption.bold())
                ForEach(backup.entries) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(entry.weight)")
                            .font(ThawType.micro.monospaced())
                            .foregroundStyle(ThawInk.supporting)
                            .frame(width: 48, alignment: .trailing)
                        Text(entry.key)
                            .font(ThawType.micro.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ThawSpacing.inset)
        }
        .frame(width: 420, height: 320)
    }

    private func summary(for backup: MenuBarLayoutBackups.Backup) -> String {
        guard !backup.entries.isEmpty else {
            return String(localized: "No saved positions")
        }
        if backup.includesLiveTable {
            return String(localized: "\(backup.entries.count) saved positions")
        }
        return String(localized: "\(backup.entries.count) saved positions, from macOS's older preference file")
    }

    /// True when the host keeps its table somewhere this process may not read,
    /// which is what makes a capture come out partial.
    private var isLayoutTableUnreadable: Bool {
        RuntimePreferenceStore.positionsDomainAccess() == .denied
    }

    // MARK: - Actions

    private func restore(_ backup: MenuBarLayoutBackups.Backup) async {
        isWorking = true
        statusMessage = nil
        defer { isWorking = false }
        // Killing the host mid-move strands the move's events.
        await appState.itemManager.moveActivity.waitUntilIdle()

        do {
            let outcome = try await MaintenanceTools.restoreMenuBarLayout(from: backup)
            backups = await MenuBarLayoutBackups.list()

            if outcome.restored.isEmpty {
                awaitsRelaunch = false
                report(String(localized: "Nothing could be written back. Grant Menu Bar Layout Access on the Privacy page and try again."))
            } else if outcome.skipped.isEmpty {
                awaitsRelaunch = true
                report(String(localized: "Layout restored. The positions in use before this are saved as a new backup."))
            } else {
                awaitsRelaunch = true
                let total = outcome.restored.count + outcome.skipped.count
                report(
                    String(
                        localized: "Layout partly restored: \(outcome.skipped.count) of \(total) files could not be written. Grant Menu Bar Layout Access on the Privacy page to restore the rest."
                    )
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ backup: MenuBarLayoutBackups.Backup) async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await MenuBarLayoutBackups.delete(backup)
            backups = await MenuBarLayoutBackups.list()
            report(String(localized: "Backup deleted."))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func report(_ message: String) {
        statusMessage = message
        AccessibilityAnnouncements.post(message)
    }
}
