import Foundation

/// A consented rules revision. Legacy saves retain their existing planning and visual layout.
public enum CityIdentityRules {
    public static let version = "town-0.5"
    public static let historyLimit = 12
    public static func goals(for policy: Policy) -> [CivicTrack: Int] {
        var goals = Dictionary(uniqueKeysWithValues: CivicTrack.allCases.map { ($0, 1) })
        let focus: [CivicTrack]
        switch policy {
        case .supply: focus = [.water, .homes, .gardens]
        case .trade: focus = [.commerce, .streets, .academy]
        case .industry: focus = [.industry, .water, .streets]
        case .military: focus = [.ramparts, .industry, .streets]
        case .balanced: focus = [.streets, .water, .homes, .commerce]
        }
        for track in focus { goals[track] = policy == .balanced ? 2 : 3 }
        return goals
    }
    public static func requirement(_ track: CivicTrack) -> BuildingKind {
        switch track {
        case .water: .farm
        case .homes, .gardens: .house
        case .commerce: .market
        case .industry: .workshop
        case .streets, .academy, .ramparts: .hall
        }
    }
    public static func quote(_ track: CivicTrack, level: Int) -> CivicQuote {
        let tier = min(3, max(1, level))
        let base: Int64 = switch track {
        case .water, .homes: 1_400
        case .streets, .gardens: 1_600
        default: 1_800
        }
        let cost = tier == 1 ? base : tier == 2 ? 3_000 : 4_000
        let days: Int64 = tier == 1 ? 2 : tier == 2 ? 6 : 12
        let metal: Int64 = [.water, .homes, .gardens].contains(track) ? 25 : 60
        let tools: Int64 = track == .industry ? 12 : 8
        return .init(cash: cost, materials: ["wood": 100_000 * Int64(tier),
                     "iron": metal * 1_000 * Int64(tier), "tools": tools * 1_000 * Int64(tier)],
                     work: days * RealmRules.day * 2)
    }
}
public struct CivicQuote: Equatable, Sendable {
    public let cash: Int64
    public let materials: [String: Int64]
    /// Person-seconds. Two actual assigned workers achieve the nominal quoted duration.
    public let work: Int64
}
public struct CityPlanTrace: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var time: Int64
    public var policy: Policy
    public var policyVersion: Int
    public var officialID: String
    public var track: CivicTrack
    public var level: Int
    public var reason: String
    public var alternative: String
    public var committedCash: Int64
    public var completedAt: Int64? = nil
}
public struct CityIdentityState: Codable, Equatable, Sendable {
    public var version = 1
    public var adoptedAt: Int64
    public var traces: [String: [CityPlanTrace]] = [:]
}
public struct CivicCandidate: Sendable {
    public var track: CivicTrack
    public var level: Int
    public var score: Int
    public var reason: String
    public var prerequisite: String?
    public var quote: CivicQuote { CityIdentityRules.quote(track, level: level) }
}

