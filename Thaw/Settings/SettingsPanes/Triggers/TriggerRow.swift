//
//  TriggerRow.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

private extension MenuBarSection.Name {
    var triggerPickerDisplayString: String {
        switch self {
        case .visible: "Visible Bar"
        case .hidden: "Hidden Bar"
        case .alwaysHidden: "Always-Hidden Bar"
        }
    }
}

private extension MenuBarItemTriggerRuntimeStatus {
    var label: String {
        switch self {
        case .off: "Off"
        case .inactive: "Inactive"
        case .settling: "Settling"
        case .moving: "Moving"
        case .active: "Active"
        case .idle: "Idle"
        case .pending: "Pending"
        case .overridden: "Overridden"
        case .deferred: "Deferred"
        case .unavailable: "Unavailable"
        case .failed: "Failed"
        }
    }

    var color: Color {
        switch self {
        case .off: .secondary
        case .inactive: .orange
        case .settling, .pending: .yellow
        case .moving: .blue
        case .active: .green
        case .idle: .secondary
        case .overridden, .deferred, .unavailable: .orange
        case .failed: .red
        }
    }

    var helpText: String {
        switch self {
        case .off:
            "This trigger is turned off."
        case .inactive:
            "A condition this trigger needs is turned off in Trigger Sources."
        case .settling:
            "The condition changed and is waiting for its settle delay before moving the item."
        case .moving:
            "The trigger has queued or started the menu bar item move."
        case .active:
            "The reveal decision was applied."
        case .idle:
            "No reveal is currently applied."
        case .pending:
            "The condition is true, but no move has been queued yet."
        case let .overridden(names):
            if names.isEmpty {
                "A higher-priority trigger currently owns this item."
            } else {
                "Overridden by \(names.joined(separator: ", "))."
            }
        case .deferred:
            "The move was deferred because another layout operation is in progress."
        case .unavailable:
            "The target item or required menu bar controls are not available."
        case .failed:
            "The item move was attempted but failed."
        }
    }
}

// MARK: - TriggerRow

/// An inline editor for a single ``MenuBarItemTrigger``.
struct TriggerRow: View {
    @Binding var trigger: MenuBarItemTrigger
    let itemOptions: [TriggerItemOption]
    let appOptions: [TriggerAppOption]
    let bluetoothOptions: [TriggerBluetoothOption]
    let refreshBluetoothOptions: () -> Void
    let enabledKinds: [TriggerConditionKind]
    let compoundEnabled: Bool
    let invertEnabled: Bool
    let advancedEnabled: Bool
    let conditionActive: Bool
    let liveStatus: MenuBarItemTriggerRuntimeStatus
    let hasConflict: Bool
    let priorityNumber: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let allowsCollapseToggle: Bool
    let isCollapsed: Bool
    let isDragging: Bool
    let dropIndicatorPlacement: TriggerDropIndicatorPlacement?
    let onToggleCollapsedExpansion: () -> Void
    let dragProvider: () -> NSItemProvider
    let currentCoordinate: () -> (latitude: Double, longitude: Double)?
    let captureReference: (String) async -> ImageComparisonReference?
    var focusedField: FocusState<String?>.Binding
    let onDelete: () -> Void

    private var kindBinding: Binding<TriggerConditionKind> {
        Binding(
            get: { trigger.condition.kind },
            set: { trigger.condition = .make(kind: $0, preserving: trigger.condition) }
        )
    }

    /// Resolves a configured target to the current option list. A trigger can
    /// safely follow a re-enumerated instance when it captured a live
    /// namespace/title base; show that target as available rather than as a
    /// misleading "not present" entry.
    private func itemOption(
        matching identifier: String,
        baseIdentifier: String?
    ) -> TriggerItemOption? {
        if let exact = itemOptions.first(where: { $0.id == identifier }) {
            return exact
        }
        guard let baseIdentifier else { return nil }
        let matches = itemOptions.filter { $0.baseIdentifier == baseIdentifier }
        return matches.count == 1 ? matches[0] : nil
    }

