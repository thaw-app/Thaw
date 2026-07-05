//
//  AssessmentModeBackend.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Real macOS 27 menu bar item hiding, via the private MenuBarClientCore
/// "Assessment Mode" visibility-restriction assertion (see
/// ``ThawAssessmentModeHidingActivate``).
///
/// The assertion is an **allowlist**: every menu bar item whose owner is not
/// listed is hidden and the bar reflows. Thaw's model is a *deny* set (the
/// items the user chose to hide), so this backend inverts it — allow every
/// running app except the owners of hidden items, keep all Apple core system
/// items, and preserve MenuBarAgent extras by their logical bundle IDs.
///
/// Granularity for third-party items is per owning app: the assertion allowlist
/// keys on bundle identifiers, so hiding *any* item of an app hides *all* of
/// that app's items as a group. In practice almost every app vends a single
/// menu bar item, so this matches user expectations.
///
/// For the rare multi-item app, this backend errs on the side of *not* hiding:
/// a bundle is concealed only when none of its currently-enumerated items are
/// assigned `.visible` (see ``apply(sectionAssignment:allItems:)``).
/// That keeps the visible items — and the Visible layout bar — truthful, at the
/// cost of an item assigned Hidden staying visible while a sibling is Visible.
/// When the private API is unavailable this backend is simply inert; there is no
/// fallback.
@MainActor
final class AssessmentModeBackend: ObservableObject {
    /// Whether the private assertion API is present on this system.
    static var isAvailable: Bool {
        ThawAssessmentModeHidingAvailable()
    }

    /// Observable mirror of ``isAvailable``, captured at init and refreshed by
    /// ``refreshAvailability()``. macOS can update while the app is running, so
    /// callers should re-check on `NSApplication.didBecomeActiveNotification`
    /// rather than trusting this forever.
    @Published private(set) var isHidingAvailable = AssessmentModeBackend.isAvailable

    /// Re-evaluates ``isAvailable`` and updates ``isHidingAvailable``. Returns
    /// the freshly-observed value.
    @discardableResult
    func refreshAvailability() -> Bool {
        let available = Self.isAvailable
        isHidingAvailable = available
        return available
    }

    /// The Apple system-item identifiers known to the Assessment Mode
    /// restriction.
    ///
    /// `MBSystemItemIdentifier` has exactly 9 cases, raw values 0...8 (battery,
    /// Bluetooth, clock, displays, keyboard, volume, Wi-Fi, screen mirroring, and
    /// the primary BentoBox). The 2026-06-18 probe proved this is the only useful
    /// value: widening past 8 maps to nothing (identical result), and an empty
    /// list hides ALL system items. Menu extras (AirDrop/Focus/User/NowPlaying)
    /// are not in this enum and cannot be preserved by the allowlist — that
    /// collateral is accepted. See [[macos27-system-item-hiding-approach]].
    static let allSystemItems: Set<Int> = Set(0 ... 8)

    /// The default Apple system-item identifiers kept visible by the Assessment
    /// Mode restriction.
    static let allowedSystemItems: [NSNumber] = allSystemItems
        .sorted()
        .map { NSNumber(value: $0) }

    /// Known `MBSystemItemIdentifier` raw values. Apple does not publish this
    /// enum; these values are intentionally best-effort and guarded by the
    /// experimental setting that opts into hiding system items.
    static func systemItemIdentifier(for tag: MenuBarItemTag) -> Int? {
        switch tag.title {
        case "Battery":
            return 0
        case "Bluetooth", "com.apple.menuextra.bluetooth":
            return 1
        case "Clock", "com.apple.menuextra.clock":
            return 2
        case "Displays", "Display", "com.apple.menuextra.displays":
            return 3
        case "Keyboard", "com.apple.menuextra.keyboard":
            return 4
        case "Sound", "Volume", "com.apple.menuextra.volume":
            return 5
        case "WiFi", "Wi-Fi", "com.apple.menuextra.wifi":
            return 6
        case "ScreenMirroring", "Screen Mirroring", "com.apple.menuextra.screenmirroring":
            return 7
        case "BentoBox-0", "ControlCenter", "com.apple.menuextra.controlcenter":
            return 8
        default:
            return nil
        }
    }