/// Finite, deterministic candidate comparison. It never fabricates inventory or asks for daily approval.
public enum CityIdentityPlanner {
    public static func candidates(city id: String, world: WorldState) -> [CivicCandidate] {
        guard let city = world.cities[id], let plan = world.growth?.cities[id],
              let civic = world.realm?.civic[id] else { return [] }
        let policy = world.policy(for: city)
        let goals = CityIdentityRules.goals(for: policy)
        let order = CivicTrack.order(for: policy)
        return CivicTrack.allCases.compactMap { track -> CivicCandidate? in
            let next = civic.level(track) + 1
            guard next <= goals[track, default: 1] else { return nil }
            let building = CityIdentityRules.requirement(track)
            var blocker = plan.level(building) == 0 ? "需先建成\(building.title)" : nil
            // A real income channel is a solvency requirement, not an all-facilities unlock.
            if plan.level(.market) == 0 { blocker = "先建立集市收入，保留开局发展资金" }
            let rank = order.firstIndex(of: track) ?? 7
            var score = 80 - rank * 4 - (next - 1) * 12
            var reasons = ["按\(policy.title)方向，目标\(goals[track, default: 1])阶段"]
            if civic.level(track) == 0 { score += 12; reasons.append("补齐本项基础服务") }
            if track == .water, city.inventory.free(.grain) < city.grainFloor * 2 {
                score += 70; reasons.append("粮食覆盖偏低，先改善农桑供给")
            }
            if track == .homes, plan.housing <= city.population + 2 {
                score += 45; reasons.append("住房余量不足，先腾出安居空间")
            }
            if track == .industry, city.inventory.free(.tools) < 12_000 {
                score += 25; reasons.append("器材存量偏低，完善工造供应")
            }
            if track == .ramparts, world.growth?.legion?.cityID == id {
                score += 18; reasons.append("配合已批准的本城军团，不新增战争授权")
            }
            return .init(track: track, level: next, score: score,
                         reason: reasons.joined(separator: "；"), prerequisite: blocker)
        }.sorted { a, b in
            a.score == b.score ? a.track.rawValue < b.track.rawValue : a.score > b.score
        }
    }
    static func urgentBuilding(city id: String, world: WorldState) -> Bool {
        guard let city = world.cities[id], let plan = world.growth?.cities[id] else { return true }
        return plan.level(.market) == 0 || city.inventory.free(.grain) < city.grainFloor ||
            plan.housing <= city.population ||
            (world.growth?.legion?.cityID == id && plan.level(.barracks) == 0)
    }
    static func reserveForCivic(city id: String, world: WorldState) -> Bool {
        guard world.realm?.civic[id]?.project == nil, !urgentBuilding(city: id, world: world) else { return false }
        // Do not lock the whole town behind an unavailable facility or a completed profile.
        return candidates(city: id, world: world).contains { $0.prerequisite == nil }
    }
    public static func summary(city id: String, world: WorldState) -> String {
        guard let plan = world.growth?.cities[id], let civic = world.realm?.civic[id] else { return "尚未启用街区治理" }
        if world.growth?.enabled != true { return "暂停新增规划；已开工事务按原约定处理" }
        if let project = civic.project {
            return project.paused ? "此街区工程已暂停，进度与预留保留" :
                "执行\(project.track.title)第\(project.level)阶段；\(project.workers)人施工，不需逐项批准"
        }
        let choices = candidates(city: id, world: world)
        guard let next = choices.first(where: { $0.prerequisite == nil }) else {
            return choices.isEmpty ? "现行方向的街区目标已完成；保持稳定经营，转型由主公决定" :
                choices.first?.prerequisite ?? "等待相关设施"
        }
        if world.growth!.finance.capital < next.quote.cash {
            return "为\(next.track.title)积累发展额度；普通生产继续，不追加税费"
        }
        if GrowthRuntime.freeCash(world) < next.quote.cash {
            return "自由资金不足；尊重民生储备和已承诺工程"
        }
        if next.quote.materials.contains(where: { key, amount in
            guard let resource = Resource(rawValue: key) else { return true }
            return world.cities[id]!.inventory.free(resource) < amount
        }) { return "为\(next.track.title)备料；太守比较可行替代，不要求手动采购" }
        return plan.projects.filter(\.live).count > 0 ? "普通建设与街区工程共享劳力" : "等待下一次定时规划"
    }
}

