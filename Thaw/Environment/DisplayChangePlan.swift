//
//  DisplayChangePlan.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// One step of the work a settled display change runs.
nonisolated enum DisplayChangeStep: Equatable, Sendable {
    /// Tells the repair orchestrator the displays changed, so the passes planned on the old arrangement are called off.
    case stampDisplayChanged
    /// Starts the item manager's settling period, which holds back the saved-layout restore until the bar settles.
    case startSettle(reason: String)
    /// Waits for that settling period to end.
    case awaitSettle
    /// Rebuilds the item cache, and after a removed display drops the stale images and captures again.
    case refreshCaches(cleansImages: Bool)
}

/// Which steps each kind of settled display change runs, in order.
nonisolated enum DisplayChangePlan {
    /// The steps for one change. An unchanged settle runs none.
    static func steps(for change: EnvironmentChange) -> [DisplayChangeStep] {
        guard let reason = settlingReason(for: change) else { return [] }
        return [
            .stampDisplayChanged,
            .startSettle(reason: reason),
            .awaitSettle,
            .refreshCaches(cleansImages: change == .displayRemoved),
        ]
    }

    /// The reason the settling period logs. A resolution change keeps the reason a rearrangement has,
    /// because the arrangement check this replaced counted a new size as a rearrangement.
    static func settlingReason(for change: EnvironmentChange) -> String? {
        switch change {
        case .displayAdded: "displayConnect"
        case .displayRemoved: "displayDisconnect"
        case .rearranged, .resolutionOnly: "displayArrangement"
        case .none: nil
        }
    }
}
