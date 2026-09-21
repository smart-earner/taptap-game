import Foundation

/// Food-chain rules for the eight-resource game. Water and pasture are services,
/// not additional inventories. A pig is a unique entity, never a meat timer.
public struct LifeHusbandryRules: Codable, Equatable, Sendable {
    public var capacity = 8
    public var purchasePrice: Int64 = 20
    public var deliverySeconds: Int64 = 300
    public var growthSegments = 6
    public var segmentSeconds: Int64 = 2880
    public var feedPerSegment: Int64 = 250
    public var careWorkSeconds: Int64 = 30
    public var butcherWorkSeconds: Int64 = 90
    public var meatPerAnimal: Int64 = 8000
    public var purchasePeriodSeconds: Int64 = 21600
    public var pastureCash: Int64 = 60
    public var pastureWorkSeconds: Int64 = 1800
    public var pastureMaterials: [String: Int64] = ["wood": 8000, "stone": 4000]
    public var butcherCash: Int64 = 40
    public var butcherBenchWorkSeconds: Int64 = 900
    public var butcherMaterials: [String: Int64] = ["wood": 3000, "stone": 2000]

    public init() {}

    public func validate() throws {
        guard (1...8).contains(capacity), (1...12).contains(growthSegments),
              (1...10_000).contains(purchasePrice), (1...86_400).contains(deliverySeconds),
              (60...86_400).contains(segmentSeconds), (1...100_000).contains(feedPerSegment),
              (1...3600).contains(careWorkSeconds), (1...3600).contains(butcherWorkSeconds),
              (1...24_000).contains(meatPerAnimal), (3600...86_400).contains(purchasePeriodSeconds),
              (1...100_000).contains(pastureCash), (1...100_000).contains(butcherCash),
              (1...86_400).contains(pastureWorkSeconds),
              (1...86_400).contains(butcherBenchWorkSeconds) else {
            throw LifeError.invalid("养殖参数超出安全范围")
        }
        for inputs in [pastureMaterials, butcherMaterials] {
            guard !inputs.isEmpty, inputs.allSatisfy({ LifeResource(rawValue: $0.key) != nil && (1...100_000).contains($0.value) }) else {
                throw LifeError.invalid("养殖设施引用了无效物资")
            }
        }
    }
}

public enum LifePigStage: String, Codable, Sendable {
    case inTransit, atGate, receiving, waitingForCare, caring, growing, ready, leading, processing

    public var title: String {
        switch self {
        case .inTransit: "幼猪在途"
        case .atGate: "城门待接回"
        case .receiving: "牵往牧栏"
        case .waitingForCare: "等待饲料与照料"
        case .caring: "添料照料"
        case .growing: "放牧成长"
        case .ready: "已可出栏"
        case .leading: "牵往肉食台"
        case .processing: "院内加工"
        }
    }
}

public struct LifePig: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var stage: LifePigStage = .inTransit
    public var node = "gate"
    public var purchasedAt: Int64
    public var paidCash: Int64
    public var due: Int64?
    public var completedSegments = 0
    public var fedSegments = 0
    public var taskID: String?

    public init(id: String, purchasedAt: Int64, rules: LifeHusbandryRules) {
        self.id = id
        self.purchasedAt = purchasedAt
        self.paidCash = rules.purchasePrice
        self.due = purchasedAt + rules.deliverySeconds
    }
}

/// One standing authorization. Changing or pausing it never refunds purchases or
/// refreshes the six-hour spending meter. Existing pigs remain cared for.
public struct LifeHusbandry: Codable, Equatable, Sendable {
    public var rules: LifeHusbandryRules
    public var enabled = true
    public var herdTarget: Int
    public var purchaseLimit: Int64
    public var period: Int64
    public var periodSpent: Int64 = 0
    public var lifetimePurchaseSpent: Int64 = 0
    public var purchasedCount = 0
    public var processedCount = 0
    public var consumedFeed: Int64 = 0
    public var recentMeals: [Bool] = [] // Last eight completed kitchen batches.
    public var animals: [String: LifePig] = [:]
    public var lastReason = "等待牧栏与肉食台"

    public init(at time: Int64, herdTarget: Int = 2, purchaseLimit: Int64 = 40,
                rules: LifeHusbandryRules = .init()) throws {
        try rules.validate()
        guard time >= 0, (1...rules.capacity).contains(herdTarget),
              (rules.purchasePrice...160).contains(purchaseLimit) else {
            throw LifeError.invalid("养殖规模或六小时采购额度不合法")
        }
        self.rules = rules
        self.herdTarget = herdTarget
        self.purchaseLimit = purchaseLimit
        self.period = time / rules.purchasePeriodSeconds
    }

    public var purchaseRemaining: Int64 { max(0, purchaseLimit - periodSpent) }
    public var feedPaid: Int64 { animals.values.reduce(0) { $0 + Int64($1.fedSegments) * rules.feedPerSegment } }
    public var meatProduced: Int64 { Int64(processedCount) * rules.meatPerAnimal }
}
