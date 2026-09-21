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
