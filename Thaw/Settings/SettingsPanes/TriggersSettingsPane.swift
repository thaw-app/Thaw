//
//  TriggersSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

// MARK: - Option value types

/// A stable, value-type representation of a menu bar item that can be
/// targeted by a trigger. Decoupling the picker's options from the live
/// item cache keeps the SwiftUI `Picker` from rebuilding (and dropping an
/// in-progress selection) on every cache publish.
struct TriggerItemOption: Hashable {
    let id: String
    let name: String
}

/// A running application offered in the app-condition picker.
struct TriggerAppOption: Hashable {
    let bundleID: String
    let name: String
}

/// The live status of a trigger, shown as a small badge in its row.
enum TriggerLiveStatus {
    /// The trigger is turned off.
    case disabled
    /// The trigger is on, but its condition's feature flag is off.
    case inactive
    /// The condition is currently met; the item is (being) revealed.
    case revealing
    /// The condition is not met; the item is (being) hidden.
    case hidden

    var label: String {
        switch self {
        case .disabled: "Off"
        case .inactive: "Inactive"
        case .revealing: "Revealing"
        case .hidden: "Idle"
        }
    }

    var color: Color {
        switch self {
        case .disabled: .secondary
        case .inactive: .orange
        case .revealing: .green
        case .hidden: .secondary
        }
    }
}

// MARK: - TriggersSettingsPane

/// Settings pane for configuring conditional menu bar item triggers.
struct TriggersSettingsPane: View {
    @ObservedObject var manager: MenuBarItemTriggersManager
    @ObservedObject private var flags: TriggerFeatureFlagsManager

    // A plain reference, not an @ObservedObject: observing the item manager
    // would re-render the pane on every item cache publish, stealing focus.
    let itemManager: MenuBarItemManager

    @State private var itemOptions: [TriggerItemOption] = []
    @State private var appOptions: [TriggerAppOption] = []

    /// Bumped on a timer to recompute the live status indicators.
    @State private var liveTick = 0

    private let liveTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    /// Composite key ("name-<id>" / "text-<id>") of the focused text field.
    @FocusState private var focusedField: String?

    init(manager: MenuBarItemTriggersManager, itemManager: MenuBarItemManager) {
        self.manager = manager
        self.itemManager = itemManager
        _flags = ObservedObject(wrappedValue: manager.featureFlags)
    }

