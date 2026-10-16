//
//  ConditionEditorView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - ConditionEditorView

/// A self-contained editor for one ``TriggerCondition`` (kind picker plus the
/// kind-specific editor). Used for a trigger's additional compound
/// conditions; the primary condition is edited inline by ``TriggerRow``.
struct ConditionEditorView: View {
    @Binding var condition: TriggerCondition
    let kinds: [TriggerConditionKind]
    let appOptions: [TriggerAppOption]
    let bluetoothOptions: [TriggerBluetoothOption]
    let refreshBluetoothOptions: () -> Void
    let itemOptions: [TriggerItemOption]
    let currentCoordinate: () -> (latitude: Double, longitude: Double)?
    let captureReference: (String) async -> ImageComparisonReference?
    var focusedField: FocusState<String?>.Binding
    let focusID: String

    private var kindOptions: [TriggerConditionKind] {
        kinds.contains(condition.kind) ? kinds : kinds + [condition.kind]
    }

    private var kindBinding: Binding<TriggerConditionKind> {
        Binding(
            get: { condition.kind },
            set: { condition = .make(kind: $0, preserving: condition) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IcePicker("Condition", selection: kindBinding) {
                ForEach(kindOptions) { kind in
                    Text(kind.displayString).tag(kind)
                }
            }
            editor
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch condition.kind.editor {
        case .percentage:
            HStack(spacing: 12) {
                Slider(value: percentageBinding, in: 0 ... 100, step: 1) { Text("Battery level") }
                Text(verbatim: "\(Int(percentageBinding.wrappedValue.rounded()))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        case .appPicker:
            IcePicker("Application", selection: bundleIDBinding) {
                let current = condition.bundleID ?? ""
                if current.isEmpty {
                    Text("Choose an app…").tag("")
                } else if !appOptions.contains(where: { $0.bundleID == current }) {
                    Text("\(current) (not running)").tag(current)
                }
                ForEach(appOptions, id: \.bundleID) { option in
                    Text(option.name).tag(option.bundleID)
                }
            }
        case let .text(prompt):
            CommitTextField(
                title: prompt,
                prompt: prompt,
                value: textBinding,
                focusedField: focusedField,
                focusID: "text-\(focusID)"
            )
        case .timeRange:
            let window = condition.scheduleWindow ?? (start: 540, end: 1020)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    DatePicker("From", selection: scheduleBinding(isStart: true, window: window), displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: scheduleBinding(isStart: false, window: window), displayedComponents: .hourAndMinute)
                }
                ScheduleWeekdayPicker(selection: scheduleWeekdaysBinding)
            }
        case .location:
            locationEditor
        case .bluetoothPicker:
            BluetoothDevicePicker(
                name: textBinding,
                options: bluetoothOptions,
                refreshOptions: refreshBluetoothOptions,
                focusedField: focusedField,
                focusID: "bt-\(focusID)"
            )
        case .energyMode:
            EnergyModePicker(match: energyModeBinding)
        case .thermalLevel:
            IcePicker("Threshold", selection: thermalLevelBinding) {
                ForEach(ThermalLevel.allCases) { level in
                    Text(level.displayString).tag(level)
                }
            }
        case .script:
            ScriptConditionEditor(condition: $condition, focusedField: focusedField, focusID: focusID)
        case .imageComparison:
            ImageConditionEditor(condition: $condition, itemOptions: itemOptions, captureReference: captureReference)
        case .itemPicker:
            AttentionConditionEditor(condition: $condition, itemOptions: itemOptions)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var locationEditor: some View {
        let location = condition.locationValue ?? (latitude: 0, longitude: 0, radiusMeters: 150, label: "")
        let coordinate = currentCoordinate()
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Use Current Location") {
                    if let coordinate {
                        condition = condition.withLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    }
                }
                .disabled(coordinate == nil)
                Spacer()
                if location.latitude != 0 || location.longitude != 0 {
                    Text(verbatim: String(format: "%.4f, %.4f", location.latitude, location.longitude))
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                } else {
                    Text("No location captured").font(.caption).foregroundStyle(.secondary)
                }
            }
            IcePicker("Radius", selection: radiusBinding) {
                ForEach(TriggerRow.radiusPresets(including: location.radiusMeters), id: \.self) { meters in
                    Text("\(Int(meters)) m").tag(meters)
                }
            }
            CommitTextField(
                title: "Label (e.g. Home)",
                prompt: "Label",
                value: locationLabelBinding,
                focusedField: focusedField,
                focusID: "loclabel-\(focusID)"
            )
        }
    }

    // MARK: Bindings

    private var percentageBinding: Binding<Double> {
        Binding(get: { condition.percentage ?? 50 }, set: { condition = condition.withPercentage($0) })
    }

    private var bundleIDBinding: Binding<String> {
        Binding(get: { condition.bundleID ?? "" }, set: { condition = condition.withBundleID($0) })
    }

    private var textBinding: Binding<String> {
        Binding(get: { condition.text ?? "" }, set: { condition = condition.withText($0) })
    }

    private var radiusBinding: Binding<Double> {
        Binding(get: { condition.locationValue?.radiusMeters ?? 150 }, set: { condition = condition.withLocation(radiusMeters: $0) })
    }

    private var locationLabelBinding: Binding<String> {
        Binding(get: { condition.locationValue?.label ?? "" }, set: { condition = condition.withLocation(label: $0) })
    }

    private var energyModeBinding: Binding<EnergyModeMatch> {
        Binding(get: { condition.energyModeMatch ?? .low }, set: { condition = condition.withEnergyMode($0) })
    }

    private var thermalLevelBinding: Binding<ThermalLevel> {
        Binding(get: { condition.thermalLevel ?? .serious }, set: { condition = condition.withThermalLevel($0) })
    }

    private func scheduleBinding(isStart: Bool, window: (start: Int, end: Int)) -> Binding<Date> {
        Binding(
            get: { TriggerRow.minutesToDate(isStart ? window.start : window.end) },
            set: { newDate in
                let minutes = TriggerRow.dateToMinutes(newDate)
                condition = isStart
                    ? condition.withSchedule(start: minutes, end: window.end)
                    : condition.withSchedule(start: window.start, end: minutes)
                clearTriggerEditorFocus(focusedField)
            }
        )
    }

    private var scheduleWeekdaysBinding: Binding<Set<ScheduleWeekday>> {
        Binding(
            get: { condition.scheduleWeekdays ?? ScheduleWeekday.everyDay },
            set: { condition = condition.withScheduleWeekdays($0) }
        )
    }
}
