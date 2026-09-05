//
//  MenuBarItemManager+MoveFailureReporting.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// Persists and presents diagnostic reports for automatic moves that reached
/// a definitive failure. Expected deferrals are left to the caller's next
/// cache or layout pass.
extension MenuBarItemManager {
    /// Whether an automatic move outcome is final enough to report.
    nonisolated enum AutomaticMoveFailureDisposition: Equatable {
        case report
        case deferred
    }

    /// Whether the user-facing presentation is allowed by the cooldown.
    /// This decision gates only the alert or notification; report persistence
    /// is never skipped because presentation is rate-limited.
    nonisolated enum AutomaticMoveFailurePresentationDecision: Equatable {
        case present
        case suppressSameItem(elapsed: TimeInterval)
        case suppressBurst(elapsed: TimeInterval)
    }

    /// Where an allowed user-facing failure is presented.
    nonisolated enum AutomaticMoveFailurePresentationRoute: Equatable {
        case settingsSheet
        case notification
    }

    /// Work performed for one classified outcome and cooldown decision.
    nonisolated struct AutomaticMoveFailureHandlingPlan: Equatable {
        let shouldPersist: Bool
        let shouldPresent: Bool
    }

    /// How long one item's presentations stay quiet after an alert or
    /// notification about it.
    static nonisolated let automaticMoveFailureReportCooldown: TimeInterval = 10 * 60

    /// Minimum spacing between presentations for different items, so one
    /// failed bulk pass does not produce a notification storm.
    static nonisolated let automaticMoveFailureReportSpacing: TimeInterval = 30

    /// Classifies outcomes with no UI or live state, so every automatic mover
    /// applies the same failure-versus-deferral rule.
    static nonisolated func automaticMoveFailureDisposition(
        for error: any Error
    ) -> AutomaticMoveFailureDisposition {
        if error is CancellationError {
            return .deferred
        }
        guard let error = error as? EventError else {
            return .report
        }
        switch error {
        case .missingItemBounds, .missingDestinationBounds, .menuTrackingActive,
             .staleDestination, .moveSuperseded, .moveEngineBusy,
             .unsafeMovePath, .inputPauseTimedOut:
            // The item or destination changed, the user still owns the menu,
            // or another transaction owns the bar. A fresh pass may produce
            // a different valid plan, and no terminal malfunction is proven.
            return .deferred
        case let .itemNotMovable(item):
            // A generic Control Center slot can become movable as soon as its
            // source identity resolves. A static macOS prohibition will not.
            if case .unresolvedControlCenterPlaceholder? = item.immovabilityReason {
                return .deferred
            }
            return .report
        case .cannotComplete, .invalidEventSource, .missingMouseLocation,
             .eventCreationFailure, .eventOperationTimeout,
             .itemResponseTimeout, .ownerUnresponsive, .eventWindowMismatch,
             .dropReverted, .moveTimedOut:
            return .report
        }
    }

    /// Applies the per-item and burst cooldowns to a reportable failure.
    /// Exact boundary timestamps are allowed.
    static nonisolated func automaticMoveFailurePresentationDecision(
        now: Date,
        lastForItem: Date?,
        lastOverall: Date?,
        itemCooldown: TimeInterval = automaticMoveFailureReportCooldown,
        burstSpacing: TimeInterval = automaticMoveFailureReportSpacing
    ) -> AutomaticMoveFailurePresentationDecision {
        if let lastForItem {
            let elapsed = now.timeIntervalSince(lastForItem)
            if elapsed < itemCooldown {
                return .suppressSameItem(elapsed: elapsed)
            }
        }
        if let lastOverall {
            let elapsed = now.timeIntervalSince(lastOverall)
            if elapsed < burstSpacing {
                return .suppressBurst(elapsed: elapsed)
            }
        }
        return .present
    }

    /// Selects a sheet only when Settings is already visible; an automatic
    /// background move never opens Settings over the user's current work.
    static nonisolated func automaticMoveFailurePresentationRoute(
        settingsWindowVisible: Bool
    ) -> AutomaticMoveFailurePresentationRoute {
        settingsWindowVisible ? .settingsSheet : .notification
    }

    /// Keeps persistence independent from presentation throttling: every
    /// definitive failure is saved, while only `.present` reaches the user.
    static nonisolated func automaticMoveFailureHandlingPlan(
        disposition: AutomaticMoveFailureDisposition,
        presentationDecision: AutomaticMoveFailurePresentationDecision
    ) -> AutomaticMoveFailureHandlingPlan {
        guard disposition == .report else {
            return AutomaticMoveFailureHandlingPlan(
                shouldPersist: false,
                shouldPresent: false
            )
        }
        let shouldPresent = if case .present = presentationDecision {
            true
        } else {
            false
        }
        return AutomaticMoveFailureHandlingPlan(
            shouldPersist: true,
            shouldPresent: shouldPresent
        )
    }