    var body: some View {
        IceForm {
            introSection

            if manager.triggers.isEmpty {
                emptyState
            } else {
                let conflicts = conflictingItemIdentifiers()
                let kinds = enabledKinds()
                ForEach($manager.triggers) { $trigger in
                    TriggerRow(
                        trigger: $trigger,
                        itemOptions: itemOptions,
                        appOptions: appOptions,
                        enabledKinds: kinds,
                        compoundEnabled: flags.isEnabled(.compoundConditions),
                        invertEnabled: flags.isEnabled(.invertAction),
                        advancedEnabled: flags.isEnabled(.advancedOptions),
                        conditionActive: allConditionsActive(trigger),
                        liveStatus: liveStatus(for: trigger),
                        hasConflict: trigger.allItemIdentifiers.contains { conflicts.contains($0) },
                        currentCoordinate: { manager.systemMonitor.currentCoordinate },
                        captureReference: { await manager.captureReferenceHash(forItemIdentifier: $0) },
                        focusedField: $focusedField,
                        onDelete: { manager.remove(id: trigger.id) }
                    )
                }
            }

            addButton
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
        .onAppear {
            refreshItemOptions()
            refreshAppOptions()
        }
        .onReceive(itemManager.$itemCache) { _ in
            refreshItemOptions()
        }
        .onReceive(liveTimer) { _ in
            liveTick &+= 1
        }
    }

    // MARK: Live status

    /// The current live status of a trigger, recomputed on the live timer.
    private func liveStatus(for trigger: MenuBarItemTrigger) -> TriggerLiveStatus {
        _ = liveTick // re-read on each tick
        guard trigger.isEnabled else { return .disabled }
        guard allConditionsActive(trigger) else { return .inactive }
        return trigger.shouldReveal(state: manager.currentSystemState) ? .revealing : .hidden
    }

    /// Item identifiers targeted by more than one enabled trigger.
    private func conflictingItemIdentifiers() -> Set<String> {
        var counts = [String: Int]()
        for trigger in manager.triggers where trigger.isEnabled {
            for identifier in Set(trigger.allItemIdentifiers) {
                counts[identifier, default: 0] += 1
            }
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    // MARK: Available condition kinds

    /// The condition kinds offered in the picker: always-available power
    /// kinds, kinds whose feature flag is enabled, plus the trigger's own
    /// current kind (so a disabled flag never hides an existing selection).
    /// Condition kinds whose feature flag is enabled (or which are always
    /// available). The editor additionally always includes a condition's own
    /// current kind, so a disabled flag never hides an existing selection.
    private func enabledKinds() -> [TriggerConditionKind] {
        TriggerConditionKind.allCases.filter { kind in
            guard let feature = kind.requiredFeature else { return true }
            return flags.isEnabled(feature)
        }
    }

    /// Whether all of the trigger's conditions are currently active (their
    /// feature flags enabled). An inactive trigger will not be evaluated.
    private func allConditionsActive(_ trigger: MenuBarItemTrigger) -> Bool {
        trigger.allConditions.allSatisfy { condition in
            guard let feature = condition.kind.requiredFeature else { return true }
            return flags.isEnabled(feature)
        }
    }

    // MARK: Options refresh

    private func refreshItemOptions() {
        let items = itemManager.itemCache.managedItems
            .filter { $0.tag.isMovable && $0.tag.canBeHidden }

        var nameCounts = [String: Int]()
        for item in items {
            nameCounts[item.displayName, default: 0] += 1
        }

        var options = items.map { item -> TriggerItemOption in
            let base = item.displayName
            let name = (nameCounts[base] ?? 0) > 1 ? "\(base) — \(item.tag.tagIdentifier)" : base
            return TriggerItemOption(id: item.tag.tagIdentifier, name: name)
        }
        options.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if options != itemOptions {
            itemOptions = options
        }
    }

    private func refreshAppOptions() {
        var options = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> TriggerAppOption? in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return TriggerAppOption(bundleID: bundleID, name: app.localizedName ?? bundleID)
            }
        // Deduplicate by bundle id (multiple windows / instances).
        var seen = Set<String>()
        options = options.filter { seen.insert($0.bundleID).inserted }
        options.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        appOptions = options
    }

    // MARK: Sections

    private var introSection: some View {
        IceSection(options: [.isBordered]) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Conditional Triggers")
                    .font(.headline)
                Text("Automatically reveal a menu bar item while a condition is met, then hide it again when the condition no longer applies. Enable additional condition types in the Developer pane.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var emptyState: some View {
        IceSection(options: [.isBordered]) {
            VStack(spacing: 6) {
                Image(systemName: "bolt.badge.automatic")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("No triggers yet")
                    .font(.headline)
                Text("Add a trigger to reveal a menu bar item when a condition is met.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
    }

    private var addButton: some View {
        Button {
            addTrigger()
        } label: {
            Label("Add Trigger", systemImage: "plus")
        }
        .controlSize(.large)
    }

    private func addTrigger() {
        let firstItem = itemOptions.first
        let trigger = MenuBarItemTrigger(
            itemIdentifier: firstItem?.id ?? "",
            itemDisplayName: firstItem?.name ?? "",
            revealSection: .visible,
            hideSection: .hidden,
            condition: .batteryBelow(percentage: 20)
        )
        manager.add(trigger)
    }
}

// MARK: - TriggerRow

/// An inline editor for a single ``MenuBarItemTrigger``.
private struct TriggerRow: View {
    @Binding var trigger: MenuBarItemTrigger
    let itemOptions: [TriggerItemOption]
    let appOptions: [TriggerAppOption]
    let enabledKinds: [TriggerConditionKind]
    let compoundEnabled: Bool
    let invertEnabled: Bool
    let advancedEnabled: Bool
    let conditionActive: Bool
    let liveStatus: TriggerLiveStatus
    let hasConflict: Bool
    let currentCoordinate: () -> (latitude: Double, longitude: Double)?
    let captureReference: (String) async -> UInt64?
    var focusedField: FocusState<String?>.Binding
    let onDelete: () -> Void

    private var kindBinding: Binding<TriggerConditionKind> {
        Binding(
            get: { trigger.condition.kind },
            set: { trigger.condition = .make(kind: $0, preserving: trigger.condition) }
        )
    }

    private var selectedItemName: String {
        if let match = itemOptions.first(where: { $0.id == trigger.itemIdentifier }) {
            return match.name
        }
        if !trigger.itemDisplayName.isEmpty { return trigger.itemDisplayName }
        return trigger.itemIdentifier.isEmpty ? "No item selected" : trigger.itemIdentifier
    }

    private var isSelectedItemMissing: Bool {
        !trigger.itemIdentifier.isEmpty && !itemOptions.contains { $0.id == trigger.itemIdentifier }
    }

    var body: some View {
        IceSection(options: [.isBordered]) {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                itemPicker
                conditionsSection
                if trigger.isEnabled, !conditionActive {
                    inactiveConditionWarning
                }
                if hasConflict {
                    conflictWarning
                }
                sectionPickers
                if invertEnabled {
                    Toggle("Hide the item while the condition is met (invert)", isOn: $trigger.invert)
                        .toggleStyle(.switch)
                }
                if advancedEnabled {
                    advancedOptions
                }
            }
            .padding(8)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            CommitTextField(
                title: "Trigger name",
                prompt: trigger.autoTitle,
                value: $trigger.name,
                focusedField: focusedField,
                focusID: "name-\(trigger.id)"
            )

            statusBadge

            Toggle("Enabled", isOn: $trigger.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this trigger")
        }
    }

    private var advancedOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            ForEach(Array(trigger.additionalItems.indices), id: \.self) { index in
                HStack(spacing: 8) {
                    IcePicker("Also move", selection: additionalItemBinding(index)) {
                        let current = trigger.additionalItems[index].identifier
                        if !current.isEmpty, !itemOptions.contains(where: { $0.id == current }) {
                            Text("\(trigger.additionalItems[index].displayName) (not present)").tag(current)
                        }
                        if current.isEmpty {
                            Text("Choose an item…").tag("")
                        }
                        ForEach(itemOptions, id: \.id) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    Button(role: .destructive) {
                        trigger.additionalItems.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                trigger.additionalItems.append(TriggerTargetItem())
            } label: {
                Label("Also move another item", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            Toggle("Notify when this reveals the item", isOn: $trigger.notifyOnReveal)
                .toggleStyle(.switch)
            HStack(spacing: 12) {
                Toggle("Custom delay", isOn: delayEnabledBinding)
                    .toggleStyle(.switch)
                if trigger.settleSecondsOverride != nil {
                    Stepper(value: delaySecondsBinding, in: 0 ... 120, step: 1) {
                        Text(verbatim: "\(Int(delaySecondsBinding.wrappedValue)) s")
                            .monospacedDigit()
                    }
                    .fixedSize()
                }
            }
        }
    }

    private func additionalItemBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                index < trigger.additionalItems.count ? trigger.additionalItems[index].identifier : ""
            },
            set: { newValue in
                guard index < trigger.additionalItems.count else { return }
                let name = itemOptions.first(where: { $0.id == newValue })?.name ?? ""
                trigger.additionalItems[index] = TriggerTargetItem(identifier: newValue, displayName: name)
            }
        )
    }

    private var delayEnabledBinding: Binding<Bool> {
        Binding(
            get: { trigger.settleSecondsOverride != nil },
            set: { trigger.settleSecondsOverride = $0 ? (trigger.settleSecondsOverride ?? 2) : nil }
        )
    }

    private var delaySecondsBinding: Binding<Double> {
        Binding(
            get: { trigger.settleSecondsOverride ?? 2 },
            set: { trigger.settleSecondsOverride = $0 }
        )
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(liveStatus.color)
                .frame(width: 7, height: 7)
            Text(liveStatus.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help("Live status of this trigger")
        .fixedSize()
    }

    // MARK: Pickers

    private var itemPicker: some View {
        IcePicker("Menu bar item", selection: itemBinding) {
            if isSelectedItemMissing {
                Text("\(selectedItemName) (not present)").tag(trigger.itemIdentifier)
            }
            ForEach(itemOptions, id: \.id) { option in
                Text(option.name).tag(option.id)
            }
        }
    }

    private var conditionPicker: some View {
        IcePicker("Condition", selection: kindBinding) {
            ForEach(kindOptions) { kind in
                Text(kind.displayString).tag(kind)
            }
        }
    }

    /// Enabled kinds, always including the current selection so a disabled
    /// flag never hides an existing condition.
    private var kindOptions: [TriggerConditionKind] {
        enabledKinds.contains(trigger.condition.kind) ? enabledKinds : enabledKinds + [trigger.condition.kind]
    }

    // MARK: Conditions (primary + optional compound)

    @ViewBuilder
    private var conditionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if compoundEnabled, !trigger.additionalConditions.isEmpty {
                IcePicker("Match", selection: $trigger.combinator) {
                    ForEach(TriggerCombinator.allCases) { combinator in
                        Text(combinator.displayString).tag(combinator)
                    }
                }
            }

            conditionPicker
            conditionEditor

            if compoundEnabled {
                ForEach(Array(trigger.additionalConditions.indices), id: \.self) { index in
                    Divider()
                    HStack(alignment: .top, spacing: 8) {
                        ConditionEditorView(
                            condition: additionalConditionBinding(index),
                            kinds: enabledKinds,
                            appOptions: appOptions,
                            itemOptions: itemOptions,
                            currentCoordinate: currentCoordinate,
                            captureReference: captureReference,
                            focusedField: focusedField,
                            focusID: "c\(index + 1)-\(trigger.id)"
                        )
                        Button(role: .destructive) {
                            removeCondition(index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this condition")
                    }
                }

                Button {
                    addCondition()
                } label: {
                    Label("Add Condition", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func additionalConditionBinding(_ index: Int) -> Binding<TriggerCondition> {
        Binding(
            get: {
                index < trigger.additionalConditions.count ? trigger.additionalConditions[index] : .onACPower
            },
            set: { newValue in
                guard index < trigger.additionalConditions.count else { return }
                trigger.additionalConditions[index] = newValue
            }
        )
    }

    private func addCondition() {
        let kind = enabledKinds.first ?? .batteryBelow
        trigger.additionalConditions.append(.defaultCondition(for: kind))
    }

    private func removeCondition(_ index: Int) {
        guard index < trigger.additionalConditions.count else { return }
        trigger.additionalConditions.remove(at: index)
    }

    private var inactiveConditionWarning: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("This condition is turned off in Developer settings, so the trigger won't run.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var conflictWarning: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Another enabled trigger also targets this item; they may fight over showing and hiding it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var conditionEditor: some View {
        switch trigger.condition.kind.editor {
        case .percentage:
            percentageEditor
        case .appPicker:
            appPicker
        case let .text(prompt):
            CommitTextField(
                title: prompt,
                prompt: prompt,
                value: textBinding,
                focusedField: focusedField,
                focusID: "text-\(trigger.id)"
            )
        case .timeRange:
            timeRangeEditor
        case .location:
            locationEditor
        case .thermalLevel:
            IcePicker("Threshold", selection: thermalLevelBinding) {
                ForEach(ThermalLevel.allCases) { level in
                    Text(level.displayString).tag(level)
                }
            }
        case .script:
            ScriptConditionEditor(condition: $trigger.condition, focusedField: focusedField, focusID: "c0-\(trigger.id)")
        case .imageComparison:
            ImageConditionEditor(condition: $trigger.condition, itemOptions: itemOptions, captureReference: captureReference)
        case .none:
            EmptyView()
        }
    }

    private var sectionPickers: some View {
        Group {
            IcePicker("Show in", selection: $trigger.revealSection) {
                ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                    Text(section.displayString).tag(section)
                }
            }
            IcePicker("Otherwise hide in", selection: $trigger.hideSection) {
                ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                    Text(section.displayString).tag(section)
                }
            }
        }
    }

    // MARK: Editors

    private var percentageEditor: some View {
        HStack(spacing: 12) {
            Slider(value: percentageBinding, in: 0 ... 100, step: 1) {
                Text("Battery level")
            }
            Text(verbatim: "\(Int(percentageBinding.wrappedValue.rounded()))%")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var appPicker: some View {
        IcePicker("Application", selection: bundleIDBinding) {
            let current = trigger.condition.bundleID ?? ""
            if current.isEmpty {
                Text("Choose an app…").tag("")
            } else if !appOptions.contains(where: { $0.bundleID == current }) {
                Text("\(current) (not running)").tag(current)
            }
            ForEach(appOptions, id: \.bundleID) { option in
                Text(option.name).tag(option.bundleID)
            }
        }
    }

    private var timeRangeEditor: some View {
        let window = trigger.condition.scheduleWindow ?? (start: 540, end: 1020)
        return HStack(spacing: 12) {
            DatePicker(
                "From",
                selection: scheduleBinding(isStart: true, window: window),
                displayedComponents: .hourAndMinute
            )
            DatePicker(
                "To",
                selection: scheduleBinding(isStart: false, window: window),
                displayedComponents: .hourAndMinute
            )
        }
    }

    @ViewBuilder
    private var locationEditor: some View {
        let location = trigger.condition.locationValue ?? (latitude: 0, longitude: 0, radiusMeters: 150, label: "")
        let coordinate = currentCoordinate()

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Use Current Location") {
                    if let coordinate {
                        trigger.condition = trigger.condition.withLocation(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        )
                    }
                }
                .disabled(coordinate == nil)

                Spacer()

                if location.latitude != 0 || location.longitude != 0 {
                    Text(verbatim: String(format: "%.4f, %.4f", location.latitude, location.longitude))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("No location captured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            IcePicker("Radius", selection: radiusBinding) {
                ForEach(Self.radiusPresets(including: location.radiusMeters), id: \.self) { meters in
                    Text("\(Int(meters)) m").tag(meters)
                }
            }

            CommitTextField(
                title: "Label (e.g. Home)",
                prompt: "Label",
                value: locationLabelBinding,
                focusedField: focusedField,
                focusID: "loclabel-\(trigger.id)"
            )

            if coordinate == nil {
                Text("Turn on the Location flag in Developer settings and grant permission to capture your current location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func radiusPresets(including current: Double) -> [Double] {
        var presets: [Double] = [50, 100, 150, 300, 500, 1000]
        if !presets.contains(current) {
            presets.append(current)
            presets.sort()
        }
        return presets
    }

    // MARK: Bindings

    private var radiusBinding: Binding<Double> {
        Binding(
            get: { trigger.condition.locationValue?.radiusMeters ?? 150 },
            set: { trigger.condition = trigger.condition.withLocation(radiusMeters: $0) }
        )
    }

    private var locationLabelBinding: Binding<String> {
        Binding(
            get: { trigger.condition.locationValue?.label ?? "" },
            set: { trigger.condition = trigger.condition.withLocation(label: $0) }
        )
    }

    private var thermalLevelBinding: Binding<ThermalLevel> {
        Binding(
            get: { trigger.condition.thermalLevel ?? .serious },
            set: { trigger.condition = trigger.condition.withThermalLevel($0) }
        )
    }

    private var itemBinding: Binding<String> {
        Binding(
            get: { trigger.itemIdentifier },
            set: { newValue in
                trigger.itemIdentifier = newValue
                if let match = itemOptions.first(where: { $0.id == newValue }) {
                    trigger.itemDisplayName = match.name
                }
            }
        )
    }

    private var percentageBinding: Binding<Double> {
        Binding(
            get: { trigger.condition.percentage ?? 50 },
            set: { trigger.condition = trigger.condition.withPercentage($0) }
        )
    }

    private var bundleIDBinding: Binding<String> {
        Binding(
            get: { trigger.condition.bundleID ?? "" },
            set: { trigger.condition = trigger.condition.withBundleID($0) }
        )
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { trigger.condition.text ?? "" },
            set: { trigger.condition = trigger.condition.withText($0) }
        )
    }

    private func scheduleBinding(isStart: Bool, window: (start: Int, end: Int)) -> Binding<Date> {
        Binding(
            get: { Self.minutesToDate(isStart ? window.start : window.end) },
            set: { newDate in
                let minutes = Self.dateToMinutes(newDate)
                if isStart {
                    trigger.condition = trigger.condition.withSchedule(start: minutes, end: window.end)
                } else {
                    trigger.condition = trigger.condition.withSchedule(start: window.start, end: minutes)
                }
            }
        )
    }

    static func minutesToDate(_ minutes: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
        ) ?? Date()
    }

    static func dateToMinutes(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

// MARK: - ConditionEditorView

/// A self-contained editor for one ``TriggerCondition`` (kind picker plus the
/// kind-specific editor). Used for a trigger's additional compound
/// conditions; the primary condition is edited inline by ``TriggerRow``.
private struct ConditionEditorView: View {
    @Binding var condition: TriggerCondition
    let kinds: [TriggerConditionKind]
    let appOptions: [TriggerAppOption]
    let itemOptions: [TriggerItemOption]
    let currentCoordinate: () -> (latitude: Double, longitude: Double)?
    let captureReference: (String) async -> UInt64?
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
            HStack(spacing: 12) {
                DatePicker("From", selection: scheduleBinding(isStart: true, window: window), displayedComponents: .hourAndMinute)
                DatePicker("To", selection: scheduleBinding(isStart: false, window: window), displayedComponents: .hourAndMinute)
            }
        case .location:
            locationEditor
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
            }
        )
    }
}

// MARK: - ScriptConditionEditor

/// Editor for a script-result condition: a script path (with a file picker)
/// and an optional expected-output substring.
private struct ScriptConditionEditor: View {
    @Binding var condition: TriggerCondition
    var focusedField: FocusState<String?>.Binding
    let focusID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CommitTextField(
                    title: "Script path",
                    prompt: "/path/to/script",
                    value: pathBinding,
                    focusedField: focusedField,
                    focusID: "scriptpath-\(focusID)"
                )
                Button("Choose…") { chooseScript() }
            }
            CommitTextField(
                title: "Expected output (optional)",
                prompt: "Leave empty to use exit code 0",
                value: expectedBinding,
                focusedField: focusedField,
                focusID: "scriptexp-\(focusID)"
            )
            Text("Runs your script about every 30 seconds. Reveals when it exits 0, or — if an expected output is set — when its output contains that text.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pathBinding: Binding<String> {
        Binding(get: { condition.scriptValue?.path ?? "" }, set: { condition = condition.withScriptPath($0) })
    }

    private var expectedBinding: Binding<String> {
        Binding(get: { condition.scriptValue?.expectedOutput ?? "" }, set: { condition = condition.withScriptExpectedOutput($0) })
    }

    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            condition = condition.withScriptPath(url.path)
        }
    }
}

// MARK: - ImageConditionEditor

/// Editor for an image-comparison condition: pick a menu bar item to watch
/// and capture a reference image of its icon.
private struct ImageConditionEditor: View {
    @Binding var condition: TriggerCondition
    let itemOptions: [TriggerItemOption]
    let captureReference: (String) async -> UInt64?

    @State private var isCapturing = false

    private var watchedID: String { condition.imageValue?.itemIdentifier ?? "" }
    private var hasReference: Bool {
        guard case let .imageChanged(_, referenceHash) = condition else { return false }
        return referenceHash != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IcePicker("Watched item", selection: itemBinding) {
                if watchedID.isEmpty {
                    Text("Choose an item…").tag("")
                } else if !itemOptions.contains(where: { $0.id == watchedID }) {
                    Text("\(watchedID) (not present)").tag(watchedID)
                }
                ForEach(itemOptions, id: \.id) { option in
                    Text(option.name).tag(option.id)
                }
            }

            HStack(spacing: 12) {
                Button(isCapturing ? "Capturing…" : "Capture Reference") { capture() }
                    .disabled(isCapturing || watchedID.isEmpty)
                Spacer()
                Text(hasReference ? "Reference captured" : "No reference yet")
                    .font(.caption)
                    .foregroundStyle(hasReference ? .green : .secondary)
            }

            Text("Captures the icon now as a reference, then reveals the item when the icon later changes from it. Requires screen recording permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var itemBinding: Binding<String> {
        Binding(get: { watchedID }, set: { condition = condition.withImageItem($0) })
    }

    private func capture() {
        let id = watchedID
        guard !id.isEmpty else { return }
        isCapturing = true
        Task { @MainActor in
            let hash = await captureReference(id)
            isCapturing = false
            if let hash {
                condition = condition.withImageReferenceHash(hash)
            }
        }
    }
}

// MARK: - CommitTextField

/// A text field that edits a local draft and commits to the bound value
/// only on Enter or focus loss, so per-keystroke typing does not churn the
/// settings object graph (which re-renders the whole settings window and
/// steals focus). Focus is owned by the enclosing pane so clicking away
/// dismisses the field.
private struct CommitTextField: View {
    let title: String
    let prompt: String?
    @Binding var value: String
    var focusedField: FocusState<String?>.Binding
    let focusID: String

    @State private var draft: String = ""

    var body: some View {
        TextField(title, text: $draft, prompt: prompt.map { Text(verbatim: $0) })
            .textFieldStyle(.roundedBorder)
            .focused(focusedField, equals: focusID)
            .onAppear { draft = value }
            .onChange(of: value) { _, newValue in
                if focusedField.wrappedValue != focusID { draft = newValue }
            }
            .onChange(of: focusedField.wrappedValue) { _, newValue in
                if newValue != focusID { commit() }
            }
            .onSubmit {
                commit()
                focusedField.wrappedValue = nil
            }
    }

    private func commit() {
        if draft != value { value = draft }
    }
}
