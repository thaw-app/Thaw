import Testing
@testable import Thaw

@MainActor
struct SpacingReapplyTests {
    @Test func automaticRefreshDoesNotRelaunchMatchingApps() {
        #expect(MenuBarItemSpacingManager.shouldSkipRelaunch(valuesMatch: true, forceRelaunch: false))
    }

    @Test func explicitReapplyReloadsAnAlreadySavedValue() {
        #expect(!MenuBarItemSpacingManager.shouldSkipRelaunch(valuesMatch: true, forceRelaunch: true))
    }

    @Test(arguments: [false, true])
    func changedValuesStillApply(force: Bool) {
        #expect(!MenuBarItemSpacingManager.shouldSkipRelaunch(valuesMatch: false, forceRelaunch: force))
    }
}
