//
//  TriggersSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Option value types

/// A stable, value-type representation of a menu bar item that can be
/// targeted by a trigger. Decoupling the picker's options from the live
/// item cache keeps the SwiftUI `Picker` from rebuilding (and dropping an
/// in-progress selection) on every cache publish.
struct TriggerItemOption: Hashable {
    let id: String
    let name: String
    let baseIdentifier: String
}

/// A paired Bluetooth device offered in the device-condition picker.
struct TriggerBluetoothOption: Hashable {
    let name: String
    let isConnected: Bool

    var displayString: String {
        isConnected ? "\(name) (connected)" : name
    }
}

/// A running application offered in the app-condition picker.
struct TriggerAppOption: Hashable {
    let bundleID: String
    let name: String
}

private enum TriggerListDisplayMode: String, CaseIterable, Identifiable {
    case expanded
    case compact

    var id: Self {
        self
    }

    var label: String {
        switch self {
        case .expanded: "Expanded"
        case .compact: "Compact"
        }
    }
}

private enum TriggerDropIndicatorPlacement {
    case above
    case below
}

private struct TriggerDropIndicator: Equatable {
    let targetID: UUID
    let placement: TriggerDropIndicatorPlacement
}

private extension UTType {
    static let thawTriggerPriority = UTType(exportedAs: "com.stonerl.Thaw.trigger-priority")
}

