import Testing
@testable import Thaw

@MainActor
struct StartupRepairSchedulingTests {
    @Test func startupRestrictionChangesDoNotQueueRepairs() {
        let manager = MenuBarItemManager()
        manager.barSettling.holdForTesting()
        defer {
            manager.barSettling.releaseForTesting()
            manager.postRestrictionRepairTask?.cancel()
        }

        manager.noteRestrictionChange()
        manager.noteRestrictionChange()

        #expect(manager.postRestrictionRepairTask == nil)
    }

    @Test func startupNormalizationDoesNotQueueARewrite() {
        let manager = MenuBarItemManager()
        manager.barSettling.holdForTesting()
        defer {
            manager.barSettling.releaseForTesting()
            manager.structuralNormalizationTask?.cancel()
        }

        manager.scheduleStructuralNormalization(cause: .settled)

        #expect(manager.structuralNormalizationTask == nil)
    }

    @Test func settledStartupCanScheduleRepairsAgain() {
        let manager = MenuBarItemManager()
        manager.barSettling.holdForTesting()
        manager.noteRestrictionChange()
        manager.barSettling.releaseForTesting()
        defer {
            manager.postRestrictionRepairTask?.cancel()
            manager.structuralNormalizationTask?.cancel()
        }

        manager.noteRestrictionChange()
        manager.scheduleStructuralNormalization(cause: .settled)

        #expect(manager.postRestrictionRepairTask != nil)
        #expect(manager.structuralNormalizationTask != nil)
    }
}
