//
//  DisplayChangePlan.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

nonisolated enum DisplayChangeStep: Equatable, Sendable {
    /// Tells the repair orchestrator the displays changed, so the passes planned on the old arrangement are called off.
    case stampDisplayChanged
    /// Starts the item manager's settling period, which holds back the saved-layout restore until the bar settles.
    case startSettle(reason: String)
    case awaitSettle
    /// Drops the images captured on a removed display and captures again.
    case cleanImages
}

nonisolated enum DisplayChangePlan {
    /// An unchanged settle runs none. Only a removed display waits out the settle, since only its image
    /// cleanup comes after it; another change would hold the run open for nothing.
    static func steps(for change: EnvironmentChange) -> [DisplayChangeStep] {
        guard let reason = settlingReason(for: change) else { return [] }
        let steps: [DisplayChangeStep] = [.stampDisplayChanged, .startSettle(reason: reason)]
        guard change == .displayRemoved else { return steps }
        return steps + [.awaitSettle, .cleanImages]
    }

    /// A resolution change logs as a rearrangement, as the arrangement check this replaced did.
    static func settlingReason(for change: EnvironmentChange) -> String? {
        switch change {
        case .displayAdded: "displayConnect"
        case .displayRemoved: "displayDisconnect"
        case .rearranged, .resolutionOnly: "displayArrangement"
        case .none: nil
        }
    }
}
