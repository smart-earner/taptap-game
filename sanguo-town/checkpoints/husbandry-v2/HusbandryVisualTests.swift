import XCTest
@testable import SanguoLife
import SanguoLifeVisual
import SanguoPresentation

final class HusbandryVisualTests: XCTestCase {
    func make() throws -> LifeRuntime { try .init(catalog: .bundled(), wallUTC: 0) }
    func testNoFreePenOrPigBeforeAuthorizationAndConstruction() throws {
        var e = try make()
        XCTAssertTrue(LifePigArt.frames(e.world, at: 0).isEmpty)
        XCTAssertTrue(LifePigArt.structures(e.world).isEmpty)
        try e.setHusbandry(enabled: true)
        XCTAssertTrue(LifePigArt.frames(e.world, at: 0).isEmpty)
        XCTAssertTrue(LifePigArt.structures(e.world).isEmpty)
    }
    func testPurchasedAnimalIsNotShownUntilActualArrival() throws {
        var e = try make(); try e.setHusbandry(enabled: true)
        e.world.husbandry!.pigs["pig-1"] = LifePig(id: "pig-1", orderedAt: 0)
        XCTAssertTrue(LifePigArt.frames(e.world, at: 10).isEmpty)
        e.world.husbandry!.pigs["pig-1"]!.phase = .awaitingEscort
        let frames = LifePigArt.frames(e.world, at: 300)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].point, LifeMap.point("gate"))
    }
    func testSixthFeedingDoesNotLookLikeCompletedGrowth() {
        var pig = LifePig(id: "pig", orderedAt: 0)
        pig.phase = .growing; pig.segmentsFed = 6; pig.due = 2880
        XCTAssertEqual(pig.growthProgress(at: 0), 5.0/6, accuracy: 0.00001)
        XCTAssertLessThan(pig.growthProgress(at: 2879), 1)
        pig.advancePassive(to: 2880)
        XCTAssertEqual(pig.growthProgress(at: 2880), 1)
    }
    func testLeadingUsesActualCarrierPathAndProcessingIsIndoors() throws {
        var e=try make();try e.setHusbandry(enabled:true)
        var pig=LifePig(id:"pig-1",orderedAt:0);pig.phase = .leading;pig.segmentsFed=6;pig.due=nil;pig.taskID="lead-1"
        e.world.husbandry!.pigs[pig.id]=pig
        e.world.tasks["lead-1"] = .init(id:"lead-1",worker:"r15",kind:"pig_process",job:"butcher",subject:pig.id,
            steps:[.init(kind:"lead",seconds:10,route:[.init(100,100),.init(200,100)],destination:"butcher")],started:0,due:10,rate:10000)
        let f=try XCTUnwrap(LifePigArt.frames(e.world,at:5).first)
        XCTAssertEqual(f.point,LifePoint(132,93));XCTAssertTrue(f.walking)
        e.world.husbandry!.pigs[pig.id]!.phase = .processing
        XCTAssertTrue(LifePigArt.frames(e.world,at:5).isEmpty)
    }
    func testVisibilityBudgetAndNamedPeopleUseTheSameSelection() throws {
        var e = try make()
        for i in 0..<120 {
            let id = "ordinary-\(i)"
            e.world.agents[id] = .init(id:id,name:id,job:"flex",node:"gate",home:"home",dining:"home-meals")
        }
        let a=LifeVisual.visibleAgents(e.world,limit:48)
        XCTAssertEqual(a.count,48);XCTAssertTrue(a.contains{$0.id=="xunyu"})
        XCTAssertEqual(a.map(\.id),LifeVisual.visibleAgents(e.world,limit:48).map(\.id))
        XCTAssertEqual(LifeVisual.visibleAgents(e.world,limit:0).count,0)
        XCTAssertLessThanOrEqual(LifeVisual.visibleAgents(e.world,limit:999).count,160)
    }
    func testMeatAndMealAreDistinctWithoutChangingEconomy() throws {
        let e = try make(), before=e.world
        let grain=SVG.node(LifeVisual.cargo(.grain))
        let meat=SVG.node(LifeVisual.cargo(.meat))
        XCTAssertNotEqual(grain,meat)
        XCTAssertNotEqual(SVG.node(LifeVisual.cargo(.meal)),SVG.node(LifeVisual.cargo(.meal,quality:"hearty")))
        _ = LifeVisual.svg(e.world,at:10000)
        XCTAssertEqual(e.world,before)
    }
}
