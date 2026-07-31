//
//  PredicatesTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Covers ``Predicates``, the namespace the app uses to name closures that
/// would otherwise be anonymous at the call site.
///
/// Three of the four factories are pass-throughs, but they exist as an
/// overload set, and an overload set is a thing that can be resolved wrongly.
/// The zero-argument factories in particular wrap the body in a closure that
/// discards its input, so a mix-up between them and the one-argument factories
/// would compile and then quietly ignore the value being tested. Each test
/// therefore pins the result type explicitly, which forces a specific overload
/// rather than whatever the type checker happens to prefer.
///
/// ``Predicates/controlItemConstraint(button:)`` is the one factory with real
/// logic: it captures the button's superview *at creation time* and matches
/// against `secondItem`. Capturing eagerly is deliberate — the caller removes
/// constraints while walking the view tree — so the test pins that the target
/// is the superview and not the button itself.
@MainActor
@Suite("Predicates")
struct PredicatesTests {
    private enum PredicateError: Error {
        case rejected
    }

    // MARK: - One-Argument Factories

    @Test("A non-throwing predicate receives its input")
    func nonThrowingPredicateReceivesItsInput() {
        let isEven: Predicates<Int>.NonThrowingPredicate = Predicates<Int>.predicate { (value: Int) -> Bool in
            value.isMultiple(of: 2)
        }

        #expect(isEven(4))
        #expect(!isEven(5))
    }

    @Test("A throwing predicate receives its input")
    func throwingPredicateReceivesItsInput() throws {
        let isEven: Predicates<Int>.ThrowingPredicate = Predicates<Int>.predicate { (value: Int) throws -> Bool in
            guard value >= 0 else {
                throw PredicateError.rejected
            }
            return value.isMultiple(of: 2)
        }

        #expect(try isEven(4))
        #expect(try !isEven(5))
    }

    @Test("A throwing predicate propagates the error its body throws")
    func throwingPredicatePropagatesItsError() {
        let isEven: Predicates<Int>.ThrowingPredicate = Predicates<Int>.predicate { (value: Int) throws -> Bool in
            guard value >= 0 else {
                throw PredicateError.rejected
            }
            return value.isMultiple(of: 2)
        }

        #expect(throws: PredicateError.rejected) {
            try isEven(-1)
        }
    }

    // MARK: - Zero-Argument Factories

    /// The zero-argument factory has to build a one-argument closure around the
    /// body, so the test checks that the body runs once per call rather than
    /// once at creation.
    @Test("A non-throwing input-less predicate runs its body on every call")
    func nonThrowingInputLessPredicateRunsPerCall() {
        final class Counter {
            var calls = 0
        }

        let counter = Counter()
        let predicate: Predicates<String>.NonThrowingPredicate = Predicates<String>.predicate { () -> Bool in
            counter.calls += 1
            return true
        }

        #expect(counter.calls == 0)
        #expect(predicate("ignored"))
        #expect(predicate("also ignored"))
        #expect(counter.calls == 2)
    }

    @Test("A non-throwing input-less predicate ignores its input")
    func nonThrowingInputLessPredicateIgnoresItsInput() {
        let never: Predicates<String>.NonThrowingPredicate = Predicates<String>.predicate { () -> Bool in false }

        #expect(!never(""))
        #expect(!never("anything at all"))
    }

    @Test("A throwing input-less predicate returns its body's result")
    func throwingInputLessPredicateReturnsItsResult() throws {
        let always: Predicates<String>.ThrowingPredicate = Predicates<String>.predicate { () throws -> Bool in true }

        #expect(try always("ignored"))
    }

    @Test("A throwing input-less predicate propagates the error its body throws")
    func throwingInputLessPredicatePropagatesItsError() {
        let failing: Predicates<String>.ThrowingPredicate = Predicates<String>.predicate { () throws -> Bool in
            throw PredicateError.rejected
        }

        #expect(throws: PredicateError.rejected) {
            try failing("ignored")
        }
    }

    // MARK: - Control Item Constraints

    /// Builds a button inside a container, mimicking the status item's view
    /// tree closely enough for the predicate to have a superview to match.
    @MainActor
    @Suite("Control item constraint")
    struct ControlItemConstraintTests {
        private let container = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 22))
        private let button = NSStatusBarButton(frame: CGRect(x: 0, y: 0, width: 25, height: 22))
        private let sibling = NSView(frame: CGRect(x: 0, y: 0, width: 25, height: 22))

        init() {
            container.addSubview(button)
            container.addSubview(sibling)
        }

        private func constraint(to item: NSView?) -> NSLayoutConstraint {
            NSLayoutConstraint(
                item: button,
                attribute: .width,
                relatedBy: .equal,
                toItem: item,
                attribute: item == nil ? .notAnAttribute : .width,
                multiplier: 1,
                constant: item == nil ? 25 : 0
            )
        }

        @Test("A constraint against the button's superview matches")
        func constraintAgainstTheSuperviewMatches() {
            let predicate = Predicates<NSLayoutConstraint>.controlItemConstraint(button: button)

            #expect(predicate(constraint(to: container)))
        }

        @Test("A constraint against a sibling view does not match")
        func constraintAgainstASiblingDoesNotMatch() {
            let predicate = Predicates<NSLayoutConstraint>.controlItemConstraint(button: button)

            #expect(!predicate(constraint(to: sibling)))
        }

        /// Width and height constraints have no second item at all; they must
        /// not be swept up by a predicate that only compares against nil when
        /// the button genuinely has no superview.
        @Test("A constraint with no second item does not match")
        func constraintWithNoSecondItemDoesNotMatch() {
            let predicate = Predicates<NSLayoutConstraint>.controlItemConstraint(button: button)

            #expect(!predicate(constraint(to: nil)))
        }

        /// The predicate matches the superview, not the button, so a constraint
        /// whose second item is the button itself is left alone.
        @Test("A constraint against the button itself does not match")
        func constraintAgainstTheButtonDoesNotMatch() {
            let predicate = Predicates<NSLayoutConstraint>.controlItemConstraint(button: button)
            let selfReferential = NSLayoutConstraint(
                item: sibling,
                attribute: .width,
                relatedBy: .equal,
                toItem: button,
                attribute: .width,
                multiplier: 1,
                constant: 0
            )

            #expect(!predicate(selfReferential))
        }

        /// The superview is captured when the predicate is created, so moving
        /// the button afterwards does not retarget an existing predicate.
        @Test("The target superview is captured when the predicate is created")
        func targetSuperviewIsCapturedAtCreation() {
            let predicate = Predicates<NSLayoutConstraint>.controlItemConstraint(button: button)
            let newParent = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 22))

            newParent.addSubview(button)

            #expect(predicate(constraint(to: container)))
            #expect(!predicate(constraint(to: newParent)))
        }
    }
}
