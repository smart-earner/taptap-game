import XCTest
@testable import SanguoLife

final class HusbandryRuntimeTests: XCTestCase {
    func make() throws -> LifeRuntime { try .init(catalog: .bundled(), wallUTC: 0) }
    func testOptInDoesNotGrantAnimalsOrResourcesAndIsIdempotent() throws {
        var e = try make()
        let initial = e.world.initial, cash = e.world.treasury
        try e.setHusbandry(enabled: true)
        XCTAssertEqual(e.world.format, 2)
        XCTAssertEqual(e.world.husbandry?.pigs.count, 0)
        XCTAssertEqual(e.world.initial, initial)
        XCTAssertEqual(e.world.treasury, cash)
        let before = e.world
        try e.setHusbandry(enabled: true)
        XCTAssertEqual(before, e.world)
        try e.world.validate()
    }
    func testFormerLifeSaveStillLoadsWithoutOptIn() throws {
        let e = try make()
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(e.world)) as! [String: Any]
        XCTAssertNil(json["husbandry"])
        let decoded = try JSONDecoder().decode(LifeWorld.self, from: JSONSerialization.data(withJSONObject: json))
        let restored = try LifeRuntime(catalog: e.catalog, world: decoded)
        XCTAssertEqual(restored.world.format, 1)
        XCTAssertNil(restored.world.husbandry)
    }
    func testChangedRulesCannotBeMislabelledAsOldSave() throws {
        var e = try make()
        try e.setHusbandry(enabled: true)
        e.world.format = 1
        e.world.rules = "life-0.7.2-v1"
        XCTAssertThrowsError(try e.world.validate())
    }
    func testRealConstructionAnimalsMeatCookingAndConsumption() throws {
        var e = try make()
        try e.setHusbandry(enabled: true)
        try e.advance(to: 172800)
        let h = try XCTUnwrap(e.world.husbandry)
        XCTAssertEqual(e.world.projects["pasture"]?.completed, true)
        XCTAssertEqual(e.world.projects["butcher"]?.completed, true)
        XCTAssertGreaterThan(h.processedTotal, 0)
        XCTAssertEqual(e.world.produced["meat"], h.processedTotal * 8000)
        XCTAssertEqual(h.purchasedTotal - h.processedTotal, Int64(h.pigs.count))
        XCTAssertGreaterThan(e.world.counters["hearty_meals_consumed", default: 0], 0)
        XCTAssertGreaterThan(e.world.consumed["meat", default: 0], 0)
        XCTAssertEqual(e.world.foodCoverage, 10000)
        XCTAssertLessThanOrEqual(h.occupiedPlaces, 2)
        try e.world.validate()
    }
    func testCadenceAndReloadDoNotChangeResult() throws {
        var a = try make(), b = try make()
        try a.setHusbandry(enabled: true)
        try b.setHusbandry(enabled: true)
        try a.advance(to: 86400)
        for t in stride(from: Int64(173), to: 86400, by: 173) {
            try b.advance(to: t)
        }
        let saved = try LifeSaveStore.encode(b.world)
        b = try LifeRuntime(catalog: b.catalog, world: LifeSaveStore.decode(saved))
        try b.advance(to: 86400)
        XCTAssertEqual(a.world, b.world)
        let before = b.world
        try b.advance(to: 86400)
        XCTAssertEqual(before, b.world)
    }
    func testCareReservesFeedBeforeArrivalAndChargesOnlyOnSite() throws {
        var e = try make()
        try e.setHusbandry(enabled: true)
        var observed = false
        for t in stride(from: Int64(30), through: 86400, by: 30) {
            try e.advance(to: t)
            guard let task = e.world.tasks.values.first(where: {
                $0.kind == "pig_care" && $0.current.kind == "walk"
            }) else { continue }
            let pig = try XCTUnwrap(e.world.husbandry?.pigs[task.subject])
            XCTAssertFalse(pig.feedConsumed)
            XCTAssertEqual(task.reservations.reduce(Int64(0)) { $0 + $1.amount }, 250)
            for part in task.reservations {
                XCTAssertEqual(e.world.lots[part.lotID]?.location, "pasture-feed")
            }
            let copy = try LifeSaveStore.decode(LifeSaveStore.encode(e.world))
            var resumed = try LifeRuntime(catalog: e.catalog, world: copy)
            try e.advance(to: t + 200)
            try resumed.advance(to: t + 200)
            XCTAssertEqual(e.world, resumed.world)
            observed = true
            break
        }
        XCTAssertTrue(observed)
    }
    func testOutputFullDoesNotConsumeReadyPigOrProduceGhostMeat() throws {
        var e = try make()
        try e.setHusbandry(enabled: true)
        e.world.storages["butcher-out"]!.capacity = 0
        try e.advance(to: 86400)
        XCTAssertEqual(e.world.husbandry?.processedTotal, 0)
        XCTAssertEqual(e.world.produced["meat", default: 0], 0)
        XCTAssertTrue(e.world.husbandry!.pigs.values.contains { $0.phase == .ready })
        XCTAssertFalse(e.world.tasks.values.contains { $0.kind == "pig_process" })
        try e.world.validate()
    }
    func testNoMarketNoFreeLivestock() throws {
        var e = try make()
        try e.setHusbandry(enabled: true)
        e.world.growthEnabled = false
        try e.advance(to: 28800)
        XCTAssertEqual(e.world.husbandry?.purchasedTotal, 0)
        XCTAssertEqual(e.world.amount(.meat), 0)
    }
    func testPauseAndResumeDoesNotRefreshBudgetOrLoseAnimals() throws {
        var e = try make()
        try e.setHusbandry(enabled: true)
        try e.advance(to: 86400)
        let before = e.world.husbandry!
        try e.setHusbandry(enabled: false)
        try e.setHusbandry(enabled: true)
        XCTAssertEqual(e.world.husbandry?.purchaseSpent, before.purchaseSpent)
        XCTAssertEqual(e.world.husbandry?.pigs, before.pigs)
        try e.setHusbandry(enabled: false)
        let purchased = e.world.husbandry!.purchasedTotal
        try e.advance(to: 172800)
        XCTAssertEqual(e.world.husbandry?.purchasedTotal, purchased)
        try e.world.validate()
    }
    func testFoodFloorPreventsDiscretionaryFeedAndPurchase() throws {
        var e = try make()
        try e.setHusbandry(enabled: true)
        try e.advance(to: 43200)
        e.world.foodCoverage = 0
        let h = e.world.husbandry!, used = e.world.consumed["grain", default: 0]
        XCTAssertFalse(e.canSparePigFeed(250))
        e.planHusbandry()
        XCTAssertEqual(e.world.husbandry?.purchasedTotal, h.purchasedTotal)
        XCTAssertEqual(e.world.consumed["grain", default: 0], used)
        try e.world.validate()
    }
    func testAnimalAndResourceLedgerRejectsCorruption() throws {
        var e = try make()
        try e.setHusbandry(enabled: true)
        e.world.husbandry!.purchasedTotal = 1
        XCTAssertThrowsError(try e.world.validate())
        e.world.husbandry!.purchasedTotal = 0
        e.world.husbandry!.purchaseSpent = 41
        XCTAssertThrowsError(try e.world.validate())
    }
    func testSaveFailureDoesNotPublishActivation() async throws {
        struct Failing: LifePersistence {func save(_ world: LifeWorld) throws {throw LifeError.invalid("test disk error")}}
        let e = try make(), session = LifeSession(engine: e, store: Failing())
        do { try await session.send(.husbandry(true)); XCTFail("Should fail") } catch {}
        let world = await session.snapshot()
        XCTAssertEqual(world, e.world)
    }
}
