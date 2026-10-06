//
//  ControlItem.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import MenuBarModel

// MARK: - ControlItem

/// One of the status items Thaw owns, marking the boundary of a menu bar
/// section.
///
/// Three of these exist, one per section. The Thaw icon is the only one the
/// user is meant to see and click; the other two are dividers whose real job is
/// to sit at a known position so the items around them can be classified. All
/// three are always registered with the system once they have been touched,
/// they are shown and hidden by changing their length, never by unpublishing
/// them, because an unpublished status item cannot be brought back without
/// losing its slot.
@MainActor
final class ControlItem: NSObject {
    /// The boundary this control item marks.
    ///
    /// Lives in MenuBarModel so that item tagging can name control items
    /// without depending on this class.
    typealias Identifier = ControlItemIdentifier

    /// Whether the section behind this control item is currently revealed.
    @Published var state = HidingState.hideSection

    /// The window AppKit hosts this item's button in.
    @Published private(set) var window: NSWindow?

    /// The hosting window's frame, coalesced so consumers are not woken for
    /// every intermediate step of a menu bar reflow.
    @Published private(set) var frame: CGRect?

    /// The item's frame while it actually overlaps its screen, and nil while
    /// it is parked off screen.
    @Published private(set) var onScreenFrame: CGRect?

    /// The boundary this item marks.
    let identifier: Identifier

    private let diagLog = DiagLog(category: "ControlItem")

    private weak var appState: AppState?

    /// The settings this component reads. MenuBarEngineConfiguration states
    /// why the engine holds this rather than AppState.
    private var configuration: any MenuBarEngineConfiguration = AppSettings.engineDefaults

    /// The status item backing this control item, once something has needed it.
    private var registeredHost: StatusItemHost?

    /// Pending re-check for a persistent off-band frame. See noteDegenerateFrame().
    private var offBandRecoveryTask: Task<Void, Never>?
    private var lastOffBandEscalation = Date.distantPast
    private var offBandRecoveryLevel = 0
    private var offBandRecoveryCycle = 0
    private var offBandRecoveryExhausted = false

    /// Why the visible item is still missing after recovery ran out, or nil
    /// while it is seated or still being recovered.
    @Published private(set) var placementBlock: PlacementBlock?

    private var menuController: ControlItemMenuController?

    private var nudge = MenuBarAgentNudge()

    /// The last displayed state setThawIconDisplayed(_:) actually applied,
    /// so a re-set to the same state can be skipped. nil until the first
    /// apply. See setThawIconDisplayed(_:) for why the re-render matters.
    private var lastAppliedThawIconDisplayed: Bool?

    private let appearanceUpdates = StateAppearanceUpdates()
    private var primaryActivationSequence = PrimaryActivationSequence()

    /// Modifier flags from the mouse-down behind the activation MenuBarAgent is
    /// about to forward; the mouse-up can arrive after the option is released.
    private var primaryPressModifiers: NSEvent.ModifierFlags?

    /// Records the press-time modifiers for the forwarded activation, or
    /// clears a stale record when the press landed elsewhere.
    func recordPrimaryPressModifiers(_ flags: NSEvent.ModifierFlags?) {
        primaryPressModifiers = flags
    }

    /// Coalesces the queued state notification with an appearance already
    /// rendered synchronously by the section toggle.
    final class StateAppearanceUpdates {
        private var renderedState: HidingState?

        @discardableResult
        func apply(state: HidingState, stateChangeOnly: Bool, render: () -> Bool) -> Bool {
            guard !stateChangeOnly || renderedState != state else { return false }
            guard render() else { return false }
            renderedState = state
            return true
        }
    }

    private var cancellables = Set<AnyCancellable>()

    /// Tasks backing the settings-observation reactions in
    /// observeSettings(appState:). GeneralSettings and
    /// AdvancedSettings are @Observable (not Combine
    /// ObservableObjects), so their property changes are observed via the
    /// Observations async sequence instead of $property publishers.
    private var showThawIconObservationTask: Task<Void, Never>?
    private var thawIconObservationTask: Task<Void, Never>?
    private var sectionDividerStyleObservationTask: Task<Void, Never>?
    private var alwaysHiddenSectionObservationTask: Task<Void, Never>?

    deinit {
        showThawIconObservationTask?.cancel()
        thawIconObservationTask?.cancel()
        sectionDividerStyleObservationTask?.cancel()
        alwaysHiddenSectionObservationTask?.cancel()
        offBandRecoveryTask?.cancel()
    }

    init(identifier: Identifier) {
        self.identifier = identifier
        super.init()
    }

    /// Attaches the control item to the app and starts observing everything its
    /// appearance depends on.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configuration = appState.settings
        menuController = ControlItemMenuController(appState: appState)
        beginObserving()
    }
}

// MARK: - Status item hosting

extension ControlItem {
    /// The status item this control item is hosted by, registering one on first
    /// use.
    ///
    /// Registration is deferred because it is observable: it claims a slot in
    /// the menu bar, seeds defaults, and installs the macOS 27 activation
    /// handlers. A control item torn down before performSetup(with:) has run
    /// (the app can quit from the permissions flow before launch completes)
    /// leaves no trace of itself in the bar or in the defaults database.
    private var host: StatusItemHost {
        if let registeredHost {
            return registeredHost
        }
        let host = StatusItemHost(controlItem: self)
        registeredHost = host
        if identifier == .visible {
            diagLog.info("VisibleControlLifecycle[registered] \(diagnosticStateDescription())")
        }
        return host
    }

    private var statusItem: NSStatusItem {
        host.statusItem
    }

    /// The horizontal constraint AppKit installs on the button's content view.
    ///
    /// Deactivating it is half of collapsing an item to nothing; the other half
    /// is the item's length.
    private var constraint: NSLayoutConstraint? {
        host.constraint
    }

    /// Whether this control item divides two sections rather than representing
    /// Thaw itself.
    var isSectionDivider: Bool {
        identifier != .visible
    }

    /// Whether the status item is currently published to the menu bar.
    var isAddedToMenuBar: Bool {
        statusItem.isVisible
    }

