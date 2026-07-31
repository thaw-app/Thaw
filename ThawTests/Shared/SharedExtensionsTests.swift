//
//  SharedExtensionsTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@Suite("Shared extensions")
struct SharedExtensionsTests {
    // MARK: - CGError Extension Tests

    @Suite("CGError")
    struct CGErrorExtensionTests {
        // MARK: - LogString Tests

        @Test("success logs its name")
        func successLogString() {
            let error = CGError.success
            #expect(error.logString == "\(error.rawValue): success")
        }

        @Test("failure logs its name")
        func failureLogString() {
            let error = CGError.failure
            #expect(error.logString == "\(error.rawValue): failure")
        }

        @Test("illegalArgument logs its name")
        func illegalArgumentLogString() {
            let error = CGError.illegalArgument
            #expect(error.logString == "\(error.rawValue): illegalArgument")
        }

        @Test("invalidConnection logs its name")
        func invalidConnectionLogString() {
            let error = CGError.invalidConnection
            #expect(error.logString == "\(error.rawValue): invalidConnection")
        }

        @Test("invalidContext logs its name")
        func invalidContextLogString() {
            let error = CGError.invalidContext
            #expect(error.logString == "\(error.rawValue): invalidContext")
        }

        @Test("cannotComplete logs its name")
        func cannotCompleteLogString() {
            let error = CGError.cannotComplete
            #expect(error.logString == "\(error.rawValue): cannotComplete")
        }

        @Test("notImplemented logs its name")
        func notImplementedLogString() {
            let error = CGError.notImplemented
            #expect(error.logString == "\(error.rawValue): notImplemented")
        }

        @Test("rangeCheck logs its name")
        func rangeCheckLogString() {
            let error = CGError.rangeCheck
            #expect(error.logString == "\(error.rawValue): rangeCheck")
        }

        @Test("typeCheck logs its name")
        func typeCheckLogString() {
            let error = CGError.typeCheck
            #expect(error.logString == "\(error.rawValue): typeCheck")
        }

        @Test("invalidOperation logs its name")
        func invalidOperationLogString() {
            let error = CGError.invalidOperation
            #expect(error.logString == "\(error.rawValue): invalidOperation")
        }

        @Test("noneAvailable logs its name")
        func noneAvailableLogString() {
            let error = CGError.noneAvailable
            #expect(error.logString == "\(error.rawValue): noneAvailable")
        }

        @Test("The log string carries the raw value")
        func logStringContainsRawValue() {
            let error = CGError.failure
            #expect(error.logString.contains("\(error.rawValue)"))
        }
    }

    // MARK: - CGPoint Extension Tests

    @Suite("CGPoint")
    struct CGPointExtensionTests {
        // MARK: - Distance Tests

        @Test("A point is zero distance from itself")
        func distanceToSamePoint() {
            let point = CGPoint(x: 10, y: 20)
            #expect(point.distance(to: point) == 0)
        }

        @Test("A horizontal offset measures its width")
        func distanceHorizontal() {
            let point1 = CGPoint(x: 0, y: 0)
            let point2 = CGPoint(x: 10, y: 0)
            #expect(point1.distance(to: point2) == 10)
        }

        @Test("A vertical offset measures its height")
        func distanceVertical() {
            let point1 = CGPoint(x: 0, y: 0)
            let point2 = CGPoint(x: 0, y: 15)
            #expect(point1.distance(to: point2) == 15)
        }

        @Test("A 3-4-5 triangle measures 5")
        func distanceDiagonal345() {
            // 3-4-5 right triangle
            let point1 = CGPoint(x: 0, y: 0)
            let point2 = CGPoint(x: 3, y: 4)
            #expect(point1.distance(to: point2) == 5)
        }

        @Test("Negative coordinates measure the same distance")
        func distanceNegativeCoordinates() {
            let point1 = CGPoint(x: -5, y: -5)
            let point2 = CGPoint(x: -5, y: 5)
            #expect(point1.distance(to: point2) == 10)
        }

        @Test("Distance is symmetric")
        func distanceIsSymmetric() {
            let point1 = CGPoint(x: 10, y: 20)
            let point2 = CGPoint(x: 30, y: 40)
            #expect(point1.distance(to: point2) == point2.distance(to: point1))
        }

        @Test("A unit diagonal measures the square root of two")
        func distanceFractional() {
            let point1 = CGPoint(x: 0, y: 0)
            let point2 = CGPoint(x: 1, y: 1)
            let expected = sqrt(2.0)
            #expect(abs(point1.distance(to: point2) - expected) < 0.0001)
        }

        @Test("Large coordinates stay accurate")
        func distanceLargeValues() {
            let point1 = CGPoint(x: 0, y: 0)
            let point2 = CGPoint(x: 1000, y: 1000)
            let expected = sqrt(2_000_000.0)
            #expect(abs(point1.distance(to: point2) - expected) < 0.0001)
        }
    }

    // MARK: - CGRect Extension Tests

    @Suite("CGRect")
    struct CGRectExtensionTests {
        // MARK: - Center Tests

        @Test("A rect at the origin centers on its half size")
        func centerOfOriginRect() {
            let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
            #expect(rect.center == CGPoint(x: 50, y: 50))
        }

        @Test("An offset rect centers relative to its origin")
        func centerOfOffsetRect() {
            let rect = CGRect(x: 10, y: 20, width: 100, height: 200)
            #expect(rect.center == CGPoint(x: 60, y: 120))
        }

        @Test("A negatively positioned rect centers correctly")
        func centerOfNegativeOriginRect() {
            let rect = CGRect(x: -50, y: -50, width: 100, height: 100)
            #expect(rect.center == CGPoint(x: 0, y: 0))
        }

        @Test("A zero-size rect centers on its origin")
        func centerOfZeroSizeRect() {
            let rect = CGRect(x: 10, y: 20, width: 0, height: 0)
            #expect(rect.center == CGPoint(x: 10, y: 20))
        }

        @Test("A unit rect centers on a half point")
        func centerOfUnitRect() {
            let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
            #expect(rect.center == CGPoint(x: 0.5, y: 0.5))
        }

        @Test("An asymmetric rect centers on each axis independently")
        func centerOfAsymmetricRect() {
            let rect = CGRect(x: 0, y: 0, width: 200, height: 50)
            #expect(rect.center == CGPoint(x: 100, y: 25))
        }

        @Test("The center agrees with midX and midY")
        func centerUsesMidXMidY() {
            let rect = CGRect(x: 5, y: 10, width: 30, height: 40)
            #expect(rect.center.x == rect.midX)
            #expect(rect.center.y == rect.midY)
        }
    }
}
