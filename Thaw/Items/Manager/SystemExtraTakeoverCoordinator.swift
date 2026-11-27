//
//  SystemExtraTakeoverCoordinator.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import MenuBarModel
import Observation
import PlatformRuntimeKit

/// The section controller calls the stand-ins make, so tests can drive them without the live bar.
protocol StandInSectionControlling: AnyObject {
    var sectionAssignment: [String: MenuBarSectionName] { get }
    var sectionItemOrder: [MenuBarSectionName: [String]] { get }
    /// Fires whenever the assignment or the order changes.
    var layoutChanges: AnyPublisher<Void, Never> { get }
    func authoredSection(for identifier: String) -> MenuBarSectionName
    func setSection(_ section: MenuBarSectionName, identifier: String)
    func setSectionOrder(_ identifiers: [String], for section: MenuBarSectionName)
    /// Originals with a stand-in, which stay hidden through reveals.
    func setReplacedItems(_ identifiers: Set<String>)
}

extension RuntimeSectionController: StandInSectionControlling {
    var layoutChanges: AnyPublisher<Void, Never> {
        Publishers.CombineLatest($sectionAssignment, $sectionItemOrder).map { _ in () }.eraseToAnyPublisher()
    }
}

/// Feed SystemExtraTakeoverEngine from settings and authored layout, never geometry; Time Machine uses SystemUIServer.menuExtras and Timer remains unavailable without a verified switch.
/// Focus, AirDrop, Now Playing, and Fast User Switching bypass the engine: macOS hides them when any third-party item is hidden, even in Visible; enabled stand-ins assign originals Hidden, and disabling restores their stand-in sections.
/// Wi-Fi, Bluetooth and Sound take the same path, and their originals are also kept out of reveals.
@MainActor
@Observable
final class SystemExtraTakeoverCoordinator {
    let engine: SystemExtraTakeoverEngine

    @ObservationIgnored private weak var settings: LayoutSettings?
    @ObservationIgnored private weak var controller: (any StandInSectionControlling)?
    @ObservationIgnored private var observationTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var layoutSubscription: AnyCancellable?
    /// Shared with the Space indicator, so one spacing restart reaches every stand-in.
    @ObservationIgnored let launcher: SystemExtraStandInLauncher
    /// Observed, so the Thaw Bar, Layout and the settings process hear which originals are replaced.
    /// It is changed only where it really changes, since every write notifies them.
    private var activeModuleStandIns: Set<SystemExtraStandIn> = []
    @ObservationIgnored private let isShownInMenuBar: @MainActor (String) -> Bool

    /// The Control Center modules the runtime removes while hidden, keyed to
    /// their stand-ins, with the identifier the runtime gives each on macOS 27.
    private static let moduleOriginals: [SystemExtraStandIn: String] = [
        .focus: "com.apple.menuextra.focusmode",
        .airDrop: "com.apple.menuextra.airdrop",
        .nowPlaying: "com.apple.menuextra.now-playing",
        .userSwitcher: "com.apple.menuextra.user",
        .wiFi: "com.apple.menuextra.wifi",
        .bluetooth: "com.apple.menuextra.bluetooth",
        .sound: "com.apple.menuextra.sound",
    ].mapValues { MenuBarItemTag(namespace: .menuBarAgent, title: $0).tagIdentifier }

    /// Adapters, launcher and the Control Center read are parameters so tests reach no system setting or app.
    init(
        journal: any SystemExtraOriginalJournaling = FileSystemExtraOriginalJournal(),
        adapters: [SystemExtraItem: any SystemExtraNativeControlling]? = nil,
        launcher: SystemExtraStandInLauncher = SystemExtraStandInLauncher(),
        isShownInMenuBar: @escaping @MainActor (String) -> Bool = SystemExtraTakeoverCoordinator.isShownInMenuBar
    ) {
        self.launcher = launcher
        self.isShownInMenuBar = isShownInMenuBar
        engine = SystemExtraTakeoverEngine(
            adapters: adapters ?? Self.productionAdapters(),
            replacementProvider: launcher,
            journal: journal
        )
    }

    /// The app's answer, in the settings process, where no stand-in runs. Nil in the app.
    private var mirroredReplacedOriginals: Set<String>?