    private var selectedItemOption: TriggerItemOption? {
        itemOption(
            matching: trigger.itemIdentifier,
            baseIdentifier: trigger.itemBaseIdentifier
        )
    }

    private var selectedItemName: String {
        if let selectedItemOption {
            return selectedItemOption.name
        }
        if !trigger.itemDisplayName.isEmpty {
            return trigger.itemDisplayName
        }
        return trigger.itemIdentifier.isEmpty ? "No item selected" : trigger.itemIdentifier
    }

    private var isSelectedItemMissing: Bool {
        !trigger.itemIdentifier.isEmpty && selectedItemOption == nil
    }

    private var overriddenNames: [String] {
        if case let .overridden(names) = liveStatus {
            return names
        }
        return []
    }

    var body: some View {
        if isCollapsed {
            rowWithDropIndicator
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onDrag(dragProvider) {
                    dragPreview
                }
        } else {
            rowWithDropIndicator
        }
    }

    private var rowWithDropIndicator: some View {
        VStack(spacing: 4) {
            if dropIndicatorPlacement == .above {
                dropIndicatorLine
            }

            rowContent

            if dropIndicatorPlacement == .below {
                dropIndicatorLine
            }
        }
    }

    private var rowContent: some View {
        IceSection {
            VStack(alignment: .leading, spacing: 12) {
                header
                if !isCollapsed {
                    Divider()
                    itemPicker
                    conditionsSection
                    if trigger.isEnabled, !conditionActive {
                        inactiveConditionWarning
                    }
                    if hasConflict {
                        conflictWarning
                    }
                    if trigger.isEnabled, conditionActive {
                        savedLayoutOverrideNote
                    }
                    if !overriddenNames.isEmpty {
                        overriddenWarning(names: overriddenNames)
                    }
                    sectionPickers
                    if invertEnabled || trigger.invert {
                        Toggle("Hide the item while the condition is met (invert)", isOn: $trigger.invert)
                            .toggleStyle(.switch)
                    }
                    if advancedEnabled
                        || !trigger.additionalItems.isEmpty
                        || trigger.notifyOnReveal
                        || trigger.settleSecondsOverride != nil
                    {
                        advancedOptions
                    }
                }
            }
            .padding(isCollapsed ? 6 : 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous)
                .stroke(isDragging ? Color.orange : .clear, lineWidth: 2)
        }
        .animation(.easeInOut(duration: 0.12), value: isDragging)
    }

    private var dropIndicatorLine: some View {
        Capsule()
            .fill(Color.orange)
            .frame(height: 3)
            .padding(.horizontal, 12)
            .shadow(color: .orange.opacity(0.45), radius: 4)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            priorityControls

            if allowsCollapseToggle {
                compactExpansionButton
            }

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

    private var compactExpansionButton: some View {
        Button {
            onToggleCollapsedExpansion()
        } label: {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .frame(width: 14)
        }
        .buttonStyle(.borderless)
        .help(isCollapsed ? "Expand trigger" : "Collapse trigger")
    }

    @ViewBuilder
    private var priorityControls: some View {
        if isCollapsed {
            priorityControlsContent
        } else {
            priorityControlsContent
                .onDrag(dragProvider) {
                    dragPreview
                }
        }
    }

    private var priorityControlsContent: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .help("Drag to change trigger priority")

            Text(verbatim: "\(priorityNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 14)

            VStack(spacing: 0) {
                Button {
                    onMoveUp()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(!canMoveUp)
                .help("Move trigger up")

                Button {
                    onMoveDown()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(!canMoveDown)
                .help("Move trigger down")
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
        }
        .fixedSize()
    }

    private var dragPreview: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)

            Text(verbatim: "\(priorityNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 14)

            Text(trigger.displayName)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            statusBadge

            dragPreviewToggle
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 560, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous)
                .stroke(.secondary.opacity(0.25))
        }
        .thawShadow(.raised)
    }

