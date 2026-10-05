//
//  LayoutBarFeedback.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import MenuBarModel

/// Publishes transient, user-facing explanations for layout actions the app
/// refused to perform.
///
/// Deliberately not an NSAlert. A modal sheet in response to a direct
/// manipulation gesture is disproportionate, and it covers the very layout bar
/// the user needs to look at. The drop still snaps back, and the pane shows a
/// dismissible warning pill alongside it, matching how the pane already
/// surfaces "hiding unavailable".
@MainActor
@Observable
final class LayoutBarFeedbackCenter {
    nonisolated struct Refusal: Identifiable, Equatable, Sendable {
        let id = UUID()
        let title: String
        let message: String

        static func == (lhs: Refusal, rhs: Refusal) -> Bool {
            lhs.id == rhs.id
        }
    }

    private(set) var refusal: Refusal?

    /// How long a refusal stays on screen before clearing itself. Long enough to
    /// read a sentence, short enough that a stale message never explains an
    /// action the user has since forgotten about.
    private static let lifetime: Duration = .seconds(8)

    private var clearTask: Task<Void, Never>?

    func post(_ refusal: Refusal) {
        self.refusal = refusal
        // VoiceOver users never see the pill appear, so announce it. Mirrors
        // LayoutResetControls, which announces its inline status the same way.
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
    /// Names the blocking app, and states the consequence plainly, "no items
    /// were moved", because the visible result is a snap-back that otherwise
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

    /// A drag of one of Apple's own items, refused only because the switch that
    /// governs them is off.
    ///
    /// The switch sits below the editor where a user watching an item snap
    /// back will not find it, so the message names it and says where it is.
    /// The search panel posts this too, so the location is the full Settings
    /// path rather than "below".
    static nonisolated func systemItemHidingDisabled(
        itemName: String,
        section: MenuBarSection.Name
    ) -> Refusal {
        Refusal(
            title: String(
                localized: "“\(itemName)” couldn’t move to \(section.displayString)",
                comment: "Title shown when an Apple item was refused because system item hiding is off"
            ),
            message: String(
                localized: "It’s one of Apple’s own items, which macOS keeps in the menu bar unless \(Constants.displayName) asks it not to. Turn on “Allow hiding Apple’s own menu bar items” in Settings \(Constants.menuArrow) Layout to move it.",
                comment: "Explanation shown when an Apple item was refused because system item hiding is off"
            )
        )
    }

    /// A drag refused for a reason the user cannot change.
    ///
    /// Distinguished from systemItemHidingDisabled(itemName:section:) on
    /// purpose: pointing someone at a switch that would not have helped is
    /// worse than saying plainly that the item stays put.
    static nonisolated func itemCannotMove(
        itemName: String,
        section: MenuBarSection.Name
    ) -> Refusal {
        Refusal(
            title: String(
                localized: "“\(itemName)” couldn’t move to \(section.displayString)",
                comment: "Title shown when an item cannot be assigned to a section"
            ),
            message: String(
                localized: "macOS doesn’t allow this item to leave its place in the menu bar.",
                comment: "Explanation shown when an item cannot be assigned to a section"
            )
        )
    }

    /// A drag started on an item macOS does not let anything move.
    static nonisolated func itemNotMovable(itemName: String) -> Refusal {
        Refusal(
            title: String(
                localized: "“\(itemName)” can’t be moved",
                comment: "Title shown when a drag starts on an item macOS does not allow to move"
            ),
            message: String(
                localized: "macOS doesn’t allow this item to leave its place in the menu bar.",
                comment: "Explanation shown when an item cannot be assigned to a section"
            )
        )
    }

    /// A drag started on an item whose app is not responding.
    static nonisolated func ownerUnresponsive(itemName: String) -> Refusal {
        Refusal(
            title: String(
                localized: "“\(itemName)” can’t be moved",
                comment: "Title shown when a drag starts on an item macOS does not allow to move"
            ),
            message: String(
                localized: "Its app isn’t responding. Restart the app to move this item. Other items may not move reliably until then.",
                comment: "Explanation shown when a drag starts on an item whose app is hung"
            )
        )
    }

    /// A section change asked for from Thaw while arrangement mode is Manual.
    ///
    /// In Manual the bar decides membership: an item's section is the side of
    /// the dividers it sits on. Assigning it from here would leave it on the
    /// wrong side, hidden with one section and revealed in another.
    static nonisolated func manualSectionChange() -> Refusal {
        Refusal(
            title: String(
                localized: "Move it in the menu bar",
                comment: "Title shown when a section change is refused because arrangement mode is Manual"
            ),
            message: String(
                localized: "Item arrangement is set to Manual, so an item's section is the side of the dividers it sits on. ⌘-drag it past a divider in the menu bar, or switch to Automatic in Settings \(Constants.menuArrow) Layout.",
                comment: "Explanation shown when a section change is refused because arrangement mode is Manual"
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
                localized: "macOS didn’t apply every move in \(section.displayString). The group’s saved order is correct and \(Constants.displayName) will try again.",
                comment: "Explanation shown when a group reorder did not converge"
            )
        )
    }
}
