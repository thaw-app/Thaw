//
//  ThawBarConfigurationControls.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Share display and template controls; Context selects wording and ExtraControls supplies global-only toggles.
/// Internal access lets the pane's separate files use the same block.
struct ThawBarConfigurationControls<ExtraControls: View>: View {
    enum Context {
        case display
        case globalTemplate
    }

    @Binding var alwaysShowHiddenItems: Bool
    @Binding var useThawBar: Bool
    @Binding var location: ThawBarLocation
    @Binding var layout: ThawBarLayout
    @Binding var gridColumns: Int
    @Binding var itemScale: Double

    /// App-wide, so only the Thaw Bar page passes it; the template for new displays has no row for it.
    private let shortcutPlacement: Binding<ThawBarShortcutPlacement>?
    private let useThawBarForAlwaysHidden: Bool
    private let context: Context
    private let extraControls: () -> ExtraControls

    init(
        alwaysShowHiddenItems: Binding<Bool>,
        useThawBar: Binding<Bool>,
        location: Binding<ThawBarLocation>,
        layout: Binding<ThawBarLayout>,
        gridColumns: Binding<Int>,
        itemScale: Binding<Double>,
        shortcutPlacement: Binding<ThawBarShortcutPlacement>? = nil,
        useThawBarForAlwaysHidden: Bool = false,
        context: Context,
        @ViewBuilder extraControls: @escaping () -> ExtraControls
    ) {
        _alwaysShowHiddenItems = alwaysShowHiddenItems
        _useThawBar = useThawBar
        _location = location
        _layout = layout
        _gridColumns = gridColumns
        _itemScale = itemScale
        self.shortcutPlacement = shortcutPlacement
        self.useThawBarForAlwaysHidden = useThawBarForAlwaysHidden
        self.context = context
        self.extraControls = extraControls
    }

    var body: some View {
        Toggle("\(Constants.displayName) Bar", isOn: thawBarSwitch)
            .settingsSearchAnchor("displays.useThawBar")
            .annotation { thawBarAnnotation }

        Toggle("Always show hidden items", isOn: alwaysShowSwitch)
            .settingsSearchAnchor("displays.alwaysShowHiddenItems")
            .disabled(isAlwaysShowDisabled)
            .annotation { alwaysShowAnnotation }

        extraControls()

        if useThawBar || useThawBarForAlwaysHidden {
            ThawPicker("Location", selection: $location) {
                ForEach(ThawBarLocation.allCases) { location in
                    Text(location.localized).tag(location)
                }
            }
            .settingsSearchAnchor("displays.thawBarLocation")
            .annotation { locationAnnotation }

            if let shortcutPlacement {
                ThawPicker("When opened by a shortcut", selection: shortcutPlacement) {
                    ForEach(ThawBarShortcutPlacement.allCases) { placement in
                        Text(placement.localized).tag(placement)
                    }
                }
                .settingsSearchAnchor("general.thawBarLocationOnHotkey")
                .annotation { shortcutPlacementAnnotation(shortcutPlacement.wrappedValue) }
            }

            ThawPillPicker(
                "Arrangement",
                selection: $layout,
                options: ThawBarLayout.allCases.map { ThawPillPicker.Option($0, title: $0.localized, systemImage: $0.systemImage) }
            )
            .settingsSearchAnchor("displays.thawBarLayout")
            .annotation { layoutAnnotation }

            if layout == .grid {
                let gridColumnsDouble = Binding<Double>(
                    get: { Double(gridColumns) },
                    set: { gridColumns = Int($0) }
                )
                SliderRow("Columns", value: gridColumnsDouble, in: 2 ... 10, step: 1) { _ in
                    Text(verbatim: "\(gridColumns)")
                }
                .annotation("Maximum number of items per row in the grid arrangement.")
            }

            ThawBarItemSizeRow(scale: $itemScale)
                .settingsSearchAnchor("displays.thawBarItemSize")
        }
    }

