//
//  WidgetsSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The editor for the persistent widget item. The item itself lives in
/// StatusIconWidgetController and survives closing this pane.
struct WidgetsSettingsPane: View {
    @AppStorage("StatusIconPrototype.outer") private var outer = StatusIconComposition.Outer.arc
    @AppStorage("StatusIconPrototype.outerSource") private var outerSource = StatusIconComposition.Source.battery
    @AppStorage("StatusIconPrototype.center") private var center = StatusIconComposition.Center.wifi
    @AppStorage("StatusIconPrototype.bottom") private var bottom = StatusIconComposition.Bottom.dots
    @AppStorage("StatusIconPrototype.bottomSource") private var bottomSource = StatusIconComposition.Source.wifi
    @AppStorage("StatusIconPrototype.live") private var liveData = true
    @State private var widget = StatusIconWidgetController.shared
    @State private var manualSamples = StatusIconSamples()
    @State private var didRestoreSamples = false

    private var composition: StatusIconComposition {
        StatusIconComposition(outer: outer, outerSource: outerSource, center: center, bottom: bottom, bottomSource: bottomSource)
    }

    private var previewState: StatusIconPreviewState {
        var samples = liveData ? widget.liveSamples : manualSamples
        // Volume has no live source; the manual slider wins in both modes.
        samples.volume = manualSamples.volume
        return StatusIconPreviewState(composition: composition, samples: samples, isLive: liveData)
    }

    var body: some View {
        ThawForm {
            ThawSection("Menu bar") {
                Toggle("Show in menu bar", isOn: Binding(
                    get: { widget.isEnabled },
                    set: { widget.setEnabled($0) }
                ))
                .disabled(composition.isEmpty && !widget.isEnabled)
                .annotation(
                    enableSummary,
                    more: "Click it for its readings or to open Network Settings."
                )
            }
            ThawSection("Icon builder") {
                VStack(alignment: .leading, spacing: ThawSpacing.base) {
                    HStack {
                        Text("Combine up to three indicators in one icon.")
                        ThawBadge.alpha
                    }
                    Text("Your design is saved automatically. The menu bar preview does not change Apple's icons.")
                        .font(ThawType.caption)
                        .foregroundStyle(ThawInk.supporting)
                }
                StatusIconPreview(state: previewState)
                Button("Reset to original combination") {
                    let original = StatusIconComposition()
                    outer = original.outer
                    outerSource = original.outerSource
                    center = original.center
                    bottom = original.bottom
                    bottomSource = original.bottomSource
                    manualSamples = StatusIconSamples()
                }
                .buttonStyle(.settingsGlass)
            }
            ThawSection("Outer indicator") {
                ThawPicker("Shape", selection: $outer) {
                    ForEach(StatusIconComposition.Outer.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                if outer != .none {
                    sourcePicker("Outer reading", selection: $outerSource)
                }
            }
            ThawSection("Center symbol") {
                ThawPicker("Symbol", selection: $center) {
                    ForEach(StatusIconComposition.Center.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .annotation(
                    "Network follows the active connection: Wi-Fi, Ethernet, cellular, another connection, or disconnected.",
                    more: "The other center symbols are decorative."
                )
            }
            ThawSection("Bottom indicator") {
                ThawPicker("Style", selection: $bottom) {
                    ForEach(StatusIconComposition.Bottom.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                if bottom != .none {
                    sourcePicker("Bottom reading", selection: $bottomSource)
                }
            }
            readingsSection
        }
        .onAppear {
            if !didRestoreSamples {
                didRestoreSamples = true
                manualSamples = widget.storedSamples()
            }
        }
        .onChange(of: liveData) {
            widget.setLive(liveData)
            widget.refresh(with: previewState)
        }
        .onChange(of: previewState) { widget.refresh(with: previewState) }
    }

    /// The enable toggle cannot turn on while every indicator is off, so its
    /// description says what unlocks it instead of leaving it greyed out.
    private var enableSummary: LocalizedStringKey {
        composition.isEmpty && !widget.isEnabled
            ? "Choose at least one indicator below to show the item."
            : "The item stays while \(Constants.displayName) runs and returns automatically at launch."
    }

    /// Both states of the readings toggle need explaining, so the description
    /// switches with the toggle.
    private var readingsSummary: LocalizedStringKey {
        liveData
            ? "Connection type follows the system's default route, not whether Wi-Fi is switched on."
            : "Choose a connection and move the sliders to test your icon."
    }

    private var readingsDetail: LocalizedStringKey {
        liveData
            ? "Battery, Wi-Fi strength, and CPU refresh every 2 seconds. Volume is manual."
            : "These are sample readings."
    }

    private var readingsSection: some View {
        ThawSection("Readings") {
            Toggle("Use my Mac’s readings", isOn: $liveData)
                .annotation(readingsSummary, more: readingsDetail)
            if !liveData, center == .wifi {
                ThawPicker("Sample connection", selection: $manualSamples.network) {
                    ForEach(StatusIconNetwork.allCases, id: \.self) { network in
                        Text(network.title).tag(network)
                    }
                }
            }
            // Live readings drive every source but volume, so their sliders
            // would do nothing; only the ones the user can move are shown.
            ForEach(previewState.sources.filter { !liveData || $0 == .volume }, id: \.self) { source in
                StatusIconSampleSlider(
                    source: source,
                    value: Binding(get: { previewState.samples[source] }, set: { manualSamples[source] = $0 })
                )
            }
        }
    }

    private func sourcePicker(_ title: LocalizedStringKey, selection: Binding<StatusIconComposition.Source>) -> some View {
        ThawPicker(title, selection: selection) {
            ForEach(StatusIconComposition.Source.allCases, id: \.self) { source in
                Text(source.title).tag(source)
            }
        }
    }
}

private struct StatusIconPreview: View {
    let state: StatusIconPreviewState

    var body: some View {
        VStack(spacing: ThawSpacing.gutter) {
            HStack(alignment: .center, spacing: ThawSpacing.section) {
                preview(size: 112, title: "Enlarged")
                preview(size: 22, title: "Menu-bar size")
            }
            .frame(maxWidth: .infinity)
            Text(state.title)
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)
            Text(state.details.joined(separator: " · "))
                .font(ThawType.caption)
            if state.composition.isEmpty {
                Text("Choose at least one indicator to make your icon visible.")
                    .font(ThawType.caption)
                    .foregroundStyle(ThawInk.supporting)
            }
        }
        .padding(.vertical, ThawSpacing.inset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityDescription)
    }

    private func preview(size: CGFloat, title: LocalizedStringKey) -> some View {
        VStack(spacing: ThawSpacing.base) {
            CompositeStatusIcon(composition: state.composition, samples: state.samples)
                .frame(width: size, height: size)
                .frame(height: 112)
            Text(title)
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)
        }
    }
}

private struct StatusIconSampleSlider: View {
    let source: StatusIconComposition.Source
    @Binding var value: Double

    var body: some View {
        LabeledContent {
            ThawSlider(value: $value, in: 0 ... 1, step: 0.01) {
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .accessibilityValue(value.formatted(.percent.precision(.fractionLength(0))))
        } label: {
            Text(source.title)
        }
    }
}
