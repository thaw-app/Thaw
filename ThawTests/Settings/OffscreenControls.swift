//
//  OffscreenControls.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing

/// Works the controls of a view drawn off screen. Buttons are pressed through the
/// accessibility tree SwiftUI builds for the view, and menus are asked for their items
/// and never opened, so nothing shows on screen and no event reaches another app.
@MainActor
extension OffscreenRender {
    /// Every accessibility element under the view, in reading order.
    func elements() -> [NSObject] {
        host.layoutSubtreeIfNeeded()
        // SwiftUI builds its accessibility tree only once something asks for it; a hit test does.
        _ = host.accessibilityHitTest(.zero)
        return OffscreenAccessibility.descendants(of: host)
    }

    /// The elements with this role and label.
    func elements(role: NSAccessibility.Role, label: String) -> [NSObject] {
        elements().filter {
            OffscreenAccessibility.role(of: $0) == role && OffscreenAccessibility.label(of: $0) == label
        }
    }

    /// The words the view shows, as VoiceOver reads them.
    func texts() -> [String] {
        elements().compactMap { element in
            OffscreenAccessibility.role(of: element) == .staticText
                ? OffscreenAccessibility.string("accessibilityValue", of: element)
                : OffscreenAccessibility.label(of: element)
        }
    }

    /// Presses the button with this label, as VoiceOver's press does.
    func press(_ label: String, at index: Int = 0, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let buttons = elements(role: .button, label: label)
        try #require(buttons.indices.contains(index), "no button \(label) at \(index)", sourceLocation: sourceLocation)
        OffscreenAccessibility.press(buttons[index])
    }

    /// The AppKit views of one kind that SwiftUI made for the view.
    func views<T: NSView>(_ type: T.Type) -> [T] {
        host.layoutSubtreeIfNeeded()
        return OffscreenAccessibility.subviews(of: host, as: type)
    }

    /// Puts text in a field the way typing does, so SwiftUI hears the change.
    func type(_ text: String, into field: NSTextField) {
        field.stringValue = text
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    /// Ends editing in a field the way Return does.
    func submit(_ field: NSTextField) {
        field.sendAction(field.action, to: field.target)
    }

    /// The context menu SwiftUI would open over an element, with its items filled in. Nothing opens.
    func contextMenu(over element: NSObject) throws -> NSMenu {
        let window = try #require(host.window)
        let frame = try #require((element.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue)
        let point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        let menu = try #require(host.menu(for: event))
        menu.delegate?.menuNeedsUpdate?(menu)
        return menu
    }

    /// The menu behind a segmented control's arrow, with its items filled in. Nothing opens.
    func menu(of control: NSSegmentedControl, segment: Int) throws -> NSMenu {
        let menu = try #require(control.menu(forSegment: segment))
        menu.delegate?.menuNeedsUpdate?(menu)
        return menu
    }
}

@MainActor
extension NSMenu {
    /// Runs the item with this title, as choosing it does. The menu is never shown.
    func choose(_ title: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let index = indexOfItem(withTitle: title)
        try #require(index >= 0, "no menu item \(title)", sourceLocation: sourceLocation)
        performActionForItem(at: index)
    }
}

/// Reads accessibility elements by selector. SwiftUI's elements are plain objects
/// that answer the accessibility methods without adopting NSAccessibilityProtocol.
@MainActor
enum OffscreenAccessibility {
    static func object(_ selector: String, of element: NSObject) -> Any? {
        let selector = NSSelectorFromString(selector)
        guard element.responds(to: selector) else { return nil }
        return element.perform(selector)?.takeUnretainedValue()
    }

    static func string(_ selector: String, of element: NSObject) -> String? {
        object(selector, of: element) as? String
    }

    static func role(of element: NSObject) -> NSAccessibility.Role? {
        string("accessibilityRole", of: element).map(NSAccessibility.Role.init(rawValue:))
    }

    static func label(of element: NSObject) -> String? {
        string("accessibilityLabel", of: element)
    }

    static func descendants(of element: NSObject) -> [NSObject] {
        let children = object("accessibilityChildren", of: element) as? [NSObject] ?? []
        return [element] + children.flatMap { descendants(of: $0) }
    }

    static func press(_ element: NSObject) {
        _ = element.perform(NSSelectorFromString("accessibilityPerformPress"))
    }

    static func subviews<T: NSView>(of view: NSView, as type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { subviews(of: $0, as: type) }
    }
}
