//
//  DisplaySettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct DisplaySettingsPane: View {
    @ObservedObject var displaySettings: DisplaySettingsManager

    @State private var maxSliderLabelWidth: CGFloat = 0
    /// Per-display draft of the spacing slider, keyed by display UUID.
    /// Until the user clicks Apply, dragging the slider only updates this
    /// dictionary — it does not touch the saved configuration or trigger
    /// any relaunches.
    @State private var draftSpacing: [String: CGFloat] = [:]

    var body: some View {
        IceForm {
            ForEach(displaySettings.allDisplays()) { display in
                IceSection {
                    displayRow(for: display)
                }
            }
        }
    }

    @ViewBuilder
    private func displayRow(for display: DisplaySettingsManager.DisplayInfo) -> some View {
        let useIceBar = Binding<Bool>(
            get: { displaySettings.configuration(forUUID: display.id).useIceBar },
            set: { newValue in
                displaySettings.updateConfiguration(forDisplayUUID: display.id) { config in
                    config.withUseIceBar(newValue)
                }
            }
        )

        let location = Binding<IceBarLocation>(
            get: { displaySettings.configuration(forUUID: display.id).iceBarLocation },
            set: { newValue in
                displaySettings.updateConfiguration(forDisplayUUID: display.id) { config in
                    config.withIceBarLocation(newValue)
                }
            }
        )

        let alwaysShowHiddenItems = Binding<Bool>(
            get: { displaySettings.configuration(forUUID: display.id).alwaysShowHiddenItems },
            set: { newValue in
                displaySettings.updateConfiguration(forDisplayUUID: display.id) { config in
                    config.withAlwaysShowHiddenItems(newValue)
                }
            }
        )

        let layout = Binding<IceBarLayout>(
            get: { displaySettings.configuration(forUUID: display.id).iceBarLayout },
            set: { newValue in
                displaySettings.updateConfiguration(forDisplayUUID: display.id) { config in
                    config.withIceBarLayout(newValue)
                }
            }
        )

        let gridColumns = Binding<Int>(
            get: { displaySettings.configuration(forUUID: display.id).gridColumns },
            set: { newValue in
                displaySettings.updateConfiguration(forDisplayUUID: display.id) { config in
                    config.withGridColumns(newValue)
                }
            }
        )

        HStack {
            Spacer()
            Text(display.name)
                .font(.headline)
            if display.hasNotch {
                Text("Notch")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            if !display.isConnected {
                Text("Disconnected")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }

        Toggle("Always show hidden items", isOn: alwaysShowHiddenItems)
            .disabled(useIceBar.wrappedValue)
            .annotation {
                if useIceBar.wrappedValue {
                    Text("Not available because the \(Constants.displayName) Bar is enabled for this display.")
                } else {
                    Text("Always show hidden menu bar items in the menu bar on this display.")
                }
            }

        Toggle("Use \(Constants.displayName) Bar", isOn: useIceBar)
            .annotation("Show hidden menu bar items in a separate bar below the menu bar on this display.")

        if useIceBar.wrappedValue {
            IcePicker("Location", selection: location) {
                ForEach(IceBarLocation.allCases) { loc in
                    Text(loc.localized).tag(loc)
                }
            }
            .annotation {
                switch location.wrappedValue {
                case .dynamic:
                    Text("The \(Constants.displayName) Bar's location changes based on context.")
                case .mousePointer:
                    Text("The \(Constants.displayName) Bar is centered below the mouse pointer.")
                case .iceIcon:
                    Text("The \(Constants.displayName) Bar is centered below the \(Constants.displayName) icon.")
                case .leftAligned:
                    Text("The \(Constants.displayName) Bar is aligned to the left edge of the display.")
                case .rightAligned:
                    Text("The \(Constants.displayName) Bar is aligned to the right edge of the display.")
                }
            }

            IcePicker("Layout", selection: layout) {
                ForEach(IceBarLayout.allCases) { lay in
                    Text(lay.localized).tag(lay)
                }
            }
            .annotation {
                switch layout.wrappedValue {
                case .horizontal:
                    Text("Items are arranged in a single horizontal row.")
                case .vertical:
                    Text("Items are stacked vertically in a single column.")
                case .grid:
                    Text("Items are arranged in a grid with multiple columns.")
                }
            }

            if layout.wrappedValue == .grid {
                let gridColumnsDouble = Binding<Double>(
                    get: { Double(gridColumns.wrappedValue) },
                    set: { gridColumns.wrappedValue = Int($0) }
                )
                LabeledContent {
                    IceSlider(
                        value: gridColumnsDouble,
                        in: 2 ... 10,
                        step: 1
                    ) {
                        Text("\(gridColumns.wrappedValue)")
                    }
                } label: {
                    Text("Columns")
                        .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                        .onFrameChange { frame in
                            maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                        }
                }
                .annotation("Maximum number of items per row in the grid layout.")
            }
        }

        spacingRow(for: display)
    }

    @ViewBuilder
    private func spacingRow(for display: DisplaySettingsManager.DisplayInfo) -> some View {
        let savedOffset = displaySettings.configuration(forUUID: display.id).itemSpacingOffset
        let draft = draftSpacing[display.id] ?? CGFloat(savedOffset)
        let canApply = draft != CGFloat(savedOffset)

        let sliderBinding = Binding<CGFloat>(
            get: { draftSpacing[display.id] ?? CGFloat(savedOffset) },
            set: { draftSpacing[display.id] = $0 }
        )

        let labelKey: LocalizedStringKey = switch draft {
        case -16: "none"
        case 0: "default"
        case 16: "max"
        default: LocalizedStringKey(draft.formatted())
        }

        LabeledContent {
            IceSlider(
                labelKey,
                value: sliderBinding,
                in: -16 ... 16,
                step: 2
            )
        } label: {
            LabeledContent {
                Button("Apply") {
                    displaySettings.updateConfiguration(forDisplayUUID: display.id) { config in
                        config.withItemSpacingOffset(Double(draft))
                    }
                }
                .help(Text("Apply the spacing for this display"))
                .disabled(!canApply)

                Button {
                    draftSpacing[display.id] = 0
                    displaySettings.updateConfiguration(forDisplayUUID: display.id) { config in
                        config.withItemSpacingOffset(0)
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(Text("Reset to the default spacing"))
                .disabled(savedOffset == 0 && draft == 0)
            } label: {
                Text("Menu bar item spacing")
            }
        }
        .annotation(
            "Apply briefly relaunches apps with menu bar items so they pick up the new spacing. Setting takes effect when this display is the active menu bar display."
        )
        .onChange(of: savedOffset) { _, newValue in
            // Sync draft when the saved value changes externally
            // (profile load, URI scheme, etc.).
            draftSpacing[display.id] = CGFloat(newValue)
        }
    }
}
