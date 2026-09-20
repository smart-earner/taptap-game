import Foundation

public enum LifeError: Error, LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let s) = self { return s }; return nil }
}

public struct LifeRules: Codable, Sendable {
    public struct Clock: Codable, Sendable { public let cycle, dawnEnd, dayEnd, duskEnd, planning: Int64; public let meals: [Int64]; public let mealGrace, eatSeconds, offlineLimit: Int64 }
    public struct Movement: Codable, Sendable { public let emptySpeed, loadedSpeed: Double; public let loadSeconds, unloadSeconds: Int64; public let roadY: Double }
    public struct Limits: Codable, Sendable { public let people, activeTasks, taskQueue, history, storePerResource: Int }
    public struct Resource: Codable, Sendable { public let id, name, unit: String; public let carry: Int }
    public struct Crop: Codable, Sendable { public let id, name: String; public let sow, grow, harvest: Int64; public let inputs, outputs: [String:Int] }
    public struct Recipe: Codable, Sendable { public let id, name, job, facility, stage: String; public let work, passive: Int64; public let inputs, outputs: [String:Int] }
    public struct Facility: Codable, Sendable { public let id, name: String; public let x, y: Double }
    public struct Start: Codable, Sendable { public let population, treasury, housing: Int; public let roles: [String]; public let stocks: [String:[String:Int]]; public let farmCrops: [String:String] }
    public struct Construction: Codable, Sendable { public let id, name: String; public let work: Int64; public let cash, housingAdded, maxCount: Int; public let inputs: [String:Int] }
    public struct Satisfaction: Codable, Sendable { public let initial, base, coverageWeight, qualityWeight, fallCap, riseCap, immigrationFloor: Int }
    public struct Hero: Codable, Sendable { public let id, name, office, effect, stage, prerequisite: String; public let attributes: [String:Int]; public let cash: Int; public let recruitSeconds: [Int64]; public let materials: [String:Int] }
    public let schema: Int
    public let rules: String
    public let clock: Clock
    public let movement: Movement
    public let limits: Limits
    public let resources: [Resource]
    public let crops: [Crop]
    public let recipes: [Recipe]
    public let facilities: [Facility]
    public let start: Start
    public let targets: [String:Int]
    public let construction: Construction
    public let satisfaction: Satisfaction
    public let heroes: [Hero]

