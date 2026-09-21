import XCTest
@testable import SanguoLife
import SanguoLifeVisual

final class LiveSceneTests: XCTestCase {
    func fixture(_ stage: LifePigStage) throws -> LifeWorld {
        var e = try LifeRuntime(catalog: .bundled(), wallUTC: 0)
        try e.authorizeHusbandry()
        var w = e.world
        var pig = LifePig(id: "pig-fixture", purchasedAt: 0, rules: w.husbandry!.rules)
        pig.stage = stage
        pig.node = [.inTransit, .atGate, .receiving].contains(stage) ? "gate" : "pasture"
        w.husbandry!.animals[pig.id] = pig
        return w // Deliberate art fixture; not a gameplay save or asset grant.
    }
    func testLiveSceneCombinesRealFacilitiesOnlyOnce() throws {
        var w = try fixture(.ready)
        w.buildings["pasture"] = 1
        let scene = LifeLiveVisual.scene(w)
        XCTAssertEqual(scene.filter { $0.id == "life-pasture-back" }.count, 1)
        XCTAssertEqual(scene.filter { $0.id == "life-pasture-front" }.count, 1)
    }
    func testSVGContainsOwnedAnimalAndNoNetworkCalls() throws {
        let w = try fixture(.growing), before = w
        let svg = LifeLiveVisual.svg(w)
        XCTAssertTrue(svg.contains("data-animal=\"pig-fixture\""))
        XCTAssertFalse(svg.contains("<script"))
        XCTAssertFalse(svg.contains("<image"))
        XCTAssertEqual(w, before)
    }
    func testHerderTaskTextDescribesActualWork() throws {
        var w = try fixture(.caring)
        let step = LifeStep(kind: "work", seconds: 30)
        let t = LifeTask(id:"care",worker:"r01",kind:"pig_care",job:"herder",subject:"pig-fixture",steps:[step],started:0,due:30,rate:10000)
        w.tasks[t.id] = t; w.agents["r01"]!.taskID = t.id
        let f = LifeLiveVisual.actor(w.agents["r01"]!,world:w,at:10)
        XCTAssertEqual(f.action,"添料照料（已扣饲料）")
        XCTAssertEqual(LifeLiveVisual.jobName("herder"),"牧工")
    }
    func testSVGAndNativeUseSameVisibleAgentSelection() throws {
        let w = try fixture(.ready)
        let svg = LifeLiveVisual.svg(w,limit:1)
        let ids = LifeFoodVisual.visibleAgents(w,limit:1).map(\.id)
        XCTAssertEqual(ids,["xunyu"])
        XCTAssertEqual(svg.components(separatedBy:"data-agent=").count-1,1)
        XCTAssertTrue(svg.contains("data-agent=\"xunyu\""))
    }
}
