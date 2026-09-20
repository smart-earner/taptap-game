import Foundation

public struct AdvanceResult: Equatable, Sendable {
    public let simulatedSeconds: Int64
    public let restedSeconds: Int64
    public let tickCount: Int
}
public enum GameEngine {
    public static let offlineLimit: Int64 = 7 * 24 * 3600
    @discardableResult
    public static func apply(_ command: GameCommand, to world: inout WorldState) throws -> Receipt {
        try world.validate()
        guard !command.id.isEmpty, command.id.count <= 80 else { throw GameError.invalid("命令ID") }
        let fingerprint = try command.fingerprint()
        guard fingerprint.utf8.count <= 4096 else { throw GameError.invalid("命令过大") }
        if let previous = world.receipts[command.id] {
            guard previous.fingerprint == fingerprint else { throw GameError.duplicateID }
            return previous
        }
        guard command.expectedRevision == world.revision else { throw GameError.stale }
        guard world.receipts.count < 10_000 else { throw GameError.invalid("原型命令账本已达上限") }
        var draft = world
        switch command.action {
        case .setPolicy(let scope, let policy):
            switch scope {
            case .realm:
                guard command.principal == .player else { throw GameError.denied("全势力方针由主公决定") }
                draft.policy = policy
            case .city(let id):
                guard draft.cities[id] != nil else { throw GameError.invalid("未知城市") }
                guard Governance.mayManage(command.principal, cityID: id, prefectAllowed: true, world: draft) else { throw GameError.denied("城市方针范围") }
                draft.cities[id]?.policy = policy
            case .district(let id):
                guard let district = draft.districts[id] else { throw GameError.invalid("未知辖区") }
                guard command.principal == .player || command.principal == .person(district.governorID) else { throw GameError.denied("辖区方针范围") }
                draft.districts[id]?.policy = policy
            }
            if draft.growth == nil {
                for id in draft.cities.keys.sorted() { Governance.plan(cityID: id, world: &draft) }
            } else {
                draft.growth!.policyVersion += 1
                try GrowthRuntime.manage(world: &draft)
            }
            draft.record("policy", "施政方针已更新为\(policy.title)，不会因时间经过而到期。")
        case .appointPrefect(let cityID, let personID):
            try Governance.appoint(cityID: cityID, personID: personID, principal: command.principal, world: &draft)
        case .establishDistrict(let id, let cityIDs, let governorID):
            guard command.principal == .player else { throw GameError.denied("设都督辖区需主公决定") }
            guard !id.isEmpty, id.count <= 80, draft.districts.isEmpty, (2...3).contains(cityIDs.count), Set(cityIDs).count == cityIDs.count,
                  cityIDs.allSatisfy({ draft.cities[$0] != nil && draft.cities[$0]?.districtID == nil }) else { throw GameError.invalid("辖区范围") }
            guard var governor = draft.people[governorID], governor.office == nil, !governor.locked,
                  cityIDs.contains(governor.cityID) else { throw GameError.denied("都督需空闲、未锁定且已在辖区") }
            governor.office = .init(kind: .governor, scope: id, since: draft.simulationTime)
            draft.people[governorID] = governor
            draft.districts[id] = .init(id: id, cityIDs: cityIDs.sorted(), governorID: governorID,
                talentIDs: draft.people.values.filter { cityIDs.contains($0.cityID) }.map(\.id).sorted())
            for cityID in cityIDs { draft.cities[cityID]?.districtID = id }
            draft.record("district", actor: governorID, "\(governor.name)已任都督，辖\(cityIDs.count)城；可在授权人才池内任用太守。")
        case .setPersonLock(let id, let locked):
            guard command.principal == .player else { throw GameError.denied("只有主公可改人物锁定") }
            guard draft.people[id] != nil else { throw GameError.invalid("未知人物") }
            draft.people[id]?.locked = locked
        default:
            try GrowthRuntime.handle(command.action, principal:command.principal, world:&draft)
        }
        draft.revision += 1
        let receipt = Receipt(fingerprint: fingerprint, revision: draft.revision)
        draft.receipts[command.id] = receipt
        try draft.validate(); world = draft
        return receipt
    }
    @discardableResult
    public static func advance(to wallUTC: Int64, world: inout WorldState) throws -> AdvanceResult {
        try world.validate()
        guard (0...4_000_000_000_000).contains(wallUTC) else { throw GameError.invalid("输入时钟") }
        guard wallUTC > world.lastWallUTC else { return .init(simulatedSeconds: 0, restedSeconds: 0, tickCount: 0) }
        if world.growth != nil { return try GrowthRuntime.advance(to: wallUTC, world:&world) }
        let elapsed = wallUTC - world.lastWallUTC
        let active = min(elapsed, offlineLimit), target = world.simulationTime + active
        guard target <= 31_536_000_000 else { throw GameError.invalid("模拟时钟已达上限") }
        var draft = world, ticks = 0
        var next = (draft.simulationTime / 600 + 1) * 600
        while next <= target {
            draft.simulationTime = next
            Economy.tick(world: &draft)
            if next % 3600 == 0 { try Governance.govern(world: &draft) }
            for id in draft.cities.keys.sorted() {
                if next % 1800 == 0 || draft.cities[id]!.jobs.isEmpty || draft.cities[id]!.inventory.free(.grain) < draft.cities[id]!.grainFloor {
                    Governance.plan(cityID: id, world: &draft)
                }
            }
            draft.revision += 1; ticks += 1; next += 600
        }
        draft.simulationTime = target; draft.lastWallUTC = wallUTC
        if elapsed > active { draft.record("rest", "正常结算七天，其余时间安全休整；同一现实区间不会重复补算。") }
        try draft.validate(); world = draft
        return .init(simulatedSeconds: active, restedSeconds: elapsed - active, tickCount: ticks)
    }
}