    public static func load() throws -> Self {
        guard let url = Bundle.module.url(forResource:"rules", withExtension:"json") else { throw LifeError.invalid("缺少生活城配置") }
        let rules = try JSONDecoder().decode(Self.self, from:Data(contentsOf:url))
        try rules.validate(); return rules
    }
    public func validate() throws {
        func need(_ test: Bool, _ message: String) throws { if !test { throw LifeError.invalid(message) } }
        try need(schema == 1 && rules == "life-0.6.0", "生活规则版本不支持")
        try need(clock.cycle == 2880 && clock.planning > 0 && clock.mealGrace > 0 && clock.meals == clock.meals.sorted(), "时间参数无效")
        try need(clock.meals.allSatisfy { $0 >= 0 && $0 + clock.mealGrace < clock.cycle }, "餐时越界")
        try need(movement.emptySpeed > 0 && movement.loadedSpeed > 0, "移动速度必须为正")
        let keys = Set(resources.map(\.id)), sites = Set(facilities.map(\.id))
        try need(keys.count == resources.count && sites.count == facilities.count, "重复物资／地点ID")
        try need(Set(crops.map(\.id)).count == crops.count && Set(recipes.map(\.id)).count == recipes.count, "重复作物／配方ID")
        try need(start.population == start.roles.count && start.population <= limits.people, "人口与岗位不一致")
        for row in recipes {
            try need(row.work > 0 && row.passive >= 0 && sites.contains(row.facility), "无效配方工位")
            try need(row.outputs.values.allSatisfy { $0 > 0 } && row.inputs.values.allSatisfy { $0 > 0 }, "配方数量必须为正")
            try need(Set(row.inputs.keys).union(row.outputs.keys).isSubset(of:keys), "未知配方资源")
        }
        for crop in crops {
            try need(crop.sow > 0 && crop.grow > 0 && crop.harvest > 0, "作物时间必须为正")
            try need(Set(crop.inputs.keys).union(crop.outputs.keys).isSubset(of:keys), "未知作物资源")
        }
        for (site, stock) in start.stocks { try need(sites.contains(site) && Set(stock.keys).isSubset(of:keys) && stock.values.allSatisfy { $0 >= 0 && $0 <= limits.storePerResource }, "开局库存无效") }
        try need(heroes.count == 6 && Set(heroes.map(\.id)).count == 6, "首批武将数量错误")
    }
    public func recipe(_ id: String) -> Recipe? { recipes.first { $0.id == id } }
    public func crop(_ id: String) -> Crop? { crops.first { $0.id == id } }
    public func point(_ site: String) -> LifePoint { facilities.first { $0.id == site }.map { .init(x:$0.x,y:$0.y) } ?? .init(x:850,y:540) }
    public func path(_ from: String, _ to: String) -> [LifePoint] {
        let a = point(from), b = point(to)
        return [a, .init(x:a.x,y:movement.roadY), .init(x:b.x,y:movement.roadY), b].reduce(into:[]) { if $0.last != $1 { $0.append($1) } }
    }
    public func travel(_ from: String, _ to: String, loaded: Bool = false) -> Int64 {
        let p = path(from,to), distance = zip(p,p.dropFirst()).reduce(0.0) { $0 + $1.0.distance($1.1) }
        return Int64(ceil(distance / (loaded ? movement.loadedSpeed : movement.emptySpeed)))
    }
}