    /// The section this control item marks the boundary of.
    var sectionName: MenuBarSection.Name {
        switch identifier {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }

    /// A registered NSStatusItem and the AppKit state that comes with it.
    ///
    /// Wrapped in an object of its own so that "this control item has claimed a
    /// slot in the menu bar" is a single nullable reference, and so releasing
    /// that reference is what gives the slot back.
    private final class StatusItemHost {
        let statusItem: NSStatusItem

        /// The width constraint AppKit installs for the status button, if it
        /// could be identified.
        let constraint: NSLayoutConstraint?

        @MainActor
        init(controlItem: ControlItem) {
            // The system reads these the moment the item is registered, so they
            // have to be in place before the next line runs.
            ControlItemDefaults.prepareDefaults(for: controlItem.identifier)

            statusItem = NSStatusBar.system.statusItem(withLength: 0)
            statusItem.autosaveName = controlItem.identifier.rawValue

            guard let button = statusItem.button else {
                constraint = nil
                return
            }

            if let contentView = button.window?.contentView {
                let horizontalConstraints = contentView.constraintsAffectingLayout(for: .horizontal)
                let isButtonWidth = Predicates.controlItemConstraint(button: button)
                constraint = horizontalConstraints.first(where: isButtonWidth)
                assert(horizontalConstraints.filter(isButtonWidth).count <= 1)

                button.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
            } else {
                constraint = nil
            }

            Self.routeActivation(from: button, to: controlItem)

            // The WindowServer no longer exposes individual menu bar item
            // windows, so Thaw enumerates items through the Accessibility tree
            // (see MenuBarItemAXProvider). AX does not surface a status item's
            // autosave name, so the control item's stable identifier is
            // published as the accessibility identifier instead, that is what
            // lets the enumerator recognize Thaw's own items and match them to
            // their tag.
            button.setAccessibilityIdentifier(controlItem.identifier.rawValue)
        }

        deinit {
            // An isolated deinit would express this directly, but it crashes
            // SILGen for this class specifically (emitIsolatingDestructor),
            // though it compiles elsewhere, e.g. Hotkey.Listener. Retest before
            // adopting it. This host is only created and released on the main
            // actor, so assuming isolation is sound.
            MainActor.assumeIsolated {
                // Unregistering also deletes the item's stored placement and
                // visibility. Losing the placement is accepted, dividers never
                // persist one, and the system re-places the Thaw icon, but the
                // visibility flags must survive, or AppKit will refuse to
                // publish the item on the next launch.
                let autosaveName = statusItem.autosaveName as String
                NSStatusBar.system.removeStatusItem(statusItem)
                ControlItemDefaults.restoreVisibilityIfNeeded(autosaveName: autosaveName)
            }
        }

        /// Points the button's activation at controlItem.
        ///
        /// The Thaw icon prefers macOS 27's semantic primary action, which
        /// MenuBarAgent forwards on behalf of the remotely hosted button. That
        /// path carries no secondary-click gesture, HIDEventManager picks
        /// that up from the live icon frame instead. Everything else, and the
        /// icon itself if the runtime API is missing, falls back to plain
        /// target/action.
        @MainActor
        private static func routeActivation(from button: NSStatusBarButton, to controlItem: ControlItem) {
            if controlItem.identifier == .visible,
               PrimaryActionBridge.attach(
                   to: button,
                   target: controlItem,
                   action: #selector(controlItem.performPrimaryAction)
               )
            {
                return
            }
            button.target = controlItem
            button.action = #selector(controlItem.performAction)
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])
        }
    }

    /// Registers a status button's semantic primary action through an AppKit
    /// API the build SDK does not declare.
    ///
    /// Xcode 26 has no addTarget:action:forControlEvents: on
    /// NSStatusBarButton, but macOS 27 uses it to deliver activation from
    /// MenuBarAgent. Resolving it at runtime keeps distribution builds on the
    /// older SDK.
    private enum PrimaryActionBridge {
        private static let diagLog = DiagLog(category: "ControlItem.PrimaryAction")

        private static let selector = NSSelectorFromString("addTarget:action:forControlEvents:")

        /// The raw value of NSControl.Event.primaryActionTriggered.
        private static let primaryActionTriggered: UInt = 1 << 13

        private typealias AddTarget = @convention(c) (
            AnyObject,
            Selector,
            AnyObject?,
            Selector,
            UInt
        ) -> Void

        /// Registers action for primary activation, reporting whether the
        /// runtime accepted the registration.
        @MainActor
        static func attach(to button: NSStatusBarButton, target: ControlItem, action: Selector) -> Bool {
            guard button.responds(to: selector) else {
                return false
            }

            // responds(to:) only proves the selector resolves to some
            // implementation, not that it matches the C convention the cast
            // below assumes. Checking the runtime's own type encoding first
            // means a point release that changes the signature declines the
            // fast path instead of corrupting the call stack.
            guard
                let method = class_getInstanceMethod(type(of: button), selector),
                let encoding = method_getTypeEncoding(method).map(String.init(cString:))
            else {
                diagLog.warning(
                    "addTarget:action:forControlEvents: has no resolvable type encoding; falling back to target/action."
                )
                return false
            }
            guard ControlItem.isSupportedAddTargetTypeEncoding(encoding) else {
                diagLog.warning(
                    """
                    addTarget:action:forControlEvents: signature (\(encoding)) is not a known \
                    (void, id, SEL, id, SEL, NSUInteger) encoding; falling back to target/action.
                    """
                )
                return false
            }

            let addTarget = unsafeBitCast(button.method(for: selector), to: AddTarget.self)
            addTarget(button, selector, target, action, primaryActionTriggered)
            return true
        }
    }
}

// MARK: - Re-publishing

extension ControlItem {
    /// What republishIfUnseated() decided to do about an unseated window.
    nonisolated enum RepublishDecision: Equatable {
        /// Re-register the status item. attempt is the 1-based try number.
        case republish(attempt: Int)

        /// This session's re-publish budget is spent.
        case exhausted
    }

    /// Two covers the observed failure; a third means the host is rejecting
    /// every window Thaw registers, which re-registering cannot fix.
    static nonisolated let maximumRepublishes = 2

    /// How long a spent budget waits before it re-arms.
    ///
    /// A budget latched off for the session leaves the icon parked for good;
    /// re-arming bounds the churn to one re-register per cooldown.
    static nonisolated let republishRearmCooldown: Duration = .seconds(60)

    /// Re-publishes spent per identifier this session. See
    /// republishIfUnseated().
    private static var republishCounts: [Identifier: Int] = [:]

    /// When each identifier last re-published. Feeds the re-arm cooldown.
    private static var republishLastAttempt: [Identifier: ContinuousClock.Instant] = [:]

    /// The decision for one unseated-window event. Pure, so the budget rule is
    /// testable without AppKit.
    static nonisolated func republishDecision(
        priorCount: Int,
        elapsedSinceLastAttempt: Duration? = nil,
        ceiling: Int = maximumRepublishes,
        rearmCooldown: Duration = republishRearmCooldown
    ) -> RepublishDecision {
        if priorCount < ceiling {
            return .republish(attempt: priorCount + 1)
        }
        if let elapsed = elapsedSinceLastAttempt, elapsed >= rearmCooldown {
            return .republish(attempt: 1)
        }
        return .exhausted
    }