    private let diagLog = DiagLog(category: "AssessmentModeBackend")

    /// Bundles that own system menu extras that must be concealed via their
    /// system-item index (`concealedSystemItemIDs`) rather than the bundle path.
    /// Bundle-level concealment of these hosts would blank every item the host
    /// owns on each restriction reflow (the whole system side of the bar).
    ///
    /// `com.apple.MenuBarAgent` and `com.apple.controlcenter` are listed because
    /// they host many system items (Clock, Control Center, sound, …) each with a
    /// known `MBSystemItemIdentifier` raw value that the index path can conceal
    /// precisely. `com.apple.systemuiserver` is intentionally NOT listed here:
    /// on macOS 27 it hosts only Siri, which has no `MBSystemItemIdentifier` entry
    /// and therefore falls through to bundle-level concealment — the
    /// `bundlesWithVisibleItem` guard is sufficient to prevent collateral damage
    /// if a sibling ever appears.
    private static let systemHostBundleIDs: Set<String> = [
        "com.apple.MenuBarAgent",
        "com.apple.controlcenter",
    ]

    static func isSystemHostBundleID(_ bundleID: String) -> Bool {
        systemHostBundleIDs.contains(bundleID)
    }

    static func resolveConcealment(
        sectionAssignment: [String: MenuBarSection.Name],
        allItems: [MenuBarItem],
        knownBundleIDs: [String: String],
        knownSystemItemIDs: [String: Int],
        protectedBundleIDs: Set<String> = protectedBundleIDs,
        hidingUnsupportedBundleIDs: Set<String> = MenuBarItemTag.hidingUnsupportedBundleIDs
    ) -> (concealedBundleIDs: Set<String>, concealedSystemItemIDs: Set<Int>, allowedSystemItemSet: Set<Int>) {
        let concealed = Set(sectionAssignment.compactMap { identifier, section -> String? in
            switch section {
            case .visible:
                nil
            case .hidden, .alwaysHidden:
                identifier
            }
        })

        var bundlesWithVisibleItem = Set<String>()
        for item in allItems where !concealed.contains(item.uniqueIdentifier) {
            if let bundleID = knownBundleIDs[item.uniqueIdentifier] ?? item.sourceApplication?.bundleIdentifier {
                bundlesWithVisibleItem.insert(bundleID)
            }
        }

        var concealedBundleIDs = Set(concealed.compactMap { knownBundleIDs[$0] })
            .subtracting(bundlesWithVisibleItem)

        concealedBundleIDs.subtract(protectedBundleIDs)
        concealedBundleIDs.subtract(hidingUnsupportedBundleIDs)

        let dynamicSystemHostBundleIDs = Set(concealed.compactMap { identifier -> String? in
            guard knownSystemItemIDs[identifier] != nil else { return nil }
            return knownBundleIDs[identifier]
        })
        concealedBundleIDs.subtract(dynamicSystemHostBundleIDs)
        concealedBundleIDs.subtract(Self.systemHostBundleIDs)

        let concealedSystemItemIDs = Set(concealed.compactMap { knownSystemItemIDs[$0] })
        let allowedSystemItemSet = Self.allSystemItems.subtracting(concealedSystemItemIDs)
        return (concealedBundleIDs, concealedSystemItemIDs, allowedSystemItemSet)
    }

