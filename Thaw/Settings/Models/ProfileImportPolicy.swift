//
//  ProfileImportPolicy.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// What an imported profile may bring with it. A file can come from anyone, so it
/// can't switch on anything that runs code or acts without asking.
nonisolated enum ProfileImportPolicy {
    /// The most profiles one file may hold.
    static let maxEntries = 100

    enum ImportError: LocalizedError, Equatable {
        case tooManyProfiles(Int)

        var errorDescription: String? {
            switch self {
            case let .tooManyProfiles(count):
                String(localized: "The file holds \(count) profiles; at most \(ProfileImportPolicy.maxEntries) can be imported at once.")
            }
        }
    }

    /// Refuses a file before any of it is written.
    static func validate(_ bundle: ProfileExportBundle) throws {
        guard bundle.entries.count <= maxEntries else {
            throw ImportError.tooManyProfiles(bundle.entries.count)
        }
    }

    /// The content with its hooks switched off, relaunch confirmation on, and its
    /// gradients cut to what Thaw draws.
    static func sanitized(_ content: ProfileContent) -> ProfileContent {
        var content = content
        content.automation?.preHook?.isEnabled = false
        content.automation?.postHook?.isEnabled = false
        content.confirmSpacingRelaunch = true

        var appearance = content.appearanceConfiguration
        capGradients(in: &appearance.lightModeConfiguration)
        capGradients(in: &appearance.darkModeConfiguration)
        capGradients(in: &appearance.staticConfiguration)
        capStops(of: &appearance.thawBarAppearance.tintGradient)
        content.appearanceConfiguration = appearance
        return content
    }

    private static func capGradients(in configuration: inout MenuBarAppearancePartialConfiguration) {
        capStops(of: &configuration.tintGradient)
        capStops(of: &configuration.backgroundGradient)
    }

    private static func capStops(of gradient: inout IceGradient) {
        gradient.stops = sampled(gradient.stops, cap: IceGradient.maxImportedStops)
    }

    /// At most cap elements picked evenly across the whole array, keeping the first and
    /// the last, so a capped gradient still spans the colors it had.
    static func sampled<Element>(_ elements: [Element], cap: Int) -> [Element] {
        let count = elements.count
        guard count > cap else { return elements }
        guard cap > 1 else { return Array(elements.prefix(cap)) }
        return (0 ..< cap).map { index in
            let position = Double(index * (count - 1)) / Double(cap - 1)
            return elements[Int(position.rounded())]
        }
    }
}