    /// Tears the status item down and registers a fresh one.
    ///
    /// Re-registering is the only lever that ends an unseated window: the move
    /// machinery can only fail against the old window forever.
    @discardableResult
    func republishIfUnseated() -> RepublishDecision {
        let now = ContinuousClock.now
        let priorCount = Self.republishCounts[identifier, default: 0]
        let elapsedSinceLastAttempt = Self.republishLastAttempt[identifier].map { now - $0 }
        let decision = Self.republishDecision(
            priorCount: priorCount,
            elapsedSinceLastAttempt: elapsedSinceLastAttempt
        )
        guard case let .republish(attempt) = decision else {
            diagLog.error(
                "republish budget for \(identifier.rawValue) exhausted; leaving the unseated item alone"
            )
            return decision
        }
        if priorCount >= Self.maximumRepublishes {
            diagLog.notice(
                "republish budget for \(identifier.rawValue) re-armed; the parked item gets another re-register"
            )
        }
        Self.republishCounts[identifier] = attempt
        Self.republishLastAttempt[identifier] = now

        let oldWindowNumber = statusItem.button?.window?.windowNumber ?? -1
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        registeredHost = nil
        // The host registers lazily; touching it builds the fresh item.
        _ = host
        // The fresh button is blank, and the skip-guards would otherwise read
        // "already applied" from the old item's state; re-render explicitly.
        lastAppliedThawIconDisplayed = nil
        beginObserving()
        updateStatusItem()
        diagLog.warning(
            "re-published \(identifier.rawValue) status item (attempt \(attempt)); window \(oldWindowNumber) -> \(statusItem.button?.window?.windowNumber ?? -1)"
        )
        return decision
    }

    // MARK: Off-band recovery

    /// What the ladder does next for a persistent off-band window.
    nonisolated enum OffBandRecoveryAction: Equatable {
        /// Nudge the status item's width so MenuBarAgent re-reads the layout.
        case nudge
        /// Withdraw and republish visibility, forcing AppKit to re-place the
        /// window without losing the slot.
        case toggleVisibility
        /// Tear the status item down and register a fresh one.
        case republishStatusItem
        /// This session's recovery budget is spent.
        case exhausted
    }

    /// The rung the ladder takes next. Pure, so the ordering is testable.
    static nonisolated func offBandRecoveryAction(
        takenInCycle: Int,
        cycle: Int,
        maxCycles: Int = maximumRepublishes
    ) -> OffBandRecoveryAction {
        guard cycle < maxCycles else { return .exhausted }
        switch takenInCycle {
        case 0: return .nudge
        case 1: return .toggleVisibility
        default: return .republishStatusItem
        }
    }

    /// Why the visible item stays out of the bar once the ladder is spent.
    nonisolated enum PlacementBlock: Equatable {
        /// macOS has Thaw switched off in its menu bar settings, which no
        /// re-register can change.
        case deniedBySystem
        /// The item never landed and the switch could not be read.
        case unknown
    }

    /// The block for what Control Center's switch reads. Pure, so the rule is
    /// testable without the app list.
    static nonisolated func placementBlock(systemAllowsThaw: Bool?) -> PlacementBlock {
        systemAllowsThaw == false ? .deniedBySystem : .unknown
    }

    /// Records why the item is still missing and returns it.
    @discardableResult
    private func notePlacementBlocked() -> PlacementBlock {
        let block = Self.placementBlock(systemAllowsThaw: MenuBarAllowState.ofThaw())
        if placementBlock != block {
            placementBlock = block
            if block == .deniedBySystem {
                diagLog.warning(
                    "macOS has \(Constants.displayName) switched off in its menu bar settings; waiting for the switch instead of re-registering"
                )
            }
        }
        return block
    }

    /// How long a rung has to prove itself before the next one fires.
    static nonisolated let offBandEscalationCooldown: TimeInterval = 5

    /// Called from the geometry stream for every degenerate frame. Rearms a
    /// delayed re-check that escalates one rung per cooldown while the live
    /// frame stays off-band.
    private func noteDegenerateFrame() {
        guard identifier == .visible else { return }
        guard !offBandRecoveryExhausted, offBandRecoveryTask == nil else { return }
        offBandRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.offBandRecoveryTask = nil
            self.escalateIfStillOffBand()
        }
    }

    private func escalateIfStillOffBand() {
        guard let frame = window?.frame, Self.isDegenerateMenuBarFrame(frame) else {
            return
        }
        let now = Date.now
        guard now.timeIntervalSince(lastOffBandEscalation) >= Self.offBandEscalationCooldown else {
            noteDegenerateFrame()
            return
        }
        lastOffBandEscalation = now

        switch Self.offBandRecoveryAction(
            takenInCycle: offBandRecoveryLevel,
            cycle: offBandRecoveryCycle
        ) {
        case .nudge:
            offBandRecoveryLevel += 1
            diagLog.warning(
                "visible status item still off-band (\(NSStringFromRect(frame))); nudging MenuBarAgent positions"
            )
            requestMenuBarAgentPositionRefresh()
            noteDegenerateFrame()

        case .toggleVisibility:
            offBandRecoveryLevel += 1
            diagLog.warning(
                "visible status item still off-band; toggling visibility to force re-placement"
            )
            let wasAdded = isAddedToMenuBar
            removeFromMenuBar()
            if wasAdded {
                addToMenuBar()
            }
            updateStatusItem()
            noteDegenerateFrame()

        case .republishStatusItem:
            offBandRecoveryCycle += 1
            offBandRecoveryLevel = 0
            diagLog.warning("visible status item still off-band; re-publishing the status item")
            _ = republishIfUnseated()
            noteDegenerateFrame()

        case .exhausted:
            offBandRecoveryExhausted = true
            notePlacementBlocked()
            diagLog.error(
                "off-band recovery exhausted; a re-armed re-register retries in \(Self.republishRearmCooldown)"
            )
            scheduleRepublishRearmRetry()
        }
    }

    /// Keeps one re-armed re-register in flight while the window stays
    /// off-band, at most one per cooldown.
    ///
    /// A frame that reads healthy again clears the exhaustion and stops it.
    private func scheduleRepublishRearmRetry() {
        guard offBandRecoveryTask == nil else { return }
        offBandRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.republishRearmCooldown)
            guard let self, !Task.isCancelled else { return }
            self.offBandRecoveryTask = nil
            self.retryRepublishAfterCooldown()
        }
    }

    /// Fires one re-armed re-register, then reschedules while off-band.
    private func retryRepublishAfterCooldown() {
        // A missing window is not health: re-register if the item is added,
        // only keep watching if the user turned it off.
        guard let frame = window?.frame else {
            if isAddedToMenuBar, notePlacementBlocked() != .deniedBySystem {
                republishIfUnseated()
            }
            scheduleRepublishRearmRetry()
            return
        }
        guard Self.isDegenerateMenuBarFrame(frame) else {
            // Seated again; give the ladder its budget back.
            offBandRecoveryExhausted = false
            offBandRecoveryLevel = 0
            offBandRecoveryCycle = 0
            placementBlock = nil
            return
        }
        // A denial outlasts every fresh window, so only the switch is watched.
        guard notePlacementBlocked() != .deniedBySystem else {
            scheduleRepublishRearmRetry()
            return
        }
        switch republishIfUnseated() {
        case .republish:
            // A fresh window is out; give the host the escalation cooldown
            // to seat it before judging the frame again.
            lastOffBandEscalation = Date.now
        case .exhausted:
            break
        }
        scheduleRepublishRearmRetry()
    }

    /// Restores the re-publish budget after a window the host seated, so the
    /// next unseat starts with a fresh budget.
    func markSeated() {
        guard Self.republishCounts[identifier] != nil else { return }
        Self.republishCounts[identifier] = nil
        Self.republishLastAttempt[identifier] = nil
        diagLog.debug("republish budget for \(identifier.rawValue) restored; the fresh window seated")
    }

    /// Clears the off-band recovery budget after a display configuration change.
    ///
    /// The budget is spent against one bar geometry; a display arriving or
    /// leaving rebuilds the bar, so the ladder gets a fresh attempt instead of
    /// staying latched off for the session.
    func resetOffBandRecovery() {
        let spentRepublish = Self.republishCounts[identifier] != nil
        guard offBandRecoveryExhausted || offBandRecoveryCycle > 0 || spentRepublish else {
            return
        }
        offBandRecoveryExhausted = false
        offBandRecoveryLevel = 0
        offBandRecoveryCycle = 0
        placementBlock = nil
        Self.republishCounts[identifier] = nil
        Self.republishLastAttempt[identifier] = nil
        diagLog.notice(
            "off-band recovery budget reset; the display configuration changed"
        )
        noteDegenerateFrame()
    }
}