private func clearTriggerEditorFocus(_ focusedField: FocusState<String?>.Binding) {
    focusedField.wrappedValue = nil
    DispatchQueue.main.async {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

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
            "A required trigger source is disabled in Developer settings."
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

// MARK: - TriggersSettingsPane

/// Settings pane for configuring conditional menu bar item triggers.
struct TriggersSettingsPane: View {
    var manager: MenuBarItemTriggersManager
    private var flags: TriggerFeatureFlagsManager

    /// A plain reference, not an @ObservedObject: observing the item manager
    /// would re-render the pane on every item cache publish, stealing focus.
    let itemManager: MenuBarItemManager

    @State private var itemOptions: [TriggerItemOption] = []
    @State private var appOptions: [TriggerAppOption] = []
    @State private var bluetoothOptions: [TriggerBluetoothOption] = []
    @State private var draggedTriggerID: UUID?
    @State private var dropIndicator: TriggerDropIndicator?
    @State private var dragCleanupTask: Task<Void, Never>?
    @State private var listDisplayMode: TriggerListDisplayMode = .expanded
    @State private var expandedCompactTriggerIDs = Set<UUID>()

    /// Composite key ("name-<id>" / "text-<id>") of the focused text field.
    @FocusState private var focusedField: String?

    init(manager: MenuBarItemTriggersManager, itemManager: MenuBarItemManager) {
        self.manager = manager
        self.itemManager = itemManager
        flags = manager.featureFlags
    }

    var body: some View {
        IceForm {
            introSection

            if manager.triggers.isEmpty {
                emptyState
            } else {
                listDisplayControls

                let conflicts = conflictingTriggerIDs()
                let kinds = enabledKinds()
                ForEach(Array(manager.triggers.enumerated()), id: \.element.id) { index, trigger in
                    let isCompactMode = listDisplayMode == .compact
                    TriggerRow(
                        trigger: triggerBinding(for: trigger.id),
                        itemOptions: itemOptions,
                        appOptions: appOptions,
                        bluetoothOptions: bluetoothOptions,
                        refreshBluetoothOptions: refreshBluetoothOptions,
                        enabledKinds: kinds,
                        compoundEnabled: flags.isEnabled(.compoundConditions),
                        invertEnabled: flags.isEnabled(.invertAction),
                        advancedEnabled: flags.isEnabled(.advancedOptions),
                        conditionActive: allConditionsActive(trigger),
                        liveStatus: manager.runtimeStatus(for: trigger),
                        hasConflict: conflicts.contains(trigger.id),
                        priorityNumber: index + 1,
                        canMoveUp: index > 0,
                        canMoveDown: index < manager.triggers.count - 1,
                        onMoveUp: { manager.moveTrigger(from: index, to: index - 1) },
                        onMoveDown: { manager.moveTrigger(from: index, to: index + 1) },
                        allowsCollapseToggle: isCompactMode,
                        isCollapsed: isCompactMode && !expandedCompactTriggerIDs.contains(trigger.id),
                        isDragging: draggedTriggerID == trigger.id,
                        dropIndicatorPlacement: dropIndicator?.targetID == trigger.id ? dropIndicator?.placement : nil,
                        onToggleCollapsedExpansion: { toggleCompactExpansion(for: trigger.id) },
                        dragProvider: {
                            dragProvider(for: trigger.id)
                        },
                        currentCoordinate: { manager.systemMonitor.currentCoordinate },
                        captureReference: { await manager.captureReferenceHash(forItemIdentifier: $0) },
                        focusedField: $focusedField,
                        onDelete: { manager.remove(id: trigger.id) }
                    )
                    .onDrop(
                        of: [.thawTriggerPriority],
                        delegate: TriggerPriorityDropDelegate(
                            targetID: trigger.id,
                            manager: manager,
                            draggedTriggerID: $draggedTriggerID,
                            dropIndicator: $dropIndicator
                        )
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
            refreshBluetoothOptions()
        }
        .onChange(of: itemManager.itemCache) { _, _ in
            refreshItemOptions()
        }
        .onChange(of: flags.isEnabled(.bluetooth)) { _, _ in
            refreshBluetoothOptions()
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.didLaunchApplicationNotification
            )
        ) { _ in
            refreshAppOptions()
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.didTerminateApplicationNotification
            )
        ) { _ in
            refreshAppOptions()
        }
        .onChange(of: listDisplayMode) { _, newValue in
            if newValue == .expanded {
                expandedCompactTriggerIDs.removeAll()
            }
        }
    }

    /// Item identifiers targeted by more than one enabled trigger.
    private func conflictingTriggerIDs() -> Set<UUID> {
        let presentIdentifiers = Set(itemOptions.map(\.id))
        let presentIdentifierBases = Dictionary(
            itemOptions.map { ($0.id, $0.baseIdentifier) },
            uniquingKeysWith: { first, _ in first }
        )
        var ownersByIdentifier = [String: Set<UUID>]()
        for trigger in manager.triggers where trigger.isEnabled {
            var resolvedTargets = Set<String>()
            for target in trigger.allTargetItems {
                let resolved = MenuBarItemTriggersManager.resolvedPresentIdentifier(
                    for: target.identifier,
                    capturedBaseIdentifier: target.baseIdentifier,
                    presentIdentifiers: presentIdentifiers,
                    presentIdentifierBases: presentIdentifierBases
                ) ?? target.identifier
                if !resolved.isEmpty {
                    resolvedTargets.insert(resolved)
                }
            }
            for identifier in resolvedTargets {
                ownersByIdentifier[identifier, default: []].insert(trigger.id)
            }
        }
        return ownersByIdentifier.values
            .filter { $0.count > 1 }
            .reduce(into: Set<UUID>()) { result, ids in
                result.formUnion(ids)
            }
    }

    private func dragProvider(for triggerID: UUID) -> NSItemProvider {
        draggedTriggerID = triggerID
        dropIndicator = nil
        dragCleanupTask?.cancel()
        dragCleanupTask = Task { @MainActor in
            while !Task.isCancelled, MouseHelpers.isButtonPressed() {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled, draggedTriggerID == triggerID else { return }
            draggedTriggerID = nil
            dropIndicator = nil
        }
        let data = Data(triggerID.uuidString.utf8) as NSData
        return NSItemProvider(item: data, typeIdentifier: UTType.thawTriggerPriority.identifier)
    }

    private func triggerBinding(for id: UUID) -> Binding<MenuBarItemTrigger> {
        Binding(
            get: {
                manager.triggers.first(where: { $0.id == id }) ?? MenuBarItemTrigger(id: id)
            },
            set: { updated in
                manager.update(updated)
            }
        )
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
            return TriggerItemOption(
                id: item.tag.tagIdentifier,
                name: name,
                baseIdentifier: item.tag.stableIdentifierBase
            )
        }
        options.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if options != itemOptions {
            itemOptions = options
        }
    }

    /// Refreshed when the pane appears, alongside the app list. The
    /// connected annotation can go stale while the pane stays open; the names
    /// themselves, which are what the matcher uses, do not.
    private func refreshBluetoothOptions() {
        // Gated like every other Bluetooth read: a disabled source costs
        // nothing, and the picker is only reachable once the flag is on.
        guard flags.isEnabled(.bluetooth) else {
            bluetoothOptions = []
            return
        }
        // Off the main thread: `pairedDevices()` blocks on a semaphore inside
        // IOBluetooth's CoreBluetooth coordinator, and on a Mac that has not
        // granted Bluetooth access the same call raises a TCC prompt. Doing
        // that on the main thread stalls the settings window behind a prompt
        // it is also responsible for drawing.
        Task.detached(priority: .userInitiated) {
            let devices = SystemStateMonitor.pairedBluetoothDeviceNames()
            let options = devices.map {
                TriggerBluetoothOption(name: $0.name, isConnected: $0.isConnected)
            }
            await MainActor.run {
                bluetoothOptions = options
            }
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
        IceSection() {
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
        IceSection() {
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

    private var listDisplayControls: some View {
        IceSection() {
            HStack(spacing: 12) {
                Text("Trigger list")
                    .font(.headline)

                Spacer(minLength: 12)

                Picker("Trigger list view", selection: $listDisplayMode) {
                    ForEach(TriggerListDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(8)
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
            itemBaseIdentifier: firstItem?.baseIdentifier,
            revealSection: .visible,
            hideSection: .hidden,
            condition: .batteryBelow(percentage: 20)
        )
        manager.add(trigger)
    }

    private func toggleCompactExpansion(for id: UUID) {
        if expandedCompactTriggerIDs.contains(id) {
            expandedCompactTriggerIDs.remove(id)
        } else {
            expandedCompactTriggerIDs.insert(id)
        }
    }
}

// MARK: - Trigger Priority Reordering

private struct TriggerPriorityDropDelegate: DropDelegate {
    let targetID: UUID
    let manager: MenuBarItemTriggersManager
    @Binding var draggedTriggerID: UUID?
    @Binding var dropIndicator: TriggerDropIndicator?

    func dropEntered(info: DropInfo) {
        guard info.hasItemsConforming(to: [.thawTriggerPriority]) else { return }
        guard let draggedTriggerID, draggedTriggerID != targetID else { return }
        updateDropIndicator(for: draggedTriggerID)
        manager.moveTrigger(id: draggedTriggerID, before: targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard info.hasItemsConforming(to: [.thawTriggerPriority]) else {
            return DropProposal(operation: .cancel)
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.thawTriggerPriority]) else { return false }
        draggedTriggerID = nil
        dropIndicator = nil
        return true
    }

    func dropExited(info _: DropInfo) {
        if dropIndicator?.targetID == targetID {
            dropIndicator = nil
        }
    }

    private func updateDropIndicator(for draggedTriggerID: UUID) {
        guard
            let sourceIndex = manager.triggers.firstIndex(where: { $0.id == draggedTriggerID }),
            let targetIndex = manager.triggers.firstIndex(where: { $0.id == targetID }),
            sourceIndex != targetIndex
        else {
            dropIndicator = nil
            return
        }

        let placement: TriggerDropIndicatorPlacement = sourceIndex < targetIndex ? .below : .above
        dropIndicator = TriggerDropIndicator(targetID: targetID, placement: placement)
    }
}

// MARK: - TriggerRow

/// An inline editor for a single ``MenuBarItemTrigger``.
private struct TriggerRow: View {
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
    let captureReference: (String) async -> UInt64?
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
        if !trigger.itemDisplayName.isEmpty { return trigger.itemDisplayName }
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
        IceSection() {
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.secondary.opacity(0.25))
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
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
                HStack(spacing: 8) {
                    IcePicker("Also move", selection: additionalItemBinding(index)) {
                        let currentItem = trigger.additionalItems[index]
                        let current = currentItem.identifier
                        let resolvedItem = itemOption(
                            matching: current,
                            baseIdentifier: currentItem.baseIdentifier
                        )
                        if !current.isEmpty, resolvedItem == nil {
                            Text("\(trigger.additionalItems[index].displayName) (not present)").tag(current)
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

    /// Whether the Match control is shown.
    ///
    /// Shown whenever compound conditions are available — `None of` negates a
    /// single condition, so it is useful before a second one exists — and
    /// always shown when the combinator is not the default, so a setting can
    /// never be left applied with no control to see or undo it.
    private var showsCombinatorPicker: Bool {
        compoundEnabled || trigger.combinator != .all
    }

    /// The combinators offered. With a single condition, "All of" and
    /// "Any of" are indistinguishable no-ops, so only the meaningful pair is
    /// shown — plus the current selection, which is never hidden.
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

            // Existing extra conditions render even when the compound flag is
            // off: `shouldReveal` still evaluates them, and the editor never
            // hides an existing selection behind a disabled flag. Only the
            // Add button below is flag-gated.
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
            Text("This condition is turned off in Developer settings, so the trigger won't run.")
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
        case .none:
            EmptyView()
        }
    }

    private var sectionPickers: some View {
        Group {
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

// MARK: - ConditionEditorView

/// A self-contained editor for one ``TriggerCondition`` (kind picker plus the
/// kind-specific editor). Used for a trigger's additional compound
/// conditions; the primary condition is edited inline by ``TriggerRow``.
private struct ConditionEditorView: View {
    @Binding var condition: TriggerCondition
    let kinds: [TriggerConditionKind]
    let appOptions: [TriggerAppOption]
    let bluetoothOptions: [TriggerBluetoothOption]
    let refreshBluetoothOptions: () -> Void
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

// MARK: - BluetoothDevicePicker

/// The Bluetooth device picker, shared by the trigger row and the compound
/// condition editor.
///
/// Offers the names the matcher actually compares against. A device's classic
/// Bluetooth name is not always the one System Settings shows — an AirPods set
/// can report a generic model name — so a typed guess can silently never
/// match. "Other…" keeps a device that isn't paired right now reachable.
private struct BluetoothDevicePicker: View {
    @Binding var name: String
    let options: [TriggerBluetoothOption]
    let refreshOptions: () -> Void
    var focusedField: FocusState<String?>.Binding
    let focusID: String

    /// Tags the "Other…" row. Prefixed with a control character so it can
    /// never collide with a real device name.
    private static let customTag = "\u{1}custom"

    /// Set when the user picks "Other…" while the current value is a listed
    /// device, which `isUnlisted` alone cannot detect.
    @State private var prefersCustomEntry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IcePicker("Device", selection: selection) {
                if name.isEmpty {
                    Text("Choose a device…").tag("")
                }
                ForEach(options, id: \.name) { option in
                    Text(option.displayString).tag(option.name)
                }
                Text("Other…").tag(Self.customTag)
            }
            if showsTextField {
                CommitTextField(
                    title: "Device name",
                    prompt: "Device name",
                    value: $name,
                    focusedField: focusedField,
                    focusID: focusID
                )
            }
        }
        // The condition rows are keyed by index, so deleting one shifts the
        // next into this view's identity, carrying this state with it. Clear
        // it whenever the value we are bound to names a listed device, which
        // covers both that shift and an ordinary edit.
        .onChange(of: name, initial: true) { _, newValue in
            if options.contains(where: { $0.name == newValue }) {
                prefersCustomEntry = false
            }
        }
        // Re-enumerate whenever this picker appears: the pane's own refresh
        // ran at pane-appearance, which predates a kind switched to
        // Bluetooth, a device paired since, or an access grant.
        .onAppear(perform: refreshOptions)
    }

    /// A configured name that no longer appears in the list — an unpaired
    /// device, or a value typed before this picker existed. Never hidden, or
    /// opening the editor would quietly discard it.
    private var isUnlisted: Bool {
        !name.isEmpty && !options.contains { $0.name == name }
    }

    private var showsTextField: Bool {
        prefersCustomEntry || isUnlisted
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                if showsTextField { return Self.customTag }
                return name
            },
            set: { newValue in
                if newValue == Self.customTag {
                    prefersCustomEntry = true
                } else {
                    prefersCustomEntry = false
                    name = newValue
                }
            }
        )
    }
}

// MARK: - EnergyModePicker

/// The Energy Mode picker, shared by the trigger row and the compound
/// condition editor.
private struct EnergyModePicker: View {
    @Binding var match: EnergyModeMatch

    var body: some View {
        IcePicker("Mode", selection: $match) {
            ForEach(options) { option in
                Text(option.displayString).tag(option)
            }
        }
    }

    /// High Power is offered only on Macs that have it. A trigger already
    /// set to High Power keeps showing it either way, so moving settings
    /// between Macs never silently rewrites the selection.
    private var options: [EnergyModeMatch] {
        let selectable = EnergyModeMatch.selectableCases(
            highPowerModeSupported: EnergyModeMonitor.isHighPowerModeSupported
        )
        return selectable.contains(match) ? selectable : selectable + [match]
    }
}

// MARK: - ScheduleWeekdayPicker

private struct ScheduleWeekdayPicker: View {
    @Binding var selection: Set<ScheduleWeekday>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ScheduleWeekday.allCases) { weekday in
                Button {
                    toggle(weekday)
                } label: {
                    Text(weekday.shortTitle)
                        .font(.caption)
                        .fontWeight(selection.contains(weekday) ? .semibold : .regular)
                        .frame(minWidth: 32)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection.contains(weekday) ? Color.white : Color.primary)
                .background(selection.contains(weekday) ? Color.orange : Color.secondary.opacity(0.12), in: Capsule())
                .accessibilityLabel(Text(weekday.shortTitle))
            }
        }
    }

    private func toggle(_ weekday: ScheduleWeekday) {
        if selection.contains(weekday) {
            guard selection.count > 1 else { return }
            selection.remove(weekday)
        } else {
            selection.insert(weekday)
        }
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

    private var watchedID: String {
        condition.imageValue?.itemIdentifier ?? ""
    }

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
            .disabled(isCapturing)

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
            if let hash, watchedID == id {
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