    private var dragPreviewToggle: some View {
        ZStack(alignment: trigger.isEnabled ? .trailing : .leading) {
            Capsule()
                .fill(trigger.isEnabled ? Color.accentColor : Color.secondary.opacity(0.25))

            Circle()
                .fill(.white)
                .padding(2)
        }
        .frame(width: 40, height: 22)
    }

    private var advancedOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            ForEach(Array(trigger.additionalItems.indices), id: \.self) { index in
                // Index identity shifts on removal, so SwiftUI can evaluate a
                // row whose index no longer exists. Every access tolerates a
                // stale index instead of trapping.
                let currentItem = trigger.additionalItems.indices.contains(index)
                    ? trigger.additionalItems[index]
                    : TriggerTargetItem()
                HStack(spacing: 8) {
                    IcePicker("Also move", selection: additionalItemBinding(index)) {
                        let current = currentItem.identifier
                        let resolvedItem = itemOption(
                            matching: current,
                            baseIdentifier: currentItem.baseIdentifier
                        )
                        if !current.isEmpty, resolvedItem == nil {
                            Text("\(currentItem.displayName) (not present)").tag(current)
                        } else if let resolvedItem, resolvedItem.id != current {
                            Text(resolvedItem.name).tag(current)
                        }
                        if current.isEmpty {
                            Text("Choose an item…").tag("")
                        }
                        ForEach(itemOptions, id: \.id) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                    Button(role: .destructive) {
                        guard trigger.additionalItems.indices.contains(index) else { return }
                        trigger.additionalItems.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            if advancedEnabled {
                Button {
                    trigger.additionalItems.append(TriggerTargetItem())
                } label: {
                    Label("Also move another item", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

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
                guard newValue != trigger.additionalItems[index].identifier else { return }
                let name = itemOptions.first(where: { $0.id == newValue })?.name ?? ""
                let baseIdentifier = itemOptions.first(where: { $0.id == newValue })?.baseIdentifier
                trigger.additionalItems[index] = TriggerTargetItem(
                    identifier: newValue,
                    displayName: name,
                    baseIdentifier: baseIdentifier
                )
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
        .help(liveStatus.helpText)
        .fixedSize()
    }

    // MARK: Pickers

    private var itemPicker: some View {
        IcePicker("Menu bar item", selection: itemBinding) {
            if isSelectedItemMissing {
                Text("\(selectedItemName) (not present)").tag(trigger.itemIdentifier)
            } else if let selectedItemOption, selectedItemOption.id != trigger.itemIdentifier {
                Text(selectedItemOption.name).tag(trigger.itemIdentifier)
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

    /// Shown when compound conditions are available (`None of` is useful with one
    /// condition), and whenever the combinator isn't the default so it can be undone.
    private var showsCombinatorPicker: Bool {
        compoundEnabled || trigger.combinator != .all
    }

    /// With one condition, "All of" and "Any of" are identical no-ops, so only the
    /// meaningful pair is shown, plus the current selection.
    private var combinatorOptions: [TriggerCombinator] {
        let options: [TriggerCombinator] = trigger.additionalConditions.isEmpty
            ? [.all, .noneOf]
            : TriggerCombinator.allCases
        return options.contains(trigger.combinator) ? options : options + [trigger.combinator]
    }

    // MARK: Conditions (primary + optional compound)

    private var conditionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsCombinatorPicker {
                IcePicker("Match", selection: $trigger.combinator) {
                    ForEach(combinatorOptions) { combinator in
                        Text(combinator.displayString).tag(combinator)
                    }
                }
            }

            conditionPicker
            conditionEditor

            // Existing extra conditions render even with the compound flag off, since
            // `shouldReveal` still evaluates them. Only the Add button is flag-gated.
            if compoundEnabled || !trigger.additionalConditions.isEmpty {
                ForEach(Array(trigger.additionalConditions.indices), id: \.self) { index in
                    Divider()
                    HStack(alignment: .top, spacing: 8) {
                        ConditionEditorView(
                            condition: additionalConditionBinding(index),
                            kinds: enabledKinds,
                            appOptions: appOptions,
                            bluetoothOptions: bluetoothOptions,
                            refreshBluetoothOptions: refreshBluetoothOptions,
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

                if compoundEnabled {
                    Button {
                        addCondition()
                    } label: {
                        Label("Add Condition", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
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
            Text("This condition is turned off in Trigger Sources, so the trigger won't run.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Explains that the trigger, not the Layout editor, decides where its
    /// targets sit. The claim holds whenever the trigger is enabled, not only
    /// while its condition is met, because that is when the item manager
    /// takes ownership.
    private var savedLayoutOverrideNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.orange)
            Text(controlledItemsDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Names the items this trigger takes over, falling back to a generic
    /// phrasing when no target has been chosen yet.
    private var controlledItemsDescription: String {
        let names = trigger.allTargetItems
            .filter { !$0.identifier.isEmpty }
            .compactMap { target in
                itemOption(matching: target.identifier, baseIdentifier: target.baseIdentifier)?.name
            }
        guard !names.isEmpty else {
            return String(
                localized: "While this trigger is on, it controls its target's section and your saved layout no longer applies to it."
            )
        }
        let list = ListFormatter.localizedString(byJoining: names)
        return names.count == 1
            ? String(localized: "This trigger controls \(list)'s section. Your saved layout no longer applies to it.")
            : String(localized: "This trigger controls the section of \(list). Your saved layout no longer applies to them.")
    }

    private var conflictWarning: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Another enabled trigger also targets this item. Priority runs top to bottom; the first active trigger wins.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func overriddenWarning(names: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.orange)
            Text("Overridden by \(names.joined(separator: ", ")). Move this trigger above them to give it priority.")
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
        case .bluetoothPicker:
            BluetoothDevicePicker(
                name: textBinding,
                options: bluetoothOptions,
                refreshOptions: refreshBluetoothOptions,
                focusedField: focusedField,
                focusID: "bt-\(trigger.id)"
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
            ScriptConditionEditor(condition: $trigger.condition, focusedField: focusedField, focusID: "c0-\(trigger.id)")
        case .imageComparison:
            ImageConditionEditor(condition: $trigger.condition, itemOptions: itemOptions, captureReference: captureReference)
        case .itemPicker:
            AttentionConditionEditor(condition: $trigger.condition, itemOptions: itemOptions)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var sectionPickers: some View {
        IcePicker("Show in", selection: $trigger.revealSection) {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                Text(section.triggerPickerDisplayString).tag(section)
            }
        }
        IcePicker("Otherwise hide in", selection: $trigger.hideSection) {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                Text(section.triggerPickerDisplayString).tag(section)
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
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
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
            ScheduleWeekdayPicker(selection: scheduleWeekdaysBinding)
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
                Text("Turn on Location in Trigger Sources and grant permission to capture your current location.")
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

    private var energyModeBinding: Binding<EnergyModeMatch> {
        Binding(
            get: { trigger.condition.energyModeMatch ?? .low },
            set: { trigger.condition = trigger.condition.withEnergyMode($0) }
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
                guard newValue != trigger.itemIdentifier else { return }
                trigger.itemIdentifier = newValue
                if let match = itemOptions.first(where: { $0.id == newValue }) {
                    trigger.itemDisplayName = match.name
                    trigger.itemBaseIdentifier = match.baseIdentifier
                } else {
                    trigger.itemBaseIdentifier = nil
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
                clearTriggerEditorFocus(focusedField)
            }
        )
    }

    private var scheduleWeekdaysBinding: Binding<Set<ScheduleWeekday>> {
        Binding(
            get: { trigger.condition.scheduleWeekdays ?? ScheduleWeekday.everyDay },
            set: { trigger.condition = trigger.condition.withScheduleWeekdays($0) }
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