// MARK: - Observation

extension ControlItem {
    /// Starts every subscription this control item's appearance is a function
    /// of. Called once, from performSetup(with:).
    private func beginObserving() {
        publishGeometry()

        $state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItem(stateChangeOnly: true)
            }
            .store(in: &cancellables)

        // Section hotkeys are only meaningful while the item that owns them is
        // in the bar.
        statusItem.publisher(for: \.isVisible)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                guard
                    let self,
                    let section = appState?.menuBarManager.section(withName: sectionName),
                    let hotkey = section.hotkey
                else {
                    return
                }
                if isVisible {
                    hotkey.enable()
                } else {
                    hotkey.disable()
                }
            }
            .store(in: &cancellables)

        // A spent off-band ladder was measured against one bar geometry; a
        // display change rebuilds the bar, so let it retry.
        DisplayTopology.shared.screenParametersChanged
            .sink { [weak self] in
                self?.resetOffBandRecovery()
            }
            .store(in: &cancellables)

        if let appState {
            observeSettings(appState: appState)
        }
    }

    /// Feeds the published geometry from AppKit's KVO streams.
    ///
    /// These pipelines write straight into the @Published storage, so they
    /// need no cancellable bookkeeping and cannot retain the control item. The
    /// frame streams are debounced because a menu bar reflow walks the item
    /// through a burst of intermediate positions, and consumers only care where
    /// it lands.
    private func publishGeometry() {
        statusItem.publisher(for: \.button).removeNil()
            .flatMap { $0.publisher(for: \.window) }
            .receive(on: DispatchQueue.main)
            .assign(to: &$window)

        $window.removeNil()
            .flatMap { $0.publisher(for: \.frame) }
            .removeDuplicates()
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .sink { [weak self] measuredFrame in
                guard let self else { return }
                // An item parked at x = -1, or measured with no size, has not
                // landed in the bar; re-assert the icon instead of publishing it.
                if Self.isDegenerateMenuBarFrame(measuredFrame) {
                    // Every item measures {0, 0, 1, 0} until its first layout;
                    // only an item that had landed and lost its frame is news.
                    let message = "degenerate status window frame \(NSStringFromRect(measuredFrame))"
                    if frame == nil {
                        diagLog.debug(message)
                    } else {
                        diagLog.warning(message)
                    }
                    reassertVisibleIconImage()
                    noteDegenerateFrame()
                    return
                }
                if placementBlock != nil {
                    placementBlock = nil
                }
                frame = measuredFrame
            }
            .store(in: &cancellables)

        $window.removeNil()
            .flatMap { $0.publisher(for: \.screen) }
            .removeNil()
            .flatMap { $0.publisher(for: \.frame) }
            .combineLatest($frame.removeNil())
            .removeDuplicates()
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .map { screenFrame, frame in screenFrame.intersects(frame) ? frame : nil }
            .assign(to: &$onScreenFrame)
    }

    /// Whether a measured frame means the item never landed in the menu bar.
    private static func isDegenerateMenuBarFrame(_ frame: CGRect) -> Bool {
        frame.midX <= 0 || frame.width <= 0 || frame.height <= 0
    }

    /// Tracks the settings that change how this control item looks or whether it
    /// is in the bar at all.
    private func observeSettings(appState: AppState) {
        // A drag reveals the sections, which means the dividers have to
        // redraw. AppState is @Observable; deduped by hand.
        let dragTask = Task { @MainActor [weak self, weak appState] in
            guard let appState else { return }
            let changes = Observations { appState.isDraggingMenuBarItem }
            var previous: Bool?
            for await isDragging in changes {
                guard let self else { return }
                guard isDragging != previous else { continue }
                previous = isDragging
                if isDragging {
                    updateStatusItem()
                }
            }
        }
        AnyCancellable { dragTask.cancel() }
            .store(in: &cancellables)

        // GeneralSettings and AdvancedSettings are @Observable, so
        // their properties are watched via Observations sequences rather
        // than the old $property Combine projections. Each sequence
        // delivers the current value first, matching the old subscriptions'
        // initial emissions.
        switch identifier {
        case .visible:
            let generalSettings = appState.settings.general
            showThawIconObservationTask?.cancel()
            showThawIconObservationTask = Task { @MainActor [weak self] in
                let changes = Observations { generalSettings.showThawIcon }
                for await shouldShow in changes {
                    guard let self else { return }
                    setThawIconDisplayed(shouldShow)
                }
            }

            // The template flag changes how a custom icon renders, so it counts
            // as part of the icon.
            thawIconObservationTask?.cancel()
            thawIconObservationTask = Task { @MainActor [weak self] in
                let changes = Observations {
                    (generalSettings.thawIcon, generalSettings.customThawIconIsTemplate)
                }
                for await _ in changes {
                    guard let self else { return }
                    updateStatusItem()
                }
            }

        case .alwaysHidden:
            // The item's KVO visibility (Combine) and the @Observable
            // enableAlwaysHiddenSection setting (an Observations sequence) both
            // re-derive the same add/remove decision, so a section switched on
            // while the item is absent still brings it back.
            let advancedSettings = appState.settings.advanced
            let reactToAlwaysHiddenSectionState: () -> Void = { [weak self] in
                guard let self else { return }
                if advancedSettings.enableAlwaysHiddenSection {
                    addToMenuBar()
                } else {
                    removeFromMenuBar()
                }
            }

            statusItem.publisher(for: \.isVisible)
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    reactToAlwaysHiddenSectionState()
                }
                .store(in: &cancellables)

            alwaysHiddenSectionObservationTask?.cancel()
            alwaysHiddenSectionObservationTask = Task { @MainActor in
                let changes = Observations { advancedSettings.enableAlwaysHiddenSection }
                for await _ in changes {
                    reactToAlwaysHiddenSectionState()
                }
            }

        case .hidden:
            break
        }

        if isSectionDivider {
            let advancedSettings = appState.settings.advanced
            sectionDividerStyleObservationTask?.cancel()
            sectionDividerStyleObservationTask = Task { @MainActor [weak self] in
                let changes = Observations { advancedSettings.sectionDividerStyle }
                for await _ in changes {
                    guard let self else { return }
                    updateStatusItem()
                }
            }
        }
    }
}

