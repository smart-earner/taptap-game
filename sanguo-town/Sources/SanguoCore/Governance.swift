import Foundation

public enum Principal: Codable, Equatable, Sendable { case player, person(String) }
public enum PolicyScope: Codable, Equatable, Sendable { case realm, city(String), district(String) }
public enum GameAction: Codable, Equatable, Sendable {
    case realm(RealmAction)
    case setPolicy(scope: PolicyScope, policy: Policy)
    case acceptDevelopment(policy: Policy, investment: InvestmentStyle)
    case pauseDevelopment(Bool)
    case setInvestment(InvestmentStyle)
    case lockPlot(cityID: String, plot: Int, locked: Bool)
    case startBuilding(cityID: String, kind: BuildingKind, plot: Int)
    case pauseBuilding(cityID: String, projectID: String, paused: Bool)
    case cancelBuilding(cityID: String, projectID: String)
    case authorizeLegion(cityID: String, capacity: Int, budget: Int64)
    case rememberCity(cityID: String)
    case appointPrefect(cityID: String, personID: String)
    case establishDistrict(id: String, cityIDs: [String], governorID: String)
    case setPersonLock(personID: String, locked: Bool)
}
public struct GameCommand: Codable, Equatable, Sendable {
    public var id: String
    public var expectedRevision: Int64
    public var principal: Principal
    public var action: GameAction
    public init(id: String, expectedRevision: Int64, principal: Principal = .player, action: GameAction) {
        self.id = id; self.expectedRevision = expectedRevision
        self.principal = principal; self.action = action
    }
    func fingerprint() throws -> String {
        struct Body: Encodable { let principal: Principal; let action: GameAction }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(Body(principal: principal, action: action)), as: UTF8.self)
    }
}

enum Governance {
    static func mayManage(_ principal: Principal, cityID: String, prefectAllowed: Bool, world: WorldState) -> Bool {
        if principal == .player { return true }
        guard case .person(let id) = principal, let city = world.cities[cityID] else { return false }
        if prefectAllowed && city.prefectID == id { return true }
        return city.districtID.flatMap { world.districts[$0]?.governorID } == id
    }
    static func appoint(cityID: String, personID: String, principal: Principal, world: inout WorldState) throws {
        guard var city = world.cities[cityID], var person = world.people[personID] else { throw GameError.invalid("未知城市或人物") }
        guard mayManage(principal, cityID: cityID, prefectAllowed: false, world: world) else { throw GameError.denied("不在任免范围") }
        if principal != .player {
            guard let districtID = city.districtID, world.districts[districtID]?.talentIDs.contains(personID) == true else { throw GameError.denied("人才不在授权池") }
        }
        guard world.realm?.journeys.contains(where: { $0.personID == personID }) != true else {
            throw GameError.denied("人物在途，必须到任后才能任职")
        }
        if city.prefectID == personID { return }
        guard !person.locked && world.people[city.prefectID]?.locked != true else { throw GameError.denied("人物／职位已锁定，请先由主公解锁") }
        guard person.cityID == cityID else { throw GameError.unsupported("跨城调任需旅行与交接，不能瞬移") }
        guard person.office == nil else { throw GameError.denied("人物已有实际职位") }
        let oldID = city.prefectID
        world.people[oldID]?.office = nil
        person.office = .init(kind: .prefect, scope: cityID, since: world.simulationTime)
        city.prefectID = personID; city.lastAppointment = world.simulationTime
        world.people[personID] = person; world.cities[cityID] = city
        world.record("appointment", actor: personID, "\(person.name)已任\(city.name)太守，原任已完成同城交接。")
    }
    static func govern(world: inout WorldState) throws {
        for districtID in world.districts.keys.sorted() {
            let district = world.districts[districtID]!
            for cityID in district.cityIDs.sorted() {
                let city = world.cities[cityID]!, current = world.people[city.prefectID]!
                guard !current.locked && (current.isProxy || world.simulationTime - city.lastAppointment >= 14_400) else { continue }
                let travelling = Set(world.realm?.journeys.map(\.personID) ?? [])
                let candidates = district.talentIDs.compactMap { world.people[$0] }.filter {
                    $0.office == nil && !$0.locked && !travelling.contains($0.id) && $0.cityID == cityID && $0.prefectScore >= current.prefectScore + 15
                }.sorted { $0.prefectScore == $1.prefectScore ? $0.id < $1.id : $0.prefectScore > $1.prefectScore }
                if let chosen = candidates.first {
                    try appoint(cityID: cityID, personID: chosen.id, principal: .person(district.governorID), world: &world)
                }
            }
        }
    }
    static func plan(cityID: String, world: inout WorldState) {
        guard var city = world.cities[cityID] else { return }
        let policy = world.policy(for: city)
        var jobs: [String: Int] = [:], left = city.labor
        func assign(_ resource: Resource, _ wanted: Int) {
            let key = resource.rawValue
            let count = max(0, min(left, min(wanted, city.jobCapacity[key, default: 0] - jobs[key, default: 0])))
            if count > 0 { jobs[key, default: 0] += count; left -= count }
        }
        assign(.grain, 2)
        let urgent = city.inventory.free(.grain) < city.grainFloor
        let order: [Resource]
        if urgent { order = [.grain, .wood, .iron, .tools, .wine] }
        else {
            switch policy {
            case .supply: order = [.grain, .wood, .iron, .wine, .tools]
            case .trade: order = [.wine, .wood, .iron, .grain, .tools]
            case .industry, .military: order = [.tools, .wood, .iron, .grain, .wine]
            case .balanced: order = [.wood, .iron, .wine, .grain, .tools]
            }
        }
        for resource in order { assign(resource, city.jobCapacity[resource.rawValue, default: 0]) }
        if jobs != city.jobs {
            city.jobs = jobs; world.cities[cityID] = city
            let detail = jobs.keys.sorted().map { "\($0):\(jobs[$0]!)" }.joined(separator: "，")
            world.record("allocation", actor: city.prefectID, "\(city.name)按\(urgent ? "粮食底线" : policy.title)分工：\(detail)。")
        }
    }
}
