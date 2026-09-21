import Foundation

public enum LifeError: Error, Equatable, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
public enum LifeResource: String, Codable, CaseIterable, Sendable {
    case grain, meat, meal, rations, wood, stone, iron, tools, gold_ore, gold_ingot
    public var title: String { ["grain":"食粮","meat":"肉料","meal":"饭菜","rations":"军粮","wood":"木材","stone":"石材","iron":"铁料","tools":"器材","gold_ore":"金矿石","gold_ingot":"金锭"][rawValue]! }
    public var volume: Int64 { self == .meal || self == .rations ? 250 : (self == .wood || self == .stone ? 2000 : 1000) }
}
public struct LifeHero: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var starting: Bool
    public var attributes: [String: Int]
    public var skill_ids: [String]
    public var art_family: String?
    public var art: String?
}
public struct LifeEffect: Codable, Equatable, Sendable {
    public var metric: String
    public var value: Int
    public var event: String
    public var roles: [String]
    public var family: String
    public var jobs: [String]?
    public var requires_coverage_bp: Int?
}
public struct LifeSkill: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String
    public var effects: [LifeEffect]
}
public struct LifeRecipe: Codable, Sendable, Identifiable {
    public var id: String
    public var job: String
    public var station: String
    public var input_mU: [String: Int64]
    public var output_mU: [String: Int64]
    public var meal_quality: String?
    public var prepare_s: Int64
    public var passive_s: Int64
    public var finish_s: Int64
}
public struct LifeCropDefinition: Codable, Sendable, Identifiable {
    public var id: String
    public var sow_s: Int64
    public var water_work_s: Int64
    public var mature_s: Int64
    public var harvest_s: Int64
    public var output_mU: [String: Int64]
}
public struct LifeBuildingQuote: Codable, Sendable, Identifiable {
    public var id: String
    public var cash: Int64
    public var work_s: Int64
    public var materials_mU: [String: Int64]
    public var max: Int?
    public var capacity: [Int]?
}
public struct LifeRecruitment: Codable, Sendable {
    public struct Condition: Codable, Sendable {
        public let metric: String, op: String
        public let amount: Int
        public init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            metric = try c.decode(String.self); op = try c.decode(String.self)
            if let b = try? c.decode(Bool.self) { amount = b ? 1 : 0 } else { amount = try c.decode(Int.self) }
        }
        public func encode(to encoder: Encoder) throws { var c = encoder.unkeyedContainer(); try c.encode(metric); try c.encode(op); try c.encode(amount) }
    }
    public struct Stage: Codable, Sendable {
        public var name: String
        public var passive_s: Int64
        public var cash: Int64
        public var materials_mU: [String: Int64]
    }
    public var hero: String
    public var unlock: [Condition]
    public var stages: [Stage]
}
/// A compact, reproducibly generated copy of the resolved 0.7.2 configuration.
/// Every formula consumes IDs and data; no effect branches on a historical name.
public struct LifeCatalog: Decodable, Sendable {
    public var version: String
    public var heroes: [LifeHero]
    public var skills: [LifeSkill]
    public var recipes: [LifeRecipe]
    public var crops: [LifeCropDefinition]
    public var buildings: [LifeBuildingQuote]
    public var recruitment: [LifeRecruitment]
    public var weights: [String: [String: Int]]
    public var rates: [String: Int]
    public struct Metric: Decodable, Sendable { public var event: String; public var cap: Int; public var allowed_roles: [String] }
    public var metrics: [String: Metric]
    public static func bundled() throws -> LifeCatalog {
        // App bundles use an explicit resource location; do not depend on a CI build path.
        if let appURL=Bundle.main.url(forResource:"catalog",withExtension:"json",subdirectory:"Life072") {
            return try decode(Data(contentsOf:appURL))
        }
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else { throw LifeError.invalid("缺少生活版参数包") }
        return try decode(Data(contentsOf: url))
    }
    public static func decode(_ data: Data) throws -> LifeCatalog {
        let c = try JSONDecoder().decode(Self.self, from: data); try c.validate(); return c
    }
    public func validate() throws {
        guard version == "0.7.2", heroes.count == 30, Set(heroes.map(\.id)).count == 30,
              skills.count == 22, Set(skills.map(\.id)).count == 22,
              recipes.count == 4, Set(recipes.map(\.id)).count == 4,
              recruitment.count == 29, Set(recruitment.map(\.hero)).count == 29,
              weights.count == 20 else { throw LifeError.invalid("生活版目录数量或ID不合法") }
        let attributes = Set(["administration","strategy","valor","command"])
        for (_, w) in weights { guard Set(w.keys).isSubset(of: attributes), w.values.reduce(0,+) == 10000, w.values.allSatisfy({$0 > 0}) else { throw LifeError.invalid("工种权重不合法") } }
        for h in heroes {
            guard Set(h.attributes.keys) == attributes, h.attributes.values.allSatisfy({0...100 ~= $0}),
                  1...5 ~= h.skill_ids.count, Set(h.skill_ids).count == h.skill_ids.count,
                  h.skill_ids.allSatisfy({id in skills.contains{$0.id == id}}),
                  skills.filter({h.skill_ids.contains($0.id) && $0.kind == "signature"}).count <= 1 else { throw LifeError.invalid("人物四维或技能不合法：\(h.id)") }
        }
        for s in skills { for e in s.effects {
            guard let m = metrics[e.metric], m.event == e.event, e.value > 0, e.value <= m.cap,
                  !e.roles.isEmpty, Set(e.roles).isSubset(of: Set(m.allowed_roles)),
                  e.jobs?.allSatisfy({weights[$0] != nil}) ?? true else { throw LifeError.invalid("技能原语不合法：\(s.id)") }
        } }
        for r in recipes { guard r.prepare_s > 0, r.finish_s > 0, r.passive_s >= 0 else {throw LifeError.invalid("配方工时不合法")}
            for (key, qty) in r.input_mU.merging(r.output_mU, uniquingKeysWith: +) {
                guard LifeResource(rawValue: key) != nil, qty > 0, qty <= 1_000_000 else {throw LifeError.invalid("配方仍含废弃资源")}
            }
        }
    }
    public func hero(_ id: String) -> LifeHero? { heroes.first{$0.id == id} }
    public func recipe(_ id: String) -> LifeRecipe? { recipes.first{$0.id == id} }
}
public struct LifeAbilitySource: Sendable {
    public var id: String
    public var attributes: [String: Int]
    public var skills: [String]
    public var role: String
    public var eligible: Bool
    public init(_ h: LifeHero, role: String, eligible: Bool = false) {
        id=h.id; attributes=h.attributes; skills=h.skill_ids; self.role=role; self.eligible=eligible
    }
}
public enum LifeAbilities {
    public static func aptitude(_ attributes: [String:Int], weights: [String:Int]) -> Int { weights.reduce(0){$0 + attributes[$1.key,default:50] * $1.value} / 10000 }
    public static func resolve(_ c: LifeCatalog, sources: [LifeAbilitySource], metric: String, job: String? = nil, coverage: Int = 0) throws -> Int {
        guard let metadata = c.metrics[metric], Set(sources.map(\.id)).count == sources.count,
              Set(sources.map(\.role)).count == sources.count else { throw LifeError.invalid("重复角色或未知效果") }
        var families: [String:Int] = [:]
        for source in sources where source.eligible {
            guard Set(source.skills).count == source.skills.count else {throw LifeError.invalid("重复技能")}
            for id in source.skills {
                guard let skill = c.skills.first(where:{$0.id == id}) else {throw LifeError.invalid("未知技能")}
                for e in skill.effects where e.metric == metric && e.event == metadata.event && e.roles.contains(source.role) {
                    if let jobs=e.jobs, !jobs.contains(job ?? "") {continue}
                    guard coverage >= (e.requires_coverage_bp ?? 0) else {continue}
                    let value=e.value * (source.role == "governor" ? 5000 : 10000) / 10000
                    families[e.family]=max(families[e.family,default:0],value)
                }
            }
        }
        return min(metadata.cap,families.values.reduce(0,+))
    }
    public static func workRate(_ c: LifeCatalog, worker: LifeAbilitySource, job: String, leaders: [LifeAbilitySource] = [], level: Int = 1) throws -> Int {
        guard let w=c.weights[job], 1...5 ~= level, worker.role == "worker", leaders.allSatisfy({["prefect","governor"].contains($0.role)}) else {throw LifeError.invalid("工作角色不合法")}
        let personal=min(1000,max(0,aptitude(worker.attributes,weights:w)-50)*20)
        let leader=leaders.filter(\.eligible).map { s in min(500,max(0,aptitude(s.attributes,weights:w)-50)*10) * (s.role == "governor" ? 5000 : 10000) / 10000 }.max() ?? 0
        let skill=try resolve(c,sources:[worker]+leaders,metric:"work_rate_bp",job:job)
        return min(14000,max(8000,10000+personal+leader+skill+(level-1)*100))
    }
}
