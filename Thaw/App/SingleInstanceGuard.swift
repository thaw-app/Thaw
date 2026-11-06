//
//  SingleInstanceGuard.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Keeps a second copy of Thaw from managing the menu bar next to the first. A normal launch takes the
/// instance lock; when another copy holds it or runs, the person chooses which one to keep, and this copy
/// either quits or stops the other and goes on.
@MainActor
enum SingleInstanceGuard {
    enum Choice {
        case quitThisCopy
        case quitOtherCopies
    }

    /// The live effects, swapped out in tests.
    struct Actions {
        var ask: ([SingleInstanceRule.RunningProcess]) -> Choice
        var stop: ([SingleInstanceRule.RunningProcess]) -> Bool
        /// Waits a few seconds for the lock to come free and reports whether this copy took it.
        var retakeLock: () -> Bool
        var reportFailure: ([SingleInstanceRule.RunningProcess]) -> Void
        var quitThisCopy: () -> Void
    }

    /// Waits counted in polls a tenth of a second apart: for a copy to quit on its own, after a forced
    /// quit, for the lock after the other copy quit, and for the copy a restart replaces to exit.
    static let gracefulPolls = 50
    static let forcedPolls = 20
    static let lockPolls = 50
    static let relaunchPolls = 100

    private static let diagLog = DiagLog(category: "SingleInstanceGuard")
    fileprivate static let lock = InstanceLock()

    /// True once this process holds the instance lock, which it keeps until it exits.
    static var holdsInstanceLock: Bool {
        lock.isHeld
    }

    /// Takes the instance lock and checks the running apps, asking before launch goes on when another
    /// copy is found. Returns false when this copy is quitting.
    @discardableResult
    static func enforce() -> Bool {
        let info = ProcessInfo.processInfo
        let launchMode = SingleInstanceRule.launchMode(arguments: info.arguments, environment: info.environment)
        guard launchMode == .app else { return true }
        let relaunchedFrom = SingleInstanceRule.relaunchedFrom(arguments: info.arguments)
        // The copy a restart replaces holds the lock until it exits.
        let lockState = waitForLock(polls: relaunchedFrom == nil ? 0 : relaunchPolls, pause: pause, attempt: lock.tryAcquire)
        let decision = SingleInstanceRule.decide(
            ownProcessIdentifier: info.processIdentifier,
            ownBundleIdentifier: Bundle.main.bundleIdentifier,
            launchMode: launchMode,
            lock: lockState,
            relaunchedFrom: relaunchedFrom,
            running: runningProcesses()
        )
        return resolve(decision, actions: .live)
    }

    /// Carries out a decision. Returns true when this copy goes on launching.
    static func resolve(_ decision: SingleInstanceRule.Decision, actions: Actions) -> Bool {
        guard case let .ask(others, lockHeldElsewhere) = decision else { return true }
        diagLog.info(
            "Another copy is running: \(others.map(\.displayName).joined(separator: ", ")), lock held elsewhere: \(lockHeldElsewhere)"
        )
        switch actions.ask(others) {
        case .quitThisCopy:
            actions.quitThisCopy()
            return false
        case .quitOtherCopies:
            let stopped = others.isEmpty || actions.stop(others)
            guard stopped, !lockHeldElsewhere || actions.retakeLock() else {
                actions.reportFailure(others)
                actions.quitThisCopy()
                return false
            }
            return true
        }
    }

    /// Asks each copy to quit, forces the ones still running after the grace period, and reports whether
    /// all of them exited.
    static func stop(
        _ processes: [pid_t],
        terminate: (pid_t) -> Void,
        forceTerminate: (pid_t) -> Void,
        isRunning: (pid_t) -> Bool,
        pause: () -> Void
    ) -> Bool {
        let allExited = { !processes.contains(where: isRunning) }
        processes.forEach(terminate)
        guard !poll(gracefulPolls, pause: pause, until: allExited) else { return true }
        processes.filter(isRunning).forEach(forceTerminate)
        return poll(forcedPolls, pause: pause, until: allExited)
    }

    /// Tries the lock until it is no longer held by another process, at most `polls` more times.
    static func waitForLock(
        polls: Int,
        pause: () -> Void,
        attempt: () -> SingleInstanceRule.LockState
    ) -> SingleInstanceRule.LockState {
        var state = attempt()
        for _ in 0 ..< polls where state == .heldElsewhere {
            pause()
            state = attempt()
        }
        return state
    }

