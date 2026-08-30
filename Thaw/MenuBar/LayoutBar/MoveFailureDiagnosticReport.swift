//
//  MoveFailureDiagnosticReport.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import UniformTypeIdentifiers

/// A self-contained, redacted description of a failed menu bar item move,
/// offered from the failure alert for attaching to a bug report.
///
/// A pasted log excerpt on its own cannot answer the questions that decide
/// a move investigation: what the display looks like, what the rest of the
/// bar looked like at the time, which settings the move engine ran under,
/// and whether the same mechanics had just worked for another item. This
/// gathers all of that into one text file and applies
/// ``DiagnosticRedactor`` before the user reviews and shares it.
nonisolated struct MoveFailureDiagnosticReport {
    /// The move that failed.
    struct Failure {
        /// The item that did not move.
        let item: MenuBarItem

        /// Where it was supposed to go.
        let destination: MenuBarItemManager.MoveDestination

        /// The section the destination lies in.
        let expectedSection: MenuBarSection.Name

        /// The error the move ended with.
        let error: any Error

        /// What the caller already tried, if anything.
        let note: String?

        init(
            item: MenuBarItem,
            destination: MenuBarItemManager.MoveDestination,
            expectedSection: MenuBarSection.Name,
            error: any Error,
            note: String? = nil
        ) {
            self.item = item
            self.destination = destination
            self.expectedSection = expectedSection
            self.error = error
            self.note = note
        }
    }

    /// Log categories the excerpt keeps: everything about enumerating and
    /// moving items, nothing that quotes a network, device, or script. The
    /// window-list chatter in `Bridging` is left out as noise; the move
    /// engine's own lines already summarize what each enumeration returned.
    static let logCategories: Set<String> = [
        "AppState",
        "ControlItem",
        "DisplaySettingsManager",
        "EventTap",
        "LayoutBarContainer",
        "LayoutBarItemView",
        "LayoutBarPaddingView",
        "Listener",
        "MenuBarItem",
        "MenuBarItemManager",
        "MenuBarItemService.Connection",
        "MenuBarItemSpacingManager",
        "MenuBarManager",
        "MouseHelpers",
        "NSScreen",
        "SourcePIDCache",
        "StaleIdentifierLedger",
        "WindowInfo",
    ]

    /// How many matching log lines the excerpt keeps, newest last.
    static let logLineLimit = 800

    /// Maximum on-disk log window read while building a report.
    static let logTailByteLimit = 2 * 1024 * 1024

    /// The redacted report text.
    let text: String

    /// A file name for the save panel.
    let suggestedFileName: String

    // MARK: Generation

    /// Builds the report for a failed move against the app's current state.
    @MainActor
    static func generate(for failure: Failure, appState: AppState) async -> MoveFailureDiagnosticReport {
        // Not `.onScreen`: items parked in a collapsed section are the ones
        // a failed hidden-section move is usually about.
        let liveItems = await MenuBarItem.getMenuBarItems(on: nil, option: .activeSpace, resolveSourcePID: false)
        let logger = DiagnosticLogger.shared
        let diagnosticLoggingWasEnabled = logger.isEnabled
        let logSnapshot = await logger.tailSnapshot(maxBytes: logTailByteLimit)

        var writer = Writer()
        writeHeader(to: &writer)
        writeFailure(failure, appState: appState, to: &writer)
        writeDisplays(to: &writer)
        writeSettings(appState: appState, to: &writer)
        writeCachedMenuBar(appState: appState, liveItems: liveItems, to: &writer)
        writeLiveMenuBar(liveItems, to: &writer)
        writeSavedLayout(appState: appState, to: &writer)
        writeLogExcerpt(
            logSnapshot,
            diagnosticLoggingWasEnabled: diagnosticLoggingWasEnabled,
            to: &writer
        )

        let redactor = DiagnosticRedactor(terms: DiagnosticRedactor.accountTerms())
        return MoveFailureDiagnosticReport(
            text: redactor.redact(writer.text),
            suggestedFileName: suggestedFileName(for: Date())
        )
    }

    // MARK: Presentation

    /// Presents `alert` with an added "Save Diagnostic Report…" button and
    /// saves this report when it is chosen.
    ///
    /// Shown as a sheet on `window` when there is one. An app-modal alert
    /// holds the main actor for as long as it is up, and the move engine
    /// runs on the main actor: in the field another move sat behind a
    /// modal failure alert for fifteen seconds with its synthetic press
    /// still down, and Control Center completed that orphaned drag by
    /// removing the item from the bar. A sheet returns immediately.
    @MainActor
    func run(_ alert: NSAlert, in window: NSWindow? = nil) {
        let notice = String(
            localized: "The report retains installed-app identities, menu-item titles and status text, and display/menu-bar geometry for debugging. It attempts to redact other potentially sensitive information, but redaction cannot be guaranteed. Review the report before sharing it."
        )
        alert.informativeText = alert.informativeText.isEmpty ? notice : alert.informativeText + "\n\n" + notice
        let saveResponse = Self.configureButtons(on: alert)
        guard let window else {
            if alert.runModal() == saveResponse {
                save()
            }
            return
        }
        alert.beginSheetModal(for: window) { response in
            if response == saveResponse {
                save(in: window)
            }
        }
    }

    /// Reuses the primary button supplied by `NSAlert`, adds one save
    /// button, and returns the response value for that button.
    @MainActor
    static func configureButtons(on alert: NSAlert) -> NSApplication.ModalResponse {
        // `NSAlert` supplies its default OK button lazily in some contexts.
        // Loading the window makes `buttons` accurately reflect that button
        // before we add another one.
        _ = alert.window
        if let primaryButton = alert.buttons.first {
            primaryButton.title = String(localized: "OK")
        } else {
            alert.addButton(withTitle: String(localized: "OK"))
        }
        let saveTitle = String(localized: "Save Diagnostic Report…")
        alert.addButton(withTitle: saveTitle)
        if alert.buttons.count == 1 {
            // On older AppKit, adding a button can replace the lazily supplied
            // default instead of appending to it. Add the second explicit
            // button, then restore the primary title and order.
            alert.addButton(withTitle: saveTitle)
            alert.buttons[0].title = String(localized: "OK")
        }
        let saveButtonIndex = alert.buttons.lastIndex { $0.title == saveTitle } ?? (alert.buttons.count - 1)
        return NSApplication.ModalResponse(
            rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + saveButtonIndex
        )
    }

    /// Writes the report to `url`.
    func write(to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Asks where to save the report, writes it, and reveals it in Finder.
    @MainActor
    func save(in window: NSWindow? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = suggestedFileName
        panel.canCreateDirectories = true
        panel.title = String(localized: "Save Diagnostic Report")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try write(to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                let alert = NSAlert(error: error)
                if let window {
                    alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(panel.runModal())
        }
    }

    // MARK: Log excerpt

    /// Keeps the lines whose category is in ``logCategories``, newest
    /// `limit` of them. A line that does not parse as a log line (the file
    /// header, a continuation) is dropped.
    static func filterLogLines(_ lines: [String], limit: Int = logLineLimit) -> [String] {
        guard limit > 0 else { return [] }
        var kept: [String] = []
        kept.reserveCapacity(min(lines.count, limit))
        for line in lines.reversed() {
            guard let category = logCategory(of: line), logCategories.contains(category) else {
                continue
            }
            kept.append(line)
            if kept.count == limit {
                break
            }
        }
        return Array(kept.reversed())
    }

    /// The `[Category]` field of a log line, which follows the timestamp
    /// and the level: `2026-08-28 22:16:43.817 [DEBUG] [MenuBarItemManager] …`.
    static func logCategory(of line: String) -> String? {
        guard let match = line.firstMatch(of: #/^\S+ \S+ \[[A-Z]+\] \[([^\]]+)\]/#) else {
            return nil
        }
        return String(match.1)
    }

    /// The file name offered by the save panel.
    static func suggestedFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "\(Constants.displayName)-move-diagnostic-\(formatter.string(from: date)).txt"
    }
}

// MARK: - Sections

private extension MoveFailureDiagnosticReport {
    /// Accumulates the report's lines.
    struct Writer {
        private(set) var lines: [String] = []

        var text: String {
            lines.joined(separator: "\n") + "\n"
        }

        mutating func heading(_ title: String) {
            lines.append("")
            lines.append("## \(title)")
        }

        mutating func line(_ text: String = "") {
            lines.append(text)
        }
    }

    static func writeHeader(to writer: inout Writer) {
        let commit = Bundle.main.infoDictionary?["GitCommitSHA"] as? String ?? "unknown"
        writer.line("\(Constants.displayName) move diagnostic report")
        writer.line("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        writer.line()
        writer.line(
            """
            This report intentionally retains installed-app identities, menu-item titles \
            and status text, and display/menu-bar geometry because they are needed to \
            investigate the failure. Those values may themselves be sensitive. The report \
            attempts to redact usernames and full names, home-directory paths, network and \
            connected-device names, e-mail, IP and MAC addresses, trigger names and \
            condition values, and precise location coordinates. Automated redaction cannot \
            be guaranteed to catch everything. Review the report before sharing it.
            """
        )
        writer.heading("Environment")
        writer.line("\(Constants.displayName): \(Constants.versionString) (\(Constants.buildString)) commit \(commit)")
        writer.line("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        writer.line("Hardware: \(hardwareModel())")
        writer.line("Diagnostic logging: \(DiagnosticLogger.shared.isEnabled ? "enabled" : "disabled")")
    }

    @MainActor
    static func writeFailure(_ failure: Failure, appState: AppState, to writer: inout Writer) {
        let manager = appState.itemManager
        let cache = manager.itemCache

        writer.heading("Failure")
        writer.line("Error: \(describe(failure.error))")
        if let note = failure.note {
            writer.line("Note: \(note)")
        }
        writer.line("Expected section: \(failure.expectedSection.logString)")
        writer.line("Item: \(failure.item.logString)")
        for line in itemLines(failure.item, cache: cache, manager: manager) {
            writer.line(line)
        }
        let target = failure.destination.targetItem
        writer.line("Destination: \(failure.destination.logString)")
        for line in itemLines(target, cache: cache, manager: manager) {
            writer.line(line)
        }
        if let liveTargetBounds = Bridging.getWindowBounds(for: target.windowID) {
            writer.line("  liveBounds=\(format(liveTargetBounds))")
        }

        let lastMove = manager.lastMoveOperationTimestamp.map { instant in
            String(format: "%.1f s ago", (ContinuousClock.now - instant).milliseconds / 1000)
        } ?? "none this session"
        writer.line(
            "Manager state: bulkApply=\(manager.isBulkApplyInProgress) profileApply=\(manager.isApplyingProfileLayout) "
                + "resettingLayout=\(manager.isResettingLayout) restoringOrder=\(manager.isRestoringItemOrder) "
                + "startupSettling=\(manager.isInStartupSettling) controlItemsMissing=\(manager.areControlItemsMissing) "
                + "lastMove=\(lastMove)"
        )
    }

    @MainActor
    static func itemLines(
        _ item: MenuBarItem,
        cache: MenuBarItemManager.ItemCache,
        manager: MenuBarItemManager
    ) -> [String] {
        let section = cache.address(for: item.tag)?.section.logString ?? "not in cache"
        let owner = processDescription(item.ownerPID, application: item.owningApplication)
        let source = item.sourcePID.map { processDescription($0, application: item.sourceApplication) } ?? "unresolved"
        let movability = item.immovabilityReason?.logDescription ?? "movable"
        let timeout = manager.moveOperationTimeouts[item.tag].map { "\(Int($0.milliseconds)) ms" } ?? "default"
        return [
            "  identifier=\(item.tag.tagIdentifier) windowID=\(item.windowID)",
            "  bounds=\(format(item.bounds)) onScreen=\(item.isOnScreen) cachedSection=\(section)",
            "  owner=\(owner) source=\(source)",
            "  movability=\(movability) provisionalIdentity=\(item.hasProvisionalIdentity) "
                + "systemClone=\(item.isSystemClone) canBeHidden=\(item.canBeHidden) controlItem=\(item.isControlItem)",
            "  ownerUnresponsive=\(Bridging.isProcessUnresponsive(item.ownerPID)) "
                + "sourceUnresponsive=\(item.sourcePID.map { String(Bridging.isProcessUnresponsive($0)) } ?? "n/a") "
                + "ledgerUnresponsive=\(manager.failureLedger.isUnresponsive(item)) "
                + "ledgerBackoff=\(manager.failureLedger.isUnderBackoff(for: item)) moveTimeout=\(timeout)",
        ]
    }

    @MainActor
    static func writeDisplays(to writer: inout Writer) {
        let activeDisplayID = Bridging.getActiveMenuBarDisplayID()
        writer.heading("Displays")
        for (index, screen) in NSScreen.screens.enumerated() {
            let notch = screen.frameOfNotch.map(format) ?? "none"
            writer.line(
                "[\(index)] displayID=\(screen.displayID) frame=\(format(screen.frame)) "
                    + "visibleFrame=\(format(screen.visibleFrame)) scale=\(screen.backingScaleFactor) "
                    + "notch=\(notch) safeAreaTop=\(screen.safeAreaInsets.top) "
                    + "main=\(screen == NSScreen.main) activeMenuBar=\(screen.displayID == activeDisplayID)"
            )
        }
    }

    @MainActor
    static func writeSettings(appState: AppState, to writer: inout Writer) {
        writer.heading("Settings")
        writer.line("postMoveEventsToWindowOwner=\(MenuBarItem.postsMoveEventsToWindowOwner)")
        writer.line("discardStrayMoveEvents=\(defaultsValue(.discardStrayMoveEvents))")
        writer.line("enableAlwaysHiddenSection=\(appState.settings.advanced.enableAlwaysHiddenSection)")
        writer.line("useIceBar=\(defaultsValue(.useIceBar)) useIceBarOnlyOnNotchedDisplay=\(defaultsValue(.useIceBarOnlyOnNotchedDisplay))")
        writer.line("showOnClick=\(defaultsValue(.showOnClick)) showOnHover=\(defaultsValue(.showOnHover))")
    }

    @MainActor
    static func writeCachedMenuBar(appState: AppState, liveItems: [MenuBarItem], to writer: inout Writer) {
        let manager = appState.itemManager
        let cache = manager.itemCache
        writer.heading("Menu bar (cached sections, left to right)")
        writer.line("displayID=\(cache.displayID.map(String.init) ?? "nil")")
        for section in MenuBarSection.Name.allCases {
            let items = cache[section]
            writer.line("\(section.logString) (\(items.count)):")
            for item in items {
                writer.line("  \(compactDescription(of: item))")
            }
        }
        // The control item's own window reference is often nil; the divider
        // is still enumerable as a menu bar item by its tag.
        let dividers: [(name: MenuBarSection.Name, tag: MenuBarItemTag)] = [
            (.hidden, .hiddenControlItem),
            (.alwaysHidden, .alwaysHiddenControlItem),
        ]
        for divider in dividers {
            let windowID = appState.menuBarManager.controlItem(withName: divider.name)?.window
                .flatMap { CGWindowID(exactly: $0.windowNumber) }
                ?? liveItems.first { $0.tag == divider.tag }?.windowID
            guard let windowID else {
                writer.line("\(divider.name.logString) divider: not found")
                continue
            }
            let bounds = Bridging.getWindowBounds(for: windowID).map(format) ?? "unknown"
            writer.line("\(divider.name.logString) divider: windowID=\(windowID) bounds=\(bounds)")
        }
    }

    static func writeLiveMenuBar(_ items: [MenuBarItem], to writer: inout Writer) {
        writer.heading("Menu bar (live enumeration, active space, source processes unresolved)")
        for item in items.sorted(by: { $0.bounds.minX < $1.bounds.minX }) {
            writer.line("  \(compactDescription(of: item))")
        }
    }

    @MainActor
    static func writeSavedLayout(appState: AppState, to writer: inout Writer) {
        writer.heading("Saved layout")
        let order = appState.itemManager.savedSectionOrder
        for key in order.keys.sorted() {
            writer.line("\(key): \(order[key] ?? [])")
        }
    }

    static func writeLogExcerpt(
        _ snapshot: DiagnosticLogger.TailSnapshot?,
        diagnosticLoggingWasEnabled: Bool,
        to writer: inout Writer
    ) {
        writer.heading(
            "Recent log (categories: \(logCategories.sorted().joined(separator: ", ")); "
                + "newest \(logLineLimit) matching lines from a \(logTailByteLimit / 1024 / 1024) MiB tail)"
        )
        if !diagnosticLoggingWasEnabled {
            writer.line("Diagnostic logging is disabled; the most recent log file may predate this failure.")
        }
        guard let snapshot else {
            writer.line("(no log file available)")
            return
        }
        writer.line("File: \(snapshot.fileURL.lastPathComponent)")
        let lines = snapshot.text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let filteredLines = filterLogLines(lines)
        if filteredLines.isEmpty {
            writer.line("(no matching log lines in the bounded tail)")
        }
        for line in filteredLines {
            writer.line(line)
        }
    }

    // MARK: Formatting

    static func describe(_ error: any Error) -> String {
        let description = String(describing: error)
        if let localized = (error as? LocalizedError)?.errorDescription {
            return "\(description) — \(localized)"
        }
        return description
    }

    static func compactDescription(of item: MenuBarItem) -> String {
        let source = item.sourcePID.map(String.init) ?? "unresolved"
        let control = item.isControlItem ? " [control item]" : ""
        return "\(item.tag.tagIdentifier) windowID=\(item.windowID) minX=\(format(item.bounds.minX)) "
            + "width=\(format(item.bounds.width)) onScreen=\(item.isOnScreen) source=\(source)\(control)"
    }

    /// The activation policy matters for the source app: a regular app whose
    /// window is closed can be napped, and both revert episodes in the field
    /// logs began right after a long idle stretch.
    static func processDescription(_ pid: pid_t, application: NSRunningApplication?) -> String {
        guard let application else {
            return "pid \(pid) (not a running application)"
        }
        let identity = application.bundleIdentifier
            ?? "no bundle identifier; name=\(application.localizedName ?? "unknown")"
        let policy = switch application.activationPolicy {
        case .regular: "regular"
        case .accessory: "accessory"
        case .prohibited: "prohibited"
        @unknown default: "unknown"
        }
        return "pid \(pid) (\(identity)) policy=\(policy)"
    }

    static func defaultsValue(_ key: Defaults.Key) -> String {
        Defaults.object(forKey: key).map { String(describing: $0) } ?? "default"
    }

    static func format(_ rect: CGRect) -> String {
        "(x=\(format(rect.minX)) y=\(format(rect.minY)) w=\(format(rect.width)) h=\(format(rect.height)))"
    }

    static func format(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return "unknown"
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return "unknown"
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? "unknown"
    }
}
