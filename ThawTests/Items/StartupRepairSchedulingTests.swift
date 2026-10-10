import Testing
@testable import Thaw

@MainActor
struct StartupRepairSchedulingTests {
    @Test func startupRestrictionChangesDoNotQueueRepairs() {
        let manager = MenuBarItemManager()
        manager.isInStartupSettling = true
        defer { manager.postRestrictionRepairTask?.cancel() }

        manager.noteRestrictionChange()
        manager.noteRestrictionChange()

        #expect(manager.postRestrictionRepairTask == nil)
    }

    @Test func startupNormalizationDoesNotQueueARewrite() {
        let manager = MenuBarItemManager()
        manager.isInStartupSettling = true
        defer { manager.structuralNormalizationTask?.cancel() }

        manager.scheduleStructuralNormalization(cause: .settled)

        #expect(manager.structuralNormalizationTask == nil)
    }

    @Test func settledStartupCanScheduleRepairsAgain() {
        let manager = MenuBarItemManager()
        manager.isInStartupSettling = true
        manager.noteRestrictionChange()
        manager.isInStartupSettling = false
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