    static func shouldReactivate(
        handleIsNil: Bool,
        concealedChanged: Bool,
        systemItemsChanged: Bool,
        newlyAppeared: Bool,
        desiredAllowed: Set<String>,
        desiredSystemItems: Set<Int>,
        desiredConcealed: Set<String>,
        previousConfig: (allowed: Set<String>, systemItems: Set<Int>, concealed: Set<String>, at: ContinuousClock.Instant)?,
        lastFailed: (allowed: Set<String>, systemItems: Set<Int>)?,
        antiFlapWindow: Duration,
        now: ContinuousClock.Instant
    ) -> Bool {
        guard handleIsNil || concealedChanged || systemItemsChanged || newlyAppeared else { return false }

        if !handleIsNil,
           let previousConfig,
           previousConfig.allowed == desiredAllowed,
           previousConfig.systemItems == desiredSystemItems,
           previousConfig.concealed == desiredConcealed,
           previousConfig.at.duration(to: now) < antiFlapWindow
        {
            return false
        }

        if let lastFailed,
           desiredAllowed == lastFailed.allowed,
           desiredSystemItems == lastFailed.systemItems
        {
            return false
        }

        return true
    }

    /// The live assertion handle, or `nil` when nothing is hidden.
    private var handle: UnsafeMutableRawPointer?

    isolated deinit {
        if let handle {
            ThawAssessmentModeHidingInvalidate(handle)
        }
    }

    /// The concealed-app bundle IDs baked into the currently-active assertion.
    private var appliedConcealed: Set<String> = []

    /// The allowed-app bundle IDs baked into the currently-active assertion.
    private var appliedAllowed: Set<String> = []

    /// Learned `uniqueIdentifier → owning bundle ID` map. A concealed item drops
    /// out of AX enumeration entirely (the assertion removes it), so it would no
    /// longer appear in `allItems` and we'd lose its bundle ID — resetting the
    /// restriction and flickering it back on. Remembering the mapping from when
    /// the item *was* visible keeps it concealed across refreshes.
    private var knownBundleIDs: [String: String] = [:]

    /// Learned `uniqueIdentifier → MBSystemItemIdentifier raw value` map for
    /// Apple system items that can be hidden only by removing their raw value
    /// from the Assessment Mode system-item allowlist.
    private var knownSystemItemIDs: [String: Int] = [:]

    /// Monotonic token identifying the most recent activation attempt. The
    /// assertion's failure callback fires asynchronously, by which point a newer
    /// activation may already be in effect; the callback compares against this to
    /// avoid tearing down a handle it didn't create.
    private var activationGeneration = 0

    /// The configuration whose activation most recently failed asynchronously,
    /// or `nil`. Used to avoid re-activating the *identical* failed
    /// configuration on the next 1s tick (which would hot-loop); any genuine
    /// change to the desired set clears it and allows another attempt.
    private var lastFailedConfiguration: (allowed: Set<String>, systemItems: Set<Int>)?
    private var consecutiveTearDowns = 0

    /// The allowed system-item set baked into the currently-active assertion.
    private var appliedAllowedSystemItems = AssessmentModeBackend.allSystemItems

    /// The previous applied configuration and when it was applied. Used for
    /// anti-flap hysteresis: dynamic-icon apps (codexbar, iStat-style) whose
    /// item identity churns make `concealedBundleIDs` oscillate A→B→A→B, each
    /// flip clearing the dedupe guard and re-activating the assertion → the OS
    /// reflows the whole menu bar (a visible flash). If a fresh config is
    /// identical to the one we applied just before the current one and that was
    /// within the hysteresis window, the desired state is flapping, not really
    /// changing — skip the re-activation and let it settle.
    private var previousAppliedConfiguration: (
        allowed: Set<String>,
        systemItems: Set<Int>,
        concealed: Set<String>,
        at: ContinuousClock.Instant
    )?

    /// How long a just-superseded configuration suppresses a re-activation that
    /// would revert straight back to it.
    private static let antiFlapWindow: Duration = .seconds(3)

    static var protectedBundleIDs: Set<String> {
        Constants.thawOwnedBundleIdentifiers
    }

    private var protectedBundleIDs: Set<String> {
        Self.protectedBundleIDs
    }

