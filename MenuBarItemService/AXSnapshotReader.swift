//
//  AXSnapshotReader.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import CoreGraphics
import Foundation

/// Reads menu-bar item Accessibility attributes for a set of owner processes,
/// out of process (macOS 27). A hung owner blocks this helper — which Thaw can
/// abandon and respawn — instead of a thread in Thaw's own address space.
///
/// Uses only the raw `AXUIElement` C API, so the service needs no AXSwift
/// dependency. Reads only: it never writes an attribute or holds a live element
/// across a request.
enum AXSnapshotReader {
    static func snapshots(forOwnerPIDs pids: [pid_t]) -> [MenuBarItemService.MenuBarItemAXSnapshot] {
        var results: [MenuBarItemService.MenuBarItemAXSnapshot] = []
        for pid in Set(pids) {
            let app = AXUIElementCreateApplication(pid)
            guard let bar = extrasMenuBar(of: app) else { continue }
            for child in children(of: bar) {
                results.append(
                    MenuBarItemService.MenuBarItemAXSnapshot(
                        ownerPID: pid,
                        identifier: string(child, kAXIdentifierAttribute),
                        role: string(child, kAXRoleAttribute),
                        axDescription: string(child, kAXDescriptionAttribute),
                        title: string(child, kAXTitleAttribute),
                        frame: frame(of: child)
                    )
                )
            }
        }
        return results
    }

    private static func extrasMenuBar(of app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        // Safe: guarded by the AXUIElement type-ID check above.
        // swiftlint:disable:next force_cast
        return value as! AXUIElement
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement]
        else {
            return []
        }
        return array
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let axPosition = axValue(element, kAXPositionAttribute),
              let axSize = axValue(element, kAXSizeAttribute)
        else {
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(axPosition, .cgPoint, &origin),
              AXValueGetValue(axSize, .cgSize, &size)
        else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        // Safe: guarded by the AXValue type-ID check above.
        // swiftlint:disable:next force_cast
        return value as! AXValue
    }
}
