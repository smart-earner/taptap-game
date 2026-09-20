import Foundation
import Testing
@testable import SanguoCore

@Suite("Town integration and safety")
struct RealmTests {
    func game(_ policy: Policy = .balanced) throws -> WorldState {
        var w = GrowthRuntime.newGame(wallUTC: 0)
        try send(.realm(.adopt(policy:policy,investment:.balanced)), &w)
        return w
    }
    func send(_ action: GameAction, _ w: inout WorldState, principal: Principal = .player) throws {
        try GameEngine.apply(.init(id:"realm-\(w.revision)",expectedRevision:w.revision,principal:principal,action:action),to:&w)
    }
    func days(_ count: Int, _ w: inout WorldState, cadence: Int = 3) throws {
        let end = Int64(count)*86_400
        while w.lastWallUTC < end { try GameEngine.advance(to:min(end,w.lastWallUTC+Int64(cadence)*86_400),world:&w) }
    }
    @Test func requiresExplicitAdoptionAndPreservesAssets() throws {
        var w = Seed.oneCity(wallUTC:0)
        let people = w.people, cash = w.treasury, inventory = w.cities["plain"]!.inventory.amounts
        try send(.realm(.adopt(policy:.balanced,investment:.balanced)),&w)
        #expect(w.people == people && w.treasury == cash && w.cities["plain"]!.inventory.amounts == inventory)
        #expect(w.schemaVersion == 3 && w.realm != nil && w.growth != nil)
        #expect(try SaveStore.decode(SaveStore.encode(w)) == w)
    }
    @Test func ordinaryOfficialsCannotAdoptOrSpendOnCollections() throws {
        var w = try game(); let old = w
        #expect(throws:GameError.self) { try send(.realm(.collection("zhaoyun")),&w,principal:.person(w.cities["plain"]!.prefectID)) }
        #expect(w == old)
    }
    @Test func readoptionDoesNotDuplicateCivicState() throws {
        var w = try game(); try days(12,&w); let original=w.realm
        try send(.realm(.adopt(policy:.trade,investment:.cautious)),&w)
        #expect(w.realm?.civic == original?.civic)
        #expect(w.realm?.civicCashSpent == original?.civicCashSpent)
    }
    @Test func threeMonthTownKeepsDevelopingBeyondFirstMonth() throws {
        var w = try game(); try days(30,&w); let first=w.realm!.civicCount
        try days(60,&w); let second=w.realm!.civicCount
        try days(90,&w)
        #expect(first > 0 && second > first && w.realm!.civicCount > second)
        #expect(w.realm!.civic["plain"]!.levels.values.allSatisfy{ (1...3).contains($0) })
    }
    @Test func townViewingFrequencyDoesNotChangeState() throws {
        var a = try game(), b = try game()
        try days(31,&a,cadence:1); try days(31,&b,cadence:7)
        #expect(a == b)
    }
    @Test func civicSharesWorkforceAndReservations() throws {
        var w = try game(); try days(12,&w)
        let c = w.cities["plain"]!, plan=w.growth!.cities["plain"]!, civic=w.realm!.civic["plain"]!
        #expect(c.jobs.values.reduce(0,+)+plan.builders+civic.workers <= c.labor)
        #expect(civic.project != nil || civic.levelTotal > 0)
        try w.validate()
    }
    @Test func pausedCivicDoesNotAdvance() throws {
        var w = try game(); try days(12,&w)
        guard let p=w.realm!.civic["plain"]!.project else { Issue.record("Fixture has no civic project"); return }
        try send(.realm(.pauseCivic(city:"plain",paused:true)),&w)
        try days(13,&w)
        #expect(w.realm!.civic["plain"]!.project?.work == p.work)
        #expect(w.realm!.civic["plain"]!.project?.workers == 0)
    }
    @Test func civicReservationCorruptionRejected() throws {
        var w = try game(); try days(12,&w)
        w.cities["plain"]!.inventory.reserved["wood",default:0] += 1
        #expect(throws:GameError.self) { try w.validate() }
    }
    @Test func legacySchemaCannotContainOrphanRealm() throws {
        var w = try game(); w.growth=nil; w.schemaVersion=1; w.rulesVersion=WorldState.currentRules
        #expect(throws:GameError.self) { try w.validate() }
    }
    @Test func collectionHasNoWarDependencyAndCannotRepeatReward() throws {
        var w=try game(); try send(.realm(.collection("zhaoyun")),&w); try days(7,&w)
        #expect(w.people["zhaoyun"] != nil && w.realm!.collections["zhaoyun"]?.completedAt != nil)
        #expect(w.realm!.operation == nil && w.growth!.legion == nil)
        let old=w
        #expect(throws:GameError.self) { try send(.realm(.collection("zhaoyun")),&w) }
        #expect(old == w)
    }
    @Test func changingWishDoesNotCancelPaidStage() throws {
        var w=try game(); try days(7,&w); try send(.realm(.collection("zhaoyun")),&w)
        let due=w.realm!.collections["zhaoyun"]!.dueAt
        try send(.realm(.collection("xunyu")),&w)
        #expect(w.realm!.collections["zhaoyun"]!.dueAt == due)
        #expect(w.realm!.collections.values.filter{$0.dueAt != nil}.count == 1)
        try GameEngine.advance(to:w.lastWallUTC+86_400,world:&w)
        #expect(w.realm!.collections["zhaoyun"]!.stage >= 1)
    }
    @Test func invalidEquipmentRollsBack() throws {
        var w=try game(); let old=w
        #expect(throws:GameError.self) { try send(.realm(.equip(item:"red-hare",person:w.cities["plain"]!.prefectID)),&w) }
        #expect(w == old)
    }
    @Test func growthStillLoadsWithoutRealm() throws {
        let w=GrowthRuntime.newGame(wallUTC:0)
        let restored=try SaveStore.decode(SaveStore.encode(w))
        #expect(restored.realm == nil && restored.schemaVersion == 2)
    }
    @Test func thirtyDayCapCannotStartAnInfiniteCivicChain() throws {
        var w=try game(); try GameEngine.advance(to:90*86_400,world:&w)
        #expect(w.growth!.normalGrowthSeconds == 30*86_400)
        let prior=w; try GameEngine.advance(to:90*86_400,world:&w)
        #expect(prior == w)
        try w.validate()
    }
    @Test func collectionCatalogueIsCompleteAndHasExplicitCosts() {
        #expect(CollectionCatalog.all.count == 16)
        #expect(Set(CollectionCatalog.all.map(\.id)).count == 16)
        #expect(CollectionCatalog.all.allSatisfy{ $0.totalCash>0 && $0.totalHours>0 && !$0.stages.isEmpty })
    }
    @Test func travelCannotBeReappointedOrDuplicated() throws {
        var w=Seed.threeCityDemo(wallUTC:0)
        try send(.realm(.adopt(policy:.balanced,investment:.balanced)),&w)
        let candidates=w.people.values.filter{$0.office == nil && !$0.isProxy && $0.cityID=="plain"}
        guard let p=candidates.first else { Issue.record("No travelling fixture person");return }
        try send(.realm(.movePerson(person:p.id,destination:"stone")),&w)
        #expect(throws:GameError.self) { try send(.appointPrefect(cityID:"plain",personID:p.id),&w) }
        #expect(throws:GameError.self) { try send(.realm(.movePerson(person:p.id,destination:"river")),&w) }
        try GameEngine.advance(to:4*3600,world:&w)
        #expect(w.people[p.id]!.cityID == "stone" && w.realm!.journeys.isEmpty)
    }
    @Test func earlyWishCannotStarveFirstMarket() throws {
        var w=try game(); try send(.realm(.collection("zhaoyun")),&w); try days(7,&w)
        #expect(w.growth!.cities["plain"]!.level(.market)>0)
        #expect(w.realm!.collections["zhaoyun"]?.completedAt != nil)
    }
    @Test func collectionOnlyChargesPublishedTotal() throws {
        var w=try game(); try days(10,&w)
        try send(.realm(.collection("silver-spear")),&w); try days(20,&w)
        let item=CollectionCatalog.item("silver-spear")!
        #expect(w.realm!.collections[item.id]?.spent == item.totalCash)
        #expect(w.realm!.collections[item.id]?.completedAt != nil)
        let person=w.cities["plain"]!.prefectID
        try send(.realm(.equip(item:item.id,person:person)),&w)
        #expect(w.realm!.equipment[item.id] == person)
        try send(.realm(.equip(item:item.id,person:nil)),&w)
        #expect(w.realm!.equipment[item.id] == nil)
    }
    @Test func paidCollectionStageSurvivesSaveAndReload() throws {
        var w=try game(); try days(7,&w);try send(.realm(.collection("xunyu")),&w)
        var restored=try SaveStore.decode(SaveStore.encode(w))
        try days(14,&w);try days(14,&restored)
        #expect(w == restored)
    }
    @Test func regionalAgreementPaysOnceAndDoesNotResetTreasury() throws {
        var w=try game();try days(15,&w)
        let goal=RegionalGoal.mountainTrade
        let cash=w.treasury
        try send(.realm(.regional(goal)),&w)
        #expect(w.treasury == cash-goal.cash)
        let old=w
        #expect(throws:GameError.self){try send(.realm(.regional(goal)),&w)}
        #expect(w == old)
        try days(18,&w)
        #expect(w.realm!.completedGoals.contains(goal.rawValue))
        #expect(w.growth!.legion == nil)
    }
    @Test func cooperationAddsCityOnlyAfterCompletion() throws {
        var w=try game();try days(20,&w)
        try send(.realm(.regional(.settleStone)),&w)
        #expect(w.cities.count == 1)
        try days(24,&w)
        #expect(w.cities.count == 2 && w.cities["stone"]?.prefectID == "npc-stone")
        #expect(w.realm!.civic["stone"] != nil)
        try w.validate()
    }
    @Test func noMilitaryWithoutExplicitArmyAndGoal() throws {
        var w=try game();try days(15,&w);let old=w
        #expect(throws:GameError.self){try send(.realm(.regional(.securePass)),&w)}
        #expect(w == old && w.realm!.operation == nil)
    }
    @Test func civicPolicyChangesRealOrder() throws {
        var a=try game(.trade), b=try game(.industry)
        try days(25,&a);try days(25,&b)
        #expect(a.realm!.civic["plain"]!.completedAt != b.realm!.civic["plain"]!.completedAt)
    }
    @Test func removingPinnedMemoryDoesNotTouchEconomy() throws {
        var w=try game();try send(.rememberCity(cityID:"plain"),&w)
        let memory=w.growth!.memories.first{$0.pinned}!, cash=w.treasury
        try send(.realm(.removeMemory(memory.id)),&w)
        #expect(w.treasury == cash && !w.growth!.memories.contains{$0.id==memory.id})
        let milestone=w.growth!.memories.first!.id
        #expect(throws:GameError.self){try send(.realm(.removeMemory(milestone)),&w)}
    }
}
