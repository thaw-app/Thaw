//
//  AXHelpers.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@preconcurrency import AXSwift
import Cocoa

enum AXHelpers {
    private static let queue = DispatchQueue.targetingGlobal(
        label: "AXHelpers.queue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    @discardableResult
    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        queue.sync { checkIsProcessTrusted(prompt: prompt) }
    }

    static func element(at point: CGPoint) -> UIElement? {
        queue.sync { try? systemWideElement.elementAtPosition(Float(point.x), Float(point.y)) }
    }

    static func application(for runningApp: NSRunningApplication) -> Application? {
        queue.sync { Application(runningApp) }
    }

    static func extrasMenuBar(for app: Application) -> UIElement? {
        queue.sync { try? app.attribute(.extrasMenuBar) }
    }

    static func children(for element: UIElement) -> [UIElement] {
        queue.sync { try? element.arrayAttribute(.children) } ?? []
    }

    static func isEnabled(_ element: UIElement) -> Bool {
        queue.sync { try? element.attribute(.enabled) } ?? false
    }

    static func frame(for element: UIElement) -> CGRect? {
        queue.sync { try? element.attribute(.frame) }
    }

    static func role(for element: UIElement) -> Role? {
        queue.sync { try? element.role() }
    }

    static func pid(for element: UIElement) -> pid_t? {
        queue.sync {
            var pid: pid_t = 0
            let result = AXUIElementGetPid(element.element, &pid)
            return result == .success ? pid : nil
        }
    }

    /// Returns the CGWindowID associated with the given AX element via
    /// the private _AXUIElementGetWindow SPI. Used to bridge from an
    /// AX proxy node (e.g. a Control-Center-hosted status item) back to
    /// the underlying CGWindow without relying on bounds proximity.
    static func windowID(for element: UIElement) -> CGWindowID? {
        queue.sync {
            var wid: CGWindowID = 0
            let result = _AXUIElementGetWindow(element.element, &wid)
            return result == .success ? wid : nil
        }
    }
}