    /// The identifiers currently concealed for a given assignment.
    private func concealedIdentifiers(
        sectionAssignment: [String: MenuBarSection.Name]
    ) -> Set<String> {
        var concealed = Set<String>()
        for (identifier, section) in sectionAssignment {
            switch section {
            case .visible:
                continue
            case .hidden, .alwaysHidden:
                concealed.insert(identifier)
            }
        }
        return concealed
    }

    private func isOwnAppBundleID(_ bundleID: String?) -> Bool {
        Constants.isThawOwnedBundleIdentifier(bundleID)
    }

    private func isOwnAppItem(_ item: MenuBarItem) -> Bool {
        item.tag.namespace == .thaw ||
            isOwnAppBundleID(item.sourceApplication?.bundleIdentifier) ||
            isOwnAppBundleID(item.owningApplication?.bundleIdentifier)
    }

    @discardableResult
    func apply(
        sectionAssignment: [String: MenuBarSection.Name],
        allItems: [MenuBarItem]
    ) -> Bool {
        // Learn/refresh the owner bundle ID of every currently-enumerated item.
        // owningApplication is Control Center on macOS 26+, so use
        // sourceApplication (the real app).
        for item in allItems {
            guard !isOwnAppItem(item) else {
                knownBundleIDs.removeValue(forKey: item.uniqueIdentifier)
                knownSystemItemIDs.removeValue(forKey: item.uniqueIdentifier)
                continue
            }
            if let bundleID = item.sourceApplication?.bundleIdentifier {
                knownBundleIDs[item.uniqueIdentifier] = bundleID
            }
            if let systemItemID = Self.systemItemIdentifier(for: item.tag) {
                knownSystemItemIDs[item.uniqueIdentifier] = systemItemID
            }
        }

        // The identifiers concealed right now, based on persisted section
        // assignment.
        let concealed = concealedIdentifiers(
            sectionAssignment: sectionAssignment
        )

        // Defensive fallback against a transiently empty/failed item cache.
        // `concealedBundleIDs` resolves from the sticky `knownBundleIDs` map and
        // so survives an empty `allItems`, but `bundlesWithVisibleItem` (the
        // per-bundle "keep on screen because a sibling is visible" protection)
        // is derived purely from `allItems`. If a recache lands with zero live
        // items (an AX enumeration hiccup / 0-items pass), that protection
        // collapses and every hidden-assigned bundle gets concealed with no
        // visible-sibling guard — emptying the menu bar ("reset hid every
        // icon"). When there is concealment to apply but no live items to reason
        // about, keep the current restriction and wait for a reliable cache
        // rather than guessing the bar empty.
        if allItems.isEmpty, !concealed.isEmpty {
            diagLog.warning(
                "apply: item cache is empty while \(concealed.count) item(s) are assigned hidden; keeping current restriction to avoid concealing everything"
            )
            return false
        }

        // Bundles that still have at least one item that should be visible right
        // now (assigned `.visible`).
        // The assertion allowlist is per-bundle, so concealing such a bundle
        // would also hide those visible items — worse than leaving the
        // hidden-assigned sibling on screen. Exclude them below so the Visible
        // layout bar never disagrees with the real menu bar.
        var bundlesWithVisibleItem = Set<String>()
        for item in allItems where !concealed.contains(item.uniqueIdentifier) {
            guard !isOwnAppItem(item) else {
                bundlesWithVisibleItem.formUnion(protectedBundleIDs)
                continue
            }
            // Fall back to the sticky learned map when sourceApplication
            // transiently fails to resolve (PID reuse / AX hiccup) — without
            // this, a momentary nil here drops a genuinely-visible item's
            // bundle out of the protection set and lets it get concealed
            // alongside its hidden-assigned sibling below.
            if let bundleID = item.sourceApplication?.bundleIdentifier ?? knownBundleIDs[item.uniqueIdentifier] {
                bundlesWithVisibleItem.insert(bundleID)
            }
        }

        // Owner bundle IDs of the concealed items, resolved from the learned map
        // so items that have already dropped out of enumeration stay concealed —
        // minus any bundle that still has a visible item (see above).
        var concealedBundleIDs = Set(concealed.compactMap { identifier in
            let bundleID = knownBundleIDs[identifier]
            return isOwnAppBundleID(bundleID) ? nil : bundleID
        })
        .subtracting(bundlesWithVisibleItem)

        // Never conceal Thaw itself. Thaw's own control items are *not* in
        // `allItems` (the cache exposes them separately, not as managed items),
        // so the visible-item guard above can't protect them; combined with the
        // sticky `knownBundleIDs` map, a hidden item that transiently mis-resolves
        // its owner to Thaw (PID reuse / AX hiccup) would conceal Thaw's control
        // item permanently and make the app unreachable. Self-protect
        // unconditionally — Thaw must always remain in the allowlist.
        for bundleID in protectedBundleIDs {
            concealedBundleIDs.remove(bundleID)
        }

        // Never bundle-conceal a *system* host. A concealed system item (Clock,
        // Control Center, Siri, Spotlight, …) is hidden individually via its
        // index in `concealedSystemItemIDs` below, but its owning bundle is a
        // shared host — most are hosted by `com.apple.MenuBarAgent`. The
        // per-bundle allowlist would then conceal the entire host, blanking
        // *every* system item it owns (and the whole system side of the bar)
        // on each restriction reflow — observed as the menu bar disappearing
        // for a few seconds. Drop the host bundle of any concealed item that has
        // a system-item index; the index path still conceals it precisely.
        let dynamicSystemHostBundleIDs = Set(concealed.compactMap { identifier -> String? in
            guard knownSystemItemIDs[identifier] != nil else { return nil }
            return knownBundleIDs[identifier]
        })
        concealedBundleIDs.subtract(dynamicSystemHostBundleIDs)
        concealedBundleIDs.subtract(Self.systemHostBundleIDs)

        // Never bundle-conceal a denylisted hiding-unsupported app. These items'
        // volatile title rotation defeats the assertion's identity-based
        // concealment, so hiding them leaves on-band ghosts. They are kept out
        // of the concealed set unconditionally.
        concealedBundleIDs.subtract(MenuBarItemTag.hidingUnsupportedBundleIDs)

        let concealedSystemItemIDs = Set(concealed.compactMap { knownSystemItemIDs[$0] })
        let allowedSystemItemSet = Self.allSystemItems.subtracting(concealedSystemItemIDs)

        // Nothing concealed → tear down any active restriction.
        guard !concealedBundleIDs.isEmpty || !concealedSystemItemIDs.isEmpty else {
            return reset()
        }

        // Allow every running app except those whose items are hidden. Listing
        // all running apps (not just ones currently in the cache) means apps
        // that appear later stay visible without a race. Thaw is force-included
        // so its own icon can never be hidden by the allowlist.
        var allowedSet = Set(
            NSWorkspace.shared.runningApplications
                .compactMap(\.bundleIdentifier)
                .filter { !concealedBundleIDs.contains($0) }
        )
        for bundleID in protectedBundleIDs {
            allowedSet.insert(bundleID)
        }

        // Belt-and-suspenders: also allow every known item-host bundle that isn't
        // itself concealed. Covers sub-bundle hosts that can be absent from
        // `runningApplications` on some OS builds. `knownBundleIDs` is sticky,
        // so this also survives a transient cache gap.
        for bundleID in knownBundleIDs.values where !concealedBundleIDs.contains(bundleID) {
            allowedSet.insert(bundleID)
        }

        // Denylisted hiding-unsupported bundles must never be excluded from the
        // allowlist. These items can be reordered but cannot be reliably hidden
        // — volatile title rotation defeats both the assertion's bundle
        // attribution and the identity-based concealment, leaving them as
        // on-band ghosts. Force-include their bundle IDs unconditionally so
        // they are never excluded from the allowlist.
        for bundleID in MenuBarItemTag.hidingUnsupportedBundleIDs {
            allowedSet.insert(bundleID)
            concealedBundleIDs.remove(bundleID)
        }

        // Ground-truth self-check: does the allowlist we're about to apply keep
        // every Thaw-owned icon host? If these log `allowed=true concealed=false`
        // and the icon is still hidden, the assertion is not honoring that
        // protected owner — a mechanism limitation, not an allowlist bug.
        // Re-activating tears down and rebuilds the restriction, which reflows
        // the whole menu bar — expensive, and a churn source when called on the
        // 1s timer while apps come and go (each Xcode/helper launch is a new
        // running app). So re-apply only when it actually matters:
        //   • nothing active yet, or
        //   • the concealed set changed (layout drag/reset), or
        //   • a *new* app appeared that must be kept visible (else it'd be
        //     hidden by the allowlist).
        // Apps merely quitting leave harmless stale entries in the allowlist, so
        // a pure shrink of the allowed set is ignored — no reflow needed.
        let concealedChanged = concealedBundleIDs != appliedConcealed
        let systemItemsChanged = allowedSystemItemSet != appliedAllowedSystemItems
        let newlyAppeared = !allowedSet.subtracting(appliedAllowed).isEmpty
        guard handle == nil || concealedChanged || systemItemsChanged || newlyAppeared else { return false }

        for ownBundleID in protectedBundleIDs.sorted() {
            let running = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == ownBundleID
            }
            diagLog.info("self-check: \(ownBundleID) allowed=\(allowedSet.contains(ownBundleID)) concealed=\(concealedBundleIDs.contains(ownBundleID)) inRunningApps=\(running)")
        }

