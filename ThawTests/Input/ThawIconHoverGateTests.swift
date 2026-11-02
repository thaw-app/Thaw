//
//  ThawIconHoverGateTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Hover on Thaw's icon")
struct ThawIconHoverGateTests {
    private let start = ContinuousClock.now

    private func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start + .milliseconds(milliseconds)
    }

    @Test("Only a shown icon of usable width is a hover target")
    func hoverTarget() {
        #expect(ThawIconHoverGate.isHoverTarget(showsIcon: true, iconWidth: 22))
        #expect(ThawIconHoverGate.isHoverTarget(showsIcon: true, iconWidth: ThawIconHoverGate.minimumIconWidth))
        #expect(!ThawIconHoverGate.isHoverTarget(showsIcon: false, iconWidth: 22))
        #expect(!ThawIconHoverGate.isHoverTarget(showsIcon: true, iconWidth: 2))
        #expect(!ThawIconHoverGate.isHoverTarget(showsIcon: true, iconWidth: 0))
    }

    @Test("A press on the icon holds its hover until the pointer leaves it")
    func pressLatchesUntilPointerLeaves() {
        var gate = ThawIconHoverGate()
        #expect(gate.mayArmFromIcon)

        _ = gate.notePress(onIcon: true, isHoverReveal: false, at: start)
        #expect(!gate.mayArmFromIcon)

        gate.notePointer(onIcon: true)
        #expect(!gate.mayArmFromIcon)

        gate.notePointer(onIcon: false)
        #expect(gate.mayArmFromIcon)
    }

    @Test("A press elsewhere leaves the icon's hover alone")
    func pressElsewhere() {
        var gate = ThawIconHoverGate()
        gate.noteHoverReveal(at: start)
        let elsewhere = gate.notePress(onIcon: false, isHoverReveal: true, at: at(100))
        #expect(!elsewhere)
        #expect(gate.mayArmFromIcon)
        // The reveal is still recent, so a press on the icon that follows still keeps it.
        let onIcon = gate.notePress(onIcon: true, isHoverReveal: true, at: at(200))
        #expect(onIcon)
    }

    @Test("A click right after a hover reveal keeps the section open")
    func clickAdoptsRecentHoverReveal() {
        var gate = ThawIconHoverGate()
        gate.noteHoverReveal(at: start)
        let adopts = gate.notePress(onIcon: true, isHoverReveal: true, at: at(150))
        let keepsOpen = gate.claimClick(at: at(250))
        // One click only: the next one toggles as usual.
        let keepsNextOpen = gate.claimClick(at: at(300))
        #expect(adopts)
        #expect(keepsOpen)
        #expect(!keepsNextOpen)
    }

    @Test("A click long after the hover reveal toggles as usual")
    func lateClickToggles() {
        var gate = ThawIconHoverGate()
        gate.noteHoverReveal(at: start)
        let window = ThawIconHoverGate.clickAdoptionWindow
        let adopts = gate.notePress(onIcon: true, isHoverReveal: true, at: start + window)
        let keepsOpen = gate.claimClick(at: start + window + .milliseconds(50))
        #expect(!adopts)
        #expect(!keepsOpen)
    }

    @Test("A section no longer out by hover is not kept open")
    func revealTakenOverElsewhere() {
        var gate = ThawIconHoverGate()
        gate.noteHoverReveal(at: start)
        // A click or hotkey took the reveal over, or it has closed.
        let adopts = gate.notePress(onIcon: true, isHoverReveal: false, at: at(100))
        let keepsOpen = gate.claimClick(at: at(150))
        #expect(!adopts)
        #expect(!keepsOpen)
    }

    @Test("Each hover reveal keeps open only the first click")
    func secondPressToggles() {
        var gate = ThawIconHoverGate()
        gate.noteHoverReveal(at: start)
        let firstAdopts = gate.notePress(onIcon: true, isHoverReveal: true, at: at(100))
        let firstKeepsOpen = gate.claimClick(at: at(150))
        // The first press used up the reveal, even if the flag were still set.
        let secondAdopts = gate.notePress(onIcon: true, isHoverReveal: true, at: at(400))
        let secondKeepsOpen = gate.claimClick(at: at(450))
        #expect(firstAdopts)
        #expect(firstKeepsOpen)
        #expect(!secondAdopts)
        #expect(!secondKeepsOpen)
    }

    @Test("A kept click that never arrives expires")
    func adoptionExpires() {
        var gate = ThawIconHoverGate()
        gate.noteHoverReveal(at: start)
        let adopts = gate.notePress(onIcon: true, isHoverReveal: true, at: at(100))
        let keepsOpen = gate.claimClick(at: at(100) + ThawIconHoverGate.clickAdoptionWindow)
        #expect(adopts)
        #expect(!keepsOpen)
    }

    @Test("No click is kept before any hover reveal")
    func noRevealNoAdoption() {
        var gate = ThawIconHoverGate()
        let adopts = gate.notePress(onIcon: true, isHoverReveal: true, at: start)
        let keepsOpen = gate.claimClick(at: start)
        #expect(!adopts)
        #expect(!keepsOpen)
    }
}
