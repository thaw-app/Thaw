//
//  ObjectStorage.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ObjectiveC

// MARK: - Object Storage

/// A type that uses the Objective-C runtime to store values of a given
/// type with an object.
final class ObjectStorage<Value> {
    /// The association policy to use for storage.
    private let policy = objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC

    /// The key used for value lookup.
    ///
    /// The key is unique to this instance.
    private var key: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
    }

    /// Sets the value for the given object.
    ///
    /// If the value is an object, it is stored with a strong reference.
    ///
    /// - Parameters:
    ///   - value: A value to set.
    ///   - object: An object to set the value for.
    func set(_ value: Value?, for object: AnyObject) {
        objc_setAssociatedObject(object, key, value, policy)
    }

    /// Retrieves the value stored for the given object.
    ///
    /// - Parameter object: An object to retrieve the value for.
    func value(for object: AnyObject) -> Value? {
        objc_getAssociatedObject(object, key) as? Value
    }
}