    /// Turns the Thaw Bar on or off and leaves the always-show switch as it is.
    var thawBarSwitch: Binding<Bool> {
        $useThawBar
    }

    /// Keeps hidden items in the menu bar; the Thaw Bar overrides it while it is on.
    var alwaysShowSwitch: Binding<Bool> {
        $alwaysShowHiddenItems
    }

    /// The always-show switch has no effect while the Thaw Bar is on, so it is dimmed then.
    var isAlwaysShowDisabled: Bool {
        useThawBar
    }

    @ViewBuilder
    private var thawBarAnnotation: some View {
        switch context {
        case .display:
            Text("When on, hidden items appear in the \(Constants.displayName) Bar below the menu bar on this display.")
        case .globalTemplate:
            Text("When on, hidden items appear in the \(Constants.displayName) Bar below the menu bar on new displays.")
        }
    }

    @ViewBuilder
    private var alwaysShowAnnotation: some View {
        switch (isAlwaysShowDisabled, context) {
        case (true, _):
            Text("Has no effect while the \(Constants.displayName) Bar is on, because hidden items appear in it instead.")
        case (false, .display):
            Text("Hidden items stay in the menu bar on this display instead of waiting for you to reveal them.")
        case (false, .globalTemplate):
            Text("Hidden items stay in the menu bar on new displays instead of waiting for you to reveal them.")
        }
    }

    @ViewBuilder
    private var locationAnnotation: some View {
        switch location {
        case .dynamic:
            Text("If the pointer is on an empty part of the menu bar when the \(Constants.displayName) Bar opens, it opens under the pointer. Otherwise it opens under the \(Constants.displayName) icon, or at the right edge when the icon is hidden.")
        case .mousePointer:
            Text("Opens under the menu bar, centered on the pointer.")
        case .thawIcon:
            Text("Opens under the \(Constants.displayName) icon. When the icon is hidden, it opens at the right edge.")
        case .leftAligned:
            Text("Opens under the menu bar at the left edge of the display.")
        case .rightAligned:
            Text("Opens under the menu bar at the right edge of the display.")
        }
    }

    @ViewBuilder
    private func shortcutPlacementAnnotation(_ placement: ThawBarShortcutPlacement) -> some View {
        switch placement {
        case .location:
            Text("Keyboard shortcuts, the Shortcuts app and Control Center open the \(Constants.displayName) Bar where Location says. This applies on every display.")
        case .pointer:
            Text("Keyboard shortcuts, the Shortcuts app and Control Center open the \(Constants.displayName) Bar centered on the pointer, wherever it is on the screen. This applies on every display.")
        }
    }

    @ViewBuilder
    private var layoutAnnotation: some View {
        switch layout {
        case .horizontal:
            Text("Items are arranged in a single horizontal row.")
        case .vertical:
            Text("Items are stacked vertically in a single column.")
        case .grid:
            Text("Items are arranged in a grid with multiple columns.")
        }
    }
}

extension ThawBarConfigurationControls where ExtraControls == EmptyView {
    init(
        alwaysShowHiddenItems: Binding<Bool>,
        useThawBar: Binding<Bool>,
        location: Binding<ThawBarLocation>,
        layout: Binding<ThawBarLayout>,
        gridColumns: Binding<Int>,
        itemScale: Binding<Double>,
        shortcutPlacement: Binding<ThawBarShortcutPlacement>? = nil,
        useThawBarForAlwaysHidden: Bool = false,
        context: Context
    ) {
        self.init(
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            useThawBar: useThawBar,
            location: location,
            layout: layout,
            gridColumns: gridColumns,
            itemScale: itemScale,
            shortcutPlacement: shortcutPlacement,
            useThawBarForAlwaysHidden: useThawBarForAlwaysHidden,
            context: context
        ) {
            EmptyView()
        }
    }
}