        // Anti-flap hysteresis. A dynamic-icon app whose item identity churns
        // (codexbar, iStat-style) makes the desired set oscillate A→B→A→B; each
        // flip passes the guard above and re-activates the assertion, and every
        // re-activation reflows the whole menu bar (a visible flash). If this
        // fresh config is byte-identical to the one we held *before* the current
        // one, and that was within the anti-flap window, the state is flapping
        // back rather than genuinely advancing — skip the re-activation and keep
        // the current assertion until it settles. A `handle == nil` (nothing
        // active) is never suppressed, so hiding still engages promptly.
        if handle != nil,
           let previous = previousAppliedConfiguration,
           previous.allowed == allowedSet,
           previous.systemItems == allowedSystemItemSet,
           previous.concealed == concealedBundleIDs,
           previous.at.duration(to: .now) < Self.antiFlapWindow
        {
            diagLog.debug(
                "apply: suppressing flap back to a config applied \(previous.at.duration(to: .now)) ago (anti-flap)"
            )
            return false
        }

        // Don't re-activate the exact configuration that just failed
        // asynchronously — that would hot-loop on the 1s timer. Any change to the
        // desired set (an app launching/quitting, a drag/reset) makes this
        // unequal and clears the marker below, so a genuine retry still happens.
        if let lastFailedConfiguration,
           allowedSet == lastFailedConfiguration.allowed,
           allowedSystemItemSet == lastFailedConfiguration.systemItems
        {
            if consecutiveTearDowns >= 3 {
                diagLog.error(
                    "apply: suppressing re-activation after \(consecutiveTearDowns) consecutive verify tear-downs; " +
                        "concealedBundles=\(concealedBundleIDs.sorted())"
                )
            }
            return false
        }
        lastFailedConfiguration = nil
        consecutiveTearDowns = 0

