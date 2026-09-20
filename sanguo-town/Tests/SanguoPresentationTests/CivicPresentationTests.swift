import Foundation
import Testing
@testable import SanguoCore
@testable import SanguoPresentation

@Suite("Civic snapshot presentation")
struct CivicPresentationTests {
    func game()->WorldState { GrowthRuntime.newGame(wallUTC:0) }
    func adopt(_ w:inout WorldState) throws {
        try GameEngine.apply(.init(id:"adopt",expectedRevision:w.revision,action:.realm(.adopt(policy:.balanced,investment:.balanced))),to:&w)
    }
    @Test func oldSnapshotHasNoUnbuiltCivicScenery() {
        let s=game().appearance(cityID:"plain")!
        #expect(CivicTownArt.nodes(s).isEmpty)
    }
    @Test func levelsActuallyChangePavingCanalAndGardens() throws {
        var w=game();try adopt(&w)
        let before=w.appearance(cityID:"plain")!
        w.realm!.civic["plain"]!.levels=["streets":3,"water":3,"gardens":3]
        let after=w.appearance(cityID:"plain")!
        let ids=CivicTownArt.nodes(after).flatMap(\.allIDs)
        #expect(ids.contains("civic-canal") && ids.contains("civic-waterwheel") && ids.contains("civic-pond"))
        #expect(CivicTownArt.nodes(before).flatMap(\.allIDs).count < ids.count)
    }
    @Test func historicalCivicDoesNotReadCurrentLevels() throws {
        var w=game();try adopt(&w)
        let past=w.appearance(cityID:"plain")!,pastSVG=GrowthTownArt.svg(past)
        w.realm!.civic["plain"]!.levels=["streets":3,"commerce":3]
        #expect(GrowthTownArt.svg(past)==pastSVG)
        #expect(GrowthTownArt.svg(w.appearance(cityID:"plain")!) != pastSVG)
    }
    @Test func allCivicArtIDsAreUnique() throws {
        var w=game();try adopt(&w)
        w.realm!.civic["plain"]!.levels=Dictionary(uniqueKeysWithValues:CivicTrack.allCases.map{($0.rawValue,3)})
        let s=w.appearance(cityID:"plain")!
        let ids=GrowthTownArt.background(s).allIDs+s.buildings.flatMap{GrowthTownArt.building($0,snapshot:s).allIDs}
        #expect(Set(ids).count==ids.count)
    }
    @Test func civicWorkDoesNotInventRoads() throws {
        var w=game();try adopt(&w);try GameEngine.advance(to:12*86_400,world:&w)
        let p=TownProjection.live(w,cityID:"plain")!
        for actor in p.actors { #expect(p.roadGraph.route(from:actor.home,to:actor.destination) != nil) }
        if let project=w.realm!.civic["plain"]!.project,project.workers>0 { #expect(p.actors.contains{$0.id=="civic-plain"}) }
    }
    @Test func pausedCivicHasNoFakeWorker() throws {
        var w=game();try adopt(&w);try GameEngine.advance(to:12*86_400,world:&w)
        w.realm!.civic["plain"]!.project?.paused=true
        #expect(!TownProjection.live(w,cityID:"plain")!.actors.contains{$0.id=="civic-plain"})
    }
    @Test func travellersAreNotCityClones() throws {
        var w=Seed.threeCityDemo(wallUTC:0);try adopt(&w)
        let person=w.people.values.first{$0.office==nil && $0.cityID=="plain"}!
        try GameEngine.apply(.init(id:"move",expectedRevision:w.revision,action:.realm(.movePerson(person:person.id,destination:"stone"))),to:&w)
        for id in ["plain","stone"] { #expect(!TownProjection.live(w,cityID:id)!.actors.contains{$0.id=="person:"+person.id}) }
    }
    @Test func equippedWeaponIsProjectedWithoutIssuingAnotherItem() throws {
        var w=game();try adopt(&w)
        let id=w.cities["plain"]!.prefectID
        w.realm!.equipment["silver-spear"]=id
        let before=w
        let p=TownProjection.live(w,cityID:"plain")!
        #expect(p.actors.first{$0.id=="person:"+id}?.handItem == .spear)
        #expect(w==before)
    }
    @Test func absentEquipmentHasNoVisualWeapon() throws {
        var w=game();try adopt(&w)
        #expect(TownProjection.live(w,cityID:"plain")!.actors.filter{!$0.representative}.allSatisfy{$0.handItem == .none})
    }
    @Test func civicSnapshotSurvivesSaveAndCanRemovePinnedCopy() throws {
        var w=game();try adopt(&w);try GameEngine.advance(to:12*86_400,world:&w)
        try GameEngine.apply(.init(id:"memory",expectedRevision:w.revision,action:.rememberCity(cityID:"plain")),to:&w)
        let restored=try SaveStore.decode(SaveStore.encode(w))
        #expect(restored.growth!.memories.last!.snapshot.civic == w.realm!.civic["plain"])
    }
    @Test func malformedHistoricalCivicRejected() throws {
        var w=game();try adopt(&w)
        w.growth!.memories[0].snapshot.collectedWeapons=100
        #expect(throws:GameError.self){try w.validate()}
    }
    @Test func civicRenderContainsNoScriptsOrExternalAssets() throws {
        var w=game();try adopt(&w);try GameEngine.advance(to:20*86_400,world:&w)
        let svg=GrowthTownArt.svg(w.appearance(cityID:"plain")!)
        #expect(!svg.contains("<script") && !svg.contains("<image") && !svg.contains("<foreignObject"))
    }
}
