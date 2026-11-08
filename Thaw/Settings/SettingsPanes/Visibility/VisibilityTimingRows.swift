//
//  VisibilityTimingRows.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// How long the pointer rests before hovering shows hidden items. Only while hover is on.
struct HoverDelayRow: View {
    @Bindable var settings: VisibilitySettings

    var body: some View {
        if settings.showOnHover {
            SecondsSliderRow("Hover delay", value: $settings.showOnHoverDelay, in: 0 ... 5, step: 0.1)
                .settingsSearchAnchor("visibility.showOnHoverDelay")
                .annotation("How long the pointer rests on the menu bar before hidden items show.")
        }
    }
}

/// How long the pointer rests on an item before its name shows. Only while names are on.
struct TooltipDelayRow: View {
    @Bindable var settings: VisibilitySettings

    var body: some View {
        if settings.showMenuBarTooltips {
            SecondsSliderRow("Name delay", value: $settings.tooltipDelay, in: 0 ... 5, step: 0.1)
                .settingsSearchAnchor("visibility.tooltipDelay")
                .annotation("How long the pointer rests on an item before its name shows.")
        }
    }
}

/// Any delay from 1 second to 5 minutes, beyond the menu's five. Only for a timed choice.
struct RehideDelayRow: View {
    @Bindable var settings: VisibilitySettings

    var body: some View {
        if settings.autoRehide, settings.rehideStrategy == .timed {
            SecondsSliderRow("Hide after", value: $settings.rehideInterval, in: 1 ... 300, step: 1)
        }
    }
}

/// A plain click on the icon swaps instead of revealing.
struct SwapOnIconClickToggle: View {
    @Bindable var settings: VisibilitySettings

    var body: some View {
        Toggle("Click the \(Constants.displayName) icon to swap", isOn: $settings.swapOnThawIconClick)
            .settingsSearchAnchor("visibility.swapOnThawIconClick")
            .annotation("A click on the icon swaps your shown and hidden items instead of showing the hidden ones.")
    }
}
