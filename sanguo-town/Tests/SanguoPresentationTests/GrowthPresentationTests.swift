import Testing
import Foundation
import SanguoCore
@testable import SanguoPresentation

@Suite("Real city appearance")
struct GrowthPresentationTests {
    func game() throws -> WorldState {
        var w=GrowthRuntime.newGame(wallUTC:0)
        try GameEngine.apply(.init(id:"start",expectedRevision:w.revision,action:.acceptDevelopment(policy:.industry,investment:.balanced)),to:&w)
        return w
    }
    @Test func growthProjectionUsesBuildingInstances() throws {
        let w=try game(),p=TownProjection.live(w,cityID:"plain")!
        #expect(p.appearance != nil && !p.hasWorkshop)
        #expect(p.appearance!.buildings.filter(\.isOperating).count==4)
    }
    @Test func lateTownDiffersStructurally() throws {
        var w=try game();let first=GrowthTownArt.svg(w.appearance(cityID:"plain")!)
        try GameEngine.advance(to:7*86_400,world:&w)
        let later=GrowthTownArt.svg(w.appearance(cityID:"plain")!)
        #expect(first != later && later.contains("chimney"))
    }
    @Test func pausedConstructionHasNoHammerWorker() throws {
        var w=try game();let project=w.growth!.cities["plain"]!.projects.first!
        try GameEngine.apply(.init(id:"pause",expectedRevision:w.revision,action:.pauseBuilding(cityID:"plain",projectID:project.id,paused:true)),to:&w)
        #expect(!TownProjection.live(w,cityID:"plain")!.actors.contains{$0.id==project.id})
    }
    @Test func allGrowthDestinationsHaveRealRoads() throws {
        let p=TownProjection.live(try game(),cityID:"plain")!
        for actor in p.actors { #expect(p.roadGraph.route(from:actor.home,to:actor.destination) != nil) }
    }
    @Test func smallStepsWalkToActualPlot() throws {
        let p=TownProjection.live(try game(),cityID:"plain")!
        var d=TownDirector();d.sync(p)
        for _ in 0..<3000 { d.tick(0.1) }
        #expect(d.actors.values.contains{$0.legOfTrip>0})
    }
    @Test func ledgerNotTouchedByRendering() throws {
        var w=try game();try GameEngine.advance(to:4*86_400,world:&w);let before=w
        var d=TownDirector();d.sync(TownProjection.live(w,cityID:"plain")!)
        for _ in 0..<200 { d.tick(0.1);_ = GrowthTownArt.svg(w.appearance(cityID:"plain")!) }
        #expect(w==before)
    }
    @Test func snapshotsHaveNoExternalResources() throws {
        let svg=GrowthTownArt.svg(try game().appearance(cityID:"plain")!)
        #expect(!svg.contains("<image") && !svg.contains("<script") && !svg.contains("<foreignObject"))
    }
    @Test func absentArmyDoesNotDrawTroopRepresentative() throws {
        let p=TownProjection.live(try game(),cityID:"plain")!
        #expect(!p.actors.contains{$0.id=="legion-representative"})
    }
    @Test func historyIsNotCurrentStatePaintedAgain() throws {
        var w=try game();let old=w.growth!.memories.first!.snapshot
        try GameEngine.advance(to:10*86_400,world:&w)
        #expect(old.buildings.count==4 && old != w.appearance(cityID:"plain")!)
    }
    @Test func blockedProductionDoesNotShowWorkingForge() throws {
        var w=try game();try GameEngine.advance(to:7*86_400,world:&w)
        // An explicit appearance with no working resources cannot draw a lit production furnace.
        var s=w.appearance(cityID:"plain")!;s.workingResources=[]
        #expect(!GrowthTownArt.svg(s).contains("-fire"))
    }
    @Test func plotArtIDsAreUnique() throws {
        var w=try game();try GameEngine.advance(to:15*86_400,world:&w)
        let s=w.appearance(cityID:"plain")!
        let ids=GrowthTownArt.background(s).allIDs+s.buildings.flatMap{GrowthTownArt.building($0,snapshot:s).allIDs}
        #expect(ids.count==Set(ids).count)
    }
    @Test func snapshotAdapterIsStatic() throws {
        let p=TownProjectionSnapshotAdapter.make(try game().appearance(cityID:"plain")!)
        #expect(p.actors.isEmpty && p.appearance != nil && !p.isDemo)
    }
}
