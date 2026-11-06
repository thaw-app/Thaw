//
//  HiddenAppsRestoreOffer.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Observation

/// When to ask about apps that are switched off in System Settings with no
/// record of who did it.
nonisolated enum HiddenAppsRestoreOfferRule {
    /// The offer is made once, and never over another sheet, during a drag in
    /// the menu bar, or while the record of hidden apps can't be read.
    static func shouldOffer(
        candidates: [String],
        alreadyAnswered: Bool,
        journalNeedsAttention: Bool,
        isAnotherSheetShowing: Bool,
        isDraggingMenuBarItem: Bool
    ) -> Bool {
        !candidates.isEmpty && !alreadyAnswered && !journalNeedsAttention
            && !isAnotherSheetShowing && !isDraggingMenuBarItem
    }
}

/// Offers to show apps an older version of Thaw may have switched off.
///
/// Those versions could leave an app switched off in System Settings with no
/// record, which looks exactly like an app the user switched off, so the user
/// picks which ones to show and nothing is selected for them.
@MainActor
@Observable
final class HiddenAppsRestoreOffer {
    struct Environment {
        /// Switched-off apps with no record, empty when they can't be read.
        var findCandidates: () -> [String]
        /// Switches the given apps on and returns the ones that changed.
        var showApps: (Set<String>) throws -> [String]
        var isAnswered: () -> Bool
        var markAnswered: () -> Void
    }

    private(set) var candidates: [String] = []
    var selectedBundleIDs: Set<String> = []
    var isPresented = false
    private(set) var errorMessage: String?
    @ObservationIgnored private let environment: Environment

    init(environment: Environment) {
        self.environment = environment
    }

    /// Reads the candidates while they still have no record. Native hiding
    /// takes over a switched-off app it hides, so this runs before it starts.
    func captureCandidates() {
        guard !environment.isAnswered() else { return }
        candidates = environment.findCandidates()
    }

    func presentIfDue(journalNeedsAttention: Bool, isAnotherSheetShowing: Bool, isDraggingMenuBarItem: Bool) {
        guard !isPresented, HiddenAppsRestoreOfferRule.shouldOffer(
            candidates: candidates,
            alreadyAnswered: environment.isAnswered(),
            journalNeedsAttention: journalNeedsAttention,
            isAnotherSheetShowing: isAnotherSheetShowing,
            isDraggingMenuBarItem: isDraggingMenuBarItem
        ) else { return }
        selectedBundleIDs = []
        errorMessage = nil
        isPresented = true
    }

    /// Setting an unreadable record aside leaves the apps it listed switched
    /// off with no record, so the user is asked again even after an earlier answer.
    func offerAfterSettingRecordAside() {
        candidates = environment.findCandidates()
        selectedBundleIDs = []
        errorMessage = nil
        isPresented = !candidates.isEmpty
    }

    func showSelected() {
        guard !selectedBundleIDs.isEmpty else { return }
        do {
            _ = try environment.showApps(selectedBundleIDs)
            finish()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func keepHidden() {
        finish()
    }

    private func finish() {
        environment.markAnswered()
        candidates = []
        selectedBundleIDs = []
        errorMessage = nil
        isPresented = false
    }
}
