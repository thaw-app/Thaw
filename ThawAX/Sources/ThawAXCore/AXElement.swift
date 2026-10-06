//
//  AXElement.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import CoreGraphics
import os

/// An AXUIElement that can cross concurrency domains. Equality and hashing are
/// the system's CFEqual and CFHash, so two reads of one element compare equal.
///
/// Every element gets defaultMessagingTimeout when wrapped, children included:
/// a timeout set on one element does not carry over to elements read from it.
public struct AXElement: @unchecked Sendable, Hashable {
    public let raw: AXUIElement

    private static let timeout = OSAllocatedUnfairLock<Float>(initialState: 0)

    /// Seconds; 0 keeps the system default of about six. Set once at launch.
    public static var defaultMessagingTimeout: Float {
        get { timeout.withLock { $0 } }
        set { timeout.withLock { $0 = max(newValue, 0) } }
    }

    public init(_ raw: AXUIElement) {
        self.raw = raw
        let timeout = Self.defaultMessagingTimeout
        if timeout > 0 {
            AXUIElementSetMessagingTimeout(raw, timeout)
        }
    }

    public static func application(_ pid: pid_t) -> AXElement {
        AXElement(AXUIElementCreateApplication(pid))
    }

    public var pid: pid_t? {
        AXPrimitives.pid(of: raw)
    }

    public func setMessagingTimeout(_ seconds: Float) {
        AXUIElementSetMessagingTimeout(raw, seconds)
    }

    /// One attribute, unpacked as in values(_:), or nil when it did not answer.
    public func value(_ attribute: String) -> Any? {
        AXPrimitives.copyAttribute(raw, attribute).flatMap(Self.unpack)
    }

    /// Several attributes in one message, keyed by name. The timeout bounds the
    /// whole read, so a slow app costs one timeout rather than one per attribute.
    /// Attributes that are absent, unsupported or errored are left out.
    public func values(_ attributes: [String]) -> [String: Any] {
        var array: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(
            raw,
            attributes as CFArray,
            AXCopyMultipleAttributeOptions(rawValue: 0),
            &array
        ) == .success,
            let values = array as [AnyObject]?,
            values.count == attributes.count
        else {
            return [:]
        }
        var result = [String: Any]()
        for (attribute, value) in zip(attributes, values) {
            result[attribute] = Self.unpack(value)
        }
        return result
    }

    /// The names the element advertises, or nil when it did not answer.
    public func attributeNames() -> [String]? {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(raw, &names) == .success else { return nil }
        return names as? [String]
    }

    public func perform(_ action: String) -> AXError {
        AXUIElementPerformAction(raw, action as CFString)
    }

    /// Elements become AXElement, geometry AXValues their Swift types, and an
    /// error placeholder from a batch read nil. Arrays are unpacked per element.
    static func unpack(_ value: AnyObject) -> Any? {
        if let array = value as? [AnyObject] {
            return array.compactMap(unpack)
        }
        switch CFGetTypeID(value) {
        case AXUIElementGetTypeID():
            return AXElement(unsafeDowncast(value, to: AXUIElement.self))
        case AXValueGetTypeID():
            return unpack(axValue: unsafeDowncast(value, to: AXValue.self))
        default:
            return value
        }
    }

    private static func unpack(axValue: AXValue) -> Any? {
        let type = AXValueGetType(axValue)
        switch type {
        case .cgRect:
            var rect = CGRect.zero
            return AXValueGetValue(axValue, type, &rect) ? rect : nil
        case .cgPoint:
            var point = CGPoint.zero
            return AXValueGetValue(axValue, type, &point) ? point : nil
        case .cgSize:
            var size = CGSize.zero
            return AXValueGetValue(axValue, type, &size) ? size : nil
        case .cfRange:
            var range = CFRange()
            return AXValueGetValue(axValue, type, &range) ? range : nil
        default:
            return nil
        }
    }
}
