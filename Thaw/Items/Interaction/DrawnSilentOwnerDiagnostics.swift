//
//  DrawnSilentOwnerDiagnostics.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import Cocoa
import MenuBarModel
import Synchronization
import ThawAXCore

/// How an app answered when asked for its extras menu bar, for an app whose item MenuBarAgent draws
/// but whose own tree gave the walk nothing.
nonisolated enum EmptyExtrasBarOutcome: Equatable, Hashable, Sendable {
    /// The read ran into the messaging timeout: the app is alive but too busy to answer.
    case slowResponder
    /// The read failed at once: the app runs no accessibility server.
    case noAccessibilityServer
    /// The app answered that it has no extras menu bar.
    case noExtrasBar
    /// The app has an extras menu bar with nothing in it.
    case emptyExtrasBar
    /// The second read found items the walk did not, so the walk raced the app.
    case publishedItems(Int)
    /// Any other error.
    case failed

    /// A cannot-complete answer this close to the timeout is the timeout firing, not a refusal.
    static let timeoutFraction = 0.8

    /// Sorts one extras-bar read into an outcome.
    ///
    /// - Parameters:
    ///   - result: The AX error the read returned.
    ///   - duration: How long the read took.
    ///   - childCount: The number of children the bar had, when the read succeeded.
    ///   - timeout: The messaging timeout the read ran under.
    static func classify(
        result: AXError,
        duration: Duration,
        childCount: Int?,
        timeout: Duration
    ) -> EmptyExtrasBarOutcome {
        switch result {
        case .success:
            guard let childCount, childCount > 0 else { return .emptyExtrasBar }
            return .publishedItems(childCount)
        case .cannotComplete:
            return duration >= timeout * timeoutFraction ? .slowResponder : .noAccessibilityServer
        case .noValue, .attributeUnsupported:
            return .noExtrasBar
        default:
            return .failed
        }
    }

    var label: String {
        switch self {
        case .slowResponder: "slow responder"
        case .noAccessibilityServer: "no accessibility server"
        case .noExtrasBar: "no extras bar"
        case .emptyExtrasBar: "empty extras bar"
        case let .publishedItems(count): "\(count) item(s) on a second read"
        case .failed: "failed"
        }
    }
}

/// One timed read of an app's extras menu bar.
nonisolated struct EmptyExtrasBarProbe: Equatable, Sendable {
    let rawResult: Int32
    let duration: Duration
    let outcome: EmptyExtrasBarOutcome

    var hasBar: Bool {
        rawResult == AXError.success.rawValue
    }

    /// Reads the extras menu bar of pid and counts its children. Never call it with this app's own pid
    /// from off the main actor: AppKit answers that read in-process and is not thread-safe.
    static func run(pid: pid_t, messagingTimeout: Float = AXPrimitives.defaultMessagingTimeout) -> EmptyExtrasBarProbe {
        let start = ContinuousClock.now
        let result = AXPrimitives.extrasMenuBarReadResult(pid: pid, messagingTimeout: messagingTimeout)
        let duration = ContinuousClock.now - start
        let childCount = result == .success
            ? AXPrimitives.extrasMenuBar(pid: pid, messagingTimeout: messagingTimeout).map { AXPrimitives.children(of: $0).count }
            : nil
        return EmptyExtrasBarProbe(
            rawResult: result.rawValue,
            duration: duration,
            outcome: .classify(
                result: result,
                duration: duration,
                childCount: childCount,
                timeout: .milliseconds(Int64(messagingTimeout * 1000))
            )
        )
    }

    var summary: String {
        "\(rawResult) (\(outcome.label)) in \(Int((duration / .milliseconds(1)).rounded())) ms"
    }
}

