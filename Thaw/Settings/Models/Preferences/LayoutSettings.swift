//
//  LayoutSettings.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import MenuBarModel
import Observation

/// Model for the Layout page's settings.
@MainActor
@Observable
final class LayoutSettings: SettingsURIHandling {
    var enableAlwaysHiddenSection = Defaults.DefaultValue.enableAlwaysHiddenSection {
        didSet {
            guard oldValue != enableAlwaysHiddenSection else { return }
            Defaults.set(enableAlwaysHiddenSection, forKey: .enableAlwaysHiddenSection)
        }
    }

    /// The effective state of the always-hidden section. Route behavior through
    /// this, not the raw enableAlwaysHiddenSection.
    var isAlwaysHiddenSectionEnabled: Bool {
        enableAlwaysHiddenSection
    }

    var showAllSectionsOnUserDrag = Defaults.DefaultValue.showAllSectionsOnUserDrag {
        didSet {
            guard oldValue != showAllSectionsOnUserDrag else { return }
            Defaults.set(showAllSectionsOnUserDrag, forKey: .showAllSectionsOnUserDrag)
        }
    }

    var sectionDividerStyle = Defaults.DefaultValue.sectionDividerStyle {
        didSet {
            guard oldValue != sectionDividerStyle else { return }
            Defaults.set(sectionDividerStyle.rawValue, forKey: .sectionDividerStyle)
        }
    }

    /// The image a Custom section divider draws, or nil before one is chosen.
    var customSectionDividerImage: Data? {
        didSet {
            guard oldValue != customSectionDividerImage else { return }
            if let customSectionDividerImage {
                Defaults.set(customSectionDividerImage, forKey: .customSectionDividerImage)
            } else {
                Defaults.removeObject(forKey: .customSectionDividerImage)
            }
        }
    }

    var customSectionDividerIsTemplate = Defaults.DefaultValue.customSectionDividerIsTemplate {
        didSet {
            guard oldValue != customSectionDividerIsTemplate else { return }
            Defaults.set(customSectionDividerIsTemplate, forKey: .customSectionDividerIsTemplate)
        }
    }

    /// Manual arrangement disables moves and position-table writes, but keeps hiding and revealing.
    var menuBarArrangementMode = Defaults.DefaultValue.menuBarArrangementMode {
        didSet {
            guard oldValue != menuBarArrangementMode else { return }
            Defaults.set(menuBarArrangementMode.rawValue, forKey: .menuBarArrangementMode)
            if menuBarArrangementMode == .manual {
                // Switching to Manual keeps the sections set in Layout, since the stored
                // weights of concealed items can be out of date.
                appState?.itemManager.scheduleObservedMembershipAdoption(reason: "switched to Manual", keepingAuthored: true)
            }
        }
    }

    /// Move non-fitting Visible items to Hidden only on notched displays.
    /// didSet rebalances only on changes; item-cache updates handle the launch-time pass.
    var enableMenuBarItemOverflow = Defaults.DefaultValue.enableMenuBarItemOverflow {
        didSet {
            guard oldValue != enableMenuBarItemOverflow else { return }
            Defaults.set(enableMenuBarItemOverflow, forKey: .enableMenuBarItemOverflow)
            Task { @MainActor [weak self] in
                guard let itemManager = self?.appState?.itemManager else { return }
                itemManager.repairs.request(.overflowRebalance, cause: .settingChanged)
                guard let hold = await itemManager.repairs.enter(.overflowRebalance, priority: .user) else {
                    return
                }
                let aftermath = RepairTurn.Aftermath()
                let didRebalance = await itemManager.rebalanceOverflowIfNeeded(
                    reason: .settingChange,
                    aftermath: aftermath,
                    permit: StoreWritePermit(hold)
                )
                itemManager.repairs.leave(hold)
                // One read covers both the pass's own closing read and the one a change asks for.
                if didRebalance || aftermath.needsCachePass {
                    await itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
                }
            }
        }
    }

