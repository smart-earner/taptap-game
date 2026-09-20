import Foundation
import Testing
@testable import SanguoCore

@Suite("City growth runtime")
struct GrowthTests {
    func game(_ policy:Policy = .balanced) throws -> WorldState {
        var w=GrowthRuntime.newGame(wallUTC:0)
        try GameEngine.apply(.init(id:"accept",expectedRevision:w.revision,action:.acceptDevelopment(policy:policy,investment:.balanced)),to:&w)
        return w
    }
    func send(_ action:GameAction,_ world:inout WorldState,principal:Principal = .player) throws {
        try GameEngine.apply(.init(id:"cmd-\(world.revision)",expectedRevision:world.revision,principal:principal,action:action),to:&world)
    }
    @Test func unacceptedCityDoesNotBuild() throws {
        var w=GrowthRuntime.newGame(wallUTC:0)
        try GameEngine.advance(to:86_400,world:&w)
        #expect(w.growth!.cities["plain"]!.projects.isEmpty)
    }
    @Test func initialFourRealBuildings() throws {
        let w=try game()
        #expect(w.growth!.cities["plain"]!.buildings.filter(\.isOperating).count==4)
        #expect(w.appearance(cityID:"plain")!.buildings.contains{$0.kind == .house})
    }
    @Test func firstRepairHasVisibleProgressWithinTenMinutes() throws {
        var w=try game();try GameEngine.advance(to:300,world:&w)
        let p=w.growth!.cities["plain"]!.projects.first{$0.isRepair}!
        #expect(p.completedWork>0 && p.phase>=1)
    }
    @Test func startsReserveNotInstantlySpendFullCost() throws {
        let w=try game(),g=w.growth!
        #expect(g.reservedCash>0 && w.treasury==500)
        #expect(w.cities["plain"]!.inventory.reserved["wood",default:0]>0)
    }
    @Test func sharedConstructionAndProductionLabor() throws {
        var w=try game();try GameEngine.advance(to:5*86_400,world:&w)
        #expect(w.cities["plain"]!.jobs.values.reduce(0,+)+w.growth!.cities["plain"]!.builders<=w.cities["plain"]!.labor)
    }
    @Test func completesThreeProjectsWithoutMoreClicks() throws {
        var w=try game();try GameEngine.advance(to:3*86_400,world:&w)
        #expect(w.growth!.cities["plain"]!.completedCount>=3)
    }
    @Test func constructionDoesNotOperateBeforeCompletion() throws {
        let w=try game()
        for b in w.growth!.cities["plain"]!.buildings where b.level==0 { #expect(!b.isOperating) }
        #expect(w.cities["plain"]!.jobCapacity["tools",default:0]==0)
    }
    @Test func pauseRetainsWorkAndReservations() throws {
        var w=try game();try GameEngine.advance(to:111,world:&w)
        let p=w.growth!.cities["plain"]!.projects.first!
        try send(.pauseBuilding(cityID:"plain",projectID:p.id,paused:true),&w)
        let work=w.growth!.cities["plain"]!.projects[0].completedWork
        try GameEngine.advance(to:6000,world:&w)
        #expect(w.growth!.cities["plain"]!.projects[0].completedWork==work)
        #expect(w.growth!.cities["plain"]!.projects[0].status == .paused)
    }
    @Test func cancelledProjectReleasesOnlyUnspentResources() throws {
        var w=try game();try GameEngine.advance(to:100,world:&w)
        let p=w.growth!.cities["plain"]!.projects.first!
        let treasury=w.treasury,wood=w.cities["plain"]!.inventory[.wood]
        let reserved=w.cities["plain"]!.inventory.reserved["wood",default:0]
        try send(.cancelBuilding(cityID:"plain",projectID:p.id),&w)
        #expect(w.treasury==treasury && w.cities["plain"]!.inventory[.wood]==wood)
        #expect(w.cities["plain"]!.inventory.reserved["wood",default:0] == reserved - p.materialCost["wood",default:0]+p.materialSpent["wood",default:0])
    }
    @Test func noDoubleCancellation() throws {
        var w=try game();let id=w.growth!.cities["plain"]!.projects.first!.id
        try send(.cancelBuilding(cityID:"plain",projectID:id),&w)
        let old=w
        #expect(throws:GameError.self) { try send(.cancelBuilding(cityID:"plain",projectID:id),&w) }
        #expect(w==old)
    }
    @Test func lockedPlotsNeverGetNewProjects() throws {
        var w=GrowthRuntime.newGame(wallUTC:0)
        for plot in 0..<16 { try send(.lockPlot(cityID:"plain",plot:plot,locked:true),&w) }
        try send(.acceptDevelopment(policy:.industry,investment:.active),&w)
        try GameEngine.advance(to:7*86_400,world:&w)
        #expect(w.growth!.cities["plain"]!.projects.isEmpty)
    }
    @Test func allZeroMaterialsCanRecover() throws {
        var w=GrowthRuntime.newGame(wallUTC:0)
        // Preserve any reserved batch inputs; here the initial batch has only free gathering.
        for r in Resource.allCases { w.cities["plain"]!.inventory[r]=0 }
        w.treasury=0
        try GameEngine.advance(to:7200,world:&w)
        #expect(w.cities["plain"]!.inventory[.grain]>0)
        #expect(w.cities["plain"]!.inventory[.wood]>0)
    }
    @Test func growthLedgerRoundTrip() throws {
        var w=try game();try GameEngine.advance(to:54321,world:&w)
        #expect(try SaveStore.decode(SaveStore.encode(w))==w)
    }
    @Test func oldSaveStillLoadsWithoutAutoMigration() throws {
        let old=Seed.oneCity(wallUTC:1000)
        let loaded=try SaveStore.decode(SaveStore.encode(old))
        #expect(loaded.growth==nil && loaded.rulesVersion=="core-0.1")
    }
    @Test func migrationPreservesAssetsAndPeople() throws {
        var old=Seed.oneCity(wallUTC:1000)
        let people=old.people,treasury=old.treasury,wood=old.cities["plain"]!.inventory[.wood]
        try send(.acceptDevelopment(policy:.supply,investment:.cautious),&old)
        #expect(old.people==people && old.treasury==treasury && old.cities["plain"]!.inventory[.wood]==wood)
        #expect(old.schemaVersion==2 && old.growth != nil)
    }
    @Test func repeatedAcceptanceDoesNotRefreshBudget() throws {
        var w=try game();let budget=w.growth!.finance.capital
        try send(.acceptDevelopment(policy:.trade,investment:.active),&w)
        #expect(w.growth!.finance.capital<=budget)
    }
    @Test func routinePauseDoesNotCancelOngoingWork() throws {
        var w=try game();try send(.pauseDevelopment(true),&w)
        let count=w.growth!.cities["plain"]!.projects.count
        try GameEngine.advance(to:86_400,world:&w)
        #expect(w.growth!.cities["plain"]!.projects.count==count)
        #expect(w.growth!.cities["plain"]!.completedCount>0)
    }
    @Test func noLegionWithoutConsent() throws {
        var w=try game(.military);try GameEngine.advance(to:15*86_400,world:&w)
        #expect(w.growth!.legion==nil)
    }
    @Test func armyIsNotInstantlyFull() throws {
        var w=try game();try send(.authorizeLegion(cityID:"plain",capacity:60,budget:1000),&w)
        #expect(w.growth!.legion!.active==0 && w.growth!.legion!.authorizedCapacity==60)
    }
    @Test func armySlowlyGrowsWithinTarget() throws {
        var w=try game();try send(.authorizeLegion(cityID:"plain",capacity:30,budget:1000),&w)
        try GameEngine.advance(to:15*86_400,world:&w)
        let legion=w.growth!.legion!
        #expect(legion.active>0 && legion.active<=30 && legion.spent<=1000)
        #expect(w.cities["plain"]!.inventory[.grain]>=0)
    }
    @Test func armyBudgetStopsWithoutDesertion() throws {
        var w=try game();try send(.authorizeLegion(cityID:"plain",capacity:90,budget:60),&w)
        try GameEngine.advance(to:10*86_400,world:&w)
        #expect(w.growth!.legion!.active<=5 && w.growth!.legion!.spent<=60)
        let n=w.growth!.legion!.active
        try GameEngine.advance(to:15*86_400,world:&w)
        #expect(w.growth!.legion!.active==n)
    }
    @Test func officialCannotApproveArmy() throws {
        var w=try game()
        #expect(throws:GameError.self) { try send(.authorizeLegion(cityID:"plain",capacity:90,budget:900),&w,principal:.person("npc-plain")) }
    }
    @Test func rejectsInvalidArmyCeiling() throws {
        var w=try game()
        #expect(throws:GameError.self) { try send(.authorizeLegion(cityID:"plain",capacity:10000,budget:900),&w) }
    }
    @Test func remembersActualHistoricalStates() throws {
        var w=try game();try GameEngine.advance(to:30*86_400,world:&w)
        let snapshots=w.growth!.memories
        let start=snapshots.first{$0.id=="origin-plain"}!
        let seven=snapshots.first{$0.id=="day-604800-plain"}!
        #expect(start.snapshot.time==0 && seven.snapshot.time==7*86_400)
        #expect(seven.snapshot.buildings != start.snapshot.buildings)
    }
    @Test func pinnedMemoriesDoNotAwardResources() throws {
        var w=try game();let cash=w.treasury,inventory=w.cities["plain"]!.inventory
        try send(.rememberCity(cityID:"plain"),&w)
        #expect(w.growth!.memories.filter(\.pinned).count==1)
        #expect(w.treasury==cash && w.cities["plain"]!.inventory==inventory)
    }
    @Test func pinnedMemoryCapacityDoesNotOverwrite() throws {
        var w=try game()
        for _ in 0..<20 { try send(.rememberCity(cityID:"plain"),&w) }
        let before=w
        #expect(throws:GameError.self) { try send(.rememberCity(cityID:"plain"),&w) }
        #expect(w==before)
    }
    @Test func newThirtyDayOfflineBoundary() throws {
        var w=try game()
        let r=try GameEngine.advance(to:40*86_400,world:&w)
        #expect(r.simulatedSeconds==30*86_400 && r.restedSeconds==10*86_400)
        #expect(w.growth!.normalGrowthSeconds==30*86_400 && w.lastWallUTC==40*86_400)
        let before=w;try GameEngine.advance(to:40*86_400,world:&w);#expect(w==before)
    }
    @Test func oneAndThreeDayViewingIdentical() throws {
        var a=try game(.trade),b=a
        for day in 1...9 { try GameEngine.advance(to:Int64(day)*86_400,world:&a) }
        for day in [3,6,9] { try GameEngine.advance(to:Int64(day)*86_400,world:&b) }
        #expect(a==b)
    }
    @Test func partialTimeStepsAreExactlyEquivalent() throws {
        var a=try game(),b=a
        try GameEngine.advance(to:7200,world:&a)
        for t in stride(from:Int64(17),through:7199,by:137) { try GameEngine.advance(to:t,world:&b) }
        try GameEngine.advance(to:7200,world:&b)
        #expect(a==b)
    }
    @Test func policyChangesConstructionOrder() throws {
        var a=try game(.trade),b=try game(.industry)
        try GameEngine.advance(to:2*86_400,world:&a);try GameEngine.advance(to:2*86_400,world:&b)
        let one=a.growth!.cities["plain"]!.projects.map(\.buildingID),two=b.growth!.cities["plain"]!.projects.map(\.buildingID)
        let buildingsA=a.growth!.cities["plain"]!.buildings,buildingsB=b.growth!.cities["plain"]!.buildings
        #expect(one != two || buildingsA != buildingsB)
    }
    @Test func proposalQueueDoesNotGrowPerCityOrPerViewing() throws {
        var w=try game();try GameEngine.advance(to:29*86_400,world:&w)
        #expect(w.growth!.proposals.count<=1)
        #expect(w.growth!.proposalTimes.count<=2)
    }
    @Test func corruptionInConstructionLedgerIsRejected() throws {
        var w=try game();w.growth!.cities["plain"]!.projects[0].cashSpent=999
        #expect(throws:GameError.self) { try w.validate() }
    }
    @Test func persistenceFailureDoesNotCommitConstruction() async throws {
        struct Bad:WorldPersistence { func save(_ world:WorldState)throws { throw GameError.invalid("disk") } }
        let w=GrowthRuntime.newGame(wallUTC:0),session=try GameSession(world:w,persistence:Bad())
        await #expect(throws:GameError.self) { try await session.send(.init(id:"accept",expectedRevision:0,action:.acceptDevelopment(policy:.trade,investment:.balanced))) }
        #expect(await session.snapshot()==w)
    }
}
