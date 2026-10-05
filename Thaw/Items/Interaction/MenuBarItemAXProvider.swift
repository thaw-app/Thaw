//
//  MenuBarItemAXProvider.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import AXSwift6
import Cocoa
import MenuBarModel
import os.lock
import PlatformRuntimeKit
import ThawAXCore

typealias NativeOverflowObservation = PlatformRuntimeKit.NativeOverflowObservation

/// Enumerates menu bar items through the Accessibility tree.
///
/// On macOS 27 the CGS window list returns only the backdrop and the
/// MenuBarAgent XPC interface needs private entitlements, so AX is all that is left.
///
/// Each app publishes its items under its own AXExtrasMenuBar, so the
/// publisher is the owner; system items come from MenuBarAgent. Read-only.
nonisolated enum MenuBarItemAXProvider {
    private static let diagLog = DiagLog(category: "MenuBarItemAXProvider")

    /// Floor for maxItemHeight(menuBarHeight:), above any standard bar.
    private static let minimumItemHeightCeiling: CGFloat = 40

    /// The tallest an extras-bar child may be and still count as a status item;
    /// taller children are popovers or panels. Apple's modules report the full
    /// bar height, which passes 40 pt on a notched bar at high scaled resolutions.
    ///
    /// - Parameter menuBarHeight: The tallest known menu bar, if any.
    static func maxItemHeight(menuBarHeight: CGFloat?) -> CGFloat {
        max(minimumItemHeightCeiling, (menuBarHeight ?? 0).rounded(.up) + 1)
    }

    /// Discovery and capture must skip the same frames to keep Item-N numbering aligned.
    static func itemFrame(_ reported: CGRect?, maximumHeight: CGFloat) -> CGRect? {
        guard let reported, reported.height > 0, reported.height <= maximumHeight else { return nil }
        return reported
    }

    /// Whether an AX-reported item frame lies on the given display.
    ///
    /// For locating a known item's seat, not for narrowing the inventory:
    /// macOS 27 mirrors one status-item set on every bar. Uses the midpoint
    /// so a straddling item goes to the display it mostly occupies.
    static func frame(_ frame: CGRect, isWithin displayBounds: CGRect) -> Bool {
        AXPrimitives.frame(frame, isWithin: displayBounds)
    }

    /// Returns the menu bar items for the given display by walking the
    /// Accessibility tree of every running application.
    ///
    /// - Parameters:
    ///   - display: A display to filter to, or nil for all displays.
    ///   - option: Accepted for parity with the CGS path; AX only reports
    ///     on-screen items anyway.
    static func menuBarItems(
        on display: CGDirectDisplayID? = nil,
        option: MenuBarItem.ListOption
    ) -> [MenuBarItem] {
        enumerateMenuBarItems(on: display, option: option, deadline: nil).items
    }

    /// Restores identities a transition walk left unnamed before the items
    /// leave the provider.
    ///
    /// Every consumer must see the same identities, or the position store
    /// resolves a positional name like Item-3 against an unrelated row.
    /// See MenuBarAgentIdentityReconciler.
    private static func restoredIdentities(_ items: [MenuBarItem]) -> [MenuBarItem] {
        MenuBarAgentIdentityReconciler.reconciling(items).items
    }

    private static func restoredIdentities(_ snapshot: InventorySnapshot) -> InventorySnapshot {
        InventorySnapshot(
            items: restoredIdentities(snapshot.items),
            freshItems: restoredIdentities(snapshot.freshItems),
            completed: snapshot.completed,
            hasFreshKnownInventory: snapshot.hasFreshKnownInventory,
            hasFreshMoveInventory: snapshot.hasFreshMoveInventory
        )
    }

    /// menuBarItems(on:option:) with an optional wall-clock ceiling.
    ///
    /// Each message is capped at 0.25 s but the walk is not, so one slow app
    /// can hold the caller (and on main, all mouse input) for seconds.
    /// deadline is checked between apps and children; an in-flight message
    /// still runs to completion.
    ///
    /// - Returns: the items, and whether the walk completed. A truncated walk
    ///   does not prove items gone, so callers must not read it as departures.
    static func enumerateMenuBarItems(
        on display: CGDirectDisplayID? = nil,
        option _: MenuBarItem.ListOption,
        deadline: ContinuousClock.Instant?
    ) -> (items: [MenuBarItem], completed: Bool) {
        guard AXHelpers.isProcessTrusted() else {
            diagLog.warning("menuBarItems: accessibility permission missing; cannot enumerate")
            return ([], false)
        }

        let ourBundleID = Bundle.main.bundleIdentifier
        var raw: [RawItem] = []
        let itemHeightCeiling = maxItemHeight(menuBarHeight: NSScreen.tallestCachedMenuBarHeight)
        var isOutOfTime: Bool {
            guard let deadline else { return false }
            return ContinuousClock.now >= deadline
        }

        for runningApp in NSWorkspace.shared.runningApplications {
            if isOutOfTime {
                diagLog.warning(
                    "menuBarItems: walk exceeded its budget before \(runningApp.bundleIdentifier ?? "(unnamed)"); returning incomplete"
                )
                return (restoredIdentities(assemble(raw)), false)
            }
            let appBundleID = runningApp.bundleIdentifier ?? runningApp.localizedName ?? "(pid \(runningApp.processIdentifier))"

            guard let app = AXHelpers.application(for: runningApp) else {
                continue
            }
            guard let bar = AXHelpers.extrasMenuBar(for: app) else {
                // Without its own extras bar Thaw cannot find its control items.
                if runningApp.bundleIdentifier == ourBundleID {
                    diagLog.warning("menuBarItems: Thaw (\(appBundleID)) has no AXExtrasMenuBar, control items cannot be discovered")
                }
                continue
            }

            let children = AXHelpers.children(for: bar)
            diagLog.debug("menuBarItems: \(appBundleID) → \(children.count) child(ren) in AXExtrasMenuBar")
            guard !children.isEmpty else {
                continue
            }

            let namespace = namespace(for: runningApp)
            // The native overflow chevron, identified by AXOverflowButton (not
            // its localized title) plus the memo's last-seen frames. Either
            // match drops the child.
            let overflowControl: (elements: [AXSwift6.UIElement], frames: [CGRect]) = namespace == .menuBarAgent
                ? nativeOverflowControlSignature(bar: bar, on: display)
                : ([], [])
            // Per-app fallback index so untitled items get distinct titles
            // ("Item-0", "Item-1", …), mirroring the CGS window titles.
            var fallbackIndex = 0
            var diagnosticChildDescriptions: [String] = []

            for child in children {
                if isOutOfTime {
                    diagLog.warning(
                        "menuBarItems: walk exceeded its budget inside \(appBundleID); returning incomplete"
                    )
                    return (restoredIdentities(assemble(raw)), false)
                }
                // One message for all five attributes costs the same as the
                // frame alone.
                let attributes = AXHelpers.menuBarChildAttributes(for: child)
                // Skip incidental children (open popovers / panels).
                guard let frame = Self.itemFrame(attributes.frame, maximumHeight: itemHeightCeiling) else {
                    continue
                }
                // No per-display filter: macOS 27 renders one status-item set on
                // every bar, with frames stated against a single bar's layout.
                if overflowControl.elements.contains(child)
                    || overflowControl.frames.contains(where: { Self.frame(frame, matches: $0) })
                {
                    diagLog.debug("menuBarItems: skipping native overflow control (structural) frame=\(frame)")
                    continue
                }

                // Identity is kept apart from the live title. Some apps publish
                // it on the button, so scan one level down, only when needed.
                let directIdentifier = attributes.identifier?.nonEmpty
                let directDescription = attributes.accessibilityDescription?.nonEmpty
                let (childIdentifier, childDescription) = Self.descendantIdentity(
                    of: attributes,
                    directIdentifier: directIdentifier,
                    directDescription: directDescription
                )

                // Direct attribution: the owning process is the app that
                // published this child (fall back to the element's own PID).
                let ownerPID = AXHelpers.pid(for: child) ?? runningApp.processIdentifier
                let derived = Self.rawItem(
                    namespace: namespace,
                    identifier: directIdentifier,
                    childIdentifier: childIdentifier,
                    accessibilityDescription: directDescription,
                    childDescription: childDescription,
                    axTitle: attributes.title?.nonEmpty,
                    fallbackIndex: fallbackIndex,
                    bounds: frame,
                    ownerPID: ownerPID
                )
                fallbackIndex = derived.fallbackIndex
                guard let item = derived.item else {
                    diagLog.debug("menuBarItems: skipping native overflow control (title) title='\(derived.identityTitle)' frame=\(frame)")
                    continue
                }

                if runningApp.bundleIdentifier == ourBundleID {
                    diagLog.debug("menuBarItems: Thaw item, title='\(derived.identityTitle)' frame=\(frame) ownerPID=\(ownerPID)")
                }

                if Defaults.bool(forKey: .diagnosticRestrictionSceneProbes),
                   runningApp.bundleIdentifier == SharedConstants.menuBarHostingBundleID
                {
                    diagnosticChildDescriptions.append(
                        "\(derived.identityTitle) frame=\(NSStringFromRect(frame)) ownerPID=\(ownerPID)"
                    )
                }

                raw.append(item)
            }

            if Defaults.bool(forKey: .diagnosticRestrictionSceneProbes),
               runningApp.bundleIdentifier == SharedConstants.menuBarHostingBundleID
            {
                diagLog.info(
                    "menuBarItems: MenuBarAgent children: " +
                        diagnosticChildDescriptions.joined(separator: " | ")
                )
            }
        }

        let items = assemble(raw)
        diagLog.debug("menuBarItems: enumerated \(items.count) items via AX (display=\(display.map { "\($0)" } ?? "all"))")
        return (restoredIdentities(items), true)
    }

    /// Owners that missed their per-app deadline. Cooldowns expire, so an app
    /// slow once in a launch storm is not banished; see SlowResponderLedger.
    private static let slowResponders = OSAllocatedUnfairLock(
        initialState: SlowResponderLedger()
    )

    /// Owners whose empty extras-bar read has been logged, with the AX result
    /// it gave. The wrapper folds "no value" into nil, so without this a host
    /// the walk cannot see is indistinguishable from an app with no items.
    private static let loggedEmptyExtrasBarReads = OSAllocatedUnfairLock(
        initialState: [pid_t: AXError]()
    )

    private static let perAppWalkBudget = Duration.milliseconds(400)

    /// Late answers from apps that missed their deadline, merged by the next
    /// walk so a slow app's icon is one pass late instead of absent.
    private struct LateAnswer: Sendable {
        let ownerPID: pid_t
        let generation: UInt64
        let raw: [RawItem]
    }

    private static let lateAnswers = AsyncChannel<LateAnswer>()
    private static let lateAnswerPumpStarted = OSAllocatedUnfairLock(initialState: false)
    private static let mergedLateAnswers = OSAllocatedUnfairLock(
        initialState: [pid_t: LateAnswer]()
    )

    /// Starts the one-time pump for late answers. The flag's result must be
    /// used: a return inside the lock closure only leaves the closure, and
    /// every enumeration would spawn another immortal consumer.
    private static func startLateAnswerPump() {
        let shouldStart = lateAnswerPumpStarted.withLock { started -> Bool in
            guard !started else { return false }
            started = true
            return true
        }
        guard shouldStart else { return }
        Task {
            for await answer in lateAnswers {
                mergedLateAnswers.withLock { answers in
                    if (answers[answer.ownerPID]?.generation ?? 0) <= answer.generation {
                        answers[answer.ownerPID] = answer
                    }
                }
            }
        }
    }

    /// The concurrent walk with a per-app deadline, so one slow app cannot eat
    /// the budget every pass and leave "Loading menu bar items" stuck.
    ///
    /// A timed-out app is skipped but its detached task keeps running.
    /// Skipped bundles are memoized with an expiry so a slow-once app is retried.
    private static func enumerateMenuBarItemsResilient(
        state previousState: MenuBarScanState<RawItem>,
        scope: MenuBarScanScope,
        priorityPIDs: Set<pid_t>
    ) async -> (snapshot: InventorySnapshot, state: MenuBarScanState<RawItem>) {
        guard AXHelpers.isProcessTrusted() else {
            diagLog.warning("menuBarItems: accessibility permission missing; cannot enumerate")
            return (.unavailable, MenuBarScanState())
        }

        let ourBundleID = Bundle.main.bundleIdentifier
        let runningApps = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        let appsByPID = Dictionary(runningApps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let controlPIDs = Set(runningApps.filter {
            $0.bundleIdentifier == ourBundleID || $0.bundleIdentifier == SharedConstants.menuBarHostingBundleID
        }.map(\.processIdentifier))
        var state = previousState
        let requiredOwners = controlPIDs.union(priorityPIDs)
        let pass = state.begin(
            owners: runningApps.map(\.processIdentifier),
            priorityOwners: requiredOwners,
            scope: scope
        )
        // A chronically slow app must not refuse every move, so slow owners
        // are excused from move geometry unless the move names them.
        var slowOwners: [Int32: String] = [:]
        slowResponders.withLock { $0.retain(runningOwners: Set(appsByPID.keys)) }
        var truncated = false
        startLateAnswerPump()
        let late = mergedLateAnswers.withLock { dict -> [LateAnswer] in
            let drained = Array(dict.values)
            dict.removeAll()
            return drained
        }
        if !late.isEmpty {
            for answer in late {
                state.record(answer.raw, owner: answer.ownerPID, generation: answer.generation)
            }
            diagLog.info("menuBarItems: merged \(late.count) late answer(s) from slow responders")
        }
        // Scale the discovery ceiling with the process count so a walk on a
        // process-heavy machine is not cut off mid-pass; the 1.5 s floor
        // bounds small tables and the per-app deadline caps any one slow app.
        let globalBudget = max(
            Duration.milliseconds(1500),
            Duration.milliseconds(15) * pass.owners.count
        )
        let walkStart = ContinuousClock.now
        let globalDeadline = walkStart + globalBudget

        // Discovery probes every app; a move refreshes selected owners. The
        // counters tell one slow app from sheer app count in the log.
        var appsProbed = 0
        var appsWithExtrasBar = 0
        defer {
            let elapsed = ContinuousClock.now - walkStart
            diagLog.info(
                """
                menuBarItems: \(scope == .discovery ? "discovery" : "targeted") walk \
                \(truncated ? "TRUNCATED" : "completed") in \(elapsed), \
                probed \(appsProbed)/\(pass.owners.count) selected / \(runningApps.count) running app(s), \
                \(appsWithExtrasBar) had an extras menu bar, budget \(globalBudget)
                """
            )
        }

        for ownerPID in pass.owners {
            guard !Task.isCancelled else { truncated = true; break }
            if ContinuousClock.now >= globalDeadline {
                // Logged so a machine that never completes a walk leaves
                // evidence of how far it got.
                diagLog.warning(
                    """
                    menuBarItems: global budget \(globalBudget) exhausted after \
                    \(appsProbed)/\(pass.owners.count) selected app(s); returning incomplete
                    """
                )
                truncated = true
                break
            }
            guard let runningApp = appsByPID[ownerPID] else { continue }
            appsProbed += 1
            let appBundleID = runningApp.bundleIdentifier
                ?? runningApp.localizedName
                ?? "(pid \(runningApp.processIdentifier))"
            let skipsOwner: Bool
            switch slowResponders.withLock({ $0.decision(for: ownerPID) }) {
            case .probe:
                skipsOwner = false
            case .skipInFlight, .skipCoolingDown:
                skipsOwner = true
            case .probeIfResponsive:
                // Asked outside the lock: a window server round trip, paid only
                // by owners that were slow before.
                skipsOwner = Bridging.isProcessUnresponsive(ownerPID)
                if skipsOwner {
                    let cooldown = slowResponders.withLock { $0.stillUnresponsive(ownerPID) }
                    diagLog.warning(
                        "menuBarItems: \(appBundleID) is not responding; skipping it for \(cooldown)"
                    )
                }
            }
            if skipsOwner {
                // Not observed, so the walk is incomplete; a complete-but-short
                // answer would read its icon as departed until the cooldown ends.
                truncated = true
                slowOwners[ownerPID] = appBundleID
                continue
            }

            state.didAttempt(owner: ownerPID, generation: pass.generation)
            let collected = Task.detached(priority: .userInitiated) {
                Self.collectApp(
                    runningApp: runningApp,
                    appBundleID: appBundleID,
                    display: nil,
                    displayBounds: nil,
                    ourBundleID: ourBundleID
                )
            }
            let collectedResult = await withTaskGroup(
                of: CollectAppResult?.self
            ) { group in
                // Awaiting collected.value directly ignores cancelAll(), so the
                // group would wait for the hung AX call and defeat the deadline.
                group.addTask { await Self.valueOrCancelled(of: collected) }
                group.addTask {
                    try? await Task.sleep(for: Self.perAppWalkBudget)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            switch collectedResult {
            case .none where Task.isCancelled:
                // Foreground geometry can interrupt discovery. Keep this answer
                // when it arrives, but do not label the owner a slow responder.
                truncated = true
                Task {
                    let late = await collected.value
                    await Self.lateAnswers.send(LateAnswer(ownerPID: ownerPID, generation: pass.generation, raw: late))
                }
            case .none:
                let (cooldown, strikes) = slowResponders.withLock {
                    ($0.timedOut(ownerPID), $0.strikes(for: ownerPID))
                }
                diagLog.warning(
                    "menuBarItems: \(appBundleID) exceeded its per-app deadline (miss \(strikes)); skipping it for \(cooldown)"
                )
                truncated = true
                slowOwners[ownerPID] = appBundleID
                // Publish the late answer for the next walk; until then the
                // ledger holds off another probe of the owner.
                Task {
                    let late = await collected.value
                    slowResponders.withLock { $0.lateAnswerArrived(ownerPID) }
                    await Self.lateAnswers.send(LateAnswer(ownerPID: ownerPID, generation: pass.generation, raw: late))
                }
            case let .some(result):
                slowResponders.withLock { $0.answered(ownerPID) }
                if !result.isEmpty {
                    appsWithExtrasBar += 1
                }
                state.record(result, owner: ownerPID, generation: pass.generation)
            }
        }

        let items = assemble(state.observations)
        let freshItems = assemble(state.freshObservations(generation: pass.generation))
        diagLog.debug("menuBarItems: inventory=\(items.count), fresh=\(freshItems.count), truncated=\(truncated)")
        let excused = Set(slowOwners.keys).subtracting(requiredOwners)
        let hasFreshMoveInventory = !Task.isCancelled && state.isComplete(pass, excusing: excused)
            && state.hasFreshKnownInventory(generation: pass.generation, excusing: excused)
        if hasFreshMoveInventory, !excused.isEmpty {
            diagLog.info(
                "menuBarItems: move geometry excuses slow owner(s) \(excused.compactMap { slowOwners[$0] }.sorted())"
            )
        }
        return (InventorySnapshot(
            items: items,
            freshItems: freshItems,
            completed: state.isComplete(generation: pass.generation),
            hasFreshKnownInventory: state.hasFreshKnownInventory(generation: pass.generation),
            hasFreshMoveInventory: hasFreshMoveInventory
        ), state)
    }

    /// Awaits task's value, or nil if the waiter is cancelled first.
    /// Task.value on a non-throwing task ignores cancellation.
    private static func valueOrCancelled<T: Sendable>(of task: Task<T, Never>) async -> T? {
        if Task.isCancelled {
            return nil
        }
        let race = TimeoutRace<T>()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                race.awaitOutcome(continuation)
                // Spawned after registration so the value side cannot settle
                // before there is a continuation to settle. The watcher lives
                // only as long as the blocked call does.
                race.observeValue(of: task)
            }
        }, onCancel: {
            race.cancel()
        })
    }

    /// Settles valueOrCancelled(of:) exactly once, whichever side lands first.
    private final class TimeoutRace<T: Sendable>: @unchecked Sendable {
        private enum State {
            case open
            case awaiting(CheckedContinuation<T?, Never>)
            case cancelled
        }

        private let state = OSAllocatedUnfairLock<State>(initialState: .open)

        /// Registers the continuation, or resumes it immediately with nil
        /// when cancellation already won.
        func awaitOutcome(_ continuation: CheckedContinuation<T?, Never>) {
            let cancelledFirst = state.withLock { state -> Bool in
                if case .cancelled = state {
                    return true
                }
                state = .awaiting(continuation)
                return false
            }
            if cancelledFirst {
                continuation.resume(returning: nil)
            }
        }

        /// Settles with the task's value when it arrives, unless cancellation
        /// got there first.
        func observeValue(of task: Task<T, Never>) {
            Task.detached(priority: .utility) {
                let value = await task.value
                let continuation = self.state.withLock { state -> CheckedContinuation<T?, Never>? in
                    guard case let .awaiting(continuation) = state else { return nil }
                    state = .cancelled
                    return continuation
                }
                continuation?.resume(returning: value)
            }
        }

        /// Cancellation's settlement.
        func cancel() {
            let continuation = state.withLock { state -> CheckedContinuation<T?, Never>? in
                guard case let .awaiting(continuation) = state else {
                    state = .cancelled
                    return nil
                }
                state = .cancelled
                return continuation
            }
            continuation?.resume(returning: nil)
        }
    }

    private typealias CollectAppResult = [RawItem]

    /// The per-app enumeration body shared by both walks. Returns the app's
    /// raw items; an app with no extras bar or no children contributes an
    /// empty array.
    private static func collectApp(
        runningApp: NSRunningApplication,
        appBundleID: String,
        display: CGDirectDisplayID?,
        displayBounds: CGRect?,
        ourBundleID: String?
    ) -> [RawItem] {
        guard let app = AXHelpers.application(for: runningApp) else {
            return []
        }
        guard let bar = AXHelpers.extrasMenuBar(for: app) else {
            if runningApp.bundleIdentifier == ourBundleID {
                diagLog.warning(
                    "menuBarItems: Thaw (\(appBundleID)) has no AXExtrasMenuBar, control items cannot be discovered"
                )
            }
            logEmptyExtrasBarReadOnce(for: runningApp, appBundleID: appBundleID, hasBar: false)
            return []
        }

        let children = AXHelpers.children(for: bar)
        guard !children.isEmpty else {
            logEmptyExtrasBarReadOnce(for: runningApp, appBundleID: appBundleID, hasBar: true)
            return []
        }

        let namespace = namespace(for: runningApp)
        let overflowControl: (elements: [AXSwift6.UIElement], frames: [CGRect]) = namespace == .menuBarAgent
            ? nativeOverflowControlSignature(bar: bar, on: display)
            : ([], [])
        var fallbackIndex = 0
        var raw: [RawItem] = []
        let itemHeightCeiling = maxItemHeight(menuBarHeight: NSScreen.tallestCachedMenuBarHeight)

        for (childIndex, child) in children.enumerated() {
            let attributes = AXHelpers.menuBarChildAttributes(for: child)
            let diagnosticIdentity = attributes.identifier?.nonEmpty
                ?? attributes.accessibilityDescription?.nonEmpty
                ?? "child-\(childIndex)"
            if CaptureDiagnostics.shouldCompareFrame(ownerPID: runningApp.processIdentifier, identity: diagnosticIdentity) {
                try? child.setMessagingTimeout(AXPrimitives.defaultMessagingTimeout)
                let singleFrame = AXHelpers.frame(for: child)
                let descendantFrames = attributes.children.prefix(4).compactMap { descendant -> CGRect? in
                    try? descendant.setMessagingTimeout(AXPrimitives.defaultMessagingTimeout)
                    return AXHelpers.descendantAttributes(for: descendant).frame
                }
                diagLog.debug(
                    "[CaptureFrameTrace] bundle=\(appBundleID) pid=\(runningApp.processIdentifier) child=\(childIndex) " +
                        "identifier=\(attributes.identifier ?? "nil") " +
                        "title=\(attributes.title ?? "nil") " +
                        "description=\(attributes.accessibilityDescription ?? "nil") " +
                        "batch=\(attributes.frame.map { NSStringFromRect($0) } ?? "nil") " +
                        "single=\(singleFrame.map { NSStringFromRect($0) } ?? "nil") " +
                        "descendants=\(descendantFrames.map { NSStringFromRect($0) })"
                )
            }
            guard let frame = Self.itemFrame(attributes.frame, maximumHeight: itemHeightCeiling) else {
                continue
            }
            // Dormant: the live caller passes no bounds. Don't use it to narrow
            // the inventory; a frame's display is not an item attribute.
            if let displayBounds, !Self.frame(frame, isWithin: displayBounds) {
                continue
            }
            if overflowControl.elements.contains(child)
                || overflowControl.frames.contains(where: { Self.frame(frame, matches: $0) })
            {
                continue
            }

            let directIdentifier = attributes.identifier?.nonEmpty
            let directDescription = attributes.accessibilityDescription?.nonEmpty
            let (childIdentifier, childDescription) = Self.descendantIdentity(
                of: attributes,
                directIdentifier: directIdentifier,
                directDescription: directDescription
            )
            let ownerPID = AXHelpers.pid(for: child) ?? runningApp.processIdentifier
            let derived = Self.rawItem(
                namespace: namespace,
                identifier: directIdentifier,
                childIdentifier: childIdentifier,
                accessibilityDescription: directDescription,
                childDescription: childDescription,
                axTitle: attributes.title?.nonEmpty,
                fallbackIndex: fallbackIndex,
                bounds: frame,
                ownerPID: ownerPID
            )
            fallbackIndex = derived.fallbackIndex
            guard let item = derived.item else {
                continue
            }
            raw.append(item)
        }
        return raw
    }

    /// Logs, once per owner and AX result, why an app that had menu bar items
    /// last session gave the walk none.
    ///
    /// Most apps never had an extras bar. A former host answering anything
    /// but "no value" or "unsupported", or with an empty bar, is being missed.
    private static func logEmptyExtrasBarReadOnce(
        for runningApp: NSRunningApplication,
        appBundleID: String,
        hasBar: Bool
    ) {
        guard UnseenMenuBarHosts.wasHost(appBundleID) else { return }
        let pid = runningApp.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, AXPrimitives.defaultMessagingTimeout)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &value)
        let isNew = loggedEmptyExtrasBarReads.withLock { logged in
            guard logged[pid] != result else { return false }
            logged[pid] = result
            return true
        }
        guard isNew else { return }
        diagLog.debug(
            """
            menuBarItems: \(appBundleID) (pid \(pid), policy \(runningApp.activationPolicy.rawValue)) gave no items: \
            extrasBar=\(hasBar ? "present, no children" : "absent") rawRead=\(result.rawValue)
            """
        )
    }

    /// Resolves and presses a hosted item by its owning process ID.
    ///
    /// A parked element has no frame to hit-test, but the AX press still
    /// materializes it: the host seats the window on demand.
    static func pressHostedItem(sourcePID: pid_t) -> Bool {
        guard AXHelpers.isProcessTrusted() else { return false }
        return AXPrimitives.pressHostedItem(sourcePID: sourcePID)
    }

    /// Presses the first of the resolved elements that takes a press. One AX
    /// round trip per candidate, with no walk in front of it.
    static func press(resolved elements: [UIElement]) -> Bool {
        for element in elements where AXHelpers.press(element) {
            return true
        }
        return false
    }

    /// Frames occupied by the native overflow controls on a display. They are
    /// excluded from the managed item list, but capture needs their geometry so
    /// stale item bounds cannot crop the chevrons as item thumbnails.
    static func nativeOverflowControlBounds(on display: CGDirectDisplayID) -> [CGRect] {
        // Cached-only: the AX tree walk on main froze the UI. The off-main
        // variant below keeps the memo warm.
        guard case let .present(bounds) = nativeOverflowObservationCachedOnly(on: display) else {
            return []
        }
        return bounds
    }

    // MARK: - Concurrent entry points

    /// @concurrent counterparts of the sync walks, so a hung app never stalls
    /// the main actor. Not overloads: those would resolve by context, not intent.
    @concurrent
    static func menuBarItemsConcurrent(
        on display: CGDirectDisplayID? = nil,
        option _: MenuBarItem.ListOption,
        freshOnly: Bool = false,
        priorityPIDs: Set<pid_t> = []
    ) async -> [MenuBarItem] {
        // Out-of-process walk when enabled. The move/settle hot path calls
        // menuBarItemsForMoveConcurrent, which this does not touch.
        if let subprocessItems = await MenuBarAXSubprocess.items(displayID: display) {
            return restoredIdentities(subprocessItems)
        }
        let snapshot = await menuBarInventoryConcurrent(freshOnly: freshOnly, priorityPIDs: priorityPIDs)
        return freshOnly ? snapshot.freshItems : snapshot.items
        // display does not narrow the inventory: macOS 27 mirrors one
        // status-item set on every bar.
    }

    struct InventorySnapshot: Sendable {
        let items: [MenuBarItem]
        let freshItems: [MenuBarItem]
        let completed: Bool
        let hasFreshKnownInventory: Bool
        let hasFreshMoveInventory: Bool

        static let unavailable = InventorySnapshot(
            items: [],
            freshItems: [],
            completed: false,
            hasFreshKnownInventory: false,
            hasFreshMoveInventory: false
        )
    }

    /// Fresh geometry for every known owner, including neighbours and controls.
    /// An incomplete pass must not prove adjacency or replace a saved order.
    @concurrent
    static func menuBarItemsForMoveConcurrent(priorityPIDs: Set<pid_t>) async -> [MenuBarItem]? {
        guard let snapshot = await inventoryGate.snapshot(
            freshOnly: true, scope: .knownOwners, priorityOwners: priorityPIDs
        ), snapshot.hasFreshMoveInventory else { return nil }
        return restoredIdentities(snapshot).freshItems
    }

    /// Re-reads the owners appearance already knows, skipping discovery's
    /// probes of expired empty apps.
    @concurrent
    static func menuBarItemsForAppearanceConcurrent(knownOwners: Set<pid_t>) async -> [MenuBarItem]? {
        guard let snapshot = await inventoryGate.snapshot(
            freshOnly: true, scope: .requestedOwners, priorityOwners: knownOwners
        ), snapshot.hasFreshMoveInventory else { return nil }
        return restoredIdentities(snapshot).freshItems
    }

    /// Re-reads the owners a thumbnail pass names. It runs every refresh tick,
    /// so it waits out a discovery walk in flight rather than cancelling it.
    @concurrent
    static func menuBarItemsForCaptureConcurrent(knownOwners: Set<pid_t>) async -> [MenuBarItem]? {
        guard let snapshot = await inventoryGate.snapshot(
            freshOnly: true, scope: .requestedOwners, priorityOwners: knownOwners, preemptsDiscovery: false
        ), snapshot.hasFreshMoveInventory else { return nil }
        return restoredIdentities(snapshot).freshItems
    }

    @concurrent
    static func menuBarInventoryConcurrent(
        freshOnly: Bool = false,
        priorityPIDs: Set<pid_t> = []
    ) async -> InventorySnapshot {
        guard let snapshot = await inventoryGate.snapshot(
            freshOnly: freshOnly, priorityOwners: priorityPIDs
        ) else { return .unavailable }
        return restoredIdentities(snapshot)
    }

    /// See nativeOverflowControlBounds(on:).
    @concurrent
    static func nativeOverflowControlBoundsConcurrent(
        on display: CGDirectDisplayID
    ) async -> [CGRect] {
        // Warms the memo for the main-thread reader. Must not call the sync
        // nativeOverflowControlBounds, which is cached-only and never walks.
        guard case let .present(bounds) = await OverflowWalkGate.shared.observation(on: display) else {
            return []
        }
        return bounds
    }

    /// See nativeOverflowObservation(on:).
    @concurrent
    static func nativeOverflowObservationConcurrent(
        on display: CGDirectDisplayID
    ) async -> NativeOverflowObservation {
        await OverflowWalkGate.shared.observation(on: display)
    }

    /// Keeps one overflow walk in flight per display.
    ///
    /// Callers tend to miss the 250 ms memo together (capture and refresh wake
    /// on the same event), so a late caller waits on the walk in flight.
    ///
    /// Detached, so a cancelled waiter leaves only itself; others still get
    /// their answer.
    private actor OverflowWalkGate {
        static let shared = OverflowWalkGate()

        private var inFlight: [CGDirectDisplayID: Task<NativeOverflowObservation, Never>] = [:]

        func observation(on display: CGDirectDisplayID) async -> NativeOverflowObservation {
            if let existing = inFlight[display] {
                return await existing.value
            }
            // Detached tasks inherit no priority, so the first caller's is
            // passed explicitly; later waiters escalate by awaiting.
            let walk = Task.detached(priority: Task.currentPriority) {
                MenuBarItemAXProvider.nativeOverflowObservation(on: display)
            }
            inFlight[display] = walk
            let observation = await walk.value
            // Only the installer clears the slot, so a successor's walk is safe.
            inFlight[display] = nil
            return observation
        }
    }

    /// One all-display inventory prevents simultaneous display/capture callers
    /// from walking every application independently. Display filtering happens
    /// after assembly, so retained observations never leak across scan scopes.
    private static let inventoryGate = MenuBarInventoryScanGate<RawItem, InventorySnapshot> { state, scope, priorityOwners in
        await enumerateMenuBarItemsResilient(state: state, scope: scope, priorityPIDs: priorityOwners)
    }

    // MARK: - Chevron hit-test sweep

    /// What the last hit-test sweep on a display learned, so the next one can
    /// be cheaper.
    private struct ChevronProbeMemo {
        /// Where a chevron was last seen, or nil when the last full sweep
        /// found none.
        var hint: CGRect?

        /// When the last full sweep came back empty. Only meaningful while
        /// hint is nil.
        var lastAbsentAt: ContinuousClock.Instant?
    }

    /// Reached from a detached task, so the memo needs its own lock rather
    /// than actor isolation.
    private static let chevronProbeMemo = OSAllocatedUnfairLock(
        initialState: [CGDirectDisplayID: ChevronProbeMemo]()
    )

    /// How long an empty full sweep is trusted. Without it the sweep (80-230 ms
    /// of AX hit-tests) runs on every refresh; chevrons appear only when Thaw
    /// conceals, so the latency is cheap. Must exceed the 5 s refresh backstop.
    private static let chevronAbsenceCooldown = Duration.seconds(12)

    /// The chevron hit-test, narrowed by what the last sweep found.
    ///
    /// A full sweep is about 128 AX hit-tests; the chevron reappears at nearly
    /// the same x, so a narrow band answers first and a miss falls back.
    ///
    /// Returns .unavailable only when a sweep ran out of budget; a partial
    /// sweep must never claim .absent.
    private static func chevronObservationByHitTest(
        on display: CGDirectDisplayID,
        displayBounds: CGRect
    ) -> NativeOverflowObservation {
        let memo = chevronProbeMemo.withLock { $0[display] } ?? ChevronProbeMemo()

        // A reveal mask sits above the bar, so a hit-test taken while it is up
        // reads the mask, not the bar; hold the last observation instead.
        if ClockRevealMaskActivity.isAnyMaskShowing {
            if memo.hint == nil, memo.lastAbsentAt == nil {
                diagLog.debug(
                    "chevron: skipping the strip on display \(display) while a reveal mask is up; no absence recorded"
                )
            }
            return Self.chevronObservationWhileMasked(hint: memo.hint, lastAbsentAt: memo.lastAbsentAt, now: .now)
        }

        if let hint = memo.hint {
            switch MenuBarChevronProbeProvider.current.sweepForChevrons(
                in: narrowedProbeRect(around: hint, in: displayBounds)
            ) {
            case let .present(frames):
                recordChevronSweep(found: frames.first, on: display)
                return .present(frames)
            case .unavailable:
                // The band gave up: keep the hint and don't widen on a slow bar.
                return .unavailable
            case .absent:
                break
            }
        } else if let lastAbsentAt = memo.lastAbsentAt,
                  ContinuousClock.now - lastAbsentAt < chevronAbsenceCooldown
        {
            return .absent
        }

        let full = MenuBarChevronProbeProvider.current.sweepForChevrons(in: displayBounds)
        switch full {
        case let .present(frames):
            recordChevronSweep(found: frames.first, on: display)
        case .absent:
            recordChevronSweep(found: nil, on: display)
        case .unavailable:
            // Not recorded: an unfinished sweep must not start the 12 s cooldown.
            break
        }
        return full
    }

    /// A known chevron or an absence inside its cooldown stands; anything else
    /// is unavailable, so a masked bar cannot start a new absence.
    static nonisolated func chevronObservationWhileMasked(
        hint: CGRect?,
        lastAbsentAt: ContinuousClock.Instant?,
        now: ContinuousClock.Instant
    ) -> NativeOverflowObservation {
        if let hint {
            return .present([hint])
        }
        if let lastAbsentAt, now - lastAbsentAt < chevronAbsenceCooldown {
            return .absent
        }
        return .unavailable
    }

    /// The band to sweep around a previous sighting.
    ///
    /// Only the horizontal span may shrink: detectChevrons probes at the rect's
    /// minY and rejects hits centred outside it.
    private static func narrowedProbeRect(around hint: CGRect, in displayBounds: CGRect) -> CGRect {
        let padding: CGFloat = 60
        let minX = max(displayBounds.minX, hint.minX - padding)
        let maxX = min(displayBounds.maxX, hint.maxX + padding)
        guard maxX > minX else {
            return displayBounds
        }
        return CGRect(
            x: minX,
            y: displayBounds.minY,
            width: maxX - minX,
            height: displayBounds.height
        )
    }

    private static func recordChevronSweep(found frame: CGRect?, on display: CGDirectDisplayID) {
        let previous = chevronProbeMemo.withLock { memo -> ChevronProbeMemo? in
            let previous = memo[display]
            if let frame {
                memo[display] = ChevronProbeMemo(hint: frame, lastAbsentAt: nil)
            } else {
                memo[display] = ChevronProbeMemo(hint: nil, lastAbsentAt: .now)
            }
            return previous
        }
        // Logged on transitions only: the probe runs up to four times a second,
        // and only the edge a chevron was lost or found on matters.
        if previous?.hint != nil, frame == nil {
            diagLog.notice(
                "chevron: a full sweep found none on display \(display) after a sighting; the arrows may be back"
            )
        } else if previous?.hint == nil, let frame {
            diagLog.info("chevron: found at \(frame) on display \(display)")
        }
    }

    /// Distinguishes a trustworthy absence from an AX/MenuBarAgent read that
    /// could not be completed. Runtime monitoring must not interpret a missing
    /// permission or transient agent restart as overflow disappearing.
    /// A recent answer from the tree walk, per display.
    private struct OverflowObservationMemo {
        var observation: NativeOverflowObservation
        var readAt: ContinuousClock.Instant
    }

    /// Reached from detached tasks, so a lock rather than actor isolation.
    private static let overflowObservationMemo = OSAllocatedUnfairLock(
        initialState: [CGDirectDisplayID: OverflowObservationMemo]()
    )

    /// How long a tree walk's answer is reused; callers ask up to four times
    /// a second and the chevron does not move that fast.
    private static let overflowObservationLifetime = Duration.milliseconds(250)

    /// The memoized sync walk, for off-main one-offs like a diagnostic dump.
    /// Everything else uses nativeOverflowObservationConcurrent(on:).
    static func nativeOverflowObservation(on display: CGDirectDisplayID) -> NativeOverflowObservation {
        let now = ContinuousClock.now
        if let memo = overflowObservationMemo.withLock({ $0[display] }),
           now - memo.readAt < overflowObservationLifetime
        {
            return memo.observation
        }
        let observation = nativeOverflowObservationUncached(on: display)
        overflowObservationMemo.withLock {
            $0[display] = OverflowObservationMemo(observation: observation, readAt: now)
        }
        return observation
    }

    /// Main-thread reader: the last memoized answer, even stale, or .absent
    /// when cold. Never walks; on main the walk can take seconds and freeze
    /// the UI. Off-main callers keep the memo warm.
    static func nativeOverflowObservationCachedOnly(
        on display: CGDirectDisplayID
    ) -> NativeOverflowObservation {
        overflowObservationMemo.withLock { $0[display]?.observation } ?? .absent
    }

    /// Every overflow control frame the memo currently holds for display,
    /// or for all displays when none is given. Memo-only, like
    /// nativeOverflowObservationCachedOnly(on:), and for the same reason.
    static func nativeOverflowControlFramesCachedOnly(on display: CGDirectDisplayID?) -> [CGRect] {
        overflowObservationMemo.withLock { memo in
            let observations: [NativeOverflowObservation] = if let display {
                [memo[display]?.observation].compactMap(\.self)
            } else {
                memo.values.map(\.observation)
            }
            return observations.flatMap { observation -> [CGRect] in
                guard case let .present(frames) = observation else { return [] }
                return frames
            }
        }
    }

    /// The tree walk itself; see nativeOverflowObservation(on:) for the memo.
    private static func nativeOverflowObservationUncached(on display: CGDirectDisplayID) -> NativeOverflowObservation {
        guard AXHelpers.isProcessTrusted(),
              let bar = AXHelpers.menuBarAgentExtrasBar()
        else {
            return .unavailable
        }

        let displayBounds = CGDisplayBounds(display)
        guard let children = AXHelpers.childrenIfAvailable(for: bar) else {
            return .unavailable
        }
        let descendants = children.flatMap { child -> [AXSwift6.UIElement] in
            let childDescendants = AXHelpers.childrenIfAvailable(for: child) ?? []
            return [child] + childDescendants
        }
        var attributeReadFailed = false
        let attributedControls = ([bar] + children).compactMap { element -> AXSwift6.UIElement? in
            guard let supportsOverflowButton = AXHelpers.supportsOverflowButton(element) else {
                attributeReadFailed = true
                return nil
            }
            guard supportsOverflowButton else { return nil }
            guard let button = AXHelpers.overflowButton(for: element) else {
                attributeReadFailed = true
                return nil
            }
            return button
        }
        let labeledControls = descendants.filter { element in
            let identifier = AXHelpers.identifier(for: element)?.nonEmpty
            let accessibilityDescription = AXHelpers.description(for: element)?.nonEmpty
            let displayTitle = AXHelpers.title(for: element)?.nonEmpty
                ?? accessibilityDescription
                ?? identifier
                ?? ""
            let stableTitle = identityTitle(
                namespace: .menuBarAgent,
                identifier: identifier,
                accessibilityDescription: accessibilityDescription,
                displayTitle: displayTitle
            )
            return isNativeOverflowChevronPlaceholder(
                namespace: .menuBarAgent,
                identityTitle: stableTitle,
                displayTitle: displayTitle
            )
        }

        var seenFrames = Set<CGRect>()
        let frames: [CGRect] = (attributedControls + labeledControls).compactMap { control -> CGRect? in
            guard let frame = AXHelpers.frame(for: control),
                  !frame.isNull,
                  !frame.isEmpty,
                  displayBounds.contains(frame.center),
                  seenFrames.insert(frame).inserted
            else {
                return nil
            }
            return frame
        }
        // The walk finds only AXOverflowButton; the notchless macOS 27
        // indicator is a composited AXImage outside the extras bar. Fall back
        // to the shared strip hit-test so the cover sees the same answer.
        var mergedFrames = frames
        var hitTestGaveUp = false
        if frames.isEmpty {
            switch chevronObservationByHitTest(on: display, displayBounds: displayBounds) {
            case let .present(hitTestFrames):
                for frame in hitTestFrames where seenFrames.insert(frame).inserted {
                    mergedFrames.append(frame)
                }
            case .absent:
                break
            case .unavailable:
                hitTestGaveUp = true
            }
        }

        if mergedFrames.isEmpty {
            // A partial sweep must not report .absent, or the reducer retires
            // the overflow state on a busy bar.
            guard !hitTestGaveUp else { return .unavailable }
            if attributeReadFailed || !(attributedControls + labeledControls).isEmpty {
                return .unavailable
            }
            return .absent
        }
        return .present(mergedFrames)
    }

    // MARK: - Assembly

    /// A pre-tag item collected from the AX walk.
    ///
    /// Internal plain data so assemble is testable with fixtures.
    struct RawItem {
        let namespace: MenuBarItemTag.Namespace
        let identityTitle: String
        let displayTitle: String
        let bounds: CGRect
        let ownerPID: pid_t
    }

    /// Builds the final MenuBarItem list: assigns stable instance indices to
    /// items that share a (namespace, title) key, synthesizes window IDs, and
    /// sorts left-to-right by position.
    static func assemble(_ raw: [RawItem]) -> [MenuBarItem] {
        // Sort by x so instance indices are positional and stable.
        let sorted = raw.sorted { $0.bounds.minX < $1.bounds.minX }

        // macOS 27 vends third-party items twice (app and MenuBarAgent), which
        // would render as two tiles. Drop the agent copy at the same position.
        let deduped = dropDuplicateMenuBarAgentRevends(sorted)

        var indexByKey: [String: Int] = [:]
        var items: [MenuBarItem] = []
        items.reserveCapacity(deduped.count)

        for entry in deduped {
            if isNativeOverflowChevronPlaceholder(
                namespace: entry.namespace,
                identityTitle: entry.identityTitle,
                displayTitle: entry.displayTitle
            ) {
                diagLog.debug("assemble: skipping native overflow control title='\(entry.identityTitle)' frame=\(entry.bounds)")
                continue
            }

            let key = "\(entry.namespace):\(entry.identityTitle)"
            let instanceIndex = indexByKey[key, default: 0]
            indexByKey[key] = instanceIndex + 1

            let windowID = syntheticWindowID(namespace: entry.namespace, title: entry.identityTitle, instanceIndex: instanceIndex)
            let tag = MenuBarItemTag(
                namespace: entry.namespace,
                title: entry.identityTitle,
                windowID: windowID,
                instanceIndex: instanceIndex
            )
            items.append(
                MenuBarItem(
                    tag: tag,
                    windowID: windowID,
                    ownerPID: entry.ownerPID,
                    // Attribution is direct under AX: owner == source.
                    sourcePID: entry.ownerPID,
                    bounds: entry.bounds,
                    title: entry.displayTitle,
                    isOnScreen: true
                )
            )
        }
        return items
    }

    // MARK: - Identity derivation

    /// Maps a running application to the namespace used for its items.
    static func namespace(forBundleIdentifier bundleID: String?, localizedName: String? = nil) -> MenuBarItemTag.Namespace {
        guard let bundleID else {
            return .optional(localizedName)
        }
        switch bundleID {
        case SharedConstants.menuBarHostingBundleID:
            return .menuBarAgent
        case _ where Constants.isThawOwnedBundleIdentifier(bundleID):
            return .thaw
        default:
            return .string(bundleID)
        }
    }

    /// The identifier and description an item publishes one level down, on
    /// its button or menu, for an item that did not publish them on itself.
    /// Eager on purpose: a lazy compactMap runs its transform twice for the
    /// first match, and a live read can change between the two and trap.
    static func descendantIdentity(
        of attributes: AXHelpers.MenuBarChildAttributes,
        directIdentifier: String?,
        directDescription: String?
    ) -> (identifier: String?, description: String?) {
        let needsIdentifier = stableAXIdentifier(directIdentifier) == nil
        let needsDescription = directDescription == nil
        guard needsIdentifier || needsDescription else { return (nil, nil) }
        let descendants = attributes.children.map { AXHelpers.descendantAttributes(for: $0) }
        return (
            needsIdentifier ? descendants.compactMap { stableAXIdentifier($0.identifier?.nonEmpty) }.first : nil,
            needsDescription ? descendants.compactMap { $0.accessibilityDescription?.nonEmpty }.first : nil
        )
    }

    /// The identifier when it is one worth keying identity on.
    ///
    /// AppKit's _NS:<number> placeholders change every launch and would orphan
    /// the persisted entry, so they return nil and callers fall back.
    static func stableAXIdentifier(_ identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        guard isStableAXIdentifier(identifier) else { return nil }
        return identifier
    }

    /// Identity title for an item; restores Time Machine's stable identity for
    /// an unnamed SystemUIServer extra before the default derivation.
    static func resolvedIdentityTitle(
        namespace: MenuBarItemTag.Namespace,
        identifier: String?,
        accessibilityDescription: String?,
        axTitle: String?,
        displayTitle: String
    ) -> String {
        MenuBarItemTag.legacySystemUIServerIdentity(
            namespace: namespace,
            identifier: identifier,
            accessibilityDescription: accessibilityDescription,
            axTitle: axTitle
        ) ?? identityTitle(
            namespace: namespace,
            identifier: identifier,
            accessibilityDescription: accessibilityDescription,
            displayTitle: displayTitle
        )
    }

    /// Chooses the stable tag title apart from the displayed text, so live
    /// metric or clock titles do not mint a new identity every refresh.
    static func identityTitle(
        namespace: MenuBarItemTag.Namespace,
        identifier: String?,
        accessibilityDescription: String?,
        displayTitle: String
    ) -> String {
        // Control Center controls end in an instance UUID re-minted on every
        // placement; drop it so identity survives a remove and re-add.
        if namespace == .menuBarAgent,
           let identifier = identifier?.nonEmpty,
           let stableIdentity = ChronoControlIdentity.stableIdentity(forAXIdentifier: identifier)
        {
            return stableIdentity
        }

        // For apps with stable titles AXIdentifier is stable by convention;
        // return raw.
        guard case let .string(bundleID) = namespace,
              MenuBarItemTag.hasCanonicalizableTitles(bundleID)
        else {
            return identifier?.nonEmpty ?? displayTitle
        }

        // These apps may carry the live value in AXIdentifier, AXDescription or
        // AXTitle depending on the version, so normalize whichever attribute is
        // present rather than trusting the identifier alone.
        //
        // Canonicalized here too because assemble(_:) groups by this title;
        // a raw one would mint a fresh identity every tick.
        let candidate = identifier?.nonEmpty
            ?? accessibilityDescription?.nonEmpty
            ?? displayTitle
        return MenuBarItemTag.canonicalTitle(namespace: namespace, title: candidate)
    }

    /// macOS 27 can publish native menu-bar overflow chevrons as AX extras
    /// under MenuBarAgent. They are not real status items, and managing them
    /// makes the layout editor fill with < / << placeholders.
    ///
    /// Title-only, shared with the model; the structural pass in
    /// enumerateMenuBarItems runs first and ignores the localized title.
    static func isNativeOverflowChevronPlaceholder(
        namespace: MenuBarItemTag.Namespace,
        identityTitle: String,
        displayTitle: String
    ) -> Bool {
        guard namespace == .menuBarAgent else { return false }
        return MenuBarItemTag.isNativeOverflowControlTitle(identityTitle)
            || MenuBarItemTag.isNativeOverflowControlTitle(displayTitle)
    }

    /// The per-child identity derivation shared by the in-process walk and the
    /// subprocess assembly.
    ///
    /// Returns the fallback index to carry to the next child, so untitled
    /// items keep the in-process walk's "Item-N" numbering.
    static func rawItem(
        namespace: MenuBarItemTag.Namespace,
        identifier: String?,
        childIdentifier: String?,
        accessibilityDescription: String?,
        childDescription: String?,
        axTitle: String?,
        fallbackIndex: Int,
        bounds: CGRect,
        ownerPID: pid_t
    ) -> (item: RawItem?, identityTitle: String, fallbackIndex: Int) {
        let identifier = stableAXIdentifier(identifier?.nonEmpty)
            ?? stableAXIdentifier(childIdentifier?.nonEmpty)
        let accessibilityDescription = accessibilityDescription?.nonEmpty
            ?? childDescription?.nonEmpty
        let axTitle = axTitle?.nonEmpty
        let fallbackTitle = "Item-\(fallbackIndex)"
        let displayTitle = axTitle ?? accessibilityDescription ?? identifier ?? fallbackTitle
        let nextFallbackIndex = axTitle == nil && accessibilityDescription == nil && identifier == nil
            ? fallbackIndex + 1
            : fallbackIndex
        let identityTitle = resolvedIdentityTitle(
            namespace: namespace,
            identifier: identifier,
            accessibilityDescription: accessibilityDescription,
            axTitle: axTitle,
            displayTitle: displayTitle
        )
        guard !isNativeOverflowChevronPlaceholder(
            namespace: namespace,
            identityTitle: identityTitle,
            displayTitle: displayTitle
        ) else {
            return (nil, identityTitle, nextFallbackIndex)
        }
        return (
            RawItem(
                namespace: namespace,
                identityTitle: identityTitle,
                displayTitle: displayTitle,
                bounds: bounds,
                ownerPID: ownerPID
            ),
            identityTitle,
            nextFallbackIndex
        )
    }

    /// The overflow control's identity for one pass: the AXOverflowButton
    /// element plus the memo's overflow frames. Memo-only because this runs
    /// inside the 4 Hz live loop.
    static func nativeOverflowControlSignature(
        bar: AXSwift6.UIElement,
        on display: CGDirectDisplayID?
    ) -> (elements: [AXSwift6.UIElement], frames: [CGRect]) {
        var elements = [AXSwift6.UIElement]()
        var frames = [CGRect]()
        if let button = AXHelpers.overflowButton(for: bar) {
            elements.append(button)
            if let frame = AXHelpers.frame(for: button), !frame.isNull, !frame.isEmpty {
                frames.append(frame)
            }
        }
        for frame in nativeOverflowControlFramesCachedOnly(on: display) where !frames.contains(frame) {
            frames.append(frame)
        }
        return (elements, frames)
    }

    /// Whether two AX frames describe the same on-screen control. AX reports
    /// frames in points and the chevron does not resize, so a sub-point
    /// tolerance separates "the same rect read twice" from a neighbour.
    static func frame(_ frame: CGRect, matches other: CGRect) -> Bool {
        abs(frame.minX - other.minX) < 0.5
            && abs(frame.minY - other.minY) < 0.5
            && abs(frame.width - other.width) < 0.5
            && abs(frame.height - other.height) < 0.5
    }

    private static func namespace(for app: NSRunningApplication) -> MenuBarItemTag.Namespace {
        namespace(forBundleIdentifier: app.bundleIdentifier, localizedName: app.localizedName)
    }

    /// Points within which two AX entries are one item vended twice. Both axes
    /// count, so stacked displays stay distinct.
    static let duplicateRevendPositionTolerance: CGFloat = 1

    /// Removes MenuBarAgent re-vends of items that are also published directly by
    /// their owning app.
    ///
    /// Keeps the direct-app copy, whose owner is right for persistence;
    /// agent-only entries are preserved.
    ///
    /// sorted must be ordered by bounds.minX.
    static func dropDuplicateMenuBarAgentRevends(_ sorted: [RawItem]) -> [RawItem] {
        let directOrigins = sorted
            .filter { $0.namespace != .menuBarAgent }
            .map { CGPoint(x: $0.bounds.minX, y: $0.bounds.minY) }
        guard !directOrigins.isEmpty else { return sorted }

        return sorted.filter { entry in
            guard entry.namespace == .menuBarAgent else { return true }
            let hasDirectTwin = directOrigins.contains {
                abs($0.x - entry.bounds.minX) <= duplicateRevendPositionTolerance &&
                    abs($0.y - entry.bounds.minY) <= duplicateRevendPositionTolerance
            }
            if hasDirectTwin {
                diagLog.debug(
                    "assemble: dropping MenuBarAgent re-vend title='\(entry.identityTitle)' at minX=\(entry.bounds.minX)"
                )
            }
            return !hasDirectTwin
        }
    }

    /// Produces a deterministic window identifier for an AX item.
    ///
    /// macOS 27 items have no real CGWindowID; failed CGS lookups fall back to
    /// stored bounds, so a stable synthetic ID is safe. The top bit avoids real
    /// IDs. Internal so PositionStoreItemSource can mint the same ID.
    static func syntheticWindowID(
        namespace: MenuBarItemTag.Namespace,
        title: String,
        instanceIndex: Int
    ) -> CGWindowID {
        let key = "\(namespace):\(title):\(instanceIndex)"
        // FNV-1a (32-bit), deterministic regardless of process seed.
        var hash: UInt32 = 0x811C_9DC5
        for byte in key.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return CGWindowID(0x8000_0000 | (hash & 0x7FFF_FFFF))
    }
}

private extension String {
    /// Returns self when it contains non-whitespace characters, otherwise nil.
    nonisolated var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