/// Logs why an app whose item MenuBarAgent draws gave the walk no items.
///
/// The walk reads such an app as having nothing on the bar, and says nothing about it. Each owner is
/// read again off the main actor, then once more after a short delay, and the pair is logged once
/// per owner and outcome. An owner is probed at most once per probe interval.
nonisolated final class DrawnSilentOwnerDiagnostics: Sendable {
    /// What the log line says about one silent owner.
    struct Owner: Sendable {
        let pid: pid_t
        let bundleID: String
        let activationPolicy: Int
        let entryWidths: [CGFloat]
    }

    static let retryDelay = Duration.seconds(1)
    static let probeInterval = Duration.seconds(60)

    private struct State {
        var lastProbe: [pid_t: ContinuousClock.Instant] = [:]
        var inFlight: Set<pid_t> = []
        var logged: [pid_t: Set<[EmptyExtrasBarOutcome]>] = [:]
    }

    private let diagLog = DiagLog(category: "MenuBarItemAXProvider")
    private let state = Mutex(State())
    private let retryDelay: Duration

    init(retryDelay: Duration = DrawnSilentOwnerDiagnostics.retryDelay) {
        self.retryDelay = retryDelay
    }

    /// Owners whose probe has not finished.
    var probesInFlight: Set<pid_t> {
        state.withLock { $0.inFlight }
    }

    /// The drawn entries of owners that answered the walk with no items, grouped by owner.
    static func silentEntries(
        drawn: [MenuBarAgentWindow.Entry],
        answeredEmpty: Set<pid_t>
    ) -> [pid_t: [MenuBarAgentWindow.Entry]] {
        Dictionary(grouping: drawn.filter { answeredEmpty.contains($0.ownerPID) }, by: \.ownerPID)
    }

    /// Whether an owner may be probed now.
    static func admits(
        lastProbe: ContinuousClock.Instant?,
        inFlight: Bool,
        now: ContinuousClock.Instant,
        interval: Duration = probeInterval
    ) -> Bool {
        guard !inFlight else { return false }
        guard let lastProbe else { return true }
        return now - lastProbe >= interval
    }

    /// The log line for one owner, its first read and the retry.
    static func message(
        for owner: Owner,
        first: EmptyExtrasBarProbe,
        retry: EmptyExtrasBarProbe,
        retryDelay: Duration = retryDelay
    ) -> String {
        let count = owner.entryWidths.count
        let widths = owner.entryWidths.map { "\(Int($0.rounded()))" }.joined(separator: ",")
        let delay = retryDelay / .seconds(1)
        return """
        menuBarItems: \(owner.bundleID) (pid \(owner.pid), policy \(owner.activationPolicy)) is drawn \
        (\(count) \(count == 1 ? "entry" : "entries"), w=\(widths)) but gave no items: \
        extrasBar=\(first.hasBar ? "present" : "absent") rawRead=\(first.summary); \
        retry(\(String(format: "%.1f", delay)) s)=\(retry.summary)
        """
    }

    /// Probes each silent drawn owner the interval admits, on a detached task.
    ///
    /// - Parameters:
    ///   - drawn: A settled read of MenuBarAgent's window.
    ///   - answeredEmpty: Owners that answered this pass with no items. This app's own pid and
    ///     MenuBarAgent's must not be in it.
    ///   - apps: The running apps by pid.
    /// - Returns: The owners probed.
    @discardableResult
    func note(
        drawn: [MenuBarAgentWindow.Entry],
        answeredEmpty: Set<pid_t>,
        apps: [pid_t: NSRunningApplication],
        now: ContinuousClock.Instant = .now
    ) -> [Owner] {
        let silent = Self.silentEntries(drawn: drawn, answeredEmpty: answeredEmpty)
        let admitted: [Owner] = state.withLock { state in
            state.lastProbe = state.lastProbe.filter { apps[$0.key] != nil }
            state.logged = state.logged.filter { apps[$0.key] != nil }
            return silent.compactMap { pid, entries in
                guard let app = apps[pid], !AXPrimitives.isOwnProcess(pid),
                      Self.admits(lastProbe: state.lastProbe[pid], inFlight: state.inFlight.contains(pid), now: now)
                else { return nil }
                state.lastProbe[pid] = now
                state.inFlight.insert(pid)
                return Owner(
                    pid: pid,
                    bundleID: app.bundleIdentifier ?? app.localizedName ?? "(pid \(pid))",
                    activationPolicy: app.activationPolicy.rawValue,
                    entryWidths: entries.map(\.frame.width)
                )
            }
        }
        for owner in admitted {
            Task.detached(priority: .utility) { [self] in
                let first = EmptyExtrasBarProbe.run(pid: owner.pid)
                try? await Task.sleep(for: retryDelay)
                let retry = EmptyExtrasBarProbe.run(pid: owner.pid)
                let isNew = state.withLock { state in
                    state.inFlight.remove(owner.pid)
                    return state.logged[owner.pid, default: []].insert([first.outcome, retry.outcome]).inserted
                }
                if isNew {
                    diagLog.info(Self.message(for: owner, first: first, retry: retry, retryDelay: retryDelay))
                }
            }
        }
        return admitted
    }
}
