//
//  ProfileLayoutKeeper.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// Saves layout changes into the active profile when it keeps them, so the
/// next switch to it brings them back instead of the layout it was saved with.
@MainActor
final class ProfileLayoutKeeper {
    /// Long enough for a drag's section to be read and its moves to land.
    static let settleDelay: Duration = .seconds(3)

    private static let diagLog = DiagLog(category: "ProfileLayoutKeeper")

    private let delay: Duration
    /// The active profile when it keeps changes and no profile is being
    /// applied, otherwise nil.
    private let target: @MainActor () -> UUID?
    private let save: @MainActor (UUID) throws -> Void
    private let sleep: @MainActor (Duration) async throws -> Void
    private var pending: Task<Void, Never>?

    init(
        delay: Duration = ProfileLayoutKeeper.settleDelay,
        target: @escaping @MainActor () -> UUID?,
        save: @escaping @MainActor (UUID) throws -> Void,
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.delay = delay
        self.target = target
        self.save = save
        self.sleep = sleep
    }

    /// The keeper for the app's profiles and live layout.
    convenience init(profileManager: ProfileManager, itemManager: MenuBarItemManager, groupManager: MenuBarItemGroupManager) {
        self.init(
            target: { [weak profileManager] in
                guard let profileManager, profileManager.layoutTask == nil,
                      let id = profileManager.activeProfileID,
                      profileManager.profiles.first(where: { $0.id == id })?.keepsLayoutChanges == true
                else { return nil }
                return id
            },
            save: { [weak profileManager, weak itemManager, weak groupManager] id in
                guard let profileManager, let itemManager else { return }
                try profileManager.updateProfileLayout(id: id, itemManager: itemManager, groups: groupManager?.snapshot())
            }
        )
    }

    /// Saves once the bar has settled after the user's last layout change.
    /// A switch to another profile in the meantime drops the save.
    func noteUserLayoutChange() {
        guard let id = target() else { return }
        pending?.cancel()
        pending = Task { [weak self, delay, sleep] in
            try? await sleep(delay)
            guard let self, !Task.isCancelled, target() == id else { return }
            pending = nil
            do {
                try save(id)
                Self.diagLog.info("saved layout changes into profile \(id.uuidString)")
            } catch {
                Self.diagLog.error("couldn't save layout changes into profile \(id.uuidString): \(error.localizedDescription)")
            }
        }
    }
}
