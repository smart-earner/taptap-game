import XCTest
@testable import SanguoLife

final class HeroPreviewTests:XCTestCase {
    func make() throws -> LifeRuntime {try .init(catalog:.bundled(),wallUTC:0,heroPreview:true)}
    func testBootstrap() throws {
        let e=try make()
        XCTAssertEqual(e.world.agents.count,5);XCTAssertEqual(e.world.housing,5)
        XCTAssertEqual(e.world.treasury,400);XCTAssertEqual(e.world.amount(.meal),10000)
        XCTAssertEqual(e.world.amount(.grain),24000)
        XCTAssertTrue(e.world.agents.values.allSatisfy{$0.id==$0.heroID})
        XCTAssertEqual(e.catalog.recipe("cook_basic")?.input_mU,["grain":1000,"wood":250])
    }
    func testRealFoodChainAndFiveUniqueHeroes() throws {
        var e=try make();try e.advance(to:7200)
        XCTAssertEqual(e.world.agents.count,5)
        XCTAssertGreaterThan(e.world.produced["meal",default:0],0)
        XCTAssertGreaterThan(e.world.produced["grain",default:0],0)
        XCTAssertGreaterThan(e.world.counters["deliveries",default:0],0)
        XCTAssertGreaterThan(e.world.counters["resident_meals_consumed",default:0],0)
        XCTAssertTrue(e.world.projects["repair"]?.completed==true)
        try e.world.validate()
    }
    func testSaveAndCadence() throws {
        var a=try make();try a.advance(to:333)
        var b=try LifeRuntime(catalog:.bundled(),world:LifeSaveStore.decode(LifeSaveStore.encode(a.world)))
        try a.advance(to:3600)
        for t in stride(from:Int64(350),to:3600,by:17){try b.advance(to:t)}
        try b.advance(to:3600);XCTAssertEqual(a.world,b.world)
    }
    func testUnsupportedFeaturesDoNotChangeWorld() throws {
        var e=try make();let before=e.world
        XCTAssertThrowsError(try e.requestRecruit("caocao"));XCTAssertThrowsError(try e.setHusbandry(enabled:true))
        XCTAssertEqual(e.world,before)
    }
    func testPreferenceDoesNotCancelTask() throws {
        var e=try make();let tasks=e.world.tasks
        try e.setHeroPreference("liubei","builder")
        XCTAssertEqual(e.world.tasks,tasks);XCTAssertEqual(e.world.agents["liubei"]?.job,"builder")
    }
}