public struct LifePoint: Codable, Equatable, Sendable { public var x, y: Double; public init(x:Double,y:Double) { self.x=x;self.y=y }; public func distance(_ b:Self) -> Double { hypot(x-b.x,y-b.y) } }
public struct LifeAgent: Codable, Equatable, Identifiable, Sendable {
    public var id, name, role, site: String
    public var task: Int?
    public var meal: Int?
    public var activity = "等待安排"
}
public struct LifeField: Codable, Equatable, Sendable {
    public var crop: String
    public var nextCrop: String?
    public var phase = "empty"
    public var maturesAt: Int64?
    public var plantedAt: Int64?
    public var task: Int?
}
public struct LifeTask: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var actor, kind, phase, source, destination, key: String
    public var phaseFrom: String
    public var began, due: Int64
    public var quantity = 0
    public var inputs: [String:Int] = [:]
    public var outputs: [String:Int] = [:]
    public var work: Int64 = 0
    public var inputsTaken = false
    public var cargo = 0
    public var mealID: Int?
}
public struct LifeMeal: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var starts, deadline: Int64
    public var expected: [String]
    public var served: [String] = []
    public var hearty = 0
    public var closed = false
}
public struct LifeEvent: Codable, Equatable, Sendable { public var time: Int64; public var kind, text: String }
public struct LifeLedger: Codable, Equatable, Sendable {
    public var initial: [String:Int] = [:]
    public var produced: [String:Int] = [:]
    public var consumed: [String:Int] = [:]
}
public struct LifeState: Codable, Equatable, Sendable {
    public var schema = 1
    public var rulesVersion = "life-0.6.0"
    public var time: Int64 = 0
    public var lastWallUTC: Int64
    public var nextPlan: Int64 = 0
    public var nextMeal: Int64 = 600
    public var nextMealID = 0
    public var nextID = 1
    public var treasury: Int
    public var housing: Int
    public var satisfaction: Int
    public var stores: [String:[String:Int]] = [:]
    public var agents: [LifeAgent] = []
    public var fields: [String:LifeField] = [:]
    public var tasks: [LifeTask] = []
    public var meals: [LifeMeal] = []
    public var history: [LifeEvent] = []
    public var ledger = LifeLedger()
    public var achievements: [String] = []
    public var constructionCount = 0
    public var forestRemaining = 120
    public var nextForestRenewal: Int64 = 14_400
    public var totalServed = 0
    public var completedTasks = 0
    public var isNight: Bool { time % 2880 >= 2160 }
    public var clockName: String { switch time % 2880 { case ..<240: "清晨"; case ..<1920: "白天"; case ..<2160: "黄昏"; default: "夜晚" } }
    public var population: Int { agents.count }
    public func stock(_ site: String, _ key: String) -> Int { stores[site]?[key] ?? 0 }
    public func reserved(_ site: String, _ key: String) -> Int {
        tasks.reduce(0) { total,t in
            if t.kind == "haul", t.source == site, t.cargo == 0 { return total + (t.key == key ? t.quantity : 0) }
            if t.kind != "haul", t.destination == site, !t.inputsTaken { return total + (t.inputs[key] ?? 0) }
            return total
        }
    }
    public func incoming(_ site: String, _ key: String) -> Int { tasks.filter { $0.kind == "haul" && $0.destination == site && $0.key == key }.reduce(0) { $0+$1.quantity } }
    public func pendingOutput(_ site: String, _ key: String) -> Int { tasks.filter { $0.kind != "haul" && $0.destination == site }.reduce(0) { $0+($1.outputs[key] ?? 0) } }
    public func free(_ site: String, _ key: String) -> Int { stock(site,key)-reserved(site,key) }
    public func total(_ key: String) -> Int { stores.values.reduce(0) { $0+($1[key] ?? 0) } }
    public mutating func record(_ kind: String, _ text: String, limit: Int = 128) { history.append(.init(time:time,kind:kind,text:text)); if history.count>limit { history.removeFirst(history.count-limit) } }
    public func validate(_ r:LifeRules) throws {
        func need(_ ok:Bool,_ text:String) throws { if !ok { throw LifeError.invalid(text) } }
        try need(schema == 1 && rulesVersion == r.rules && time>=0 && treasury>=0 && (0...100).contains(satisfaction),"生活存档头或状态无效")
        try need(agents.count<=r.limits.people && Set(agents.map(\.id)).count==agents.count,"居民ID重复／超限")
        try need(tasks.count<=r.limits.activeTasks && Set(tasks.map(\.id)).count==tasks.count && Set(tasks.map(\.actor)).count==tasks.count,"同一居民重复任务")
        let sites=Set(r.facilities.map(\.id)), keys=Set(r.resources.map(\.id))
        for (site,goods) in stores {
            try need(sites.contains(site) && Set(goods.keys).isSubset(of:keys),"未知仓位或货物")
            for key in keys { let n=goods[key] ?? 0; try need(n>=0 && n+incoming(site,key)+pendingOutput(site,key)<=r.limits.storePerResource && reserved(site,key)<=n,"库存/容量/预留错误：\(site)/\(key)") }
        }
        for task in tasks { try need(agents.contains { $0.id==task.actor && $0.task==task.id } && sites.contains(task.source) && sites.contains(task.destination) && task.due>=time,"任务归属或时间错误") }
        for agent in agents { try need(sites.contains(agent.site) && (agent.task == nil || tasks.contains { $0.id==agent.task && $0.actor==agent.id }),"人物任务引用错误") }
        for key in keys {
            let carried=tasks.filter { $0.kind=="haul" && $0.key==key }.reduce(0) { $0+$1.cargo }
            let wip=tasks.filter { $0.kind != "haul" && $0.inputsTaken }.reduce(0) { $0+($1.inputs[key] ?? 0) }
            try need(total(key)+carried+wip == ledger.initial[key,default:0]+ledger.produced[key,default:0]-ledger.consumed[key,default:0],"物料不守恒：\(key)")
        }
    }
}
