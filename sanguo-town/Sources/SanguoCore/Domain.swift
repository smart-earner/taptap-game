import Foundation

public enum GameError: Error, Equatable, Sendable, LocalizedError {
    case invalid(String), denied(String), unsupported(String), stale, duplicateID
    public var errorDescription: String? {
        switch self {
        case .invalid(let s): return "数据无效：\(s)"
        case .denied(let s): return "未获授权：\(s)"
        case .unsupported(let s): return "本开发版尚未实现：\(s)"
        case .stale: return "状态已变化，请刷新后重新决定。"
        case .duplicateID: return "同一命令ID不能代表不同操作。"
        }
    }
}
public enum Policy: String, Codable, CaseIterable, Sendable {
    case supply, trade, industry, military, balanced
    public var title: String {
        switch self {
        case .supply: "安民"
        case .trade: "兴商"
        case .industry: "兴业"
        case .military: "备战"
        case .balanced: "均衡"
        }
    }
}
public enum Resource: String, Codable, CaseIterable, Sendable {
    case grain, wood, iron, wine, tools
    public var title: String {
        switch self {
        case .grain: "粮食"
        case .wood: "木材"
        case .iron: "铁料"
        case .wine: "酒"
        case .tools: "器材"
        }
    }
}
public enum Profession: String, Codable, CaseIterable, Sendable {
    case governance, coordination, military, diplomacy
}
public struct Attributes: Codable, Equatable, Sendable {
    public var command: Int
    public var valor: Int
    public var strategy: Int
    public var administration: Int
    public var charisma: Int
    public init(command: Int = 50, valor: Int = 50, strategy: Int = 50,
                administration: Int = 50, charisma: Int = 50) {
        self.command = command; self.valor = valor; self.strategy = strategy
        self.administration = administration; self.charisma = charisma
    }
    public var prefectScore: Int { (administration * 5 + strategy * 3 + charisma * 2) / 10 }
    var all: [Int] { [command, valor, strategy, administration, charisma] }
}
public struct Office: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case prefect, governor }
    public var kind: Kind
    public var scope: String
    public var since: Int64
}
public struct Person: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var cityID: String
    public var attributes: Attributes
    public var office: Office?
    public var locked: Bool = false
    public var isProxy: Bool = false
    public var experience: [String: Int] = [:]
    public var workSeconds: [String: Int] = [:]
    public init(id: String, name: String, cityID: String, attributes: Attributes = .init(),
                office: Office? = nil, isProxy: Bool = false) {
        self.id = id; self.name = name; self.cityID = cityID
        self.attributes = attributes; self.office = office; self.isProxy = isProxy
    }
    public func level(_ profession: Profession) -> Int {
        min(10, 1 + (experience[profession.rawValue, default: 0] / 100))
    }
    public var prefectScore: Int { attributes.prefectScore + level(.governance) - 1 }
    mutating func credit(_ profession: Profession, seconds: Int) {
        let key = profession.rawValue
        let total = workSeconds[key, default: 0] + seconds
        experience[key, default: 0] = min(1_000_000, experience[key, default: 0] + total / 3600 * 10)
        workSeconds[key] = total % 3600
    }
}
public struct Inventory: Codable, Equatable, Sendable {
    /// 1,000 milli-units = 1 displayed unit. No floating-point money/resource arithmetic.
    public var amounts: [String: Int64] = [:]
    public var reserved: [String: Int64] = [:]
    public var capacity: Int64 = 1_000_000
    public init(grain: Int64 = 200_000, wood: Int64 = 80_000, iron: Int64 = 30_000) {
        amounts = ["grain": grain, "wood": wood, "iron": iron, "wine": 0, "tools": 4_000]
    }
    public subscript(_ resource: Resource) -> Int64 {
        get { amounts[resource.rawValue, default: 0] }
        set { amounts[resource.rawValue] = newValue }
    }
    public func free(_ resource: Resource) -> Int64 {
        self[resource] - reserved[resource.rawValue, default: 0]
    }
    mutating func add(_ resource: Resource, _ amount: Int64) {
        self[resource] = min(capacity, self[resource] + amount)
    }
}
public struct City: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var population: Int = 8
    public var prefectID: String
    public var districtID: String?
    public var policy: Policy?
    public var inventory = Inventory()
    public var jobCapacity: [String: Int] = ["grain": 2, "wood": 1, "iron": 1]
    public var jobs: [String: Int] = [:]
    public var grainRemainder: Int64 = 0
    public var grainRatePercent: Int64 = 100
    public var ironRatePercent: Int64 = 100
    public var lastAppointment: Int64 = 0
    public var labor: Int { population * 3 / 4 }
    public var grainFloor: Int64 { max(50_000, Int64(population) * 6_000) }
    public init(id: String, name: String, prefectID: String) {
        self.id = id; self.name = name; self.prefectID = prefectID
    }
}
public struct District: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var cityIDs: [String]
    public var governorID: String
    public var talentIDs: [String]
    public var policy: Policy?
}
public struct DomainEvent: Codable, Equatable, Sendable {
    public var time: Int64
    public var kind: String
    public var actorID: String?
    public var message: String
}
public struct Receipt: Codable, Equatable, Sendable {
    public var fingerprint: String
    public var revision: Int64
}
public struct WorldState: Codable, Equatable, Sendable {
    public static let currentRules = "core-0.1"
    public var schemaVersion = 1
    public var rulesVersion = currentRules
    public var revision: Int64 = 0
    public var simulationTime: Int64 = 0
    public var lastWallUTC: Int64
    public var treasury: Int64 = 500
    public var policy: Policy = .supply
    public var cities: [String: City] = [:]
    public var people: [String: Person] = [:]
    public var districts: [String: District] = [:]
    public var receipts: [String: Receipt] = [:]
    public var events: [DomainEvent] = []
    public init(wallUTC: Int64) { lastWallUTC = wallUTC }
    public func policy(for city: City) -> Policy {
        city.policy ?? city.districtID.flatMap { districts[$0]?.policy } ?? policy
    }
    mutating func record(_ kind: String, actor: String? = nil, _ text: String) {
        events.append(.init(time: simulationTime, kind: kind, actorID: actor, message: text))
        if events.count > 100 { events.removeFirst(events.count - 100) }
    }
}
