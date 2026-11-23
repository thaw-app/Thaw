//
//  RevealRepairScopeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

/// What a repair run while a section is revealed looks at, and when it stays out of the way.
struct RevealRepairScopeTests {
    @Test("A repair may run when nothing asks it to stay out")
    func noSkip() {
        #expect(RevealRepairScope.firstSkip(arrangementIsManual: false, isUserArranging: false) == nil)
    }

    @Test("Manual arrangement and an arranging user each skip, and manual arrangement is named first")
    func skips() {
        #expect(RevealRepairScope.firstSkip(arrangementIsManual: true, isUserArranging: false) == .manualArrangement)
        #expect(RevealRepairScope.firstSkip(arrangementIsManual: false, isUserArranging: true) == .userArranging)
        #expect(RevealRepairScope.firstSkip(arrangementIsManual: true, isUserArranging: true) == .manualArrangement)
    }

    @Test("Revealing Visible or Hidden orders Hidden; revealing Always Hidden orders Hidden and Always Hidden")
    func sectionsToOrder() {
        #expect(RevealRepairScope.sectionsToOrder(revealing: .visible) == [.hidden])
        #expect(RevealRepairScope.sectionsToOrder(revealing: .hidden) == [.hidden])
        #expect(RevealRepairScope.sectionsToOrder(revealing: .alwaysHidden) == [.hidden, .alwaysHidden])
    }

    @Test("A pending edit to the Visible order adds Visible last")
    func pendingVisibleEditAddsVisible() {
        #expect(RevealRepairScope.sectionsToOrder(revealing: .hidden, includeVisible: true) == [.hidden, .visible])
        #expect(
            RevealRepairScope.sectionsToOrder(revealing: .alwaysHidden, includeVisible: true)
                == [.hidden, .alwaysHidden, .visible]
        )
        #expect(RevealRepairScope.sectionsToOrder(revealing: .hidden, includeVisible: false) == [.hidden])
    }

    @Test("A boundary reconcile always includes Visible")
    func sectionsToReconcile() {
        #expect(RevealRepairScope.sectionsToReconcile(revealing: .visible) == [.hidden, .visible])
        #expect(RevealRepairScope.sectionsToReconcile(revealing: .hidden) == [.hidden, .visible])
        #expect(
            RevealRepairScope.sectionsToReconcile(revealing: .alwaysHidden) == [.hidden, .alwaysHidden, .visible]
        )
    }

    /// Counts how often each live read was asked.
    private final class Asked {
        var leavesToMacOS = 0
        var matches = 0
    }

    private func needsApply(
        asked: Asked = Asked(),
        authoredCount: Int,
        leavesToMacOS: Bool = false,
        matches: Bool = false
    ) -> Bool {
        RevealRepairScope.authoredOrderNeedsApply(
            authoredCount: authoredCount,
            leavesOrderToMacOS: {
                asked.leavesToMacOS += 1
                return leavesToMacOS
            },
            liveOrderMatches: {
                asked.matches += 1
                return matches
            }
        )
    }

    @Test("An order of more than one item that the bar does not match needs applying")
    func disagreeingOrderNeedsApply() {
        #expect(needsApply(authoredCount: 2))
    }

    @Test("One item or none has no order to apply")
    func tooFewItems() {
        #expect(!needsApply(authoredCount: 1))
        #expect(!needsApply(authoredCount: 0))
    }

    @Test("A section macOS orders, or one the bar already matches, needs nothing")
    func macOSOrdersOrAlreadyMatches() {
        #expect(!needsApply(authoredCount: 3, leavesToMacOS: true))
        #expect(!needsApply(authoredCount: 3, matches: true))
    }

    @Test("The bar is read only when the cheaper answers did not settle it")
    func readsAreLazy() {
        let few = Asked()
        _ = needsApply(asked: few, authoredCount: 1)
        #expect(few.leavesToMacOS == 0 && few.matches == 0)

        let macOS = Asked()
        _ = needsApply(asked: macOS, authoredCount: 2, leavesToMacOS: true)
        #expect(macOS.leavesToMacOS == 1 && macOS.matches == 0)

        let both = Asked()
        _ = needsApply(asked: both, authoredCount: 2)
        #expect(both.leavesToMacOS == 1 && both.matches == 1)
    }
}
