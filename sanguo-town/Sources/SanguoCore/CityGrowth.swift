import Foundation

/// Runtime values for a finite city-building slice, not a claim of 90 days of balanced content.
public enum GrowthRules {
    public static let version = "growth-0.3"
    public static let offlineLimit: Int64 = 30 * 86_400
    public static let tick: Int64 = 600
    public static let fiscalPeriod: Int64 = 14_400
    public static let protectedCash: Int64 = 200
    public static let maxPlots = 16
}
public enum InvestmentStyle: String, Codable, CaseIterable, Sendable {
    case cautious, balanced, active
    public var percent: Int64 { switch self { case .cautious: 25; case .balanced: 40; case .active: 60 } }
    public var title: String { switch self { case .cautious: "稳健"; case .balanced: "均衡"; case .active: "积极" } }
}
public enum BuildingKind: String, Codable, CaseIterable, Sendable {
    case hall, house, farm, granary, market, tavern, workshop, stable, station, barracks
    public var title: String {
        switch self {
        case .hall: "府署"; case .house: "民居"; case .farm: "农田"; case .granary: "粮仓"
        case .market: "集市"; case .tavern: "酒肆"; case .workshop: "工坊"; case .stable: "马厩"
        case .station: "驿站"; case .barracks: "演武场"
        }
    }
    public var district: Int { switch self { case .house,.hall: 0; case .farm,.granary: 1; case .market,.tavern,.workshop: 2; default: 3 } }
    public var repeatable: Bool { self == .house || self == .farm || self == .workshop }
    public var upgradable: Bool { ![Self.hall, .station, .stable].contains(self) }
}
public struct BuildingInstance: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: BuildingKind
    public var plot: Int
    /// Last completed level. A queued new building is level 0 and has no operational capacity.
    public var level: Int
    public var restored: Bool
    public var completedAt: Int64
    public var isOperating: Bool { level > 0 }
}
public enum ConstructionStatus: String, Codable, Sendable { case working, paused, waiting, completed, cancelled }
public struct ConstructionProject: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var buildingID: String
    public var targetLevel: Int
    public var isRepair: Bool
    public var status: ConstructionStatus
    public var startedAt: Int64
    public var finishedAt: Int64?
    public var requiredWork: Int64 // person-seconds; all builders share the city's real workforce
    public var completedWork: Int64 = 0
    public var builders: Int = 0
    public var cashCost: Int64
    public var cashSpent: Int64 = 0
    public var materialCost: [String: Int64]
    public var materialSpent: [String: Int64] = [:]
    public var policyVersion: Int
    public var reason: String = ""
    public var live: Bool { status != .completed && status != .cancelled }
    public var fraction: Double { Double(completedWork) / Double(max(1, requiredWork)) }
    public var phase: Int {
        if status == .completed { return 4 }
        if completedWork * 100 < requiredWork * 15 { return 0 }
        if completedWork * 100 < requiredWork * 45 { return 1 }
        return completedWork * 100 < requiredWork * 80 ? 2 : 3
    }
    public var phaseTitle: String { ["清场备料", "地基立柱", "梁架屋顶", "门窗收尾", "正式运营"][phase] }
}
public struct ProductionBatch: Codable, Equatable, Sendable {
    public var dueAt: Int64
    public var startedAt: Int64
    public var inputs: [String: Int64]
    public var outputs: [String: Int64]
    public var workers: [String: Int]
    public var population: Int
    public var prefectID: String
}
public struct DevelopmentPlan: Codable, Equatable, Sendable {
    public var buildings: [BuildingInstance] = []
    public var projects: [ConstructionProject] = []
    public var lockedPlots: [Int] = []
    public var initialHousing: Int
    public var initialStorage: Int64
    public var residentsSupplySeconds: Int64 = 0
    public var nextPopulationCheck: Int64
    public var batch: ProductionBatch?
    public var lastWorkKinds: [String] = []
    public var blockedReason: String = ""
    public var completedCount = 0
    public var housing: Int { initialHousing + buildings.filter { $0.kind == .house && $0.isOperating }.reduce(0) { n,b in n + (b.id.hasSuffix("base-house") ? max(0,b.level-1)*4 : b.level*4) } }
    public var builders: Int { projects.filter(\.live).reduce(0) { $0 + $1.builders } }
    public func level(_ kind: BuildingKind) -> Int { buildings.filter { $0.kind == kind }.map(\.level).max() ?? 0 }
    public var appearanceLevel: Int { min(3, completedCount / 5) }
}
public struct GrowthFinance: Codable, Equatable, Sendable {
    public var period: Int64 = 0
    public var income: Int64 = 0
    public var operatingSpent: Int64 = 0
    public var capital: Int64 = 300
    public var operating: Int64 = 250
    public var protectedOperating: Int64 = 0
    public var capitalSpent: Int64 = 0
    public var sales: [String: Int64] = [:] // aggregate realm demand per period, never one quota per town
    public var lifetimeSales: Int64 = 0
    public var lifetimeConstruction: Int64 = 0
}
public struct RecruitBatch: Codable, Equatable, Sendable {
    public var dueAt: Int64
    public var number: Int
    public var cash: Int64
    public var grain: Int64
    public var tools: Int64
}
public struct LegionGrowthPlan: Codable, Equatable, Sendable {
    public var cityID: String
    public var authorizedCapacity: Int
    public var active: Int = 0
    public var trainedHours: Int64 = 0
    public var budget: Int64
    public var spent: Int64 = 0
    public var batch: RecruitBatch?
    public var pausedReason = "等待营地和补给"
    public var nextTraining: Int64
    public var recruitsThisPeriod = 0
    public var recruitPeriod: Int64 = 0
    public var trainingLevel: Int { min(3, Int(trainedHours / 72)) }
}
public struct CityAppearanceSnapshot: Codable, Equatable, Sendable {
    public var version = 1
    public var cityID: String
    public var name: String
    public var time: Int64
    public var growthAgeSeconds: Int64
    public var population: Int
    public var housing: Int
    public var buildings: [BuildingInstance]
    public var projects: [ConstructionProject]
    public var grainBand: Int
    public var legionActive: Int
    public var legionCapacity: Int
    public var policy: Policy
    public var workingResources: [String]
    // Optional fields keep previously saved growth snapshots readable.
    public var civic: CivicCity? = nil
    public var collectedWeapons: Int? = nil
    public var collectedMounts: Int? = nil
    public var legionAway: Bool? = nil
    /// Layout belongs to the historical snapshot, not to the current policy or renderer.
    public var layoutVersion: Int? = nil
}
public struct CityMemory: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var pinned: Bool
    public var snapshot: CityAppearanceSnapshot
}
public struct CityProposal: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var createdAt: Int64
    public var detail: String
}
public struct RealmGrowth: Codable, Equatable, Sendable {
    public var enabled = false
    public var investment: InvestmentStyle = .balanced
    public var policyVersion = 0
    public var cities: [String: DevelopmentPlan] = [:]
    public var finance = GrowthFinance()
    public var legion: LegionGrowthPlan?
    public var memories: [CityMemory] = []
    public var proposals: [CityProposal] = []
    public var proposalTimes: [Int64] = []
    public var nextPlanning: Int64 = 0
    public var nextFiscal: Int64 = GrowthRules.fiscalPeriod
    public var nextID: Int64 = 1
    public var normalGrowthSeconds: Int64 = 0
    public var nextCheckpointIndex = 0
    public var pendingCheckpoints: [Int64] = [7,30,60,90].map { $0*86_400 }
    public var reservedCash: Int64 {
        cities.values.flatMap(\.projects).filter(\.live).reduce(0) { $0 + $1.cashCost - $1.cashSpent } + (legion?.batch?.cash ?? 0)
    }
}
public enum BuildingCatalog {
    public static func quote(kind: BuildingKind, level: Int, repair: Bool) -> (cash: Int64, materials: [String:Int64], work: Int64) {
        if repair { return (20, ["wood":10_000], 600) }
        let base: (Int64,Int64,Int64,Int64,Int64)
        switch kind {
        case .hall: base = (180,35,10,1,7200)
        case .house: base = (100,20,0,0,3600)
        case .farm: base = (80,15,0,0,3600)
        case .granary: base = (120,25,5,0,7200)
        case .market: base = (80,10,0,0,1800)
        case .tavern: base = (120,20,0,1,7200)
        case .workshop: base = (180,30,10,1,10_800)
        case .stable: base = (160,25,0,1,10_800)
        case .station: base = (100,15,0,1,7200)
        case .barracks: base = (200,25,10,2,10_800)
        }
        // Upgrades are larger local improvement projects, not a claim that multiplying numbers creates 90-day content.
        let multiple: Int64 = level == 1 ? 1 : level == 2 ? 4 : 12
        let seconds: Int64 = level == 1 ? base.4 : level == 2 ? 43_200 : 259_200
        return (base.0*multiple, ["wood":base.1*multiple*1000,"iron":base.2*multiple*1000,"tools":base.3*multiple*1000].filter { $0.value > 0 }, seconds*2)
    }
}

