//
//  MenuBarShapePathBuilderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// The overlay's shape paths, built against the test machine's first screen.
/// Expectations that depend on a notch read it from that screen.
@Suite("Menu bar shape paths")
@MainActor
struct MenuBarShapePathBuilderTests {
    private let round = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .round)
    private let square = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
    private let rect = CGRect(x: 0, y: 0, width: 800, height: 24)

    private func screen() throws -> NSScreen {
        try #require(NSScreen.screens.first)
    }

    @Test("Corner radius scales with roundness up to half the shorter side")
    func cornerRadius() {
        #expect(MenuBarShapePathBuilder.cornerRadius(of: rect, roundness: 1) == 12)
        #expect(MenuBarShapePathBuilder.cornerRadius(of: rect, roundness: 0.5) == 6)
        #expect(MenuBarShapePathBuilder.cornerRadius(of: rect, roundness: 3) == 12)
        #expect(MenuBarShapePathBuilder.cornerRadius(of: rect, roundness: -1) == 0)
        #expect(MenuBarShapePathBuilder.cornerRadius(of: CGRect(x: 0, y: 0, width: 10, height: 24), roundness: 1) == 5)
        #expect(MenuBarShapePathBuilder.cornerRadius(of: .zero, roundness: 1) == 0)
    }

    @Test("Notch inset applies only to inset shapes on a notched display, and only rounded ends move")
    func insetForNotch() throws {
        let screen = try screen()
        let untouched = MenuBarShapePathBuilder.insetForNotch(rect, outerCaps: round, isInset: false, screen: screen, amount: 4)
        #expect(untouched == rect)

        let inset = MenuBarShapePathBuilder.insetForNotch(rect, outerCaps: round, isInset: true, screen: screen, amount: 4)
        let squareInset = MenuBarShapePathBuilder.insetForNotch(rect, outerCaps: square, isInset: true, screen: screen, amount: 4)
        if screen.hasNotch {
            #expect(inset == CGRect(x: 4, y: 4, width: 792, height: 16))
            #expect(squareInset == CGRect(x: 0, y: 4, width: 800, height: 16))
        } else {
            #expect(inset == rect)
            #expect(squareInset == rect)
        }
    }

    @Test("A shape fills its rect, pulled a hair in off a notched display")
    func shapePathBounds() throws {
        let screen = try screen()
        let roundBounds = MenuBarShapePathBuilder.shapePath(in: rect, caps: round, screen: screen).bounds
        let squareBounds = MenuBarShapePathBuilder.shapePath(in: rect, caps: square, screen: screen).bounds
        if screen.hasNotch {
            #expect(roundBounds == rect)
            #expect(squareBounds == rect)
        } else {
            #expect(roundBounds == CGRect(x: 1, y: 1, width: 798, height: 22))
            #expect(squareBounds == CGRect(x: 0, y: 1, width: 800, height: 22))
        }
    }

    @Test("Square ends fill the corners a rounded end leaves open")
    func squareEndsCoverCorners() throws {
        let screen = try screen()
        let corner = CGPoint(x: 1.5, y: 1.5)
        #expect(!MenuBarShapePathBuilder.shapePath(in: rect, caps: round, screen: screen).contains(corner))
        #expect(MenuBarShapePathBuilder.shapePath(in: rect, caps: square, screen: screen).contains(corner))
        let mixed = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .round)
        let mixedPath = MenuBarShapePathBuilder.shapePath(in: rect, caps: mixed, screen: screen)
        #expect(mixedPath.contains(corner))
        #expect(!mixedPath.contains(CGPoint(x: 798.5, y: 1.5)))
    }

    @Test("A full shape is empty without an inset amount and otherwise honours its margins")
    func fullShape() throws {
        let screen = try screen()
        let empty = MenuBarShapePathBuilder.fullShapePath(in: rect, info: square, isInset: false, screen: screen, leftMargin: 10, rightMargin: 20, insetAmount: nil)
        #expect(empty.isEmpty)
        let path = MenuBarShapePathBuilder.fullShapePath(in: rect, info: square, isInset: false, screen: screen, leftMargin: 10, rightMargin: 20, insetAmount: 2)
        #expect(path.bounds.minX == 10)
        #expect(path.bounds.maxX == 780)
    }

    @Test("A notch shape is empty without an inset amount and draws something otherwise")
    func notchShape() throws {
        let screen = try screen()
        let info = MenuBarNotchShapeInfo(leading: round, trailing: round)
        let fullRect = CGRect(origin: .zero, size: CGSize(width: screen.frame.width, height: 24))
        #expect(MenuBarShapePathBuilder.notchShapePath(in: fullRect, info: info, isInset: true, screen: screen, margins: .init(left: 0, right: 0, notch: 4), insetAmount: nil).isEmpty)
        let path = MenuBarShapePathBuilder.notchShapePath(in: fullRect, info: info, isInset: true, screen: screen, margins: .init(left: 0, right: 0, notch: 4), insetAmount: 2)
        #expect(!path.isEmpty)
        if let topLeft = screen.auxiliaryTopLeftArea, screen.hasNotch {
            // The notch itself is left uncovered between the two pills.
            let notchMidX = topLeft.maxX - screen.frame.minX + 20
            #expect(!path.contains(CGPoint(x: notchMidX, y: 12)))
        } else {
            #expect(path.contains(CGPoint(x: fullRect.midX, y: 12)), "without a notch it is one full shape")
        }
    }

    @Test("A split shape draws nothing, one pill or both depending on what is known")
    func splitShape() throws {
        let screen = try screen()
        let info = MenuBarSplitShapeInfo(leading: square, trailing: square)
        let leading = CGRect(x: 0, y: 0, width: 200, height: 24)
        let trailing = CGRect(x: 600, y: 0, width: 200, height: 24)
        func split(_ leading: CGRect, _ trailing: CGRect) -> NSBezierPath {
            MenuBarShapePathBuilder.splitShapePath(leadingPathBounds: leading, trailingPathBounds: trailing, info: info, in: rect, leftMargin: 0, rightMargin: 0, screen: screen)
        }
        #expect(split(.zero, .zero).isEmpty)
        #expect(split(leading, .zero).bounds.maxX == 200)
        #expect(split(.zero, trailing).bounds.minX == 600)

        let pair = split(leading, trailing)
        #expect(pair.contains(CGPoint(x: 100, y: 12)))
        #expect(pair.contains(CGPoint(x: 700, y: 12)))
        #expect(!pair.contains(CGPoint(x: 400, y: 12)), "the middle of the bar stays clear")

        let merged = split(leading, CGRect(x: 150, y: 0, width: 650, height: 24))
        #expect(merged.contains(CGPoint(x: 400, y: 12)), "overlapping pills merge into one shape")
    }
}
