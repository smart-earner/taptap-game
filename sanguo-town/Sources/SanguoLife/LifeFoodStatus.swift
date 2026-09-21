import Foundation

/// One policy table shared by the planner, CLI and UI. A target is not a promise
/// of available meat; missing meat must never block a basic meal.
public enum LifeFoodPolicy {
    public static func heartyTargetBP(for policy: String) -> Int {
        switch policy {
        case "supply": 5000
        case "trade", "balanced": 2500
        default: 0
        }
    }
}

/// Read-only evidence, not a second economic account. Quantities are in mU.
/// Inventory totals include stock and cargo; consumption counters count diners,
/// not finished kitchen batches or visual eating animations.
public struct LifeFoodStatus: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let herdTarget: Int
    public let pigsInTransit: Int
    public let pigsAtGate: Int
    public let pigsInCity: Int
    public let pigsProcessed: Int
    public let meatProduced: Int64
    public let meatAvailable: Int64
    public let basicMealsAvailable: Int64
    public let heartyMealsAvailable: Int64
    public let mealsConsumed: Int
    public let heartyMealsConsumed: Int
    public let feedConsumed: Int64
    public let purchaseSpent: Int64
    public let purchaseLimit: Int64
    public let nextPurchasePeriod: Int64
    public let heartyTargetBP: Int
    public let reason: String

    public init(world: LifeWorld) {
        let h = world.husbandry
        let pigs = Array(h?.animals.values ?? [:].values)
        enabled = h?.enabled == true
        herdTarget = h?.herdTarget ?? 0
        pigsInTransit = pigs.filter { $0.stage == .inTransit }.count
        pigsAtGate = pigs.filter { $0.stage == .atGate }.count
        pigsInCity = pigs.count - pigsInTransit - pigsAtGate
        pigsProcessed = h?.processedCount ?? 0
        meatProduced = h?.meatProduced ?? 0
        meatAvailable = world.amount(.meat)
        basicMealsAvailable = world.lots.values.filter { $0.resource == .meal && $0.quality != "hearty" }.reduce(0) { $0 + $1.amount }
        heartyMealsAvailable = world.lots.values.filter { $0.resource == .meal && $0.quality == "hearty" }.reduce(0) { $0 + $1.amount }
        mealsConsumed = world.counters["resident_meals_consumed", default: 0]
        heartyMealsConsumed = world.counters["hearty_meals_consumed", default: 0]
        feedConsumed = h?.consumedFeed ?? 0
        purchaseSpent = h?.periodSpent ?? 0
        purchaseLimit = h?.purchaseLimit ?? 0
        nextPurchasePeriod = h.map { (world.time / $0.rules.purchasePeriodSeconds + 1) * $0.rules.purchasePeriodSeconds } ?? 0
        heartyTargetBP = LifeFoodPolicy.heartyTargetBP(for: world.policy)
        reason = h?.lastReason ?? "尚未授权养殖；日常家常饭照常供应"
    }
}
