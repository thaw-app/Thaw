import AppKit
import Testing
@testable import Thaw

@MainActor
struct PrimaryActivationSequenceTests {
    @Test func reportedRapidActivationsRevealAlwaysHidden() {
        var sequence = ControlItem.PrimaryActivationSequence()
        // Reported sequence: two pairs arrived with clickCount=1 on every activation.
        let times = [41.802, 41.949, 49.969, 50.118]
        let intents = times.map { timestamp in
            ControlItem.menuBarAgentPrimaryActionIntent(
                identifier: .visible,
                modifierFlags: [],
                clickCount: sequence.clickCount(
                    at: timestamp, location: .zero, modifiers: [], interval: 0.5, enabled: true
                ),
                usesDoubleClick: true,
                usesOptionClick: false
            )
        }
        #expect(intents == [.toggleSection, .showAlwaysHidden, .toggleSection, .showAlwaysHidden])
    }

    @Test func completedPairDoesNotTurnThirdActivationIntoAnotherDoubleClick() {
        var sequence = ControlItem.PrimaryActivationSequence()
        let counts = [0.0, 0.15, 0.3].map {
            sequence.clickCount(at: $0, location: .zero, modifiers: [], interval: 0.5, enabled: true)
        }
        #expect(counts == [1, 2, 1])
    }

    @Test func differentLocationOrModifiersStartsANewPair() {
        var sequence = ControlItem.PrimaryActivationSequence()
        #expect(sequence.clickCount(at: 0, location: .zero, modifiers: [], interval: 0.5, enabled: true) == 1)
        #expect(sequence.clickCount(at: 0.1, location: CGPoint(x: 20, y: 0), modifiers: [], interval: 0.5, enabled: true) == 1)
        #expect(sequence.clickCount(at: 0.2, location: CGPoint(x: 20, y: 0), modifiers: .option, interval: 0.5, enabled: true) == 1)
    }

    @Test func disabledShortcutClearsPendingPair() {
        var sequence = ControlItem.PrimaryActivationSequence()
        #expect(sequence.clickCount(at: 0, location: .zero, modifiers: [], interval: 0.5, enabled: true) == 1)
        #expect(sequence.clickCount(at: 0.1, location: .zero, modifiers: [], interval: 0.5, enabled: false) == 1)
        #expect(sequence.clickCount(at: 0.2, location: .zero, modifiers: [], interval: 0.5, enabled: true) == 1)
    }

    @Test func pressTimeOptionSurvivesAReleaseBeforeTheForwardedActivation() {
        // The activation arrives after the mouse-up, so a press-recorded option
        // that is already released must still choose the always-hidden intent.
        let flags = ControlItem.resolvedPrimaryModifierFlags(
            pressModifiers: .option,
            eventModifiers: [],
            liveModifiers: []
        )
        #expect(flags == .option)
        #expect(
            ControlItem.menuBarAgentPrimaryActionIntent(
                identifier: .visible,
                modifierFlags: flags,
                clickCount: 1,
                usesDoubleClick: false,
                usesOptionClick: true
            ) == .toggleAlwaysHidden
        )
    }

    @Test func withoutARecordedPressTheForwardedEventWins() {
        let flags = ControlItem.resolvedPrimaryModifierFlags(
            pressModifiers: nil,
            eventModifiers: .option,
            liveModifiers: []
        )
        #expect(flags == .option)
    }

    @Test func emptyRecordAndEventFallBackToTheLiveState() {
        #expect(
            ControlItem.resolvedPrimaryModifierFlags(
                pressModifiers: [],
                eventModifiers: [],
                liveModifiers: .option
            ) == .option
        )
        #expect(
            ControlItem.resolvedPrimaryModifierFlags(
                pressModifiers: nil,
                eventModifiers: nil,
                liveModifiers: []
            ).isEmpty
        )
    }
}