        // Re-activate with the new allowlist. The previous assertion is dropped
        // first so the server applies a single, current restriction.
        let allowedBundleIDs = allowedSet.sorted()
        let allowedSystemItems = allowedSystemItemSet
            .sorted()
            .map { NSNumber(value: $0) }
        activationGeneration += 1
        let generation = activationGeneration
        let attemptedAllowed = allowedSet
        let attemptedSystemItems = allowedSystemItemSet
        diagLog.info(
            "applying restriction: systemItems=\(allowedSystemItems.map(\.stringValue)), " +
                "concealedBundles=\(concealedBundleIDs.sorted()), allowedBundles=\(allowedBundleIDs.count)"
        )
        // System item changes require the old assertion to be torn down BEFORE
        // the new one is created. MenuBarAgent only re-composites system-item
        // visibility when it observes an assertion going away; a silent swap
        // (create-then-invalidate) is treated as an update and items remain
        // on-screen. Bundle changes tolerate the swap order fine, so only
        // invert for system-item changes to avoid the extra reflow flash.
        let hadLiveAssertion = handle != nil
        if systemItemsChanged, let old = handle {
            diagLog.info("pre-invalidating assertion for system-item re-composite")
            ThawAssessmentModeHidingInvalidate(old)
            handle = nil
        }

