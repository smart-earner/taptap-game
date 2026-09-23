import XCTest
@testable import SanguoLife

final class CityBreakthroughTests: XCTestCase {
    private func fixture() throws -> LifeRuntime {
        var runtime=try LifeRuntime(catalog:.bundled(),wallUTC:0,formalHeroTown:true,rngSeed:7)
        try runtime.enableSharedCourtyards()
        runtime.world.projects["repair"]!.completed=true
        runtime.world.projects["repair"]!.phase=4
        runtime.world.projects["repair"]!.completedWork=runtime.world.projects["repair"]!.totalWork
        runtime.world.projects["repair"]!.allocatedWork=0
        let ids=runtime.definition!.availableHeroes(phase:0).map(\.id).sorted()
        for id in ids where runtime.world.agents.count<28 && runtime.world.agents[id]==nil {
            runtime.world.agents[id] = .init(id:id,name:id,job:"builder",node:"tavern",home:"tavern",dining:"guest-meals",heroID:id,origin:"recruited")
            runtime.world.gacha!.stars[id]=1
            runtime.world.owned.append(id)
            runtime.world.heroTown!.ownedHeroes[id] = .init(heroID:id,star:1,sourceDrawID:"fixture",
                                                               arrivalState:"resident",arrivalAt:nil,bedReservation:"tavern-1.guest")
            runtime.world.heroTown!.courtyard!.households[id] =
                .init(id:"household:\(id)",memberPersonIDs:["hero:\(id)"],
                      residencePlotID:"tavern-1",unitID:nil,createdAt:0)
        }
        runtime.world.happiness=75
        runtime.world.foodCoverage=10000
        for index in 0..<4 {
            var meal=LifeMeal(id:"fixture-\(index)",at:Int64(index*100),deadline:Int64(index*100+50),expected:["xunyu"])
            meal.served=["xunyu":1]
            meal.closed=true
            runtime.world.meals.append(meal)
        }
        runtime.world.heroTown!.city.qualifiedWindows["breakthrough.stable"]=4
        runtime.world.heroTown!.city.civics["water"]=2
        for index in runtime.world.heroTown!.city.plots.indices where runtime.world.heroTown!.city.plots[index].kind=="house" &&
            runtime.world.heroTown!.city.plots[index].developmentPermit {
            runtime.world.heroTown!.city.plots[index].level=3
            runtime.world.heroTown!.city.plots[index].capacity=8
            runtime.world.heroTown!.city.plots[index].service=10_000
        }
        runtime.syncFormalCapacities()
        return runtime
    }

    func testFirstBreakthroughNeedsActualQualificationAndDoesNotUnlockEarly() throws {
        var runtime=try fixture()
        runtime.world.happiness=64
        XCTAssertFalse(runtime.planFormalBreakthrough())
        runtime.world.happiness=75
        runtime.world.meals[runtime.world.meals.count-1].served=[:]
        XCTAssertFalse(runtime.planFormalBreakthrough())
        runtime.world.meals[runtime.world.meals.count-1].served=["xunyu":1]
        XCTAssertTrue(runtime.planFormalBreakthrough())
        let project=try XCTUnwrap(runtime.world.projects["breakthrough.1"])
        XCTAssertEqual(project.totalWork,7200)
        XCTAssertEqual(project.materials,["wood":24000,"stone":16000,"tools":4000])
        XCTAssertEqual(runtime.world.gacha?.rosterPhase,0)
        XCTAssertEqual(runtime.world.heroTown?.courtyard?.unlockedColumns,8)
        XCTAssertEqual(runtime.world.heroTown?.city.plot("house-9")?.developmentPermit,false)
        runtime.finishFormalProject(project)
        XCTAssertEqual(runtime.world.gacha?.rosterPhase,1)
        XCTAssertEqual(runtime.world.heroTown?.courtyard?.unlockedColumns,10)
        XCTAssertEqual(runtime.world.heroTown?.courtyard?.unlockedRows,5)
        XCTAssertEqual(runtime.world.heroTown?.city.plot("house-9")?.developmentPermit,true)
        XCTAssertEqual(runtime.world.heroTown?.city.plot("house-11")?.developmentPermit,false)
        XCTAssertEqual(runtime.world.gacha?.rosterTarget,40)
        runtime.finishFormalProject(project)
        XCTAssertEqual(runtime.world.gacha?.rosterPhase,1)
    }

    func testLaterBreakthroughsUnlockOnlyTheirOwnParcelsAndRoster() throws {
        var runtime=try fixture()
        let first=LifeProject(id:"breakthrough.1",kind:"breakthrough_1",node:"hall",
                              materials:[:],cash:0,totalWork:7200,targetLevel:1)
        runtime.finishFormalProject(first)
        let second=LifeProject(id:"breakthrough.2",kind:"breakthrough_2",node:"hall",
                               materials:[:],cash:0,totalWork:10800,targetLevel:2)
        runtime.finishFormalProject(second)
        XCTAssertEqual(runtime.world.gacha?.rosterTarget,50)
        XCTAssertEqual(runtime.world.heroTown?.courtyard?.unlockedRows,6)
        XCTAssertEqual(runtime.world.heroTown?.city.plot("house-13")?.developmentPermit,true)
        XCTAssertEqual(runtime.world.heroTown?.city.plot("house-14")?.developmentPermit,false)
        let third=LifeProject(id:"breakthrough.3",kind:"breakthrough_3",node:"hall",
                              materials:[:],cash:0,totalWork:14400,targetLevel:3)
        runtime.finishFormalProject(third)
        XCTAssertEqual(runtime.world.gacha?.rosterTarget,60)
        XCTAssertEqual(runtime.world.heroTown?.courtyard?.unlockedColumns,12)
        XCTAssertEqual(runtime.world.heroTown?.courtyard?.unlockedRows,7)
        XCTAssertEqual(runtime.world.heroTown?.city.plot("house-15")?.developmentPermit,true)
    }
}