public enum CityIdentityRuntime {
    static func adopt(policy: Policy, investment: InvestmentStyle, world: inout WorldState) throws {
        if world.realm == nil {
            try RealmRuntime.handle(.adopt(policy: policy, investment: investment), principal: .player, world: &world)
        }
        guard world.realm!.identity == nil else {
            // Reusing the consent action from the paused-governance panel resumes the
            // existing plan; it must not reset the budget, policy or paid contracts.
            world.growth!.enabled = true
            return
        }
        world.policy = policy
        world.growth!.enabled = true
        world.growth!.investment = investment
        world.growth!.policyVersion += 1
        world.realm!.identity = .init(adoptedAt: world.simulationTime)
        world.schemaVersion = 4; world.rulesVersion = CityIdentityRules.version
        world.record("identity_adopt", "启用城市特色与分区布局；原有建筑、街区、在建工程和收藏保留，不追溯重算旧收益。")
        // No new projects are executed here: adoption itself neither spends money nor grants a refund.
    }
    static func manage(world: inout WorldState) {
        for id in world.cities.keys.sorted() {
            guard world.realm!.civic[id]?.project == nil else { continue }
            let choices = CityIdentityPlanner.candidates(city: id, world: world)
            for candidate in choices where candidate.prerequisite == nil {
                let q = candidate.quote
                guard world.growth!.finance.capital >= q.cash,
                      GrowthRuntime.freeCash(world) >= q.cash else { continue }
                // Compare a complete funding plan before committing purchases. A rejected candidate
                // cannot spend on half its materials then switch to another project in the same tick.
                var draft = world
                draft.growth!.finance.protectedOperating = q.cash
                GrowthRuntime.purchaseShortfall(id, materials: q.materials, world: &draft)
                draft.growth!.finance.protectedOperating = 0
                guard q.materials.allSatisfy({ key, amount in
                    guard let r = Resource(rawValue: key) else { return false }
                    return draft.cities[id]!.inventory.free(r) >= amount
                }) else { continue }
                for (key, amount) in q.materials { draft.cities[id]!.inventory.reserved[key, default: 0] += amount }
                draft.realm!.civic[id]!.project = .init(track: candidate.track, level: candidate.level,
                    startedAt: draft.simulationTime, requiredWork: q.work, cash: q.cash, materials: q.materials)
                draft.growth!.finance.capital -= q.cash
                let alternative = choices.first(where: { $0.track != candidate.track }).map {
                    "\($0.track.title)：\($0.prerequisite ?? "后续比较，未承诺资源")"
                } ?? "本方向没有其他待建街区"
                let trace = CityPlanTrace(id: "\(id)-\(candidate.track.rawValue)-\(candidate.level)-\(draft.simulationTime)",
                    time: draft.simulationTime, policy: draft.policy(for: draft.cities[id]!),
                    policyVersion: draft.growth!.policyVersion, officialID: draft.cities[id]!.prefectID,
                    track: candidate.track, level: candidate.level, reason: candidate.reason,
                    alternative: alternative, committedCash: q.cash)
                var history = draft.realm!.identity!.traces[id, default: []]
                history.append(trace)
                if history.count > CityIdentityRules.historyLimit { history.removeFirst(history.count - CityIdentityRules.historyLimit) }
                draft.realm!.identity!.traces[id] = history
                draft.record("civic_plan", actor: trace.officialID,
                             "\(draft.cities[id]!.name)：\(candidate.reason)。已预留\(q.cash)铜，开工\(candidate.track.title)第\(candidate.level)阶段。")
                world = draft
                break
            }
        }
    }
    static func completed(city: String, project: CivicProject, world: inout WorldState) {
        guard var traces = world.realm?.identity?.traces[city],
              let index = traces.lastIndex(where: { $0.track == project.track && $0.level == project.level && $0.time == project.startedAt }) else { return }
        traces[index].completedAt = world.simulationTime
        world.realm!.identity!.traces[city] = traces
    }
    static func validate(_ world: WorldState) throws {
        guard let state = world.realm?.identity else { return }
        guard state.version == 1, (0...world.simulationTime).contains(state.adoptedAt),
              Set(state.traces.keys).isSubset(of: Set(world.cities.keys)) else { throw GameError.invalid("城市特色版本／归属") }
        for (city, traces) in state.traces {
            guard traces.count <= CityIdentityRules.historyLimit, Set(traces.map(\.id)).count == traces.count else { throw GameError.invalid("规划履历容量／重复") }
            for trace in traces {
                guard (state.adoptedAt...world.simulationTime).contains(trace.time), (1...3).contains(trace.level),
                      trace.policyVersion <= world.growth!.policyVersion, trace.policyVersion >= 0,
                      world.people[trace.officialID] != nil, trace.reason.count <= 500,
                      trace.alternative.count <= 200, (1...4_000).contains(trace.committedCash) else { throw GameError.invalid("规划履历内容") }
                if let end = trace.completedAt {
                    guard (trace.time...world.simulationTime).contains(end),
                          world.realm!.civic[city]!.level(trace.track) >= trace.level else { throw GameError.invalid("规划结果未实际完成") }
                }
            }
        }
    }
}
