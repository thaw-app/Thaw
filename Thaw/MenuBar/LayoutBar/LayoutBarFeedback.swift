//
//  LayoutBarFeedback.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Foundation
import MenuBarModel

/// Publishes transient, user-facing explanations for layout actions the app
/// refused to perform.
///
/// Deliberately not an `NSAlert`. A modal sheet in response to a direct
/// manipulation gesture is disproportionate, and it covers the very layout bar
/// the user needs to look at. The drop still snaps back, and the pane shows a
/// dismissible warning pill alongside it — matching how the pane already
/// surfaces "hiding unavailable".
@MainActor
final class LayoutBarFeedbackCenter: ObservableObject {
    nonisolated struct Refusal: Identifiable, Equatable, Sendable {
        let id = UUID()
        let title: String
        let message: String

        static func == (lhs: Refusal, rhs: Refusal) -> Bool {
            lhs.id == rhs.id
        }
    }

    @Published private(set) var refusal: Refusal?

    /// How long a refusal stays on screen before clearing itself. Long enough to
    /// read a sentence, short enough that a stale message never explains an
    /// action the user has since forgotten about.
    private static let lifetime: Duration = .seconds(8)

    private var clearTask: Task<Void, Never>?

    func post(_ refusal: Refusal) {
        self.refusal = refusal
        // VoiceOver users never see the pill appear, so announce it. Mirrors
        // `LayoutResetControls`, which announces its inline status the same way.
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "\(refusal.title). \(refusal.message)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.lifetime)
            guard !Task.isCancelled else { return }
            self?.refusal = nil
        }
    }

    func clear() {
        clearTask?.cancel()
        clearTask = nil
        refusal = nil
    }

    // MARK: Message builders

    /// A whole-group move that could not be applied to every member.
    ///
    /// Names the blocking app, and states the consequence plainly — "no items
    /// were moved" — because the visible result is a snap-back that otherwise
    /// reads as the app ignoring the drag.
    static nonisolated func blockedGroupMove(
        groupName: String,
        section: MenuBarSection.Name,
        refusal: GroupMoveRefusal
    ) -> Refusal {
        Refusal(
            title: String(
                localized: "“\(groupName)” couldn’t move to \(section.displayString)",
                comment: "Title shown when a whole-group move was refused"
            ),
            message: String(
                localized: "\(refusal.localizedReason) Groups always move together, so no items were moved.",
                comment: "Explanation shown when a whole-group move was refused"
            )
        )
    }

    /// A group reorder whose physical AX moves did not settle.
    ///
    /// The model is canonical either way; what the user sees is a cluster that
    /// did not finish regrouping, which is worth saying rather than only logging.
    static nonisolated func groupRegatherIncomplete(groupName: String, section: MenuBarSection.Name) -> Refusal {
        Refusal(
            title: String(
                localized: "“\(groupName)” didn’t finish regrouping",
                comment: "Title shown when a group reorder did not converge"
            ),
            message: String(
                localized: "macOS didn’t apply every move in \(section.displayString). The group’s saved order is correct and Thaw will retry.",
                comment: "Explanation shown when a group reorder did not converge"
            )
        )
    }
}
