//
//  ScreenCapture+Permissions.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import MenuBarModel
import ScreenCaptureKit

public extension ScreenCapture {
    // MARK: Permissions

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions.
    static func checkPermissions() -> Bool {
        let windowIDs = Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace])
        diagLog.debug("checkPermissions: checking \(windowIDs.count) menu bar window(s) for title access")
        var windowTitles = [String?]()

        for windowID in windowIDs {
            guard
                let window = WindowInfo(windowID: windowID),
                window.owningApplication != .current // Skip windows we own.
            else {
                continue
            }
            let hasTitle = window.title != nil
            diagLog.debug("checkPermissions: windowID=\(windowID) pid=\(window.ownerPID) owner=\"\(window.ownerName ?? "nil")\" title=\"\(window.title ?? "nil")\" → hasTitle=\(hasTitle)")
            windowTitles.append(window.title)
        }

        let preflightResult = CGPreflightScreenCaptureAccess()
        let result = permissionGranted(
            windowTitles: windowTitles,
            preflightResult: preflightResult
        )
        diagLog.debug("checkPermissions: titledWindow=\(windowTitles.contains { $0 != nil }), CGPreflightScreenCaptureAccess()=\(preflightResult) → \(result)")
        return result
    }

    /// Resolves screen capture access from all eligible window titles and the
    /// Core Graphics preflight result. A single untitled window must not mask
    /// a later titled window that proves access.
    internal static func permissionGranted(
        windowTitles: [String?],
        preflightResult: Bool
    ) -> Bool {
        preflightResult || windowTitles.contains { $0 != nil }
    }

    /// A Boolean value that indicates whether the app has screen capture
    /// permissions.
    ///
    /// This property caches its initial result and returns it on subsequent
    /// reads. Call ``recomputeCachedScreenRecordingPermission()`` to replace
    /// the cached result with a newly computed value.
    static var hasCachedScreenRecordingPermission: Bool {
        if let result = cachedPermissionResult.withLock({ $0 }) {
            return result
        }
        return recomputeCachedScreenRecordingPermission()
    }

    /// Recomputes and caches the current screen capture permission state,
    /// replacing any previously cached result.
    @discardableResult
    static func recomputeCachedScreenRecordingPermission() -> Bool {
        let result = checkPermissions()
        diagLog.debug("recomputeCachedScreenRecordingPermission: computed fresh result = \(result) (wasCached=\(cachedPermissionResult.withLock { $0 != nil }))")
        cachedPermissionResult.withLock { $0 = result }
        return result
    }

    private static func setCachedPermissionResult(_ result: Bool?) {
        cachedPermissionResult.withLock { $0 = result }
    }

    /// Re-checks screen capture access with ScreenCaptureKit so a grant made
    /// in System Settings can become visible without restarting the process.
    static func refreshPermissions() async -> Bool {
        let preflightResult = CGPreflightScreenCaptureAccess()
        if preflightResult {
            setCachedPermissionResult(true)
            return true
        }

        do {
            _ = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            setCachedPermissionResult(true)
            return true
        } catch {
            diagLog.debug("refreshPermissions: ScreenCaptureKit probe failed: \(error)")
            setCachedPermissionResult(false)
            return false
        }
    }

    static func restoreActivationPolicyAfterScreenCapturePrompt(
        currentPolicy: NSApplication.ActivationPolicy,
        setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Bool,
        activate: () -> Void
    ) -> (() -> Void)? {
        guard currentPolicy != .regular else {
            activate()
            return nil
        }

        _ = setActivationPolicy(.regular)
        activate()

        return {
            _ = setActivationPolicy(currentPolicy)
        }
    }

    /// Requests screen capture permissions.
    @MainActor
    static func requestPermissions(
        completion: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
    ) {
        diagLog.debug("requestPermissions: requesting screen capture access")
        setCachedPermissionResult(nil)

        // Thaw is an LSUIElement (agent) app with no Dock icon. The system
        // permission prompt for Screen Recording is only reliably surfaced
        // — and the app only reliably registered in System Settings' list —
        // when the requesting process is a normal frontmost app. Temporarily
        // switch out of agent mode for the request, then restore it after the
        // TCC request has been kicked off.
        let restoreActivationPolicy = restoreActivationPolicyAfterScreenCapturePrompt(
            currentPolicy: NSApp.activationPolicy(),
            setActivationPolicy: { NSApp.setActivationPolicy($0) },
            activate: { NSApp.activate(ignoringOtherApps: true) }
        )

        // CGRequestScreenCaptureAccess() was reported broken on macOS 15
        // (didn't reliably prompt), so this used to rely solely on
        // SCShareableContent to trigger the prompt. On macOS 27 that alone
        // has been observed to leave the app entirely absent from the
        // Screen Recording list, even after the call completes and even
        // after a full relaunch. Call both: CGRequestScreenCaptureAccess()
        // is the documented public API for adding an app to that list, and
        // SCShareableContent is kept as a fallback trigger.
        let cgResult = CGRequestScreenCaptureAccess()
        if cgResult {
            setCachedPermissionResult(true)
            completion(true)
        }
        diagLog.debug("requestPermissions: CGRequestScreenCaptureAccess() = \(cgResult)")

        SCShareableContent.getWithCompletionHandler { content, error in
            if let error {
                diagLog.debug("requestPermissions: SCShareableContent request failed: \(error)")
            } else {
                setCachedPermissionResult(true)
                diagLog.debug("requestPermissions: SCShareableContent request succeeded (\(content?.windows.count ?? 0) windows)")
                Task { @MainActor in
                    completion(true)
                }
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            restoreActivationPolicy?()
        }
    }
}
