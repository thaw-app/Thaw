//
//  WidgetsView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The builder for the widget icon. The icon itself lives in
/// StatusIconWidgetController and stays while the module runs.
struct WidgetsView: View {
    @AppStorage(WidgetKeys.outer) private var outer = StatusIconComposition().outer
    @AppStorage(WidgetKeys.outerSource) private var outerSource = StatusIconComposition().outerSource
    @AppStorage(WidgetKeys.center) private var center = StatusIconComposition().center
    @AppStorage(WidgetKeys.bottom) private var bottom = StatusIconComposition().bottom
    @AppStorage(WidgetKeys.bottomSource) private var bottomSource = StatusIconComposition().bottomSource
    @AppStorage(WidgetKeys.live) private var liveData = true
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
        Form {
            ThawSection("Icon builder") {
                VStack(alignment: .leading, spacing: ThawSpacing.base) {
                    Text("Combine up to three indicators in one icon.")
                    Text("Your design is saved automatically.")
                        .font(ThawType.caption)
                        .foregroundStyle(ThawInk.supporting)
                }
                StatusIconPreview(state: previewState)
                Button("Reset Icon") {
                    let original = StatusIconComposition()
                    outer = original.outer
                    outerSource = original.outerSource
                    center = original.center
                    bottom = original.bottom
                    bottomSource = original.bottomSource
                    manualSamples = StatusIconSamples()
                }
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
                Text("Network follows the active connection: Wi-Fi, Ethernet, cellular, another connection, or disconnected. The other center symbols are decorative.")
                    .font(ThawType.caption)
                    .foregroundStyle(ThawInk.supporting)
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
        .formStyle(.grouped)
        .frame(width: 520)
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
            : "Move the sliders to try other values."
    }

    private var readingsSection: some View {
        ThawSection("Readings") {
            VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                Toggle("Use my Mac’s readings", isOn: $liveData)
                Text(readingsSummary)
                    .font(ThawType.caption)
                    .foregroundStyle(ThawInk.supporting)
                Text(readingsDetail)
                    .font(ThawType.caption)
                    .foregroundStyle(ThawInk.supporting)
            }
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
                preview(size: 22, title: "Actual size")
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