    /// Extreme hidden-item weights try to make native overflow collapse them first on macOS 27 notched displays.
    /// Experimental URI/Defaults-only control has no Settings or search entry; see SearchIndex.nonSearchableProperties.
    var enableExperimentalOverflowPrevention = Defaults.DefaultValue.enableExperimentalOverflowPrevention {
        didSet {
            guard oldValue != enableExperimentalOverflowPrevention else { return }
            Defaults.set(enableExperimentalOverflowPrevention, forKey: .enableExperimentalOverflowPrevention)
        }
    }

    /// Opt-in alternative to the assessment assertion. Native app visibility
    /// persists outside Thaw, so the experiment journals and restores its writes.
    var enableNativeAppHiding = Defaults.DefaultValue.enableNativeAppHiding {
        didSet {
            guard oldValue != enableNativeAppHiding else { return }
            Defaults.set(enableNativeAppHiding, forKey: .enableNativeAppHiding)
            appState?.menuBarManager.sectionController.refresh()
        }
    }

    /// Clock, Control Center and Siri need the assertion native hiding releases, so this is on exactly when native hiding is off.
    /// Derived, not stored: a value an older build saved under its Defaults key is never read.
    var enableExperimentalSystemItemHiding: Bool {
        HidingMethod(nativeAppHidingEnabled: enableNativeAppHiding).hidesAppleItems
    }

    /// App-icon rendering avoids macOS 27 overflow-control bleed in Thaw Bar and layout captures.
    /// Only affects those previews, not the system menu bar.
    var alwaysUseAppIconForMenuBarItems = Defaults.DefaultValue.alwaysUseAppIconForMenuBarItems {
        didSet {
            guard oldValue != alwaysUseAppIconForMenuBarItems else { return }
            Defaults.set(alwaysUseAppIconForMenuBarItems, forKey: .alwaysUseAppIconForMenuBarItems)
        }
    }

    /// Movable, hideable stand-ins replace Focus, AirDrop, Now Playing, and Fast User Switching.
    /// macOS hides their originals whenever another item is hidden, even if assigned Visible.
    var enableModuleStandIns = Defaults.DefaultValue.enableModuleStandIns {
        didSet {
            guard oldValue != enableModuleStandIns else { return }
            Defaults.set(enableModuleStandIns, forKey: .enableModuleStandIns)
        }
    }

    /// The modules enableModuleStandIns leaves as Apple's own.
    var skippedModuleStandIns: Set<String> = Set(Defaults.DefaultValue.skippedModuleStandIns) {
        didSet {
            guard oldValue != skippedModuleStandIns else { return }
            Defaults.set(skippedModuleStandIns.sorted(), forKey: .skippedModuleStandIns)
        }
    }

    /// Replace hidden Time Machine with a stand-in; restore the original on Visible assignment, disable, or quit.
    var enableTimeMachineTakeover = Defaults.DefaultValue.enableTimeMachineTakeover {
        didSet {
            guard oldValue != enableTimeMachineTakeover else { return }
            Defaults.set(enableTimeMachineTakeover, forKey: .enableTimeMachineTakeover)
        }
    }

    /// The Timer counterpart of enableTimeMachineTakeover. Reports itself
    /// unavailable until Timer has a verified switch.
    var enableTimerTakeover = Defaults.DefaultValue.enableTimerTakeover {
        didSet {
            guard oldValue != enableTimerTakeover else { return }
            Defaults.set(enableTimerTakeover, forKey: .enableTimerTakeover)
        }
    }

    /// Removes the Input menu through its own switch and puts a Thaw stand-in
    /// in its place that can be hidden and moved like any item.
    var enableTextInputTakeover = Defaults.DefaultValue.enableTextInputTakeover {
        didSet {
            guard oldValue != enableTextInputTakeover else { return }
            Defaults.set(enableTextInputTakeover, forKey: .enableTextInputTakeover)
        }
    }

    /// Maximum time to wait for MenuBarAgent to apply a preferred-position
    /// reorder before Thaw continues with residual reconciliation.
    var menuBarOrderFulfillmentTimeout = Defaults.DefaultValue.menuBarOrderFulfillmentTimeout {
        didSet {
            guard oldValue != menuBarOrderFulfillmentTimeout else { return }
            Defaults.set(menuBarOrderFulfillmentTimeout, forKey: .menuBarOrderFulfillmentTimeout)
        }
    }

