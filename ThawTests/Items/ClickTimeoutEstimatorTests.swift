//
//  ClickTimeoutEstimatorTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("Each item's click timeout is learned from how long its clicks took")
struct ClickTimeoutEstimatorTests {
    @Test("An item with no clicks on record gets the default")
    func unknownItemGetsTheDefault() {
        let estimator = ClickTimeoutEstimator<String>()

        #expect(estimator.timeout(for: "a") == .milliseconds(350))
        #expect(ClickTimeoutEstimator<String>.defaultTimeout == .milliseconds(350))
    }

    @Test("The first observation moves the estimate halfway from the default")
    func firstObservationBlendsWithTheDefault() {
        var estimator = ClickTimeoutEstimator<String>()

        let estimate = estimator.record(.milliseconds(550), for: "a")

        #expect(estimate == .milliseconds(450))
        #expect(estimator.timeout(for: "a") == .milliseconds(450))
    }

    @Test("Each later observation moves the estimate halfway again")
    func laterObservationsBlendWithTheEstimate() {
        var estimator = ClickTimeoutEstimator<String>()
        estimator.record(.milliseconds(550), for: "a")

        let estimate = estimator.record(.milliseconds(650), for: "a")

        #expect(estimate == .milliseconds(550))
    }

    @Test("A fast click cannot take the estimate below the floor")
    func clampsToTheFloor() {
        var estimator = ClickTimeoutEstimator<String>()

        let estimate = estimator.record(.milliseconds(10), for: "a")

        #expect(estimate == .milliseconds(200))
        #expect(estimator.timeout(for: "a") == .milliseconds(200))
    }

    @Test("A slow click cannot take the estimate above the ceiling")
    func clampsToTheCeiling() {
        var estimator = ClickTimeoutEstimator<String>()

        let estimate = estimator.record(.seconds(30), for: "a")

        #expect(estimate == .milliseconds(1000))
        #expect(estimator.timeout(for: "a") == .milliseconds(1000))
    }

    @Test("The next blend starts from the clamped estimate, not the raw observation")
    func blendsFromTheClampedEstimate() {
        var estimator = ClickTimeoutEstimator<String>()
        estimator.record(.seconds(30), for: "a")

        let estimate = estimator.record(.milliseconds(400), for: "a")

        #expect(estimate == .milliseconds(700))
    }

    @Test("Items learn separately")
    func itemsLearnSeparately() {
        var estimator = ClickTimeoutEstimator<String>()

        estimator.record(.milliseconds(950), for: "slow")

        #expect(estimator.timeout(for: "slow") == .milliseconds(650))
        #expect(estimator.timeout(for: "other") == .milliseconds(350))
    }

    @Test("Pruning forgets items that left and keeps the rest")
    func pruneForgetsDepartedItems() {
        var estimator = ClickTimeoutEstimator<String>()
        estimator.record(.milliseconds(950), for: "gone")
        estimator.record(.milliseconds(950), for: "here")

        estimator.prune(keeping: ["here"])

        #expect(estimator.timeout(for: "gone") == .milliseconds(350))
        #expect(estimator.timeout(for: "here") == .milliseconds(650))
    }
}