// MARK: - Appearance

extension ControlItem {
    /// Redraws the status item for the current hiding state, in the caller's
    /// run-loop turn.
    ///
    /// beginObserving() drives this from $state, which fires in willSet, so the
    /// sink hops through DispatchQueue.main to a later run-loop turn. After a
    /// section toggle that splits the assertion swap and this item's width
    /// change into two MenuBarAgent passes, which animate as two reflows.
    ///
    /// Callers that just changed state call this to fold the width change into
    /// the same turn. It is safe because nothing here reads an unwritten value:
    /// the dividers derive from sectionController.revealedSection, updated
    /// synchronously before the restriction applies, and the icon reads state,
    /// which has landed once the caller's assignment returns.
    func applyAppearanceNow() {
        updateStatusItem()
    }

    /// Redraws the status item for the current hiding state.
    private func updateStatusItem(stateChangeOnly: Bool = false) {
        appearanceUpdates.apply(state: state, stateChangeOnly: stateChangeOnly) {
            guard
                let appState,
                let button = statusItem.button
            else {
                return false
            }

            let previousLength = statusItem.length
            let previousImageSize = button.image?.size
            button.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            if !button.title.isEmpty {
                button.title = ""
            }

            switch identifier {
            case .visible:
                // Assign the new image directly: clearing it first gives AppKit
                // an intermediate empty intrinsic size to lay out.
                applyIconAppearance(to: button, appState: appState)
            case .hidden, .alwaysHidden:
                applyDividerAppearance(to: button, appState: appState)
            }
            diagLog.debug(
                "appearance applied: identifier=\(identifier.rawValue) state=\(state) " +
                    "stateChangeOnly=\(stateChangeOnly) length=\(previousLength)->\(statusItem.length) " +
                    "imageSize=\(String(describing: previousImageSize))->\(String(describing: button.image?.size))"
            )
            return true
        }
    }

    /// Draws the Thaw icon.
    private func applyIconAppearance(to button: NSStatusBarButton, appState: AppState) {
        guard configuration.showThawIcon else {
            collapseStatusItem()
            return
        }

        ControlItemDefaults.restoreVisibilityIfNeeded(autosaveName: identifier.rawValue)
        addToMenuBar()
        expandStatusItem()

        button.isEnabled = true
        button.alphaValue = 1
        button.appearsDisabled = false
        button.isHighlighted = false
        button.image = iconImage(appState: appState)
    }

    /// The icon image for the current hiding state.
    private func iconImage(appState: AppState) -> NSImage? {
        let icon = configuration.thawIcon
        let image = switch state {
        case .showSection: icon.visible.nsImage(for: appState)
        case .hideSection: icon.hidden.nsImage(for: appState)
        }

        // The built-in icons are drawn at the right size already. A custom one
        // is whatever file the user picked, so it has to be brought down to fit
        // the bar.
        guard case .custom = icon.name, let image else {
            return image
        }
        return ControlItemImage.scaledToFitMenuBar(image)
    }

    /// Draws a section divider, or collapses it away.
    private func applyDividerAppearance(to button: NSStatusBarButton, appState: AppState) {
        // The section controller is the source of truth for what is revealed.
        // Stale status-item state can otherwise leave a chevron on screen after
        // an assertion has already re-hidden the items behind it.
        let revealed = appState.menuBarManager.sectionController.revealedSection
        let isRevealed = switch identifier {
        case .hidden: revealed == .hidden || revealed == .alwaysHidden
        case .alwaysHidden: revealed == .alwaysHidden
        case .visible: false
        }

        switch Self.sectionDividerPresentation(
            state: isRevealed ? .showSection : .hideSection,
            style: configuration.sectionDividerStyle
        ) {
        case .hidden:
            if button.image != nil {
                button.image = nil
            }
            button.isEnabled = true
            button.alphaValue = 1
            // A drag reveals every section, and the user still needs to see
            // where one ends and the next begins, so a dragged-over divider
            // keeps a sliver of width and draws a "|" in it.
            let keepsSliver = configuration.showAllSectionsOnUserDrag
                && appState.isDraggingMenuBarItem
            collapseStatusItem(toWidth: keepsSliver ? 3 : 0)
            button.appearsDisabled = true
            button.isHighlighted = false

            if keepsSliver {
                button.title = "|"
            }
        case .chevron:
            expandStatusItem()
            button.isEnabled = true
            button.alphaValue = 1
            button.appearsDisabled = false
            button.image = ControlItemImage.builtin(.chevronSmall).nsImage(for: appState)
        }
    }

