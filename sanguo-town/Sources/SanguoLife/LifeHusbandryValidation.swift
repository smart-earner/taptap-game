import Foundation

extension LifeHusbandryRules {
    public static func bundled() throws -> LifeHusbandryRules {
        let url = Bundle.main.url(forResource: "husbandry", withExtension: "json", subdirectory: "Life072")
            ?? Bundle.module.url(forResource: "husbandry", withExtension: "json")
        guard let url else { throw LifeError.invalid("缺少养殖参数包；没有改动存档") }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try value.validate()
        return value
    }
}

extension LifeWorld {
    func validateHusbandry() throws {
        guard let h = husbandry else { return }
        try h.rules.validate()
        let r = h.rules
        func check(_ value: Bool, _ message: String) throws {
            if !value { throw LifeError.invalid(message) }
        }
        try check((1...r.capacity).contains(h.herdTarget) && (r.purchasePrice...160).contains(h.purchaseLimit), "养殖授权超出上限")
        try check(h.animals.count <= r.capacity && (0...1_000_000).contains(h.purchasedCount) && h.processedCount >= 0 && h.processedCount <= h.purchasedCount, "动物数量不合法")
        try check(h.purchasedCount == h.animals.count + h.processedCount, "动物来源或出栏记录不守恒")
        try check(h.lifetimePurchaseSpent == Int64(h.purchasedCount) * r.purchasePrice, "动物必须来自真实采购支出")
        try check(h.period >= 0 && h.period <= time / r.purchasePeriodSeconds && (0...160).contains(h.periodSpent) && h.periodSpent <= h.lifetimePurchaseSpent, "养殖采购周期或额度错误")
        try check(h.recentMeals.count <= 8, "菜品历史超出上限")
        try check(storages["pasture-in"]?.node == "pasture" && storages["meat-out"]?.node == "butcher", "养殖缺少合法库位")
        for (id, p) in h.animals {
            try check(id == p.id && !id.isEmpty && id.count <= 100 && p.purchasedAt >= 0 && p.purchasedAt <= time && p.paidCash == r.purchasePrice, "动物身份或来源错误")
            try check((0...r.growthSegments).contains(p.completedSegments) && (p.completedSegments...r.growthSegments).contains(p.fedSegments), "动物成长或饲喂次数错误")
            try check(p.due == nil || p.due! >= time, "动物事件时间倒退")
            if let taskID = p.taskID {
                try check(tasks[taskID]?.subject == id && ["pig_receive", "pig_care", "pig_process"].contains(tasks[taskID]?.kind ?? ""), "动物关联了错误任务")
            }
            let passive = p.stage == .inTransit || p.stage == .growing
            try check((p.due != nil) == passive, "动物被动等待时点错误")
            let working = [.receiving, .caring, .leading, .processing].contains(p.stage)
            try check((p.taskID != nil) == working, "动物存在无执行人的工作")
            switch p.stage {
            case .inTransit, .atGate, .receiving:
                try check(p.node == "gate" && p.completedSegments == 0 && p.fedSegments == 0, "在途幼猪提前成长")
            case .waitingForCare:
                try check(p.node == "pasture" && p.fedSegments == p.completedSegments && p.completedSegments < r.growthSegments, "待照料阶段重复饲喂")
            case .caring:
                let hasStarted = p.taskID.flatMap { tasks[$0] }?.current.kind == "work"
                try check(p.node == "pasture" && p.completedSegments < r.growthSegments && p.fedSegments == p.completedSegments + (hasStarted ? 1 : 0), "照料未到场扣料或重复扣料")
            case .growing:
                try check(p.node == "pasture" && p.fedSegments == p.completedSegments + 1 && p.completedSegments < r.growthSegments, "动物未喂食便成长")
            case .ready, .leading:
                try check(p.node == "pasture" && p.completedSegments == r.growthSegments && p.fedSegments == r.growthSegments, "幼猪提前出栏")
            case .processing:
                try check(p.node == "butcher" && p.completedSegments == r.growthSegments && p.fedSegments == r.growthSegments, "肉食加工位置或成长阶段错误")
            }
        }
        try check(h.consumedFeed == h.feedPaid + Int64(h.processedCount * r.growthSegments) * r.feedPerSegment, "饲料被重复消耗或缺失")
        try check(consumed["grain", default: 0] >= h.consumedFeed && produced["meat", default: 0] >= h.meatProduced, "养殖与资源总账不一致")
        for task in tasks.values where task.kind.hasPrefix("pig_") {
            try check(h.animals[task.subject]?.taskID == task.id, "重复动物任务或被消费后仍在加工")
        }
    }
}
