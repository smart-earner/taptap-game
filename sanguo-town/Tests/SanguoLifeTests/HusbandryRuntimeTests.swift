import XCTest
@testable import SanguoLife

final class HusbandryRuntimeTests: XCTestCase {
    func make(enabled: Bool = true) throws -> LifeRuntime {
        var e = try LifeRuntime(catalog: .bundled(), wallUTC: 0)
        if enabled { try e.authorizeHusbandry() }
        return e
    }
    /// Deliberate test fixture: prebuilt facilities, no grants in normal gameplay.
    func fixture(pigStage: LifePigStage, completed: Int = 0) throws -> LifeRuntime {
        var e = try make()
        e.world.time = 240; e.world.nextPlan = 270
        e.world.growthEnabled = false
        e.world.fields = [:]; e.world.projects = [:]; e.world.reservedCash = 0
        e.world.tasks = [:]
        for id in e.world.agents.keys { e.world.agents[id]!.taskID = nil }
        for id in e.world.lots.keys { e.world.lots[id]!.reserved = 0 }
        for id in e.world.storages.keys { e.world.storages[id]!.incoming = 0 }
        e.world.buildings["pasture"] = 1; e.world.buildings["butcher"] = 1
        var p = LifePig(id: "pig-fixture", purchasedAt: 0, rules: e.world.husbandry!.rules)
        p.node = "pasture"; p.stage = pigStage; p.due = nil
        p.completedSegments = completed; p.fedSegments = completed
        e.world.husbandry!.animals[p.id] = p
        e.world.husbandry!.herdTarget = 1
        e.world.husbandry!.purchasedCount = 1
        e.world.husbandry!.periodSpent = 20
        e.world.husbandry!.lifetimePurchaseSpent = 20
        e.world.husbandry!.consumedFeed = Int64(completed) * 250
        XCTAssertTrue(e.world.consume(.grain, quantity: Int64(completed) * 250, at: "warehouse"))
        e.world.treasury -= 20
        try e.world.validate()
        return e
    }
    func testOptInDoesNotGrantAnimalsMeatOrMoney() throws {
        var e = try make(enabled: false)
        let before = e.world
        try e.authorizeHusbandry()
        XCTAssertEqual(e.world.treasury, before.treasury)
        XCTAssertEqual(e.world.amount(.meat), 0)
        XCTAssertEqual(e.world.husbandry?.animals.count, 0)
        XCTAssertEqual(e.world.format, 2)
        XCTAssertEqual(e.world.rules, "life-0.7.2-v2")
    }
    func testInvalidAuthorizationIsAtomic() throws {
        var e = try make(enabled: false)
        let before = e.world
        XCTAssertThrowsError(try e.authorizeHusbandry(herdTarget: 9))
        XCTAssertEqual(e.world, before)
    }
    func testBundledRulesMatchVersionedDefaults() throws {
        XCTAssertEqual(try LifeHusbandryRules.bundled(), LifeHusbandryRules())
    }
    func testCareReservesThenConsumesAtWorkSiteOnly() throws {
        var e = try fixture(pigStage: .waitingForCare)
        try e.pauseHusbandry(true)
        e.world.add(.grain, quantity: 250, at: "pasture-in", origin: "fixture")
        e.world.initial["grain", default: 0] += 250
        let before = e.world.consumed["grain", default: 0]
        e.planHusbandry()
        let task = try XCTUnwrap(e.world.tasks.values.first { $0.kind == "pig_care" })
        XCTAssertEqual(task.current.kind, "walk")
        XCTAssertEqual(e.world.consumed["grain", default: 0], before)
        XCTAssertEqual(e.world.husbandry?.animals["pig-fixture"]?.fedSegments, 0)
        try e.advance(to: task.due)
        XCTAssertEqual(e.world.consumed["grain", default: 0], before + 250)
        XCTAssertEqual(e.world.husbandry?.animals["pig-fixture"]?.fedSegments, 1)
        try e.world.validate()
    }
    func testShortagePausesCareWithoutKillingPig() throws {
        var e = try fixture(pigStage: .waitingForCare)
        for loc in e.world.storages.keys {
            let q = e.world.amount(.grain, at: loc, free: true)
            if q > 0 { XCTAssertTrue(e.world.consume(.grain, quantity: q, at: loc)) }
        }
        e.planHusbandry()
        XCTAssertEqual(e.world.husbandry?.animals["pig-fixture"]?.stage, .waitingForCare)
        XCTAssertFalse(e.world.tasks.values.contains { $0.kind == "pig_care" })
        XCTAssertEqual(e.world.husbandry?.purchasedCount, 1)
        try e.world.validate()
    }
    func testImmaturePigCannotBecomeMeat() throws {
        var e = try fixture(pigStage: .waitingForCare, completed: 5)
        e.planHusbandry()
        XCTAssertFalse(e.world.tasks.values.contains { $0.kind == "pig_process" })
        XCTAssertEqual(e.world.produced["meat", default: 0], 0)
    }
    func testReadyPigNeedsOutputCapacity() throws {
        var e = try fixture(pigStage: .ready, completed: 6)
        e.world.storages["meat-out"]!.capacity = 0
        e.planHusbandry()
        XCTAssertEqual(e.world.husbandry?.animals["pig-fixture"]?.stage, .ready)
        XCTAssertFalse(e.world.tasks.values.contains { $0.kind == "pig_process" })
        try e.world.validate()
    }
    func testRealLeadingThenOneMeatConversion() throws {
        var e = try fixture(pigStage: .ready, completed: 6)
        e.planHusbandry()
        let task = try XCTUnwrap(e.world.tasks.values.first { $0.kind == "pig_process" })
        XCTAssertTrue(task.steps.contains { $0.kind == "lead" && $0.destination == "butcher" })
        let finish = task.started + task.steps.reduce(Int64(0)) { $0 + $1.seconds }
        try e.advance(to: finish)
        XCTAssertNil(e.world.husbandry?.animals["pig-fixture"])
        XCTAssertEqual(e.world.husbandry?.processedCount, 1)
        XCTAssertEqual(e.world.produced["meat"], 8000)
        let before = e.world
        try e.advance(to: finish)
        XCTAssertEqual(before, e.world)
        try e.world.validate()
    }
    func testPausedPlanStillFinishesCommittedCare() throws {
        var e = try fixture(pigStage: .waitingForCare)
        e.world.add(.grain, quantity: 250, at: "pasture-in", origin: "fixture")
        e.world.initial["grain", default: 0] += 250
        e.planHusbandry()
        let task = try XCTUnwrap(e.world.tasks.values.first { $0.kind == "pig_care" })
        try e.pauseHusbandry(true)
        let finish = task.started + task.steps.reduce(Int64(0)) { $0 + $1.seconds }
        try e.advance(to: finish)
        XCTAssertEqual(e.world.husbandry?.animals["pig-fixture"]?.stage, .growing)
        XCTAssertEqual(e.world.husbandry?.animals["pig-fixture"]?.due, finish + 2880)
    }
    func testPauseResumeDoesNotRefreshPurchaseBudget() throws {
        var e = try fixture(pigStage: .waitingForCare)
        try e.pauseHusbandry(true)
        let money = e.world.treasury
        try e.authorizeHusbandry(herdTarget: 1, purchaseLimit: 20)
        XCTAssertEqual(e.world.husbandry?.periodSpent, 20)
        XCTAssertEqual(e.world.husbandry?.purchaseRemaining, 0)
        XCTAssertEqual(e.world.treasury, money)
    }
    func testNoNewPurchasesUnderBasicOnlyPolicy() throws {
        var e = try fixture(pigStage: .waitingForCare)
        try e.setPolicy("military")
        XCTAssertFalse(e.wantsMeatProduction)
        XCTAssertFalse(e.prefersHeartyMeal)
        let n = e.world.husbandry!.purchasedCount
        e.planHusbandry()
        XCTAssertEqual(e.world.husbandry?.purchasedCount, n)
    }
    func testNoMeatNeverBlocksBasicMeal() throws {
        var e = try make()
        XCTAssertTrue(e.prefersHeartyMeal)
        try e.advance(to: 7200)
        XCTAssertGreaterThan(e.world.counters["cook_basic_completed", default: 0], 0)
        XCTAssertEqual(e.world.foodCoverage, 10000)
    }
    func testOlderIsolatedLifeSaveLoadsWithoutEnablingFeature() throws {
        let e = try make(enabled: false)
        let data = try LifeSaveStore.encode(e.world)
        let restored = try LifeSaveStore.decode(data)
        XCTAssertEqual(restored.format, 1)
        XCTAssertNil(restored.husbandry)
        XCTAssertEqual(restored, e.world)
    }
    func testNewPayloadDoesNotPretendToBeOldRules() throws {
        var e = try make()
        e.world.format = 1; e.world.rules = "life-0.7.2-v1"
        XCTAssertThrowsError(try e.world.validate())
    }
    func testDuplicateOrUnpaidAnimalRejected() throws {
        var e = try fixture(pigStage: .ready, completed: 6)
        e.world.husbandry!.animals["another"] = e.world.husbandry!.animals["pig-fixture"]
        XCTAssertThrowsError(try e.world.validate())
    }
    func testLoadedInTransitStateHasSameFuture() throws {
        var a = try fixture(pigStage: .ready, completed: 6)
        a.planHusbandry()
        let task = try XCTUnwrap(a.world.tasks.values.first { $0.kind == "pig_process" })
        try a.advance(to: task.due + 1)
        let copy = try LifeSaveStore.decode(LifeSaveStore.encode(a.world))
        var b = try LifeRuntime(catalog: a.catalog, world: copy)
        try a.advance(to: 7200); try b.advance(to: 7200)
        XCTAssertEqual(a.world, b.world)
    }
    func testFullDayPigsMeatCookingAndActualConsumption() throws {
        var e = try make()
        try e.requestSeal()
        try e.advance(to: 86400)
        print("V2_DAY1 pigs=\(e.world.husbandry!.purchasedCount), processed=\(e.world.husbandry!.processedCount), meat=\(e.world.produced["meat", default: 0]), hearty=\(e.world.counters["cook_meat_completed", default: 0]), cash=\(e.world.treasury), coverage=\(e.world.foodCoverage)")
        XCTAssertGreaterThan(e.world.buildings["pasture", default: 0], 0)
        XCTAssertGreaterThan(e.world.buildings["butcher", default: 0], 0)
        XCTAssertGreaterThan(e.world.husbandry?.processedCount ?? 0, 0)
        XCTAssertGreaterThan(e.world.counters["cook_meat_completed", default: 0], 0)
        XCTAssertGreaterThan(e.world.consumed["meat", default: 0], 0)
        XCTAssertGreaterThan(e.world.counters["hearty_meals_consumed", default: 0], 0)
        XCTAssertEqual(e.world.foodCoverage, 10000)
        XCTAssertGreaterThanOrEqual(e.world.treasury - e.world.reservedCash, 100)
        try e.world.validate()
    }
    func testOneDayCadenceAndSaveRestoreAreIdentical() throws {
        var a = try make(), b = try make()
        try a.advance(to: 86400)
        for t in stride(from: Int64(123), to: 86400, by: 123) { try b.advance(to: t) }
        try b.advance(to: 86400)
        XCTAssertEqual(a.world, b.world)
    }
    func testMalformedFeedCountThrowsInsteadOfOverflowing() throws {
        var e = try fixture(pigStage: .ready, completed: 6)
        e.world.husbandry!.animals["pig-fixture"]!.fedSegments = Int.max
        XCTAssertThrowsError(try e.world.validate())
    }
    func testPassiveGrowthContinuesIntoNightWithoutExtraFeed() throws {
        var e = try fixture(pigStage: .waitingForCare)
        e.world.time = 2100; e.world.nextPlan = 2130
        e.world.husbandry!.enabled = false
        e.world.husbandry!.animals["pig-fixture"]!.stage = .growing
        e.world.husbandry!.animals["pig-fixture"]!.fedSegments = 1
        e.world.husbandry!.animals["pig-fixture"]!.due = 2400
        e.world.husbandry!.consumedFeed = 250
        XCTAssertTrue(e.world.consume(.grain, quantity: 250, at: "warehouse"))
        try e.advance(to: 2400)
        XCTAssertTrue(e.world.isNight)
        XCTAssertEqual(e.world.husbandry?.animals["pig-fixture"]?.completedSegments, 1)
        XCTAssertEqual(e.world.husbandry?.animals["pig-fixture"]?.stage, .waitingForCare)
        XCTAssertEqual(e.world.husbandry?.consumedFeed, 250)
        XCTAssertFalse(e.world.tasks.values.contains { $0.kind == "pig_care" })
    }

}
