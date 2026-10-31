//
//  ThawUIWords.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI
import TipKit

// ThawUI holds no text of its own. These supply Thaw's words to its controls
// once, as literals here in the app, so Xcode extracts them into Thaw's catalog
// and call sites don't repeat them.

extension ThawBadge {
    /// A tag for a feature still in alpha.
    static var alpha: ThawBadge {
        .alpha("ALPHA")
    }

    /// A tag for a feature still in beta.
    static var beta: ThawBadge {
        .beta("BETA")
    }
}

extension ToggleStyle where Self == ThawCheckboxToggleStyle {
    /// The shared checkbox, with Thaw's names for its state.
    static var thawCheckbox: ThawCheckboxToggleStyle {
        .thawCheckbox(onValue: "On", offValue: "Off")
    }
}

extension ThawFirstRunHint {
    init(
        systemImage: String,
        _ text: LocalizedStringResource,
        actionTitle: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.init(systemImage: systemImage, text, dismissLabel: "Dismiss hint", actionTitle: actionTitle, action: action, onDismiss: onDismiss)
    }
}

extension ThawHintTipViewStyle {
    init() {
        self.init(dismissLabel: "Dismiss hint")
    }
}

extension View {
    /// An alert over a failure's message; OK clears the binding.
    func errorAlert(_ title: LocalizedStringResource, message: Binding<String?>, role: ButtonRole? = nil) -> some View {
        errorAlert(title, message: message, okLabel: "OK", role: role)
    }

    /// An alert in the error's own words; OK clears the binding.
    func errorAlert(_ error: Binding<(some LocalizedError)?>) -> some View {
        errorAlert(error, okLabel: "OK")
    }

    /// A caption, with the rest of the explanation behind an info button.
    func annotation(
        _ titleKey: LocalizedStringResource,
        more: LocalizedStringResource,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .annotationDefaultSpacing,
        font: Font? = .subheadline
    ) -> some View {
        annotation(titleKey, more: more, moreLabel: "More about this setting", alignment: alignment, spacing: spacing, font: font)
    }
}

extension SectionedList {
    init(selection: Binding<ItemID?>, items: Binding<[SectionedListItem<ItemID, ItemContent>]>, isEditing: Bool = false) {
        self.init(selection: selection, items: items, openLabel: "Open", isEditing: isEditing)
    }
}

extension AppUIZoomStrings {
    static let thaw = AppUIZoomStrings(
        zoomIn: "Zoom In",
        zoomOut: "Zoom Out",
        actualSize: "Actual Size",
        level: { "Zoom: \($0)%" }
    )
}

extension ThawGradientPickerStrings {
    static let thaw = ThawGradientPickerStrings(
        addStop: "Add a color stop",
        spaceStopsEvenly: "Space color stops evenly",
        stopName: { "Color stop \($0)" }
    )
}

extension ThawGradientPicker {
    init(_ labelKey: LocalizedStringResource, gradient: Binding<ThawGradient>, supportsOpacity: Bool = true) {
        self.init(labelKey, gradient: gradient, strings: .thaw, supportsOpacity: supportsOpacity)
    }
}

// MARK: - Thaw's identity

extension ThawAppInfo {
    /// Thaw 3's name, version and links, for the shared pages and the release notes.
    static let thaw = ThawAppInfo(
        displayName: Constants.displayName,
        version: Constants.versionString,
        changelogURL: Constants.changelogURL,
        releasesURL: Constants.releasesURL,
        shownMajorVersion: 3,
        showsChannels: true
    )
}

// MARK: - HUD

nonisolated extension ThawHUDPlacement {
    /// The picker's label for this case.
    var localized: LocalizedStringResource {
        switch self {
        case .leading: "Top left"
        case .center: "Top center"
        case .trailing: "Top right"
        }
    }
}
