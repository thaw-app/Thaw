//
//  MenuBarItemEventSupportTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@Suite("Synthetic menu bar item events carry the fields the window server reads")
struct MenuBarItemEventSupportTests {
    private let item = MenuBarItem(
        tag: MenuBarItemTag(namespace: .string("com.example.events"), title: "Item", instanceIndex: 0),
        windowID: 7777,
        ownerPID: 999_993,
        sourcePID: 999_993,
        bounds: CGRect(x: 800, y: 0, width: 22, height: 24),
        title: "Item",
        isOnScreen: true
    )

    @Test("Each button maps to its own press and release pair")
    func pairsFollowTheButton() {
        #expect(MenuBarItemEventType.pair(for: .left) == (.leftMouseDown, .leftMouseUp))
        #expect(MenuBarItemEventType.pair(for: .right) == (.rightMouseDown, .rightMouseUp))
        #expect(MenuBarItemEventType.pair(for: .center) == (.otherMouseDown, .otherMouseUp))
    }

    @Test(
        "Event types report their Core Graphics type, button and click state",
        arguments: [
            (MenuBarItemEventType.leftMouseDown, CGEventType.leftMouseDown, CGMouseButton.left, Int64(1)),
            (.leftMouseUp, .leftMouseUp, .left, 0),
            (.rightMouseDown, .rightMouseDown, .right, 1),
            (.rightMouseUp, .rightMouseUp, .right, 0),
            (.otherMouseDown, .otherMouseDown, .center, 1),
            (.otherMouseUp, .otherMouseUp, .center, 0),
        ]
    )
    func eventTypeFields(type: MenuBarItemEventType, cgType: CGEventType, button: CGMouseButton, clickState: Int64) {
        #expect(type.cgEventType == cgType)
        #expect(type.cgMouseButton == button)
        #expect(type.clickState == clickState)
    }

    @Test("A menu bar item event targets the item's window with no modifiers")
    func menuBarItemEventFields() throws {
        let source = try #require(CGEventSource(stateID: .privateState))
        let location = CGPoint(x: 811, y: 12)

        let event = try #require(CGEvent.menuBarItemEvent(
            item: item,
            source: source,
            type: .rightMouseDown,
            location: location
        ))

        #expect(event.type == .rightMouseDown)
        #expect(event.location == location)
        #expect(event.flags.isEmpty)
        #expect(event.getIntegerValueField(.mouseEventWindowUnderMousePointer) == 7777)
        #expect(event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent) == 7777)
        #expect(event.getIntegerValueField(.mouseEventClickState) == 1)
        #expect(event.getIntegerValueField(.eventSourceUserData) != 0)
    }

    @Test("Two events match on the comparison fields only when they are the same event")
    func matchingUsesUserData() throws {
        let source = try #require(CGEventSource(stateID: .privateState))
        let first = try #require(CGEvent.menuBarItemEvent(item: item, source: source, type: .leftMouseDown, location: .zero))
        let second = try #require(CGEvent.menuBarItemEvent(item: item, source: source, type: .leftMouseDown, location: .zero))
        let copy = try #require(first.copy())

        #expect(first.matches(copy, byIntegerFields: CGEventField.menuBarItemEventFields))
        #expect(!first.matches(second, byIntegerFields: CGEventField.menuBarItemEventFields))
        #expect(first.matches(second, byIntegerFields: [.mouseEventWindowUnderMousePointer]))
    }

    @Test("A unique null event has its own user data")
    func uniqueNullEventsDiffer() throws {
        let first = try #require(CGEvent.uniqueNullEvent())
        let second = try #require(CGEvent.uniqueNullEvent())
        #expect(first.getIntegerValueField(.eventSourceUserData) != 0)
        #expect(!first.matches(second, byIntegerFields: [.eventSourceUserData]))
    }

    @Test("Setting a target process writes the target field")
    func targetPID() throws {
        let event = try #require(CGEvent(source: nil))
        event.setTargetPID(4321)
        #expect(event.getIntegerValueField(.eventTargetUnixProcessID) == 4321)
    }

    @Test("Durations convert to fractional milliseconds")
    func durationMilliseconds() {
        #expect(Duration.seconds(2).milliseconds == 2000)
        #expect(Duration.milliseconds(250).milliseconds == 250)
        #expect(Duration.microseconds(1500).milliseconds == 1.5)
    }

    @Test("Mouse buttons have readable names for the log")
    func mouseButtonLogStrings() {
        #expect(CGMouseButton.left.logString == "left mouse button")
        #expect(CGMouseButton.right.logString == "right mouse button")
        #expect(CGMouseButton.center.logString == "center mouse button")
    }

    @Test(
        "Event types have readable names for the log",
        arguments: [
            (CGEventType.null, "null"), (.leftMouseDown, "leftMouseDown"), (.leftMouseUp, "leftMouseUp"),
            (.rightMouseDown, "rightMouseDown"), (.rightMouseUp, "rightMouseUp"), (.mouseMoved, "mouseMoved"),
            (.leftMouseDragged, "leftMouseDragged"), (.rightMouseDragged, "rightMouseDragged"), (.keyDown, "keyDown"),
            (.keyUp, "keyUp"), (.flagsChanged, "flagsChanged"), (.scrollWheel, "scrollWheel"),
            (.tabletPointer, "tabletPointer"), (.tabletProximity, "tabletProximity"), (.otherMouseDown, "otherMouseDown"),
            (.otherMouseUp, "otherMouseUp"), (.otherMouseDragged, "otherMouseDragged"),
            (.tapDisabledByTimeout, "tapDisabledByTimeout"), (.tapDisabledByUserInput, "tapDisabledByUserInput"),
        ]
    )
    func eventTypeLogStrings(type: CGEventType, name: String) {
        #expect(type.logString == "\(name) event")
    }

    @Test("An event type the log does not know is named as unknown")
    func unknownEventTypeLogString() throws {
        let unknown = try #require(CGEventType(rawValue: 0x7FFF_FFF0))
        #expect(unknown.logString == "unknown event")
    }

    @Test("The permit-all mask allows mouse, keyboard and system events")
    func permitAllMask() {
        #expect(CGEventFilterMask.permitAllEvents.contains(.permitLocalMouseEvents))
        #expect(CGEventFilterMask.permitAllEvents.contains(.permitLocalKeyboardEvents))
        #expect(CGEventFilterMask.permitAllEvents.contains(.permitSystemDefinedEvents))
    }
}