    /// Expands the status item so it sizes itself to its own content.
    ///
    /// The system no longer reflows over-wide status items; an over-long
    /// divider just overflows the right edge and confuses section
    /// classification. So every shown item is content-sized, and concealing
    /// is collapseStatusItem(toWidth:).
    private func expandStatusItem() {
        constraint?.isActive = true
        // Writing an unchanged length still costs a MenuBarAgent reflow, and
        // updateStatusItem() runs from several triggers that often agree on
        // the answer. Only widths that actually move are worth paying for.
        guard statusItem.length != NSStatusItem.variableLength else { return }
        statusItem.length = NSStatusItem.variableLength
    }

    /// Collapses the status item to width points without unregistering it.
    ///
    /// The dividers have to stay in the bar even while they are invisible,
    /// because their positions are what decide which section an item belongs
    /// to. Clearing isVisible would remove them outright, so width is used
    /// instead: the button's constraint is deactivated, the item's length is
    /// pinned, and the hosting window is shrunk to match.
    private func collapseStatusItem(toWidth width: CGFloat = 0) {
        constraint?.isActive = false
        // Writing an unchanged length still costs a MenuBarAgent reflow, and
        // updateStatusItem() runs from several triggers that often agree on
        // the answer. The hosting window is still sized unconditionally: it can
        // arrive after the length that should have shrunk it.
        if statusItem.length != width {
            statusItem.length = width
        }

        if let window {
            let size = withMutableCopy(of: window.frame.size) { $0.width = max(width, 1) }
            window.setContentSize(size)
        }
    }

    /// Shows or collapses the Thaw icon without unregistering the status item.
    ///
    /// Publishes the item only when it is actually absent: a redundant
    /// isVisible = true on an already-visible item re-drives AppKit's
    /// variant-view scene connect (_wakeStatusItem, and with it an
    /// intermittent SIGABRT). Length is what shows and hides the icon from
    /// here on.
    private func setThawIconDisplayed(_ shouldShow: Bool) {
        ControlItemDefaults.restoreVisibilityIfNeeded(autosaveName: identifier.rawValue)

        if !isAddedToMenuBar {
            statusItem.isVisible = true
        }

        // Idempotent: updateStatusItem() clears and re-sets the button image,
        // which visibly re-renders the icon, and a restriction change almost
        // never changes the displayed state. Skip only when the item is
        // present and matches; a withdrawn or never-applied state re-asserts.
        // The length calls already no-op when unchanged, so this saves the
        // image rebuild.
        if lastAppliedThawIconDisplayed == shouldShow, isAddedToMenuBar {
            return
        }
        lastAppliedThawIconDisplayed = shouldShow

        if shouldShow {
            updateStatusItem()
        } else {
            collapseStatusItem()
        }
    }

    /// Reasserts the Thaw icon's AppKit state after the system applies a menu
    /// bar visibility restriction.
    ///
    /// Deliberately lighter than unregistering and re-registering the item: it
    /// stays owned by the app throughout, and only its visibility flags, length,
    /// constraint and image are refreshed once MenuBarAgent has finished
    /// reflowing the bar.
    func restoreVisibleIconAfterRestrictionChange() {
        guard identifier == .visible else {
            return
        }
        setThawIconDisplayed(configuration.showThawIcon == true)
        reassertVisibleIconImage()
    }

    /// Redraws the Thaw icon for a visible item AppKit drew blank, because
    /// setThawIconDisplayed(_:) or a degenerate geometry read can leave it so.
    private func reassertVisibleIconImage() {
        guard identifier == .visible, let appState, let button = statusItem.button else {
            return
        }
        applyIconAppearance(to: button, appState: appState)
    }
}

// MARK: - Menu bar registration

extension ControlItem {
    /// Publishes the status item to the menu bar.
    private func addToMenuBar() {
        guard !isAddedToMenuBar else {
            return
        }
        statusItem.isVisible = true
    }

    /// Withdraws the status item from the menu bar.
    private func removeFromMenuBar() {
        guard isAddedToMenuBar else {
            return
        }

        // Clearing isVisible also deletes the item's stored placement and
        // visibility. Losing the placement is accepted, dividers never persist
        // one, and the system re-places the Thaw icon, but the visibility
        // flags must survive, or AppKit will refuse to publish the item on the
        // next launch.
        statusItem.isVisible = false
        ControlItemDefaults.restoreVisibilityIfNeeded(autosaveName: statusItem.autosaveName as String)
    }

    /// Withdraws the control item ahead of the app terminating.
    ///
    /// A status item is not reliably dropped when its owning process exits: the
    /// icon and its now-dead menu linger as a ghost. Removing it while the app
    /// is still alive lets MenuBarAgent reclaim the slot cleanly.
    func tearDownForTermination() {
        // A control item that was never shown must not register a status item
        // on the way out. Doing so would install activation handlers nothing
        // will ever use, and can trap in debug builds when AppKit's type
        // encodings drift.
        guard registeredHost != nil else {
            return
        }
        removeFromMenuBar()
    }
}

// MARK: - MenuBarAgent layout nudge

extension ControlItem {
    /// Bookkeeping for the temporary width change used to provoke a MenuBarAgent
    /// layout pass.
    private struct MenuBarAgentNudge {
        /// The in-flight nudge, if any.
        var task: Task<Void, Never>?

        /// The length to put back once the nudge has served its purpose.
        var lengthToRestore: CGFloat?

        /// Incremented per request, so a superseded nudge can recognize that it
        /// no longer owns the item's length.
        var generation = 0
    }

    /// Provokes a MenuBarAgent layout pass after Thaw has rewritten
    /// the preferred-position table.
    ///
    /// MenuBarAgent does not act on a cross-process write until the owning
    /// status item's layout is invalidated. The temporary length matches the
    /// width the button already renders at, so nothing hides, the compositor
    /// does not flash, and the pointer does not move.
    ///
    /// Skipped while a reveal or hide is still reflowing, because changing the
    /// icon's length then keeps invalidating its hit target and rehide clicks
    /// miss. A section merely left open is settled and allowed, otherwise every
    /// hidden-section move would fall to the synthetic drag.
    ///
    /// Returns whether a nudge was armed. After a skipped nudge the write was
    /// never observable, so callers must not count the following poll as
    /// evidence about whether MenuBarAgent honors the store.
    @discardableResult
    func requestMenuBarAgentPositionRefresh() -> Bool {
        guard !shouldSuppressPositionNudge else {
            diagLog.debug("Skipping MenuBarAgent position refresh during a reveal/hide transition")
            return false
        }

        nudge.generation += 1
        let generation = nudge.generation
        nudge.task?.cancel()
        if let lengthToRestore = nudge.lengthToRestore {
            statusItem.length = lengthToRestore
            nudge.lengthToRestore = nil
        }

        nudge.task = Task { @MainActor [weak self] in
            // Give cfprefsd a moment to deliver the preference change before
            // provoking the layout pass; otherwise MenuBarAgent can persist its
            // stale in-memory order over Thaw's fresh write.
            try? await Task.sleep(for: .milliseconds(50))
            guard let self, !Task.isCancelled, generation == nudge.generation else {
                return
            }

            // A reveal may have begun during the settle delay.
            guard !shouldSuppressPositionNudge else {
                diagLog.debug("Skipping MenuBarAgent position refresh; reveal began during settle")
                nudge.task = nil
                return
            }

            let baseline = statusItem.length
            guard let temporaryLength = Self.menuBarAgentLayoutNudgeLength(
                currentLength: baseline,
                renderedWidth: statusItem.button?.bounds.width ?? 0
            ) else {
                nudge.task = nil
                return
            }

            nudge.lengthToRestore = baseline
            statusItem.length = temporaryLength
            diagLog.debug("Invalidated status-item width to refresh MenuBarAgent positions")

            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled, generation == nudge.generation else {
                return
            }
            statusItem.length = baseline
            nudge.lengthToRestore = nil
            nudge.task = nil
        }
        return true
    }

