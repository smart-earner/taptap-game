import XCTest
@testable import SanguoLife
final class LifeTests: XCTestCase {
    func testCatalog() throws {let c=try LifeCatalog.bundled();XCTAssertEqual(c.heroes.count,30);XCTAssertEqual(c.skills.count,22);XCTAssertEqual(LifeResource.allCases.count,8)}
    func testCookingRate() throws {let c=try LifeCatalog.bundled();let w=LifeHero(id:"ordinary",name:"厨师",starting:false,attributes:["administration":50,"strategy":50,"valor":50,"command":50],skill_ids:[]);let result=try LifeAbilities.workRate(c,worker:.init(w,role:"worker",eligible:true),job:"cook",leaders:[.init(c.hero("xunyu")!,role:"prefect",eligible:true)]);XCTAssertEqual(result,11410)}
}
extension LifeTests {
    func make() throws -> LifeRuntime {try .init(catalog:.bundled(),wallUTC:0)}
    func testSeedHasSixteenRealResidentsAndExactAssets() throws {let e=try make();XCTAssertEqual(e.world.agents.count,16);XCTAssertEqual(e.world.amount(.grain),64000);XCTAssertEqual(e.world.amount(.meal),32000);XCTAssertEqual(e.world.owned,["xunyu"]);try e.world.validate()}
    func testFirstHarvestAndFirstMeal() throws {var e=try make();try e.advance(to:900);XCTAssertGreaterThan(e.world.counters["harvests",default:0],0);XCTAssertEqual(e.world.counters["resident_meals_consumed"],16);XCTAssertTrue(e.world.discovered.contains("zhaoyun"));try e.world.validate()}
    func testFullFoodChain() throws {var e=try make();try e.advance(to:7200);XCTAssertGreaterThan(e.world.produced["grain",default:0],0);XCTAssertGreaterThan(e.world.produced["meal",default:0],0);XCTAssertGreaterThan(e.world.counters["deliveries",default:0],0);XCTAssertEqual(e.world.foodCoverage,10000);try e.world.validate()}
    func testCadenceDoesNotChangeEconomy() throws {var a=try make(),b=try make();try a.advance(to:7200);for t in stride(from:Int64(17),to:7200,by:17){try b.advance(to:t)};try b.advance(to:7200);XCTAssertEqual(a.world,b.world)}
    func testSerializationInTransit() throws {var a=try make();try a.advance(to:333);let data=try JSONEncoder().encode(a.world);var b=try LifeRuntime(catalog:a.catalog,world:JSONDecoder().decode(LifeWorld.self,from:data));try a.advance(to:7200);try b.advance(to:7200);XCTAssertEqual(a.world,b.world)}
    func testSealIsActualUniqueWork() throws {var e=try make();try e.requestSeal();XCTAssertThrowsError(try e.requestSeal());try e.advance(to:3600);XCTAssertTrue(e.world.owned.contains("founders_seal"));XCTAssertEqual(e.world.owned.filter{$0=="founders_seal"}.count,1);XCTAssertThrowsError(try e.requestSeal())}
    func testRewindRejectedWithoutMutation() throws {var e=try make();try e.advance(to:333);let before=e.world;XCTAssertThrowsError(try e.advance(to:332));XCTAssertEqual(before,e.world)}
    func testNoDoubleSettlementSameTime() throws {var e=try make();try e.advance(to:2880);let before=e.world;try e.advance(to:2880);XCTAssertEqual(before,e.world)}
    func testNightReturnsHomeAndNightGuardHasRealTask() throws {var e=try make();try e.advance(to:2400);XCTAssertTrue(e.world.isNight);XCTAssertTrue(e.world.agents.values.filter{$0.job != "guard_night"}.allSatisfy{$0.node=="home" || $0.taskID != nil});XCTAssertNotNil(e.world.agents["r14"]?.taskID)}
}
extension LifeTests {
    func testReservedInputsAreNotConsumedBeforeWorkerArrives() throws {
        var e=try make();try e.advance(to:240)
        var w=e.world
        w.tasks=[:];for id in w.agents.keys {w.agents[id]!.taskID=nil}
        for id in w.lots.keys {w.lots[id]!.reserved=0}
        for id in w.storages.keys {w.storages[id]!.incoming=0}
        w.fields=[:];w.projects=[:];w.reservedCash=0
        for id in w.lots.keys where w.lots[id]!.resource == .meal {w.consumed["meal",default:0]+=w.lots[id]!.amount;w.lots[id]=nil}
        e.world=w
        let before=e.world.consumed["grain",default:0]
        e.planStations(finishingOnly:false)
        let task=try XCTUnwrap(e.world.tasks.values.first{$0.kind=="prepare"})
        XCTAssertEqual(task.current.kind,"walk")
        XCTAssertEqual(e.world.consumed["grain",default:0],before)
        XCTAssertGreaterThan(task.reservations.count,0)
        try e.advance(to:task.due)
        XCTAssertEqual(e.world.consumed["grain",default:0],before+4000)
    }
    func testLotsRemainInTransitUntilUnload() throws {
        var e=try make();try e.advance(to:300)
        var seenCarry=false
        for _ in 0..<700 {
            try e.advance(to:e.world.time+1)
            for t in e.world.tasks.values where t.kind=="haul" && ["carry","unload"].contains(t.current.kind) {
                XCTAssertEqual(e.world.amount(t.resource!,at:t.id),t.quantity)
                XCTAssertGreaterThanOrEqual(e.world.storages[t.target]!.incoming,t.space)
                seenCarry=true
            }
            try e.world.validate()
        }
        XCTAssertTrue(seenCarry)
    }
    func testInputAndOutputCapacityBackpressure() throws {
        var e=try make();e.world.storages["kitchen-out"]!.capacity=0
        try e.advance(to:1800)
        XCTAssertEqual(e.world.produced["meal",default:0],0)
        try e.world.validate()
    }
    func testCorruptSaveRejectedWithoutOverwrite() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:dir)}
        let store=LifeSaveStore(url:dir.appendingPathComponent("world.json")),e=try make()
        try store.save(e.world)
        let bad=Data("broken".utf8);try bad.write(to:store.url)
        XCTAssertThrowsError(try store.load());XCTAssertThrowsError(try store.save(e.world))
        XCTAssertEqual(try Data(contentsOf:store.url),bad)
    }
    func testFutureSaveVersionRejected() throws {
        var w=try make().world;w.format=999
        XCTAssertThrowsError(try LifeSaveStore.encode(w))
    }
    func testChecksumRoundtripAndBackup() throws {
        var e=try make();let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:dir)}
        let store=LifeSaveStore(url:dir.appendingPathComponent("world.json"))
        try store.save(e.world);let first=try Data(contentsOf:store.url)
        try e.advance(to:900);try store.save(e.world)
        XCTAssertEqual(try store.load(),e.world);XCTAssertEqual(try Data(contentsOf:store.url.appendingPathExtension("bak1")),first)
    }
    func testHeroNamesDoNotAffectRates() throws {
        let c=try LifeCatalog.bundled();var h=c.hero("liang")!
        let before=try LifeAbilities.workRate(c,worker:.init(h,role:"worker",eligible:true),job:"restorer")
        h.id="custom-hero";h.name="另一个名字"
        let after=try LifeAbilities.workRate(c,worker:.init(h,role:"worker",eligible:true),job:"restorer")
        XCTAssertEqual(before,after)
    }
    func testRecruitmentUsesActualAssetsAndOneResident() throws {
        var e=try make();try e.advance(to:900);try e.requestRecruit("zhaoyun")
        try e.advance(to:28800)
        XCTAssertEqual(e.world.owned.filter{$0=="zhaoyun"}.count,1)
        XCTAssertEqual(e.world.agents.values.filter{$0.heroID=="zhaoyun"}.count,1)
        XCTAssertEqual(e.world.recruits["zhaoyun"]?.spent,130)
        XCTAssertThrowsError(try e.requestRecruit("zhaoyun"));try e.world.validate()
    }
    func testSameRecruitRequestDoesNotDuplicateStage() throws {
        var e=try make();try e.advance(to:900);try e.requestRecruit("zhaoyun");try e.requestRecruit("zhaoyun")
        try e.advance(to:1200)
        XCTAssertLessThanOrEqual(e.world.tasks.values.filter{$0.kind=="recruit_prepare"}.count,1)
    }
    func testOneDaySuppliesAndRealTrade() throws {
        var e=try make();try e.requestSeal();try e.advance(to:86400)
        XCTAssertEqual(e.world.foodCoverage,10000)
        XCTAssertGreaterThan(e.world.counters["external_transactions",default:0],0)
        XCTAssertGreaterThan(e.world.buildings["workshop",default:0],0)
        XCTAssertTrue(e.world.owned.contains("founders_seal"));try e.world.validate()
    }
}
