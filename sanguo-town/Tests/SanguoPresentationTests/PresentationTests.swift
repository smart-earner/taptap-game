import Foundation
import Testing
import SanguoCore
@testable import SanguoPresentation

@Test func artIDsUnique() {
    for costume in Costume.allCases { let ids = CharacterRig.artwork(costume).allIDs; #expect(ids.count == Set(ids).count) }
}
@Test func transformsOnlyReferenceActualParts() {
    let ids = Set(CharacterRig.artwork(.warrior).allIDs)
    for m in Motion.allCases { let p = CharacterRig.pose(motion:m,time:1); #expect(Set(p.transforms.keys).isSubset(of:ids)); #expect(p.hidden.isSubset(of:ids)) }
}
@Test func alternatingLegs() {
    let p = CharacterRig.pose(motion:.walk,time:0,distance:8)
    #expect(p.transforms["nearLeg"]!.angle > 0); #expect(p.transforms["farLeg"]!.angle < 0)
}
@Test func travelDistanceDrivesGait() {
    let a = CharacterRig.pose(motion:.walk,time:0,distance:8), b = CharacterRig.pose(motion:.walk,time:100,distance:8)
    #expect(a.transforms["nearLeg"] == b.transforms["nearLeg"])
}
@Test func facingMirrorsBodyNotShadow() {
    let p = CharacterRig.pose(motion:.idle,time:0,facing:-1)
    #expect(p.transforms["facing"]?.sx == -1); #expect(p.transforms["shadow"] == nil)
}
@Test func weaponSwapOnlyChangesVisibility() {
    let a = CharacterRig.pose(motion:.walk,time:1,item:.spear), b = CharacterRig.pose(motion:.walk,time:1,item:.sword)
    #expect(a.transforms == b.transforms); #expect(!a.hidden.contains("spear")); #expect(b.hidden.contains("spear"))
}
@Test func hammerReplacesWeapon() {
    let p = CharacterRig.pose(motion:.hammer,time:1,item:.spear)
    #expect(!p.hidden.contains("hammer")); #expect(p.hidden.contains("spear")); #expect(p.hidden.contains("sword"))
}
@Test func allPosesFinite() {
    for m in Motion.allCases { for time in [0.0,1,20,Double.nan,Double.infinity] {
        let p = CharacterRig.pose(motion:m,time:time,distance:.nan)
        #expect(p.transforms.values.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.angle.isFinite })
    } }
}
@Test func reducedMotionStopsPoseOscillation() {
    let a = CharacterRig.pose(motion:.hammer,time:1,reducedMotion:true), b = CharacterRig.pose(motion:.hammer,time:10,reducedMotion:true)
    #expect(a == b)
}
@Test func graphRejectsUnknownNode() { #expect(RoadGraph.town.route(from:"hall",to:"missing") == nil) }
@Test func graphDoesNotInventRoute() {
    let g = RoadGraph(points:["a":.init(0,0),"b":.init(1,1)],edges:[])
    #expect(g.route(from:"a",to:"b") == nil)
}
@Test func routePassesAlongStreet() {
    let r = RoadGraph.town.route(from:"hall",to:"forge")!
    #expect(r == [.init(225,130),.init(225,76),.init(455,76),.init(455,125)])
}
@Test func allDemoRoutesReachable() {
    for a in TownProjection.demo.actors { #expect(RoadGraph.town.route(from:a.home,to:a.destination) != nil) }
}
@Test func actorArrivesWorksAndReturns() {
    var a = ActorState(TownProjection.demo.actors[0]); var worked = false, left = false
    for _ in 0..<1500 { a.step(1.0/30); worked = worked || a.motion == .hammer; left = left || a.facing < 0 }
    #expect(worked && left); #expect(a.legOfTrip >= 2)
}
@Test func movementIsBoundedAndNotTeleporting() {
    var a = ActorState(TownProjection.demo.actors[0])
    for _ in 0..<600 { let old = a.position; a.step(1.0/30); #expect(old.distance(to:a.position) <= 38.0/30+0.0001) }
}
@Test func depthUsesGroundNotHead() {
    let a = ActorState(TownProjection.demo.actors[0]); #expect(a.depth == 500-a.position.y)
}
@Test func pauseFreezesPresentation() {
    var d = TownDirector(); d.sync(.demo); d.paused = true
    let before = d.actors; d.tick(0.1); #expect(d.actors == before); #expect(d.visibleTime == 0)
}
@Test func sleepDoesNotReplayHours() {
    var d = TownDirector(); d.sync(.demo); let old = d.actors
    d.tick(7200); #expect(d.actors == old); #expect(d.visibleTime == 0)
}
@Test func invalidDeltaIgnored() {
    var d = TownDirector(); d.sync(.demo); for t in [-1.0,.nan,.infinity,0] { d.tick(t) }; #expect(d.visibleTime == 0)
}
@Test func snapshotRefreshDoesNotRestartWalk() {
    var d = TownDirector(); d.sync(.demo); for _ in 0..<60 { d.tick(0.1) }
    let before = d.actors; d.sync(.demo); #expect(d.actors == before)
}
@Test func actorRemovalHasNoGhost() {
    var d = TownDirector(); d.sync(.demo); var next = TownProjection.demo; next.actors.removeFirst(); d.sync(next)
    #expect(d.actors["demo-warrior"] == nil); #expect(d.actors.count == 2)
}
@Test func citySwitchClearsOldActors() {
    var d = TownDirector(); d.sync(.demo)
    let w = Seed.oneCity(wallUTC:0); d.sync(TownProjection.live(w,cityID:"plain")!)
    #expect(d.actors.keys.allSatisfy { !$0.hasPrefix("demo-") })
}
@Test func duplicatePresentationIDsNotDuplicated() {
    var p = TownProjection.demo; p.actors += p.actors
    var d = TownDirector(); d.sync(p); #expect(d.actors.count == 3)
}
@Test func realProjectionFiltersCity() {
    let w = Seed.threeCityDemo(wallUTC:0), p = TownProjection.live(w,cityID:"stone")!
    #expect(p.actors.contains { $0.id == "person:guanyu" }); #expect(!p.actors.contains { $0.id == "person:zhaoyun" })
}
@Test func workshopNotShownBeforeCapacityExists() {
    #expect(TownProjection.live(Seed.oneCity(wallUTC:0),cityID:"plain")?.hasWorkshop == false)
    #expect(TownProjection.live(Seed.threeCityDemo(wallUTC:0),cityID:"plain")?.hasWorkshop == true)
}
@Test func noFictionalJobRepresentative() {
    var w = Seed.oneCity(wallUTC:0); w.cities["plain"]?.jobs = [:]
    let p = TownProjection.live(w,cityID:"plain")!; #expect(p.actors.allSatisfy { !$0.representative })
}
@Test func renderingNeverMutatesWorld() {
    let w = Seed.oneCity(wallUTC:0), before = w
    var d = TownDirector(); d.sync(TownProjection.live(w,cityID:"plain")!)
    for _ in 0..<1200 { d.tick(1.0/30) }
    _ = TownArt.svg(director:d); #expect(w == before)
}
@Test func deterministicPresentation() {
    var a = TownDirector(), b = TownDirector(); a.sync(.demo); b.sync(.demo)
    for _ in 0..<500 { a.tick(1.0/30); b.tick(1.0/30) }
    #expect(TownArt.svg(director:a) == TownArt.svg(director:b))
}
@Test func svgTextEscapesMarkup() { #expect(SVG.escape("<&\"") == "&lt;&amp;&quot;") }
@Test func noExternalAssetsInSVG() {
    var d = TownDirector(); d.sync(.demo); let s = TownArt.svg(director:d)
    #expect(!s.contains("href=")); #expect(!s.contains("<script")); #expect(s.hasSuffix("</svg>"))
}