    /// Whether the width nudge must be held off: the fixed reflow-settle window
    /// or an in-flight reveal/hide transition (see
    /// MenuBarManager.shouldSuppressMenuBarAgentNudge).
    private var shouldSuppressPositionNudge: Bool {
        appState?.menuBarManager.shouldSuppressMenuBarAgentNudge == true
    }
}

// MARK: - Activation

extension ControlItem {
    /// Whether the system menu bar is currently drawn on this item's screen.
    ///
    /// Clicks are suppressed while it is not. A fast click at the top of the
    /// screen during the reveal sequence under a fullscreen app would otherwise
    /// expand the hidden section off screen. currentSystemPresentationOptions
    /// is per-app and says nothing about another app's fullscreen state, so the
    /// rendered menu bar is consulted directly.
    private var isSystemMenuBarOnScreen: Bool {
        guard let screen = window?.screen ?? NSScreen.main else {
            return true
        }
        return screen.isSystemMenuBarVisible()
    }

    /// Handles a click delivered through AppKit's target/action path.
    ///
    /// Deliberately nonisolated. AppKit may deliver this on any thread: an
    /// accessibility press of this item issued from inside this process (the
    /// kit's RuntimeAXPresser) is answered inline on the pressing queue
    /// rather than on the main thread, and a @MainActor entry point would
    /// trip the dispatch-queue assertion and crash. The entry point hops to
    /// the main actor itself.
    @objc private nonisolated func performAction() {
        if Thread.isMainThread {
            // The ordinary target/action path: already on the main thread
            // during event processing, where NSApp.currentEvent is valid.
            MainActor.assumeIsolated {
                self.performActionOnMain()
            }
        } else {
            // Same-process accessibility press (RuntimeAXPresser): delivered
            // inline on the pressing queue. NSApp.currentEvent is main-thread
            // event state and is nil for AX-initiated presses anyway, so this
            // path only needs the hop, not the event.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.performActionOnMain()
                }
            }
        }
    }

    /// The click policy, on the actor the rest of the app expects it on.
    @MainActor private func performActionOnMain() {
        guard
            let appState,
            let event = NSApp.currentEvent,
            isSystemMenuBarOnScreen
        else {
            return
        }

        switch event.type {
        case .leftMouseDown:
            // Read the event's state now rather than when the task runs, so a
            // later click cannot rewrite this one's meaning.
            let modifierFlags = event.modifierFlags
            let clickCount = event.clickCount

            // Hopping through a task noticeably improves how responsive the
            // button feels.
            Task { [appState] in
                self.respondToClick(
                    modifierFlags: modifierFlags,
                    clickCount: clickCount,
                    appState: appState
                )
            }
        case .rightMouseUp:
            showMenu()
        default:
            return
        }
    }

    /// Applies the click policy for the target/action path.
    private func respondToClick(
        modifierFlags: NSEvent.ModifierFlags,
        clickCount: Int,
        appState: AppState
    ) {
        let menuBarManager = appState.menuBarManager
        let intent = Self.primaryActionIntent(
            identifier: identifier,
            modifierFlags: modifierFlags,
            clickCount: clickCount,
            usesDoubleClick: configuration.isAlwaysHiddenSectionEnabled,
            usesOptionClick: configuration.isAlwaysHiddenSectionEnabled
        )

        switch intent {
        case .toggleSection:
            toggleOwnSectionOrSwap(menuBarManager: menuBarManager)
        case .showAlwaysHidden:
            if let alwaysHidden = menuBarManager.section(withName: .alwaysHidden), alwaysHidden.isEnabled {
                alwaysHidden.show()
            }
        case .toggleAlwaysHidden:
            if let alwaysHidden = menuBarManager.section(withName: .alwaysHidden), alwaysHidden.isEnabled {
                alwaysHidden.toggle()
            }
        case .contextMenu:
            showMenu()
        case .none:
            break
        }
    }

    /// Toggles the section this control item belongs to, if it is enabled.
    /// A plain click on the Thaw icon swaps Visible and Hidden when the user
    /// asked for that, and otherwise reveals or hides the section as always.
    /// Dividers never swap.
    private func toggleOwnSectionOrSwap(menuBarManager: MenuBarManager) {
        if identifier == .visible, configuration.swapOnThawIconClick {
            menuBarManager.toggleSwap()
            return
        }
        toggleOwnSection(menuBarManager: menuBarManager)
    }

    private func toggleOwnSection(menuBarManager: MenuBarManager) {
        if let section = menuBarManager.section(withName: sectionName), section.isEnabled {
            section.toggle()
        }
    }

    /// Handles the semantic primary action MenuBarAgent forwards for the Thaw
    /// icon.
    ///
    /// Control-click and right-click context menus do not arrive here; they are
    /// routed through HIDEventManager, because MenuBarAgent does not forward
    /// secondary gestures from a remotely hosted status button.
    @objc private func performPrimaryAction() {
        guard let appState, isSystemMenuBarOnScreen else {
            return
        }

        // The recorded press-time state wins, then NSApp.currentEvent, then
        // the live keyboard state, which can already show the option released.
        let pressModifiers = primaryPressModifiers
        primaryPressModifiers = nil
        let event = NSApp.currentEvent
        let modifierFlags = Self.resolvedPrimaryModifierFlags(
            pressModifiers: pressModifiers,
            eventModifiers: event?.modifierFlags,
            liveModifiers: NSEvent.modifierFlags
        )
        // MenuBarAgent can report clickCount=1 for both clicks.
        // Pair activations on this icon using the system interval instead.
        let clickCount = primaryActivationSequence.clickCount(
            at: ProcessInfo.processInfo.systemUptime,
            location: NSEvent.mouseLocation,
            modifiers: NSEvent.modifierFlags,
            interval: NSEvent.doubleClickInterval,
            enabled: identifier == .visible && configuration.isAlwaysHiddenSectionEnabled
        )
        diagLog.debug("PrimaryActivationTrace: reportedClickCount=\(event?.clickCount ?? 0), resolvedClickCount=\(clickCount)")
        let intent = Self.menuBarAgentPrimaryActionIntent(
            identifier: identifier,
            modifierFlags: modifierFlags,
            clickCount: clickCount,
            usesDoubleClick: configuration.isAlwaysHiddenSectionEnabled,
            usesOptionClick: configuration.isAlwaysHiddenSectionEnabled,
            diagLog: diagLog
        )

        // Applied synchronously: a task hop let rapid clicks queue conflicting
        // toggles. Routed through the section, which owns the Thaw Bar decision.
        let menuBarManager = appState.menuBarManager
        switch intent {
        case .toggleSection:
            toggleOwnSectionOrSwap(menuBarManager: menuBarManager)
        case .showAlwaysHidden:
            guard let alwaysHidden = menuBarManager.section(withName: .alwaysHidden), alwaysHidden.isEnabled else {
                logUnavailableAlwaysHiddenSection(for: "showAlwaysHidden", menuBarManager: menuBarManager)
                break
            }
            // A stale click count can turn an ordinary click into a
            // double-click intent, and that must read as a hide rather than as
            // nothing at all.
            if alwaysHidden.isHidden {
                alwaysHidden.show()
            } else {
                diagLog.debug("performPrimaryAction: showAlwaysHidden while revealed → hide")
                alwaysHidden.hide()
            }
        case .toggleAlwaysHidden:
            guard let alwaysHidden = menuBarManager.section(withName: .alwaysHidden), alwaysHidden.isEnabled else {
                logUnavailableAlwaysHiddenSection(for: "toggleAlwaysHidden", menuBarManager: menuBarManager)
                break
            }
            alwaysHidden.toggle()
        case .contextMenu, .none:
            break
        }
    }

    private func logUnavailableAlwaysHiddenSection(for intent: String, menuBarManager: MenuBarManager) {
        let section = menuBarManager.section(withName: .alwaysHidden)
        diagLog.debug(
            "performPrimaryAction: \(intent), section found=\(section != nil), isEnabled=\(section?.isEnabled ?? false)"
        )
    }
}