extension WorldState {
    public func appearance(cityID: String) -> CityAppearanceSnapshot? {
        guard let city = cities[cityID], let plan = growth?.cities[cityID] else { return nil }
        let band = city.inventory[.grain] < city.grainFloor ? 0 : city.inventory[.grain] < city.inventory.capacity / 2 ? 1 : 2
        let legion = growth?.legion?.cityID == cityID ? growth?.legion : nil
        var snapshot = CityAppearanceSnapshot(cityID:cityID, name:city.name, time:simulationTime, growthAgeSeconds:growth?.normalGrowthSeconds ?? simulationTime, population:city.population,
            housing:plan.housing, buildings:plan.buildings.sorted { $0.plot < $1.plot },
            projects:plan.projects.filter(\.live), grainBand:band, legionActive:legion?.active ?? 0,
            legionCapacity:legion?.authorizedCapacity ?? 0, policy:policy(for:city), workingResources:plan.lastWorkKinds)
        snapshot.civic = realm?.civic[cityID]
        snapshot.layoutVersion = realm?.identity == nil ? nil : 2
        if let realm {
            let owned = CollectionCatalog.all.filter { realm.collections[$0.id]?.completedAt != nil && realm.collections[$0.id]?.cityID == cityID }
            snapshot.collectedWeapons = owned.filter { $0.kind == .weapon }.count
            snapshot.collectedMounts = owned.filter { $0.kind == .mount }.count
            snapshot.legionAway = realm.operation?.goal == .securePass && realm.operation?.source == cityID
        }
        return snapshot
    }
}
