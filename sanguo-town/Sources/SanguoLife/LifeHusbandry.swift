import Foundation

/// Paid livestock are unique entities, never stackable resources or decorative population.
/// Constants are the frozen slim-v0.7.2 pig contract (all times are simulation seconds).
public enum LifeHusbandryRules {
    public static let capacity = 8
    public static let juvenilePrice: Int64 = 20
    public static let deliverySeconds: Int64 = 300
    public static let growthSegments = 6
    public static let segmentSeconds: Int64 = 2880
    public static let feedPerSegment: Int64 = 250
    public static let careWork: Int64 = 30
    public static let butcherWork: Int64 = 90
    public static let meatPerPig: Int64 = 8000
    public static let fiscalSeconds: Int64 = 21600
}

public enum LifePigPhase: String, Codable, Sendable {
    case inTransit, awaitingEscort, arriving, needsCare, caring, growing, ready, leading, processing
}

public struct LifePig: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var phase: LifePigPhase = .inTransit
    public var segmentsFed = 0
    public var orderedAt: Int64
    public var due: Int64?
    public var taskID: String?
    public var feedConsumed = false

    public init(id: String, orderedAt: Int64) {
        self.id = id
        self.orderedAt = orderedAt
        self.due = orderedAt + LifeHusbandryRules.deliverySeconds
    }

    /// Passive events cannot depend on animation frames, visibility or an open window.
    mutating func advancePassive(to time: Int64) {
        guard let due, time >= due else { return }
        switch phase {
        case .inTransit:
            phase = .awaitingEscort
            self.due = nil
        case .growing:
            phase = segmentsFed == LifeHusbandryRules.growthSegments ? .ready : .needsCare
            self.due = nil
        default: break
        }
    }

    mutating func beginCare(task: String) throws {
        guard phase == .needsCare, taskID == nil,
              segmentsFed < LifeHusbandryRules.growthSegments else {
            throw LifeError.invalid("牲畜已有人照料或不处于等料阶段")
        }
        phase = .caring
        taskID = task
        feedConsumed = false
    }

    mutating func finishCare(task: String, at time: Int64) throws {
        guard phase == .caring, taskID == task, feedConsumed else {
            throw LifeError.invalid("未投入实际饲料，不能开始牲畜成长")
        }
        segmentsFed += 1
        phase = .growing
        taskID = nil
        feedConsumed = false
        due = time + LifeHusbandryRules.segmentSeconds
    }

    func validate(at time: Int64) throws {
        guard !id.isEmpty, orderedAt >= 0, orderedAt <= time,
              (0...LifeHusbandryRules.growthSegments).contains(segmentsFed) else {
            throw LifeError.invalid("牲畜身份、来源或成长段数错误")
        }
        let passive = phase == .inTransit || phase == .growing
        guard passive == (due != nil), due.map({ $0 > time }) ?? true else {
            throw LifeError.invalid("牲畜被动时钟不合法")
        }
        let staffed = [.arriving, .caring, .leading, .processing].contains(phase)
        guard staffed == (taskID != nil), phase == .caring || !feedConsumed else {
            throw LifeError.invalid("牲畜任务或饲料状态不合法")
        }
        if phase == .inTransit && segmentsFed != 0 {
            throw LifeError.invalid("未到场幼猪不能提前成长")
        }
        if [.ready, .leading, .processing].contains(phase) && segmentsFed != LifeHusbandryRules.growthSegments {
            throw LifeError.invalid("未成熟牲畜不能进入出栏链")
        }
        if phase == .needsCare && segmentsFed >= LifeHusbandryRules.growthSegments {
            throw LifeError.invalid("成熟牲畜不能再收费饲喂")
        }
        if phase == .growing && segmentsFed == 0 {
            throw LifeError.invalid("未照料牲畜不能被动成长")
        }
    }
}

/// A persistent, optional economic authorization. Hiding animals does not revoke it.
public struct LifeHusbandry: Codable, Equatable, Sendable {
    public var enabled = true
    public var targetCount = 2
    public var pigs: [String: LifePig] = [:]
    public var purchasePeriod: Int64 = 0
    public var purchaseSpent: Int64 = 0
    public var purchasedTotal: Int64 = 0
    public var processedTotal: Int64 = 0
    public var status = "等待太守安排牧栏和肉食台"
    public init() {}

    /// At most one replacement per authorized place per fixed six-hour period.
    public var purchaseLimit: Int64 { Int64(targetCount) * LifeHusbandryRules.juvenilePrice }
    public var occupiedPlaces: Int { pigs.count } // Includes paid incoming and processing pigs.
}
