//
//  AXReader.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import ThawAXCore

/// Reads the menu bar out of the Accessibility tree. Read-only, and in its own
/// process so a wedged status-item app blocks this helper, not the app's main
/// thread. Reports attributes verbatim; identity is assembled by the app.
enum AXReader {
    /// One hung app must not stall the whole walk.
    private static let messagingTimeout: Float = 0.25
    /// Fallback ceiling when the request names none. Children taller than this
    /// are popovers or panels, not status items.
    private static let defaultMaximumItemHeight: CGFloat = 40

    /// Answers one request. Every branch reports trust, so the app can fall
    /// back to its own reads when the helper was never granted Accessibility.
    static func serve(_ request: AXHelperRequest) -> AXHelperReply {
        switch request {
        case let .enumerate(enumerateRequest):
            return .enumerate(enumerate(enumerateRequest))
        case let .applicationMenuFrames(pid):
            guard AXIsProcessTrusted() else {
                return .applicationMenuFrames(frames: nil, accessibilityTrusted: false)
            }
            let frames = AXPrimitives.applicationMenuFrames(pid: pid, messagingTimeout: messagingTimeout)
            return .applicationMenuFrames(frames: frames, accessibilityTrusted: true)
        case let .hitTest(x, y):
            guard AXIsProcessTrusted() else {
                return .hitTest(nil, accessibilityTrusted: false)
            }
            return .hitTest(hitTest(at: CGPoint(x: x, y: y)), accessibilityTrusted: true)
        case let .pressStatusItem(pid, targetX, targetY, tolerance):
            guard AXIsProcessTrusted() else {
                return .press(pressed: false, accessibilityTrusted: false)
            }
            let pressed = AXPrimitives.pressNearestStatusItem(
                pid: pid,
                target: CGPoint(x: targetX, y: targetY),
                tolerance: tolerance,
                messagingTimeout: messagingTimeout
            )
            return .press(pressed: pressed, accessibilityTrusted: true)
        case let .pressHostedItem(sourcePID):
            guard AXIsProcessTrusted() else {
                return .press(pressed: false, accessibilityTrusted: false)
            }
            let pressed = AXPrimitives.pressHostedItem(
                sourcePID: sourcePID,
                messagingTimeout: messagingTimeout
            )
            return .press(pressed: pressed, accessibilityTrusted: true)
        }
    }

    static func enumerate(_ request: AXEnumerateRequest) -> AXEnumerateReply {
        let trusted = AXIsProcessTrusted()
        guard trusted else {
            return AXEnumerateReply(
                items: [],
                completed: false,
                accessibilityTrusted: false,
                errorDescription: "accessibilityNotTrusted"
            )
        }

        let deadline = request.deadlineSeconds.map { Date().addingTimeInterval($0) }
        let displayBounds = request.displayID.map { CGDisplayBounds($0) }
        let maximumItemHeight = CGFloat(request.maximumItemHeight ?? Double(defaultMaximumItemHeight))
        var observations: [AXItemObservation] = []
        var completed = true

        for app in runningApplications() {
            if app.isTerminated {
                continue
            }
            if let deadline, Date() >= deadline {
                completed = false
                break
            }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, messagingTimeout)

            guard let bar = AXPrimitives.elementAttribute(appElement, kAXExtrasMenuBarAttribute as String) else {
                continue
            }
            let overflow = AXPrimitives.elementAttribute(bar, "AXOverflowButton")
            // Builds without AXOverflowButton still mark the chevron by its role.
            let isMenuBarAgent = app.bundleIdentifier == "com.apple.MenuBarAgent"
            let children = AXPrimitives.children(of: bar)

            for child in children {
                if let deadline, Date() >= deadline {
                    completed = false
                    break
                }
                guard let reported = AXPrimitives.frame(of: child), !reported.isNull, !reported.isEmpty else { continue }
                guard let frame = AXPrimitives.itemFrame(reported, maximumHeight: maximumItemHeight) else { continue }
                if let displayBounds, !AXPrimitives.frame(frame, isWithin: displayBounds) {
                    continue
                }

                let identifier = AXPrimitives.stringAttribute(child, kAXIdentifierAttribute)
                let accessibilityDescription = AXPrimitives.stringAttribute(child, kAXDescriptionAttribute)
                // Some apps publish the stable identifier and description on the
                // status-bar button rather than its container, so read one level
                // deeper for the values the in-process walk falls back to. Only
                // scan when the item's own value would not win, mirroring the
                // in-process walk's lazy fallback.
                let childElements = needsChildScan(identifier: identifier, description: accessibilityDescription)
                    ? AXPrimitives.children(of: child)
                    : []

                observations.append(
                    AXItemObservation(
                        bundleID: app.bundleIdentifier,
                        processName: app.localizedName,
                        ownerPID: AXPrimitives.pid(of: child) ?? app.processIdentifier,
                        identifier: identifier,
                        accessibilityDescription: accessibilityDescription,
                        title: AXPrimitives.stringAttribute(child, kAXTitleAttribute),
                        help: AXPrimitives.stringAttribute(child, kAXHelpAttribute),
                        frame: frame,
                        isOverflowControl: overflow.map { CFEqual($0, child) } ?? false
                            || isMenuBarAgent && AXPrimitives.isMenuBarAgentOverflowRole(
                                AXPrimitives.stringAttribute(child, kAXRoleAttribute)
                            ),
                        childIdentifier: childElements
                            .compactMap { stableIdentifier(AXPrimitives.stringAttribute($0, kAXIdentifierAttribute)) }
                            .first,
                        childDescription: childElements
                            .compactMap { AXPrimitives.stringAttribute($0, kAXDescriptionAttribute) }
                            .first
                    )
                )
            }
        }

        return AXEnumerateReply(
            items: observations,
            completed: completed,
            accessibilityTrusted: true
        )
    }

    /// Every running application, looked up fresh by pid.
    ///
    /// Not NSWorkspace.shared.runningApplications, which this process never
    /// refreshes, even with the main run loop running.
    private static func runningApplications() -> [NSRunningApplication] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return NSWorkspace.shared.runningApplications }
        // Headroom for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return NSWorkspace.shared.runningApplications }
        return pids.prefix(Int(filled)).compactMap { NSRunningApplication(processIdentifier: $0) }
    }

    // MARK: - Pointer reads and presses

    private static func hitTest(at point: CGPoint) -> AXHitTestResult? {
        guard let element = AXPrimitives.hitTestElement(at: point, messagingTimeout: messagingTimeout),
              let pid = AXPrimitives.pid(of: element)
        else {
            return nil
        }
        return AXHitTestResult(pid: pid, role: AXPrimitives.stringAttribute(element, kAXRoleAttribute))
    }

    /// Whether the item's own identifier is missing or a per-launch placeholder
    /// and the description is missing, so the nested-child fallback is worth a
    /// scan. The stability check is shared with the app so both walks agree on
    /// which nested identifier wins.
    private static func needsChildScan(identifier: String?, description: String?) -> Bool {
        stableIdentifier(identifier) == nil || description == nil
    }

    /// A trimmed, stable AXIdentifier, or nil when the value is blank or a
    /// per-launch placeholder.
    private static func stableIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isStableAXIdentifier(trimmed) else { return nil }
        return trimmed
    }
}