        let newHandle = ThawAssessmentModeHidingActivate(allowedBundleIDs, allowedSystemItems) { [weak self] in
            // Dispatched to the main queue by the ObjC wrapper, so MainActor
            // isolation holds at runtime even though the block type is not.
            MainActor.assumeIsolated {
                // Async activation failure. If a newer activation has since run,
                // this is stale — ignore it. Otherwise tear down the dud handle
                // so the next tick can retry once the desired set changes.
                guard let self, self.activationGeneration == generation else { return }
                self.diagLog.error("activation failed asynchronously; tearing down handle to allow retry")
                if let dud = self.handle {
                    ThawAssessmentModeHidingInvalidate(dud)
                }
                self.handle = nil
                self.appliedConcealed = []
                self.appliedAllowed = []
                self.appliedAllowedSystemItems = Self.allSystemItems
                self.lastFailedConfiguration = (
                    allowed: attemptedAllowed,
                    systemItems: attemptedSystemItems
                )
            }
        }
        if let old = handle {
            ThawAssessmentModeHidingInvalidate(old)
        }
        handle = newHandle
        // Remember the config we are superseding (and when) so a flap straight
        // back to it within `antiFlapWindow` can be suppressed above. Only
        // record it when there was a live assertion to supersede.
        if hadLiveAssertion {
            previousAppliedConfiguration = (
                allowed: appliedAllowed,
                systemItems: appliedAllowedSystemItems,
                concealed: appliedConcealed,
                at: .now
            )
        }
        appliedConcealed = concealedBundleIDs
        appliedAllowed = allowedSet
        appliedAllowedSystemItems = allowedSystemItemSet
        diagLog.info(
            "applied restriction: concealing \(concealedBundleIDs.count) app(s), " +
                "\(concealedSystemItemIDs.count) system item(s), " +
                "allowing \(allowedBundleIDs.count)"
        )
        return true
    }

    /// Invalidates the live assertion and immediately re-applies the same
    /// allowlist. Assertion reflow can strand allowed bundles as invisible AX
    /// ghosts at on-band coordinates; synthetic drags cannot fix those, but a
    /// fresh activation forces MenuBarAgent to re-composite.
    func pulse(
        sectionAssignment: [String: MenuBarSection.Name],
        allItems: [MenuBarItem]
    ) -> Bool {
        if let old = handle {
            diagLog.info("pulsing restriction: invalidating assertion for MenuBarAgent re-composite")
            ThawAssessmentModeHidingInvalidate(old)
            handle = nil
            appliedConcealed = []
            appliedAllowed = []
        }
        previousAppliedConfiguration = nil
        lastFailedConfiguration = nil
        consecutiveTearDowns = 0
        return apply(sectionAssignment: sectionAssignment, allItems: allItems)
    }

    func markExternallyTornDown() {
        lastFailedConfiguration = (allowed: appliedAllowed, systemItems: appliedAllowedSystemItems)
        consecutiveTearDowns += 1
    }

    private func reset() -> Bool {
        guard handle != nil else { return false }
        ThawAssessmentModeHidingInvalidate(handle)
        handle = nil
        appliedConcealed = []
        appliedAllowed = []
        appliedAllowedSystemItems = Self.allSystemItems
        diagLog.info("restriction reset; all items revealed")
        return true
    }
}
