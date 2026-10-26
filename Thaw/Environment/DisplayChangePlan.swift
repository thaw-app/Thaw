//
//  DisplayChangePlan.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

nonisolated enum DisplayChangeStep: Equatable, Sendable {
    /// Tells the repair orchestrator the displays changed, so the passes planned on the old arrangement are called off.
    case stampDisplayChanged
    /// Records the connected displays, seeding a new display's configuration without relaunching apps.
    case seedConfigurations
    /// Starts the item manager's settling period, which holds back the saved-layout restore until the bar settles.
    case startSettle(reason: String)
    /// Applies the profile the new arrangement asks for, if that differs from the active one.
    case resolveProfile
    /// Writes the active display's spacing when the display that owns the menu bar changed.
    case applySpacing
    case awaitSettle
    /// Reveals or hides what always-show and the presentation state ask for on the settled bar.
    case applyPresentationPolicy
    /// Drops the images captured on a removed display and captures again.
    case cleanImages
    /// Captures the item images once, on the settled bar.
    case recaptureImages
}

nonisolated enum DisplayChangePlan {
    /// An unchanged settle runs none. The presentation and the recapture wait for the settled bar, and only a
    /// removed display cleans its stale images before the recapture.
    static func steps(for change: EnvironmentChange) -> [DisplayChangeStep] {
        guard let reason = settlingReason(for: change) else { return [] }
        let beforeSettle: [DisplayChangeStep] = [
            .stampDisplayChanged, .seedConfigurations, .startSettle(reason: reason), .resolveProfile, .applySpacing,
            .awaitSettle, .applyPresentationPolicy,
        ]
        return beforeSettle + (change == .displayRemoved ? [.cleanImages, .recaptureImages] : [.recaptureImages])
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
