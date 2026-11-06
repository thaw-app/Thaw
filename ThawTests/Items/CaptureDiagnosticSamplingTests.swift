import Testing
@testable import Thaw

struct CaptureDiagnosticSamplingTests {
    @Test func repeatedItemCannotExhaustOtherItemsBudget() {
        var budget = CaptureDiagnostics.SamplingBudget()
        #expect(budget.reserve(for: "owner-a:item") == 1)
        #expect(budget.reserve(for: "owner-a:item") == 2)
        #expect(budget.reserve(for: "owner-a:item") == 3)
        #expect(budget.reserve(for: "owner-a:item") == nil)
        #expect(budget.reserve(for: "owner-b:item") == 4)
    }

    @Test func changingItemIdentitiesCannotProduceUnlimitedSamples() {
        var budget = CaptureDiagnostics.SamplingBudget()
        for index in 1 ... 96 {
            #expect(budget.reserve(for: "item-\(index)") == index)
        }
        #expect(budget.reserve(for: "another-item") == nil)
        #expect(budget.reserve(for: "item-1") == nil)
    }
}
