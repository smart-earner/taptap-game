import Foundation
import Testing
@testable import SanguoCore

@Suite("City identity and explainable planning")
struct CityIdentityTests {
    func send(_ action: GameAction, _ w: inout WorldState, principal: Principal = .player) throws {
        try GameEngine.apply(.init(id:"identity-\(w.revision)", expectedRevision:w.revision,
                                   principal:principal, action:action), to:&w)
    }
    func game(_ policy:Policy = .balanced) throws -> WorldState {
        var w = Seed.oneCity(wallUTC:0)
        try send(.realm(.adoptIdentity(policy:policy,investment:.balanced)), &w)
        return w
    }
    func days(_ day:Int, _ w:inout WorldState, cadence:Int = 3) throws {
        while w.lastWallUTC < Int64(day)*86_400 {
            try GameEngine.advance(to:min(Int64(day)*86_400,w.lastWallUTC+Int64(cadence)*86_400),world:&w)
        }
    }
    @Test func legacyKeepsPlanningUntilConsent() throws {
        var w=Seed.oneCity(wallUTC:0)
        try send(.realm(.adopt(policy:.balanced,investment:.balanced)), &w)
        #expect(w.rulesVersion == "town-0.4" && w.realm!.identity == nil)
        let reloaded=try SaveStore.decode(SaveStore.encode(w))
        #expect(reloaded == w && reloaded.appearance(cityID:"plain")?.layoutVersion == nil)
    }
    @Test func adoptionPreservesPaidProjectsAndAssets() throws {
        var w=Seed.oneCity(wallUTC:0)
        try send(.realm(.adopt(policy:.balanced,investment:.balanced)), &w)
        try days(12,&w)
        let cash=w.treasury, people=w.people, cities=w.cities, civic=w.realm!.civic, memories=w.growth!.memories
        try send(.realm(.adoptIdentity(policy:.trade,investment:.balanced)), &w)
        #expect(w.treasury==cash && w.people==people && w.cities==cities && w.realm!.civic==civic)
        #expect(w.growth!.memories==memories && w.rulesVersion=="town-0.5" && w.schemaVersion==4)
        #expect(try SaveStore.decode(SaveStore.encode(w))==w)
    }
    @Test func officialCannotChangeSimulationRules() throws {
        var w=Seed.oneCity(wallUTC:0);let before=w
        #expect(throws:GameError.self) { try send(.realm(.adoptIdentity(policy:.trade,investment:.active)),&w,principal:.person(w.cities["plain"]!.prefectID)) }
        #expect(before==w)
    }
    @Test func repeatedAdoptionDoesNotResetBudget() throws {
        var w=try game();try days(3,&w);let finance=w.growth!.finance
        try send(.realm(.adoptIdentity(policy:.trade,investment:.active)),&w)
        #expect(w.growth!.finance==finance)
    }
    @Test func goalsKeepAllBasicServicesButSpecializeDepth() {
        for policy in Policy.allCases {
            let goals=CityIdentityRules.goals(for:policy)
            #expect(goals.count==8 && goals.values.allSatisfy{(1...3).contains($0)})
            #expect(goals.values.reduce(0,+)<24)
        }
        #expect(CityIdentityRules.goals(for:.trade)[.commerce]==3)
        #expect(CityIdentityRules.goals(for:.industry)[.commerce]==1)
        #expect(CityIdentityRules.goals(for:.supply)[.homes]==3)
    }
    @Test func waterDoesNotRequireStableOrTavern() throws {
        var w=try game(.supply)
        w.growth!.cities["plain"]!.buildings.append(.init(id:"test-market",kind:.market,plot:8,level:1,restored:true,completedAt:0))
        let c=CityIdentityPlanner.candidates(city:"plain",world:w)
        #expect(c.first{$0.track == .water}?.prerequisite == nil)
        #expect(c.first{$0.track == .homes}?.prerequisite == nil)
        #expect(c.first{$0.track == .industry}?.prerequisite != nil)
    }
    @Test func shortageChangesLegalPriority() throws {
        var w=try game(.trade)
        w.growth!.cities["plain"]!.buildings.append(.init(id:"test-market",kind:.market,plot:8,level:1,restored:true,completedAt:0))
        w.cities["plain"]!.inventory[.grain]=0
        #expect(CityIdentityPlanner.candidates(city:"plain",world:w).first?.track == .water)
    }
    @Test func capCompletedDoesNotKeepBlockingBuildings() throws {
        var w=try game(.trade)
        w.realm!.civic["plain"]!.levels=Dictionary(uniqueKeysWithValues:CityIdentityRules.goals(for:.trade).map{($0.key.rawValue,$0.value)})
        #expect(CityIdentityPlanner.candidates(city:"plain",world:w).isEmpty)
        #expect(!CityIdentityPlanner.reserveForCivic(city:"plain",world:w))
    }
    @Test func policyDoesNotDemolishOrRepaintCompletedAssets() throws {
        var w=try game(.trade);try days(30,&w)
        let built=w.realm!.civic["plain"]!.levels, project=w.realm!.civic["plain"]!.project, buildings=w.growth!.cities["plain"]!.buildings
        try send(.setPolicy(scope:.realm,policy:.supply),&w)
        #expect(w.realm!.civic["plain"]!.levels==built && w.growth!.cities["plain"]!.buildings==buildings)
        if let project { #expect(w.realm!.civic["plain"]!.project == project) }
    }
    @Test func trajectoriesDifferAtNinetyDays() throws {
        var trade=try game(.trade), industry=try game(.industry)
        try days(90,&trade);try days(90,&industry)
        #expect(trade.realm!.civic["plain"]!.levels != industry.realm!.civic["plain"]!.levels)
        #expect(trade.realm!.civic["plain"]!.level(.commerce) > industry.realm!.civic["plain"]!.level(.commerce))
        #expect(industry.realm!.civic["plain"]!.level(.industry) > trade.realm!.civic["plain"]!.level(.industry))
    }
    @Test func viewingCadenceRemainsEquivalent() throws {
        var a=try game(.supply), b=try game(.supply)
        try days(90,&a,cadence:1);try days(90,&b,cadence:7)
        #expect(a==b)
    }
    @Test func tracesOnlyDescribeCommittedOrCompletedProjects() throws {
        var w=try game(.industry);try days(45,&w)
        let records=w.realm!.identity!.traces["plain",default:[]]
        #expect(!records.isEmpty && records.count<=12)
        for record in records {
            #expect(record.policy == .industry && w.people[record.officialID] != nil)
            if record.completedAt != nil { #expect(w.realm!.civic["plain"]!.level(record.track)>=record.level) }
        }
    }
    @Test func oldSnapshotsRemainAtTheirOriginalLayout() throws {
        var w=try game();try days(7,&w)
        #expect(w.growth!.memories.first?.snapshot.layoutVersion == nil)
        #expect(w.appearance(cityID:"plain")?.layoutVersion==2)
    }
    @Test func migrationCannotBeReversedByVersionString() throws {
        var w=try game();w.schemaVersion=3;w.rulesVersion=RealmRules.version
        #expect(throws:GameError.self) { try w.validate() }
    }
}
