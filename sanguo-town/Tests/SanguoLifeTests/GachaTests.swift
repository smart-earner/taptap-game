import XCTest
@testable import SanguoLife

final class GachaTests:XCTestCase {
    func make()throws->LifeRuntime{try .init(catalog:.bundled(),wallUTC:0,gachaMode:true,rngSeed:42)}
    func testSeedAndLegacyIsolation()throws{
        let e=try make(),old=try LifeRuntime(catalog:.bundled(),wallUTC:0)
        XCTAssertEqual(e.world.treasury,200);XCTAssertEqual(e.world.format,4)
        XCTAssertEqual(old.world.agents.count,16);XCTAssertNil(old.world.gacha)
        XCTAssertEqual(old.world.amount(.gold_ore),0);XCTAssertEqual(old.world.amount(.gold_ingot),0)
    }
    func testRetryAndFailedDrawAreAtomic()throws{
        var e=try make();let req=LifeGachaRequest(id:"retry",action:.draw(count:1,pool:e.definition!.gacha.pool_version))
        let result=try e.performGacha(req),w=e.world
        XCTAssertEqual(try e.performGacha(req),result);XCTAssertEqual(e.world,w)
        XCTAssertThrowsError(try e.performGacha(.init(action:.draw(count:10,pool:e.definition!.gacha.pool_version))))
        XCTAssertEqual(e.world,w)
    }
    func testPity()throws{
        var e=try make();e.world.gacha!.pity=19
        let r=try e.performGacha(.init(action:.draw(count:1,pool:e.definition!.gacha.pool_version)))
        XCTAssertEqual(r.draws.first?.rarity,"legend");XCTAssertEqual(e.world.gacha!.pity,0)
    }
    func testManualCardsAndLocks()throws{
        var e=try make();e.world.gacha!.cards["test"] = .init(id:"test",heroID:"xunyu",origin:"test_fixture",count:10)
        _=try e.performGacha(.init(action:.lock(card:"test",locked:true)))
        XCTAssertThrowsError(try e.performGacha(.init(action:.starUp(hero:"xunyu",target:2))))
        XCTAssertThrowsError(try e.performGacha(.init(action:.disassemble(card:"test",quantity:1))))
        _=try e.performGacha(.init(action:.lock(card:"test",locked:false)))
        for star in 2...5 {_=try e.performGacha(.init(action:.starUp(hero:"xunyu",target:star)))}
        XCTAssertEqual(e.world.gacha!.stars["xunyu"],5);XCTAssertEqual(e.world.gacha!.cardCount("xunyu"),0)
        XCTAssertEqual(e.world.treasury,200)
    }
    func testManualExchangeAndBodyProtection()throws{
        var e=try make();e.world.gacha!.cards["test"] = .init(id:"test",heroID:"xunyu",origin:"test_fixture",count:4)
        XCTAssertThrowsError(try e.performGacha(.init(action:.disassemble(card:"xunyu",quantity:1))))
        _=try e.performGacha(.init(action:.disassemble(card:"test",quantity:4)))
        XCTAssertEqual(e.world.gacha!.souls,400)
        _=try e.performGacha(.init(action:.exchange(hero:"xunyu",quantity:1)))
        XCTAssertEqual(e.world.gacha!.souls,0);XCTAssertEqual(e.world.gacha!.stars["xunyu"],1)
        XCTAssertEqual(e.world.gacha!.cardCount("xunyu"),1)
    }
    func testActualGoldProvenanceAndFood()throws{
        var e=try make();try e.advance(to:7200)
        XCTAssertGreaterThan(e.world.gacha!.minted,0)
        XCTAssertEqual(e.world.gacha!.minted,e.world.consumed["gold_ingot",default:0]/1000*10)
        XCTAssertEqual(e.world.treasury,200+e.world.gacha!.minted)
        XCTAssertEqual(e.world.foodCoverage,10000)
    }
    func testFrameCadenceAndSave()throws{
        var a=try make();try a.advance(to:333)
        var b=try LifeRuntime(catalog:.bundled(),world:LifeSaveStore.decode(LifeSaveStore.encode(a.world)))
        try a.advance(to:7200)
        for t in stride(from:Int64(350),to:7200,by:17){try b.advance(to:t)}
        try b.advance(to:7200);XCTAssertEqual(a.world,b.world)
    }
    func testNewStarOnlyAffectsFutureTaskRates()throws{
        var e=try make();let old=e.world.tasks
        let rate1=e.starWorkRate(e.world.agents["xunyu"]!,job:"cook")
        e.world.gacha!.stars["xunyu"]=3
        XCTAssertGreaterThan(e.starWorkRate(e.world.agents["xunyu"]!,job:"cook"),rate1)
        XCTAssertEqual(e.world.tasks,old)
    }
}
