//
//  MenuBarItemAXProvider+ExtrasBarReads.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import os.lock
import ThawAXCore

/// How a walk reads one app's extras bar, and which apps it leaves out. See ExtrasBarAbsenceLedger.
nonisolated extension MenuBarItemAXProvider {
    typealias ExtrasBarAbsences = OSAllocatedUnfairLock<ExtrasBarAbsenceLedger>

    /// The ledger the app uses. A test passes its own, so tests running at once don't read each other's answers.
    static let sharedExtrasBarAbsences = ExtrasBarAbsences(initialState: ExtrasBarAbsenceLedger())

    private static let extrasBarLog = DiagLog(category: "MenuBarItemAXProvider")

    /// Whether Thaw's own extras bar was missing at its last read.
    static let ownExtrasBarMissing = OSAllocatedUnfairLock(initialState: false)

    /// Owners whose empty extras-bar read has been logged, with the AX result
    /// it gave. The wrapper folds "no value" into nil, so without this a host
    /// the walk cannot see is indistinguishable from an app with no items.
    private static let loggedEmptyExtrasBarReads = OSAllocatedUnfairLock(
        initialState: [pid_t: AXError]()
    )

    /// Former hosts whose last empty read was a plain answer: no extras bar, and no error or timeout.
    /// Such an app has no items to show. One that timed out or failed is being missed.
    static func processesAnsweringWithNoItems() -> Set<pid_t> {
        loggedEmptyExtrasBarReads.withLock { logged in
            Set(logged.filter { $0.value == .noValue || $0.value == .attributeUnsupported }.keys)
        }
    }

    /// Whether a walk leaves the app out and keeps its last, empty answer.
    ///
    /// Owners in alwaysRead (controls, requested owners and apps with an item drawn) and apps that
    /// had items last session are always asked, since a new item is most likely to come from them.
    static func skipsKnownEmptyApp(
        _ runningApp: NSRunningApplication,
        appBundleID: String,
        alwaysRead: Set<pid_t>,
        formerHosts: Set<String>,
        absences: ExtrasBarAbsences = sharedExtrasBarAbsences
    ) -> Bool {
        let pid = runningApp.processIdentifier
        guard !alwaysRead.contains(pid), !formerHosts.contains(appBundleID) else { return false }
        return absences.withLock { $0.skips(pid, bundleID: appBundleID) }
    }

    /// Reads the app's extras bar and records how it answered, so later walks can leave out an app without one.
    static func extrasBar(
        of app: AXElement,
        runningApp: NSRunningApplication,
        appBundleID: String,
        ourBundleID: String?,
        formerHosts: Set<String>
    ) -> AXElement? {
        let read = AXHelpers.extrasMenuBarRead(for: app)
        if runningApp.bundleIdentifier == ourBundleID {
            noteOwnExtrasBar(isMissing: read.bar == nil, appBundleID: appBundleID)
        }
        let absence = read.bar == nil ? ExtrasBarAbsenceLedger.absence(for: read.result, elapsed: read.elapsed) : nil
        sharedExtrasBarAbsences.withLock {
            $0.noteAnswer(absence, pid: runningApp.processIdentifier, bundleID: appBundleID)
        }
        if read.bar == nil {
            logEmptyExtrasBarReadOnce(for: runningApp, appBundleID: appBundleID, result: read.result, formerHosts: formerHosts)
        }
        return read.bar
    }

    /// Records whether Thaw's own extras bar is missing.
    ///
    /// - Returns: Whether that changed since the last read.
    @discardableResult
    static func ownExtrasBarChanged(isMissing: Bool, in state: OSAllocatedUnfairLock<Bool> = ownExtrasBarMissing) -> Bool {
        state.withLock { wasMissing in
            defer { wasMissing = isMissing }
            return wasMissing != isMissing
        }
    }

    /// Every walk reads Thaw's own bar, so the warning is logged when the bar goes, not on each read.
    private static func noteOwnExtrasBar(isMissing: Bool, appBundleID: String) {
        guard ownExtrasBarChanged(isMissing: isMissing) else { return }
        if isMissing {
            extrasBarLog.warning("menuBarItems: Thaw (\(appBundleID)) has no AXExtrasMenuBar, control items cannot be discovered")
        } else {
            extrasBarLog.info("menuBarItems: Thaw (\(appBundleID)) has its AXExtrasMenuBar again")
        }
    }

    /// Logs, once per owner and AX result, why an app that had menu bar items
    /// last session gave the walk none.
    ///
    /// Most apps never had an extras bar. A former host answering anything
    /// but "no value" or "unsupported", or with an empty bar, is being missed.
    ///
    /// - Parameter result: How the app answered the read of its extras bar; success when the bar has no children.
    static func logEmptyExtrasBarReadOnce(
        for runningApp: NSRunningApplication,
        appBundleID: String,
        result: AXError,
        formerHosts: Set<String>
    ) {
        guard formerHosts.contains(appBundleID) else { return }
        let pid = runningApp.processIdentifier
        noteAccessAnswer(result, from: pid)
        let isNew = loggedEmptyExtrasBarReads.withLock { logged in
            guard logged[pid] != result else { return false }
            logged[pid] = result
            return true
        }
        guard isNew else { return }
        extrasBarLog.debug(
            """
            menuBarItems: \(appBundleID) (pid \(pid), policy \(runningApp.activationPolicy.rawValue)) gave no items: \
            extrasBar=\(result == .success ? "present, no children" : "absent") rawRead=\(result.rawValue)
            """
        )
    }
}
