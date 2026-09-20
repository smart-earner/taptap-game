import Foundation
import Testing
@testable import SanguoCore
@testable import SanguoPresentation

@Suite("Courtyard layout and authentic city feedback")
struct TownLayoutTests {
    func snapshot()->CityAppearanceSnapshot {
        var s=GrowthRuntime.newGame(wallUTC:0).appearance(cityID:"plain")!
        s.layoutVersion=2;s.civic=CivicCity();return s
    }
    @Test func allSixteenPlotsHaveUniquePositions() {
        #expect(TownLayout.positions.count==16)
        #expect(Set(TownLayout.positions.map{"\($0.x),\($0.y)"}).count==16)
        #expect(Set(TownLayout.positions.map(\.y)).count>8)
    }
    @Test func everyEntranceIsReachable() {
        for i in 0..<16 {
            let route=TownLayout.roads.route(from:"gate",to:"plot-\(i)")
            #expect(route?.last == TownLayout.position(i))
        }
    }
    @Test func roadsDoNotCrossBuildingFootprints() {
        let graph=TownLayout.roads
        for edge in graph.edges {
            let a=graph.points[edge.0]!,b=graph.points[edge.1]!
            for i in 0...100 {
                let p=a.toward(b,fraction:Double(i)/100)
                for anchor in TownLayout.positions {
                    let intersects = p.x>anchor.x-45 && p.x<anchor.x+45 && p.y>anchor.y+2 && p.y<anchor.y+64
                    #expect(!intersects, "Road \(edge) crosses footprint at \(anchor)")
                }
            }
        }
    }
    @Test func buildingsDoNotOverlap() {
        for i in 0..<16 { for j in (i+1)..<16 {
            let a=TownLayout.positions[i],b=TownLayout.positions[j]
            #expect(abs(a.x-b.x)>=98 || abs(a.y-b.y)>=70)
        } }
    }
    @Test func legacyPositionRemainsUnchanged() {
        var s=snapshot();s.layoutVersion=nil
        for plot in 0..<16 { #expect(GrowthTownArt.position(plot,snapshot:s)==GrowthTownArt.position(plot)) }
    }
    @Test func changingPolicyAloneDoesNotChangeScenery() {
        var s=snapshot();s.civic!.levels=["commerce":3,"water":1]
        let before=GrowthTownArt.svg(s);s.policy = .military
        #expect(GrowthTownArt.svg(s)==before)
    }
    @Test func completedSpecialtyIsVisible() {
        var a=snapshot(),b=a
        a.civic!.levels=["commerce":3,"streets":3]
        b.civic!.levels=["water":3,"gardens":3]
        #expect(GrowthTownArt.svg(a) != GrowthTownArt.svg(b))
        #expect(TownLayout.civicDetails(b).flatMap(\.allIDs).contains("identity-water-wheel"))
    }
    @Test func artHasUniqueIDsAndNoRemoteImages() {
        var s=snapshot();s.civic!.levels=Dictionary(uniqueKeysWithValues:CivicTrack.allCases.map{($0.rawValue,3)})
        let ids=GrowthTownArt.background(s).allIDs
        #expect(ids.count==Set(ids).count)
        let svg=GrowthTownArt.svg(s)
        #expect(!svg.contains("<script") && !svg.contains("<image") && !svg.contains("<foreignObject"))
    }
    @Test func unbuiltSpecialtyIsNotShown() {
        let ids=GrowthTownArt.background(snapshot()).allIDs
        #expect(!ids.contains("identity-water-wheel") && !ids.contains("identity-garden-pool"))
    }
    @Test func actorRoadsUseSnapshotLayout() throws {
        var w=Seed.oneCity(wallUTC:0)
        try GameEngine.apply(.init(id:"adopt",expectedRevision:w.revision,action:.realm(.adoptIdentity(policy:.supply,investment:.balanced))),to:&w)
        let p=TownProjection.live(w,cityID:"plain")!
        #expect(p.roadGraph.points["plot-0"]==TownLayout.position(0))
        let official=p.actors.first{$0.id=="person:"+w.cities["plain"]!.prefectID}!
        #expect(official.destination=="plot-0" && official.work == .read)
    }
    @Test func changingLayoutRestartsRoutesAtNewEntrances() {
        var s=snapshot();s.layoutVersion=nil
        var old=TownProjectionSnapshotAdapter.make(s)
        old.actors=[.init(id:"a",name:"a",costume:.official,home:"plot-0",destination:"gate")]
        var director=TownDirector();director.sync(old)
        var next=old;next.appearance!.layoutVersion=2
        director.sync(next)
        #expect(director.actors["a"]?.position==TownLayout.position(0))
    }
    @Test func invalidHistoricalLayoutIsRejected() throws {
        var w=GrowthRuntime.newGame(wallUTC:0)
        w.growth!.memories[0].snapshot.layoutVersion=999
        #expect(throws:GameError.self) { try w.validate() }
    }
    @Test func historicalProjectionNeverMutatesSnapshot() {
        let s=snapshot(),before=s
        _=GrowthTownArt.svg(s);_=TownProjectionSnapshotAdapter.make(s)
        #expect(s==before)
    }
}
