//
//  ThawControlWidgets.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

// Two Control Center controls for Thaw's most-reached-for menu bar actions.
//
// Both read isOn from the snapshot Thaw publishes into the
// A7CKWF99ML.com.stonerl.Thaw app group. See ControlCommandNames.swift for
// the channel and why its constants are duplicated across targets.

import AppIntents
import notify
import SwiftUI
import WidgetKit

// MARK: - Intents

/// Posts the "toggle hidden section" command at the running app.
///
/// ControlWidgetToggle requires a SetValueIntent, but value is ignored and a
/// toggle is posted: Thaw has no set verb. A stale snapshot may flip the wrong
/// way, but the app republishes within one round trip.
struct RevealHiddenItemsControlIntent: SetValueIntent {
    static nonisolated let title: LocalizedStringResource = "Reveal Hidden Items"

    static nonisolated let description = IntentDescription(
        "Show or hide the hidden section of Thaw's menu bar.",
        categoryName: "Menu Bar"
    )

    /// Hidden from Shortcuts; the app has ToggleHiddenSectionIntent for that.
    static nonisolated let isDiscoverable = false

    /// The state the toggle was moved to. Required by SetValueIntent; see
    /// the type's doc comment for why the posted command ignores it.
    @Parameter(title: "Revealed")
    var value: Bool

    func perform() async throws -> some IntentResult {
        notify_post(ControlCommandNames.toggleHidden)
        return .result()
    }
}

/// Posts the "toggle Zen Mode" command at the running app.
///
/// Same shape, and the same reasoning, as
/// RevealHiddenItemsControlIntent: SetValueIntent for the API's sake,
/// toggle verb on the wire, drift reconciled by the app's next publish.
struct ToggleZenModeControlIntent: SetValueIntent {
    static nonisolated let title: LocalizedStringResource = "Toggle Zen Mode"

    static nonisolated let description = IntentDescription(
        "Enter or leave Zen Mode, which hides the menu bar entirely.",
        categoryName: "Menu Bar"
    )

    static nonisolated let isDiscoverable = false

    /// The state the toggle was moved to. Unused for the same reason as
    /// above.
    @Parameter(title: "Active")
    var value: Bool

    func perform() async throws -> some IntentResult {
        notify_post(ControlCommandNames.toggleZen)
        return .result()
    }
}

// MARK: - Controls

/// Reveals or conceals the hidden section.
///
/// The snapshot is read when the system asks for a body; the app reloads the
/// control whenever it changes.
struct RevealHiddenItemsControl: ControlWidget {
    static nonisolated let kind = "com.stonerl.Thaw.controls.reveal-hidden"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            let isRevealed = ControlStateSnapshot.current().isHiddenSectionRevealed
            ControlWidgetToggle(
                isOn: isRevealed,
                action: RevealHiddenItemsControlIntent(),
                label: {
                    // The glyph is picked from the same snapshot that drives
                    // isOn, so the icon can never disagree with the switch.
                    Label(
                        "Reveal Hidden Items",
                        systemImage: isRevealed ? "eye" : "eye.slash"
                    )
                },
                valueLabel: { isOn in
                    // Names the drawn state so it reads at a glance in the bar.
                    Text(isOn ? "Shown" : "Hidden")
                }
            )
        }
        .displayName("Reveal Hidden Items")
        .description("Show or hide the hidden section of Thaw's menu bar.")
    }
}

/// Enters or leaves Zen Mode.
struct ToggleZenModeControl: ControlWidget {
    static nonisolated let kind = "com.stonerl.Thaw.controls.toggle-zen"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            let isActive = ControlStateSnapshot.current().isZenModeActive
            ControlWidgetToggle(
                isOn: isActive,
                action: ToggleZenModeControlIntent(),
                label: {
                    Label(
                        "Toggle Zen Mode",
                        systemImage: isActive ? "moon.zzz.fill" : "moon.zzz"
                    )
                },
                valueLabel: { isOn in
                    Text(isOn ? "On" : "Off")
                }
            )
        }
        .displayName("Toggle Zen Mode")
        .description("Enter or leave Zen Mode, which hides the menu bar entirely.")
    }
}