    /// Checks `done`, then pauses and checks again up to `polls` times. Reports whether it came true.
    private static func poll(_ polls: Int, pause: () -> Void, until done: () -> Bool) -> Bool {
        if done() { return true }
        for _ in 0 ..< polls {
            pause()
            if done() { return true }
        }
        return false
    }

    fileprivate static func pause() {
        usleep(100_000)
    }

    static func runningProcesses() -> [SingleInstanceRule.RunningProcess] {
        NSWorkspace.shared.runningApplications.map { app in
            let entry = ProcessTable.entry(for: app.processIdentifier)
            return SingleInstanceRule.RunningProcess(
                processIdentifier: app.processIdentifier,
                parentProcessIdentifier: entry?.parentProcessIdentifier,
                bundleIdentifier: app.bundleIdentifier,
                localizedName: app.localizedName,
                isTerminated: app.isTerminated || (entry?.isZombie ?? false)
            )
        }
    }
}

extension SingleInstanceGuard.Actions {
    static var live: Self {
        Self(
            ask: askWhichCopyToKeep,
            stop: { processes in
                SingleInstanceGuard.stop(
                    processes.map(\.processIdentifier),
                    terminate: { NSRunningApplication(processIdentifier: $0)?.terminate() },
                    forceTerminate: { NSRunningApplication(processIdentifier: $0)?.forceTerminate() },
                    isRunning: ProcessTable.isRunning,
                    pause: SingleInstanceGuard.pause
                )
            },
            retakeLock: {
                SingleInstanceGuard.waitForLock(
                    polls: SingleInstanceGuard.lockPolls,
                    pause: SingleInstanceGuard.pause,
                    attempt: SingleInstanceGuard.lock.tryAcquire
                ) != .heldElsewhere
            },
            reportFailure: showFailure,
            quitThisCopy: { exit(EXIT_SUCCESS) }
        )
    }

    private static func askWhichCopyToKeep(_ others: [SingleInstanceRule.RunningProcess]) -> SingleInstanceGuard.Choice {
        let text = SingleInstancePrompt(SingleInstanceRule.Wording(others), appName: Constants.displayName)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text.title
        alert.informativeText = text.message
        alert.addButton(withTitle: String(localized: "Quit This Copy"))
        alert.addButton(withTitle: text.continueButton)
        NSApp.activate()
        return alert.runModal() == .alertSecondButtonReturn ? .quitOtherCopies : .quitThisCopy
    }

    private static func showFailure(_ others: [SingleInstanceRule.RunningProcess]) {
        let text = SingleInstancePrompt(SingleInstanceRule.Wording(others), appName: Constants.displayName)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text.failureTitle
        alert.informativeText = text.failureMessage
        alert.runModal()
    }
}

/// The words of the prompt and of the alert shown when the other copy won't quit.
nonisolated struct SingleInstancePrompt: Equatable {
    var title: String
    var message: String
    var continueButton: String
    var failureTitle: String
    var failureMessage: String

    init(_ wording: SingleInstanceRule.Wording, appName: String) {
        let onlyOne = String(localized: "Only one copy of \(appName) can manage the menu bar at a time.")
        switch wording {
        case .unnamed:
            title = String(localized: "Another Copy of \(appName) Is Running")
            message = onlyOne + " " + String(localized: "Quit this copy, or quit the other copy and continue opening this one.")
            continueButton = String(localized: "Quit It and Continue")
            failureTitle = String(localized: "Couldn’t Quit the Other Copy")
            failureMessage = String(localized: "The other copy of \(appName) is still running, so this copy will quit instead.")
        case let .one(name):
            title = String(localized: "\(name) Is Already Running")
            message = onlyOne + " " + String(localized: "Quit this copy, or quit \(name) and continue opening this one.")
            continueButton = String(localized: "Quit \(name) and Continue")
            failureTitle = String(localized: "Couldn’t Quit \(name)")
            failureMessage = String(localized: "\(name) didn’t quit, so this copy of \(appName) will quit instead.")
        case let .several(names):
            let list = names.formatted(.list(type: .and))
            title = String(localized: "Other Copies of \(appName) Are Running")
            message = String(localized: "\(list) are running.") + " " + onlyOne + " "
                + String(localized: "Quit this copy, or quit them and continue opening this one.")
            continueButton = String(localized: "Quit Them and Continue")
            failureTitle = String(localized: "Couldn’t Quit the Other Copies")
            failureMessage = String(localized: "\(list) didn’t quit, so this copy of \(appName) will quit instead.")
        }
    }
}
