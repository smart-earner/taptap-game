import XCTest
@testable import SanguoLife

final class HusbandryModelTests: XCTestCase {
    func testExactlyEightResourcesRemain() {
        XCTAssertEqual(LifeResource.allCases.count, 8)
        XCTAssertNil(LifeResource(rawValue: "water"))
        XCTAssertNil(LifeResource(rawValue: "fodder"))
    }
    func testRuleCostsMatchSlimDesign() throws {
        let r = LifeHusbandryRules()
        try r.validate()
        XCTAssertEqual(Int64(r.growthSegments) * r.segmentSeconds, 17280)
        XCTAssertEqual(Int64(r.growthSegments) * r.feedPerSegment, 1500)
        XCTAssertEqual(r.meatPerAnimal, 8000)
        XCTAssertEqual(r.pastureCash + r.butcherCash, 100)
    }
    func testPurchasedPigIsNotMeatOrReady() {
        let p = LifePig(id: "pig-1", purchasedAt: 90, rules: .init())
        XCTAssertEqual(p.stage, .inTransit)
        XCTAssertEqual(p.due, 390)
        XCTAssertEqual(p.completedSegments, 0)
        XCTAssertEqual(p.paidCash, 20)
    }
    func testAuthorizationUsesFixedFiscalWindow() throws {
        let h = try LifeHusbandry(at: 21630)
        XCTAssertEqual(h.period, 1)
        XCTAssertEqual(h.purchaseRemaining, 40)
        XCTAssertEqual(h.herdTarget, 2)
        XCTAssertEqual(h.animals.count, 0)
    }
    func testSpentBudgetDoesNotGoNegativeOrRefreshOnPause() throws {
        var h = try LifeHusbandry(at: 0)
        h.periodSpent = 40
        h.enabled = false
        h.enabled = true
        XCTAssertEqual(h.purchaseRemaining, 0)
        h.purchaseLimit = 20
        XCTAssertEqual(h.purchaseRemaining, 0)
    }
    func testInvalidConfigurationRejected() throws {
        var r = LifeHusbandryRules()
        r.pastureMaterials["fodder"] = 1
        XCTAssertThrowsError(try r.validate())
        r = .init(); r.segmentSeconds = 0
        XCTAssertThrowsError(try r.validate())
        XCTAssertThrowsError(try LifeHusbandry(at: 0, herdTarget: 9))
        XCTAssertThrowsError(try LifeHusbandry(at: 0, purchaseLimit: 0))
    }
    func testStateRoundTripRetainsIdentityFeedAndProgress() throws {
        var h = try LifeHusbandry(at: 0)
        var p = LifePig(id: "pig-7", purchasedAt: 0, rules: h.rules)
        p.stage = .growing; p.completedSegments = 2; p.fedSegments = 3
        p.due = 12345
        h.animals[p.id] = p
        let copy = try JSONDecoder().decode(LifeHusbandry.self, from: JSONEncoder().encode(h))
        XCTAssertEqual(copy, h)
        XCTAssertEqual(copy.feedPaid, 750)
        XCTAssertEqual(copy.meatProduced, 0)
    }
    func testMeatCountUsesConsumedAnimalsOnly() throws {
        var h = try LifeHusbandry(at: 0)
        h.animals["pig-1"] = LifePig(id: "pig-1", purchasedAt: 0, rules: h.rules)
        h.processedCount = 2
        XCTAssertEqual(h.meatProduced, 16000)
        XCTAssertEqual(h.animals.count, 1)
    }
}
