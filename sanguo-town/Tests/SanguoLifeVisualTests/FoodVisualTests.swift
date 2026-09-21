import XCTest
@testable import SanguoLife
import SanguoLifeVisual
import SanguoPresentation

final class FoodVisualTests: XCTestCase {
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
    func testOldSaveDoesNotInventAnimalsOrFacilities() throws {
        let w = try LifeRuntime(catalog: .bundled(), wallUTC: 0).world
        XCTAssertTrue(LifeFoodVisual.animals(w, at: 0).isEmpty)
        XCTAssertTrue(LifeFoodVisual.scene(w).isEmpty)
    }
    func testOutsideAndProcessingPigsAreNotDrawn() throws {
        for stage in [LifePigStage.inTransit, .processing] {
            XCTAssertTrue(LifeFoodVisual.animals(try fixture(stage), at: 0).isEmpty)
        }
    }
    func testAtGatePigWaitsForHandlerInsteadOfTeleporting() throws {
        let w = try fixture(.atGate)
        let f = try XCTUnwrap(LifeFoodVisual.animals(w, at: 100).first)
        XCTAssertEqual(f.position, LifeMap.point("gate"))
        XCTAssertFalse(f.walking)
    }
    func testNoPigAppearsBeforePurchaseOrAfterRemoval() throws {
        var w = try fixture(.ready)
        w.husbandry!.animals = [:]
        XCTAssertTrue(LifeFoodVisual.animals(w, at: 1).isEmpty)
    }
    func testGrowthChangesSizeNotPopulation() throws {
        var w = try fixture(.growing)
        let before = LifeFoodVisual.animals(w, at: 0)[0]
        w.husbandry!.animals[before.id]!.completedSegments = 6
        let after = LifeFoodVisual.animals(w, at: 0)[0]
        XCTAssertGreaterThan(after.scale, before.scale)
        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(w.agents.count, 16)
    }
    func testPigFollowsSameCommittedRouteAsItsHandler() throws {
        var w = try fixture(.receiving)
        let route = LifeMap.path("gate", "pasture")
        let step = LifeStep(kind: "lead", seconds: 100, route: route, destination: "pasture")
        let task = LifeTask(id: "lead-fixture", worker: "r01", kind: "pig_receive", job: "herder", subject: "pig-fixture", steps: [step], started: 10, due: 110, rate: 10000)
        w.tasks[task.id] = task
        w.husbandry!.animals["pig-fixture"]!.taskID = task.id
        let frame = try XCTUnwrap(LifeFoodVisual.animals(w, at: 60).first)
        XCTAssertTrue(frame.walking)
        XCTAssertEqual(frame.position, LifeMap.position(task, at: 59.5))
        XCTAssertEqual(LifeFoodVisual.animals(w, at: 1000)[0].position, LifeMap.position(task, at: 109.5))
    }
    func testPastureNeedsBuiltOrActualProject() throws {
        var w = try fixture(.waitingForCare)
        XCTAssertTrue(LifeFoodVisual.scene(w).isEmpty)
        w.buildings["pasture"] = 1
        XCTAssertEqual(LifeFoodVisual.scene(w).count, 2)
    }
    func testMeatAndBasicMealHaveDifferentDrawings() {
        XCTAssertNotEqual(LifeFoodVisual.cargo(.meal, hearty: false), LifeFoodVisual.cargo(.meal, hearty: true))
        XCTAssertNotEqual(LifeFoodVisual.cargo(.grain, hearty: false), LifeFoodVisual.cargo(.meat, hearty: false))
    }
    func testRenderCapPrioritizesNamedPeopleConsistently() throws {
        let w = try fixture(.ready)
        XCTAssertEqual(LifeFoodVisual.visibleAgents(w, limit: 1).map(\.id), ["xunyu"])
        XCTAssertTrue(LifeFoodVisual.visibleAgents(w, limit: -10).isEmpty)
        XCTAssertLessThanOrEqual(LifeFoodVisual.visibleAgents(w, limit: 999).count, 160)
    }
    func testSleepingPeopleDoNotWasteVisibleSlots() throws {
        var w = try fixture(.ready)
        for id in w.agents.keys { w.agents[id]!.taskID = nil; w.agents[id]!.node = w.agents[id]!.home; w.agents[id]!.restStart = 0 }
        XCTAssertTrue(LifeFoodVisual.visibleAgents(w, limit: 96).isEmpty)
    }
    func testArtworkIDsAreUniqueAndReducedMotionIsStill() throws {
        let art = LifeFoodVisual.pigArtwork()
        XCTAssertEqual(art.allIDs.count, Set(art.allIDs).count)
        let frame = try XCTUnwrap(LifeFoodVisual.animals(fixture(.growing), at: 0).first)
        XCTAssertEqual(LifeFoodVisual.pigPose(frame, time: 0, reducedMotion: true),
                       LifeFoodVisual.pigPose(frame, time: 20, reducedMotion: true))
    }
    func testRenderingCannotMutateEconomicState() throws {
        let w = try fixture(.growing), before = w
        _ = LifeVisual.svg(w, at: 100)
        _ = LifeFoodVisual.animals(w, at: 200)
        _ = LifeFoodVisual.visibleAgents(w, limit: 1)
        XCTAssertEqual(w, before)
    }
}
