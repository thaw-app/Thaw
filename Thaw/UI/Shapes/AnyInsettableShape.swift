//
//  AnyInsettableShape.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A type-erased insettable shape.
struct AnyInsettableShape: InsettableShape {
    private let base: any InsettableShape

    /// Creates a type-erased insettable shape.
    init(_ shape: some InsettableShape) {
        self.base = shape
    }

    func path(in rect: CGRect) -> Path {
        base.path(in: rect)
    }

    func inset(by amount: CGFloat) -> AnyInsettableShape {
        AnyInsettableShape(base.inset(by: amount))
    }
}