// MARK: - Menu

extension ControlItem {
    /// Presents the control item's menu beneath the status item.
    private func showMenu() {
        if let panel = appState?.controlItemPanel, panel.isEnabled {
            panel.toggle(anchor: statusItem.button, fallbackPoint: MouseHelpers.locationAppKit)
            return
        }
        guard let menu = menuController?.makeMenu() else {
            return
        }
        statusItem.showMenu(menu)
    }

    /// Presents the control item's menu at a screen location.
    ///
    /// Used because MenuBarAgent does not forward the secondary-click gesture
    /// through the remotely hosted status button, so the menu has to be raised
    /// at the point the HID event reported.
    func showContextMenu(at point: CGPoint) {
        if let panel = appState?.controlItemPanel, panel.isEnabled {
            panel.toggle(anchor: statusItem.button, fallbackPoint: point)
            return
        }
        guard let menu = menuController?.makeMenu() else {
            return
        }
        menu.popUp(positioning: nil, at: point, in: nil)
    }
}

// MARK: - Diagnostics

extension ControlItem {
    /// A one-line snapshot of the item's AppKit and defaults state.
    func diagnosticStateDescription() -> String {
        guard registeredHost != nil else {
            return "id=\(identifier.rawValue) host=unregistered"
        }
        let autosaveName = statusItem.autosaveName as String
        let button = statusItem.button
        let window = button?.window ?? window
        let accessibilityIdentifier = button?.accessibilityIdentifier()

        // The identity fields are logged in full because MenuBarAgent may key
        // the restriction's item set on any of them, and it reports
        // "No server elements for status item: nil" for Thaw's items, so
        // everything Thaw exposes is recorded to compare against a known-good
        // app's item.
        let fields = [
            "id=\(identifier.rawValue)",
            "autosaveName=\(autosaveName)",
            "buttonID=\(button?.identifier?.rawValue ?? "nil")",
            "buttonA11yID=\(accessibilityIdentifier.flatMap { $0.isEmpty ? nil : $0 } ?? "nil")",
            "windowID=\(window?.identifier?.rawValue ?? "nil")",
            "bundleID=\(Bundle.main.bundleIdentifier ?? "nil")",
            "state=\(state)",
            "statusVisible=\(statusItem.isVisible)",
            "length=\(statusItem.length)",
            "buttonExists=\(button != nil)",
            "buttonEnabled=\(button?.isEnabled.description ?? "nil")",
            "buttonAlpha=\(button.map { "\($0.alphaValue)" } ?? "nil")",
            "appearsDisabled=\(button?.appearsDisabled.description ?? "nil")",
            "hasImage=\((button?.image) != nil)",
            "windowNumber=\(window.map { "\($0.windowNumber)" } ?? "nil")",
            "windowFrame=\(window.map { NSStringFromRect($0.frame) } ?? "nil")",
            "buttonFrame=\(button.map { NSStringFromRect($0.frame) } ?? "nil")",
            "windowVisible=\(window?.isVisible.description ?? "nil")",
            "windowOnActiveSpace=\(window?.isOnActiveSpace.description ?? "nil")",
            "showThawIcon=\(String(describing: configuration.showThawIcon))",
            "lastAppliedDisplayed=\(String(describing: lastAppliedThawIconDisplayed))",
            "nudgeInFlight=\(nudge.task != nil)",
            "nudgeRestoreLength=\(String(describing: nudge.lengthToRestore))",
            "defaultsVisible=\(storedDefault(.visible, autosaveName))",
            "defaultsVisibleCC=\(storedDefault(.visibleCC, autosaveName))",
            "defaultsPreferredPosition=\(storedDefault(.preferredPosition, autosaveName))",
        ]
        return fields.joined(separator: " ")
    }

    /// A stored default rendered for the diagnostic line, or "nil".
    private func storedDefault(
        _ key: ControlItemDefaults.Key<some Any>,
        _ autosaveName: String
    ) -> String {
        ControlItemDefaults[key, autosaveName].map(String.init(describing:)) ?? "nil"
    }
}