    /// The interval between icon image refreshes in panels (Thaw Bar, search, layout).
    var iconRefreshInterval = Defaults.DefaultValue.iconRefreshInterval {
        didSet {
            guard oldValue != iconRefreshInterval else { return }
            Defaults.set(iconRefreshInterval, forKey: .iconRefreshInterval)
        }
    }

    @ObservationIgnored
    private var settingsURIChanges: AnyCancellable?

    @ObservationIgnored
    private(set) weak var appState: AppState?

    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        settingsURIChanges = subscribeToSettingsURIChanges()
    }

    /// Reads the stored values.
    func loadInitialState() {
        Defaults.ifPresent(key: .enableAlwaysHiddenSection, assign: &enableAlwaysHiddenSection)
        Defaults.ifPresent(key: .showAllSectionsOnUserDrag, assign: &showAllSectionsOnUserDrag)
        Defaults.ifPresent(key: .iconRefreshInterval, assign: &iconRefreshInterval)
        Defaults.ifPresent(key: .enableMenuBarItemOverflow, assign: &enableMenuBarItemOverflow)
        Defaults.ifPresent(key: .enableNativeAppHiding, assign: &enableNativeAppHiding)
        Defaults.ifPresent(key: .enableExperimentalOverflowPrevention, assign: &enableExperimentalOverflowPrevention)
        Defaults.ifPresent(key: .alwaysUseAppIconForMenuBarItems, assign: &alwaysUseAppIconForMenuBarItems)
        Defaults.ifPresent(key: .enableModuleStandIns, assign: &enableModuleStandIns)
        skippedModuleStandIns = Defaults.stringArray(forKey: .skippedModuleStandIns).map(Set.init) ?? skippedModuleStandIns
        Defaults.ifPresent(key: .enableTimeMachineTakeover, assign: &enableTimeMachineTakeover)
        Defaults.ifPresent(key: .enableTimerTakeover, assign: &enableTimerTakeover)
        Defaults.ifPresent(key: .enableTextInputTakeover, assign: &enableTextInputTakeover)
        Defaults.ifPresent(key: .menuBarOrderFulfillmentTimeout, assign: &menuBarOrderFulfillmentTimeout)
        Defaults.ifPresent(key: .sectionDividerStyle) { rawValue in
            if let style = SectionDividerStyle(rawValue: rawValue) {
                sectionDividerStyle = style
            }
        }
        customSectionDividerImage = Defaults.data(forKey: .customSectionDividerImage)
        Defaults.ifPresent(key: .customSectionDividerIsTemplate, assign: &customSectionDividerIsTemplate)
        Defaults.ifPresent(key: .menuBarArrangementMode) { rawValue in
            if let mode = MenuBarArrangementMode(rawValue: rawValue) {
                menuBarArrangementMode = mode
            }
        }
    }

    /// The thaw:// keys of this page's Bool settings.
    private static let uriBoolKeys: [String: ReferenceWritableKeyPath<LayoutSettings, Bool>] = [
        "enableAlwaysHiddenSection": \.enableAlwaysHiddenSection,
        "showAllSectionsOnUserDrag": \.showAllSectionsOnUserDrag,
        "enableMenuBarItemOverflow": \.enableMenuBarItemOverflow,
        "enableExperimentalOverflowPrevention": \.enableExperimentalOverflowPrevention,
        "alwaysUseAppIconForMenuBarItems": \.alwaysUseAppIconForMenuBarItems,
    ]

    /// The thaw:// keys of this page's Double settings.
    private static let uriDoubleKeys: [String: ReferenceWritableKeyPath<LayoutSettings, Double>] = [
        "iconRefreshInterval": \.iconRefreshInterval,
        "menuBarOrderFulfillmentTimeout": \.menuBarOrderFulfillmentTimeout,
    ]

    /// Applies a thaw:// settings change for one of this page's keys.
    func handleExternalSettingsChange(_ notification: Notification) {
        applySettingsURIChange(notification, bools: Self.uriBoolKeys, doubles: Self.uriDoubleKeys)
    }
}