    /// The canonical identifiers of Apple's module items whose stand-in is running. See ReplacedOriginals.
    var replacedOriginalIdentifiers: Set<String> {
        mirroredReplacedOriginals ?? Self.originalIdentifiers(replacedBy: activeModuleStandIns)
    }

    /// Takes the app's answer, for the settings process: it previews the Thaw Bar and runs no stand-in.
    func mirrorReplacedOriginals(_ identifiers: Set<String>) {
        if identifiers != mirroredReplacedOriginals {
            mirroredReplacedOriginals = identifiers
        }
    }

    static func originalIdentifiers(replacedBy standIns: Set<SystemExtraStandIn>) -> Set<String> {
        Set(standIns.compactMap { moduleOriginals[$0] }.map(MenuBarItemTag.canonicalPersistentIdentifier))
    }

    /// Reading the engine's observable dictionary makes the Layout rows update live.
    func status(for item: SystemExtraItem) -> SystemExtraTakeoverStatus {
        engine.status(for: item)
    }

    /// Restores any journaled original from a previous session. Runs before the
    /// section controller starts, like the native app-hiding recovery.
    func recoverPreviousSession() {
        engine.recoverPreviousSession()
    }

    func start(
        controller: any StandInSectionControlling,
        settings: LayoutSettings,
        markKnown: @escaping (String) -> Void
    ) {
        self.controller = controller
        self.settings = settings
        launcher.controller = controller
        launcher.markKnown = markKnown
        StandInSpacingRestart.launcher = launcher

        for item in SystemExtraItem.allCases {
            observationTasks.append(Task { @MainActor [weak self] in
                guard let self else { return }
                let enabled = Observations { [weak self] in self?.isEnabled(item) ?? false }
                for await _ in enabled {
                    guard !Task.isCancelled else { return }
                    reconcile(item: item)
                }
            })
        }

        layoutSubscription = controller.layoutChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.mirrorStandInSections()
                self?.reconcileAll()
            }

        observationTasks.append(Task { @MainActor [weak self] in
            let enabled = Observations { [weak self] in
                (
                    self?.settings?.enableModuleStandIns ?? false,
                    self?.settings?.skippedModuleStandIns ?? [],
                    self?.settings?.optInStandIns ?? []
                )
            }
            for await _ in enabled {
                guard !Task.isCancelled else { return }
                self?.reconcileModules()
            }
        })

