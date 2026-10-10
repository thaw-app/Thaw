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

    private let context: Context
    private let extraControls: () -> ExtraControls

    init(
        alwaysShowHiddenItems: Binding<Bool>,
        useThawBar: Binding<Bool>,
        location: Binding<ThawBarLocation>,
        layout: Binding<ThawBarLayout>,
        gridColumns: Binding<Int>,
        context: Context,
        @ViewBuilder extraControls: @escaping () -> ExtraControls
    ) {
        _alwaysShowHiddenItems = alwaysShowHiddenItems
        _useThawBar = useThawBar
        _location = location
        _layout = layout
        _gridColumns = gridColumns
        self.context = context
        self.extraControls = extraControls
    }

    var body: some View {
        Toggle("Use \(Constants.displayName) Bar", isOn: $useThawBar)
            .annotation("Show hidden menu bar items in a separate bar below the menu bar.")

        Toggle("Always show hidden items", isOn: $alwaysShowHiddenItems)
            .disabled(useThawBar)
            .annotation {
                if useThawBar {
                    switch context {
                    case .display:
                        Text("Not available because the \(Constants.displayName) Bar is enabled for this display.")
                    case .globalTemplate:
                        Text("Not available because the \(Constants.displayName) Bar is enabled in the global template.")
                    }
                } else {
                    switch context {
                    case .display:
                        Text("Always show hidden menu bar items in the menu bar on this display.")
                    case .globalTemplate:
                        Text("Always show hidden menu bar items in the menu bar.")
                    }
                }
            }

        extraControls()

        if useThawBar {
            ThawPicker("Location", selection: $location) {
                ForEach(ThawBarLocation.allCases) { location in
                    Text(location.localized).tag(location)
                }
            }
            .annotation { locationAnnotation }

            ThawPicker("Arrangement", selection: $layout) {
                ForEach(ThawBarLayout.allCases) { layout in
                    Text(layout.localized).tag(layout)
                }
            }
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
        }
    }

    @ViewBuilder
    private var locationAnnotation: some View {
        switch location {
        case .dynamic:
            Text("Below the pointer when it is in the menu bar, otherwise below the \(Constants.displayName) icon.")
        case .mousePointer:
            Text("The \(Constants.displayName) Bar is centered below the mouse pointer.")
        case .thawIcon:
            Text("The \(Constants.displayName) Bar is centered below the \(Constants.displayName) icon.")
        case .leftAligned:
            Text("The \(Constants.displayName) Bar is aligned to the left edge of the display.")
        case .rightAligned:
            Text("The \(Constants.displayName) Bar is aligned to the right edge of the display.")
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
        context: Context
    ) {
        self.init(
            alwaysShowHiddenItems: alwaysShowHiddenItems,
            useThawBar: useThawBar,
            location: location,
            layout: layout,
            gridColumns: gridColumns,
            context: context
        ) {
            EmptyView()
        }
    }
}
