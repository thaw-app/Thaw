//
//  TriggersSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import AsyncAlgorithms
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Option value types

/// A value-type item option. Decoupled from the live cache so the `Picker`
/// doesn't rebuild and drop an in-progress selection on every cache publish.
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

enum TriggerDropIndicatorPlacement {
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

func clearTriggerEditorFocus(_ focusedField: FocusState<String?>.Binding) {
    focusedField.wrappedValue = nil
    DispatchQueue.main.async {
        NSApp.keyWindow?.makeFirstResponder(nil)
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
                        captureReference: { await manager.captureImageReference(forItemIdentifier: $0) },
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
        // Not `.onChange(of: itemManager.itemCache)`: reading it from `body` re-renders
        // the whole pane on every cache publish and steals focus mid-edit. `Observations`
        // from `.task` watches it without `body` (as in LayoutBarItemView), debounced.
        .task {
            let changes = Observations { itemManager.itemCache }
            for await _ in changes.debounce(for: .milliseconds(150)) {
                refreshItemOptions()
            }
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
        // Off the main thread: `pairedDevices()` blocks on a semaphore in IOBluetooth
        // and can raise a TCC prompt, which would stall the window that has to draw it.
        Task.detached(priority: .userInitiated) {
            let devices = SystemStateMonitor.pairedBluetoothDeviceNames()
            // Collapse by name, since the matcher compares names (two AirPods of the same
            // model, say). Connected wins, so a device in use is labelled as such.
            var connectedByName = [String: Bool]()
            for device in devices {
                connectedByName[device.name] = (connectedByName[device.name] ?? false) || device.isConnected
            }
            let options = connectedByName
                .sorted { $0.key < $1.key }
                .map { TriggerBluetoothOption(name: $0.key, isConnected: $0.value) }
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

        if options != appOptions {
            appOptions = options
        }
    }

    // MARK: Sections

    private var introSection: some View {
        IceSection {
            VStack(alignment: .leading, spacing: 6) {
                Text("Conditional Triggers")
                    .font(.headline)
                Text("Automatically reveal a menu bar item while a condition is met, then hide it again when the condition no longer applies. Turn on more condition types in Trigger Sources.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var emptyState: some View {
        IceSection {
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
        IceSection {
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

    /// Hovering only previews. `manager.triggers` persists in `didSet`, so committing
    /// here writes once per row crossed and keeps the hovered order on cancel.
    func dropEntered(info: DropInfo) {
        guard info.hasItemsConforming(to: [.thawTriggerPriority]) else { return }
        guard let draggedTriggerID, draggedTriggerID != targetID else { return }
        updateDropIndicator(for: draggedTriggerID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard info.hasItemsConforming(to: [.thawTriggerPriority]) else {
            return DropProposal(operation: .cancel)
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.thawTriggerPriority]) else { return false }
        defer {
            draggedTriggerID = nil
            dropIndicator = nil
        }
        guard let draggedTriggerID, draggedTriggerID != targetID else { return false }
        manager.moveTrigger(id: draggedTriggerID, before: targetID)
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