        reconcileAll()
    }

    func prepareForTermination() {
        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()
        layoutSubscription = nil
        engine.prepareForTermination()
    }

    // MARK: Reconcile

    private func reconcileAll() {
        for item in SystemExtraItem.allCases {
            reconcile(item: item)
        }
        reconcileModules()
    }

    private func reconcileModules() {
        guard let controller, let settings else { return }
        let saved = Set(controller.sectionItemOrder.values.joined())
        for (standIn, original) in Self.moduleOriginals {
            let originalID = MenuBarItemTag.canonicalPersistentIdentifier(original)
            let standInID = MenuBarItemTag.canonicalPersistentIdentifier(standIn.itemIdentifier)
            let originalSection = controller.authoredSection(for: originalID)
            // Once the original is assigned Hidden its preference reads as off,
            // so the assignment is what says the module is still wanted.
            let isWanted = originalSection != .visible || isShownInMenuBar(original)
            let isChosen = Self.isChosen(standIn, in: settings)
            guard isChosen, isWanted else {
                let wasActive = activeModuleStandIns.contains(standIn)
                if wasActive {
                    activeModuleStandIns.remove(standIn)
                    launcher.stop(standIn)
                }
                // A stand-in whose original was not in the saved order never joined one,
                // but it still took the original's place.
                if wasActive || saved.contains(standInID) {
                    retire(standInID, returningTo: originalID)
                }
                continue
            }
            guard !activeModuleStandIns.contains(standIn) else { continue }
            activeModuleStandIns.insert(standIn)
            // A stand-in placed in an earlier session keeps its section; a new
            // one starts where the original was.
            let section = saved.contains(standInID) ? controller.authoredSection(for: standInID) : originalSection
            Task { [weak self, launcher] in
                do {
                    try await launcher.launch(standIn, replacing: original, in: section)
                    // A stand-in placed in Visible changes no assignment, so
                    // the layout publisher would not hand the original over.
                    self?.mirrorStandInSections()
                } catch {
                    // Forgotten so the next reconcile tries again.
                    self?.activeModuleStandIns.remove(standIn)
                    self?.publishReplacedItems()
                    DiagLog(category: "SystemExtraStandIn")
                        .error("\(standIn.rawValue) stand-in failed: \(error.localizedDescription)")
                }
            }
        }
        publishReplacedItems()
    }

    /// Wi-Fi, Bluetooth and Sound are listed when on; the four modules list the ones skipped.
    static func isChosen(_ standIn: SystemExtraStandIn, in settings: LayoutSettings) -> Bool {
        switch standIn {
        case .wiFi, .bluetooth, .sound: settings.optInStandIns.contains(standIn.rawValue)
        default: settings.enableModuleStandIns && !settings.skippedModuleStandIns.contains(standIn.rawValue)
        }
    }

    /// Wi-Fi, Bluetooth and Sound would otherwise come back beside their stand-ins on every reveal.
    private func publishReplacedItems() {
        controller?.setReplacedItems(replacedOriginalIdentifiers)
    }

    /// Return the stand-in's section to the original once, including switches disabled between sessions, without undoing later moves.
    private func retire(_ standInID: String, returningTo originalID: String) {
        guard let controller else { return }
        let section = controller.authoredSection(for: standInID)
        controller.setSection(section, identifier: originalID)
        for (orderSection, identifiers) in controller.sectionItemOrder where identifiers.contains(standInID) {
            controller.setSectionOrder(identifiers.filter { $0 != standInID }, for: orderSection)
        }
    }

    /// Keep originals Hidden regardless of stand-in section; only placed stand-ins have taken over.
    private func mirrorStandInSections() {
        guard let controller else { return }
        for (standIn, original) in Self.moduleOriginals where launcher.placed.contains(standIn) {
            let originalID = MenuBarItemTag.canonicalPersistentIdentifier(original)
            if controller.authoredSection(for: originalID) == .visible {
                controller.setSection(.hidden, identifier: originalID)
            }
        }
    }

    /// Control Center's bit 2 means shown (2 always, 18 while active); missing keys mean not shown.
    static func isShownInMenuBar(_ original: String) -> Bool {
        let identifier = MenuBarItemTag.canonicalPersistentIdentifier(original)
        guard let title = RuntimeModuleController.controlCenterMenuExtraTitle(forItemIdentifier: identifier),
              let key = SystemMenuBarModuleCatalog.controlCenterKeysByMenuExtraTitle[title]
        else { return false }
        let value = CFPreferencesCopyValue(
            key as CFString,
            "com.apple.controlcenter" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? Int
        return value.map { $0 & RuntimeModuleController.shownValue != 0 } ?? false
    }

    /// Forced-visible SystemUIServer items require a switch, not Hidden placement, to trigger replacement; disabling returns originals.
    /// Stand-ins start in the original visible slot and retain subsequent user placement while enabled.
    private func reconcile(item: SystemExtraItem) {
        guard let controller else { return }
        let enabled = isEnabled(item)
        let standInID = MenuBarItemTag.canonicalPersistentIdentifier(SystemExtraStandIn(item).itemIdentifier)
        let assigned = controller.sectionAssignment[standInID] != nil
        engine.reconcile(
            item: item,
            configured: enabled,
            desiredOwn: enabled,
            section: assigned ? controller.authoredSection(for: standInID) : .visible
        )
    }

    private func isEnabled(_ item: SystemExtraItem) -> Bool {
        guard let settings else { return false }
        return switch item {
        case .timeMachine: settings.enableTimeMachineTakeover
        case .timer: settings.enableTimerTakeover
        case .textInput: settings.enableTextInputTakeover
        }
    }

    // MARK: Production adapters

    /// Timer appears only while running; keep it unavailable until a native visibility switch is verified.
    private static func productionAdapters() -> [SystemExtraItem: any SystemExtraNativeControlling] {
        [
            .timeMachine: TimeMachineMenuExtraAdapter(),
            .textInput: TextInputMenuAdapter(),
            .timer: UnavailableSystemExtraNativeAdapter(
                item: .timer,
                reason: "The Timer menu extra has no per-item native visibility setting on this macOS version, so the original is left untouched."
            ),
        ]
    }
}
