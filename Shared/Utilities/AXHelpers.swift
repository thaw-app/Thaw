//
//  AXHelpers.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift
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

    static func title(for element: UIElement) -> String? {
        queue.sync { try? element.attribute(.title) }
    }

    static func axDescription(for element: UIElement) -> String? {
        queue.sync { try? element.attribute(.description) }
    }

    static func identifier(for element: UIElement) -> String? {
        queue.sync { try? element.attribute(.identifier) }
    }

    /// Resolves AX titles for the given menu bar item windows by matching
    /// AX extras menu bar children to CG windows by position.
    ///
    /// This is used on pre-macOS 26 where the XPC service is not available.
    /// The method iterates all running applications, finds their extras menu
    /// bar children via the Accessibility API, and matches them to the given
    /// windows using a 1-pixel center distance tolerance.
    static func resolveTitles(for windows: [WindowInfo]) -> [CGWindowID: String] {
        queue.sync {
            resolveTitlesBody(for: windows)
        }
    }

    private static func resolveTitlesBody(for windows: [WindowInfo]) -> [CGWindowID: String] {
        guard checkIsProcessTrusted() else {
            return [:]
        }

        var result = [CGWindowID: String]()
        var unresolvedWindows = Set(windows.map(\.windowID))
        let runningApps = NSWorkspace.shared.runningApplications

        for runningApp in runningApps {
            if unresolvedWindows.isEmpty {
                break
            }

            guard runningApp.isFinishedLaunching,
                  !runningApp.isTerminated,
                  !Bridging.isProcessUnresponsive(runningApp.processIdentifier)
            else {
                continue
            }

            autoreleasepool {
                guard let app = Application(runningApp),
                      let bar = try? app.attribute(.extrasMenuBar) as UIElement?
                else {
                    return
                }

                let children: [UIElement] = (try? bar.arrayAttribute(.children)) ?? []
                for child in children {
                    guard let isEnabled = try? child.attribute(.enabled) as Bool?,
                          isEnabled == true,
                          let childFrame = try? child.attribute(.frame) as CGRect?
                    else {
                        continue
                    }

                    let childCenter = childFrame.center

                    if let matchedWindow = windows.first(where: {
                        unresolvedWindows.contains($0.windowID) &&
                            $0.bounds.center.distance(to: childCenter) <= 1
                    }) {
                        let axTitle = (try? child.attribute(.title) as String?)
                            ?? (try? child.attribute(.description) as String?)
                        if let axTitle {
                            result[matchedWindow.windowID] = axTitle
                        }
                        unresolvedWindows.remove(matchedWindow.windowID)
                    }
                }
            }
        }

        return result
    }
}
