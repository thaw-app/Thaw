//
//  PredicatesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
@Suite("Predicates")
struct PredicatesTests {
    @Test("A wrapped closure answers as the closure does")
    func wrappedClosure() {
        let isEven = Predicates<Int>.predicate { $0.isMultiple(of: 2) }
        #expect(isEven(4))
        #expect(!isEven(3))
    }

    @Test("A control item constraint is one whose second item is the button's superview")
    func controlItemConstraint() {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 40, height: 24))
        let button = NSStatusBarButton(frame: container.bounds)
        container.addSubview(button)
        let other = NSView()
        container.addSubview(other)
        let matches = Predicates<NSLayoutConstraint>.controlItemConstraint(button: button)

        #expect(matches(button.widthAnchor.constraint(equalTo: container.widthAnchor)))
        #expect(!matches(button.widthAnchor.constraint(equalTo: other.widthAnchor)))
        #expect(!matches(button.widthAnchor.constraint(equalToConstant: 10)))
    }
}
