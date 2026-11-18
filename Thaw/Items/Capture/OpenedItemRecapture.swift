//
//  OpenedItemRecapture.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Takes a new picture of a hidden item opened from the Thaw Bar once its menu closes.
///
/// A hidden item's picture is otherwise only taken when it is missing, so an icon that
/// changed while hidden, such as one showing an update, kept its old picture until every
/// picture was retaken. Opening an item shows it in the menu bar for "Keep opened items in
/// the menu bar for", but while its menu is open the item is drawn highlighted. So this
/// waits until the item's app has no menu open, takes the picture, and tries again when a
/// menu opened during the try. When the item is hidden again first, or its menu stays open
/// past menuWaitLimit, the picture is left as it was.
@MainActor
final class OpenedItemRecapture {
    /// What one try at the picture found.
    enum Attempt: Equatable {
        /// The picture was taken and kept.
        case stored
        /// A menu of the item's app was open during the try, so the item may have been highlighted.
        case menuOpened
        /// The item wasn't shown any more, or no picture could be taken or kept.
        case missed
    }

    /// How a retake ended.
    enum Outcome: Equatable {
        /// The picture was taken and kept.
        case stored
        /// No picture was taken; the old one stays.
        case missed
        /// A newer retake of the same item replaced this one.
        case cancelled
    }

    /// What a retake reads and does. Tests script these.
    struct Steps {
        /// Whether a menu of the item's app is open.
        var isMenuOpen: @MainActor () async -> Bool
        /// One try at taking and keeping the picture.
        var attempt: @MainActor () async -> Attempt
        var sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
        var now: @MainActor () -> ContinuousClock.Instant = { .now }
    }

    /// The retakes the Thaw Bar starts.
    static let shared = OpenedItemRecapture()

    /// Time for the item's menu to appear after the press, so the first check doesn't miss it.
    static let menuAppearanceDelay = Duration.milliseconds(500)

    /// How often to check whether the menu has closed.
    static let pollInterval = Duration.milliseconds(250)

    /// The longest wait for the menu to close before giving up on the picture.
    static let menuWaitLimit = Duration.seconds(60)

    static nonisolated let diagLog = DiagLog(category: "OpenedItemRecapture")

    /// The retake running for each item, by tag identifier.
    private var running: [String: Task<Outcome, Never>] = [:]

    /// Starts retaking the picture of the item with identifier, replacing a retake of it
    /// that is still waiting.
    func start(_ identifier: String, steps: Steps) {
        running[identifier]?.cancel()
        running[identifier] = Task {
            let outcome = await Self.run(steps)
            Self.diagLog.debug("retake of \(identifier) ended: \(outcome)")
            return outcome
        }
    }

    /// Waits for the item's menu to close, then takes its picture.
    @discardableResult
    static func run(_ steps: Steps) async -> Outcome {
        await steps.sleep(menuAppearanceDelay)
        let deadline = steps.now().advanced(by: menuWaitLimit)
        while !Task.isCancelled, steps.now() < deadline {
            if await steps.isMenuOpen() {
                await steps.sleep(pollInterval)
                continue
            }
            switch await steps.attempt() {
            case .stored:
                return .stored
            case .menuOpened:
                await steps.sleep(pollInterval)
            case .missed:
                return Task.isCancelled ? .cancelled : .missed
            }
        }
        return Task.isCancelled ? .cancelled : .missed
    }
}
