import XCTest
@testable import SanguoLife

final class FoodStatusTests: XCTestCase {
    func make() throws -> LifeRuntime { try LifeRuntime(catalog: .bundled(), wallUTC: 0) }
    func testPolicyTargetsAreSharedWithPlanner() throws {
        var e = try make()
        for (policy, expected) in [("supply",5000),("trade",2500),("industry",0),("military",0),("balanced",2500)] {
            try e.setPolicy(policy)
            XCTAssertEqual(e.heartyTargetBP, expected)
            XCTAssertEqual(LifeFoodStatus(world: e.world).heartyTargetBP, expected)
        }
    }
    func testReadingStatusNeverEnablesFeatureOrMutatesWorld() throws {
        let e = try make(), before = e.world
        let status = LifeFoodStatus(world: e.world)
        XCTAssertFalse(status.enabled)
        XCTAssertEqual(status.pigsInCity, 0)
        XCTAssertEqual(e.world, before)
    }
    func testInitialFoodIsStockNotMealsAlreadyEaten() throws {
        let status = LifeFoodStatus(world: try make().world)
        XCTAssertEqual(status.basicMealsAvailable, 32000)
        XCTAssertEqual(status.heartyMealsAvailable, 0)
        XCTAssertEqual(status.mealsConsumed, 0)
    }
    func testQualitySummaryPreservesCargoAndStockWithoutDoubleCounting() throws {
        var e = try make()
        e.world.add(.meal, quantity: 16000, at: "kitchen-out", quality: "hearty", origin: "fixture")
        let s = LifeFoodStatus(world: e.world)
        XCTAssertEqual(s.basicMealsAvailable + s.heartyMealsAvailable, e.world.amount(.meal))
        XCTAssertEqual(s.heartyMealsAvailable, 16000)
        XCTAssertEqual(s.heartyMealsConsumed, 0)
    }
    func testPausePreservesSpendingEvidence() throws {
        var e = try make()
        try e.authorizeHusbandry()
        try e.pauseHusbandry(true)
        let s = LifeFoodStatus(world: e.world)
        XCTAssertFalse(s.enabled)
        XCTAssertEqual(s.herdTarget, 2)
        XCTAssertEqual(s.purchaseLimit, 40)
        XCTAssertEqual(s.nextPurchasePeriod, 21600)
    }
    func testStableCodableSummary() throws {
        let s = LifeFoodStatus(world: try make().world)
        XCTAssertEqual(try JSONDecoder().decode(LifeFoodStatus.self, from: JSONEncoder().encode(s)), s)
    }
    func testSummaryReportsActualResidentConsumption() throws {
        var e = try make()
        try e.advance(to: 900)
        let s = LifeFoodStatus(world: e.world)
        XCTAssertGreaterThan(s.mealsConsumed, 0)
        XCTAssertEqual(s.mealsConsumed, e.world.counters["resident_meals_consumed"])
        XCTAssertEqual(s.heartyMealsConsumed, 0)
    }
}