    /// Starts report generation outside a bulk move loop. The initial guard
    /// runs in the caller's task so cancellation is not lost when the new task
    /// is created.
    func enqueueAutomaticMoveFailureReport(
        of item: MenuBarItem,
        to destination: MoveDestination?,
        expectedSection: MenuBarSection.Name?,
        error: any Error,
        source: String
    ) {
        guard !Task.isCancelled,
              Self.automaticMoveFailureDisposition(for: error) == .report
        else {
            return
        }
        Task { [weak self] in
            await self?.reportAutomaticMoveFailure(
                of: item,
                to: destination,
                expectedSection: expectedSection,
                error: error,
                source: source
            )
        }
    }

    /// Writes a report for a definitive automatic-move failure, then presents
    /// it when the per-item and burst cooldowns allow.
    func reportAutomaticMoveFailure(
        of item: MenuBarItem,
        to destination: MoveDestination?,
        expectedSection: MenuBarSection.Name?,
        error: any Error,
        source: String
    ) async {
        guard !Task.isCancelled else { return }
        guard let appState else {
            return
        }

        let disposition = Self.automaticMoveFailureDisposition(for: error)
        let key = MenuBarItemTag.canonicalPersistentIdentifier(item.uniqueIdentifier)
        let now = Date()
        let presentationDecision = Self.automaticMoveFailurePresentationDecision(
            now: now,
            lastForItem: automaticMoveFailureReports[key],
            lastOverall: lastAutomaticMoveFailureReport
        )
        let handlingPlan = Self.automaticMoveFailureHandlingPlan(
            disposition: disposition,
            presentationDecision: presentationDecision
        )
        guard handlingPlan.shouldPersist else { return }

        // Reserve an allowed presentation before report generation yields the
        // main actor, so two simultaneous failures cannot both pass the burst
        // gate. Persistence remains allowed for the suppressed one.
        if handlingPlan.shouldPresent {
            automaticMoveFailureReports[key] = now
            lastAutomaticMoveFailureReport = now
        }

        let report = await MoveFailureDiagnosticReport.generate(
            for: .init(
                item: item,
                destination: destination,
                expectedSection: expectedSection,
                error: error,
                note: "Automatic move requested by \(source)."
            ),
            appState: appState
        )
        var savedURL: URL?
        do {
            savedURL = try report.writeToAutomaticReports()
        } catch {
            MenuBarItemManager.diagLog.error(
                "Could not save the diagnostic report for \(item.logString): \(error)"
            )
        }

        switch presentationDecision {
        case .present:
            break
        case let .suppressSameItem(elapsed):
            MenuBarItemManager.diagLog.debug(
                "Saved but did not present another failed \(source) move of \(item.logString); that item was presented \(Int(max(0, elapsed))) s ago; report=\(savedURL?.lastPathComponent ?? "not saved")"
            )
            return
        case let .suppressBurst(elapsed):
            MenuBarItemManager.diagLog.debug(
                "Saved but did not present the failed \(source) move of \(item.logString); another failure was presented \(Int(max(0, elapsed))) s ago; report=\(savedURL?.lastPathComponent ?? "not saved")"
            )
            return
        }

        let title = String(localized: "Couldn't move \(item.displayName) right now.")
        let description = (error as? LocalizedError)?.errorDescription
            ?? String(describing: error)
        MenuBarItemManager.diagLog.info(
            "Presenting the failed \(source) move of \(item.logString): \(description); report=\(savedURL?.lastPathComponent ?? "not saved")"
        )

        let settingsWindow = NSApp.window(withIdentifier: IceWindowIdentifier.settings.rawValue)
        switch Self.automaticMoveFailurePresentationRoute(
            settingsWindowVisible: settingsWindow?.isVisible == true
        ) {
        case .settingsSheet:
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            var lines = [description]
            if let suggestion = (error as? LocalizedError)?.recoverySuggestion {
                lines.append(suggestion)
            }
            alert.informativeText = lines.joined(separator: "\n\n")
            report.run(alert, in: settingsWindow)

        case .notification:
            let location = savedURL.map { url in
                let folder = url.deletingLastPathComponent().path
                    .replacingOccurrences(of: NSHomeDirectory(), with: "~")
                return String(localized: "A diagnostic report was saved to \(folder).")
            } ?? ""
            appState.userNotificationManager.requestAuthorization()
            appState.userNotificationManager.addRequest(
                with: .moveFailed,
                title: title,
                body: [description, location].filter { !$0.isEmpty }.joined(separator: ". "),
                userInfo: savedURL.map { ["reportPath": $0.path] } ?? [:]
            )
        }
    }
}
