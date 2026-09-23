import Foundation

/// Paid or time-limited municipal work is deliberately scheduled after food,
/// construction and military logistics. These are not decorative busy loops:
/// completed cleaning improves hygiene, ward rounds improve security, and
/// drills consume rations while training guards and reinforcing the capital.
public enum LifeCivicDutyContract {
    public static let cleanSites = ["hall", "kitchen", "well", "warehouse", "farm", "gate"]
    public static let shiftSeconds: Int64 = 900
    public static let drillRations: Int64 = 250
}

extension LifeWorld {
    /// Last completed shift remains effective through the following day, then
    /// expires. Starting a new day's shift must not briefly erase yesterday's
    /// protection before the replacement work is finished.
    public func civicDutyCount(_ kind: String) -> Int {
        let key = "civic.\(kind)"
        let current = counters["\(key).cycle", default: -10]
        let previous = counters["\(key).previousCycle", default: -10]
        let today = current == Int(cycle) ? counters["\(key).count", default: 0] : 0
        let yesterday = current == Int(cycle)-1 ? counters["\(key).count", default: 0] :
            (previous == Int(cycle)-1 ? counters["\(key).previousCount", default: 0] : 0)
        return max(today, yesterday)
    }

    mutating func completeCivicDuty(_ kind: String) {
        let key = "civic.\(kind)"
        if counters["\(key).cycle", default: -10] != Int(cycle) {
            counters["\(key).previousCycle"] = counters["\(key).cycle", default: -10]
            counters["\(key).previousCount"] = counters["\(key).count", default: 0]
            counters["\(key).cycle"] = Int(cycle)
            counters["\(key).count"] = 0
        }
        counters["\(key).count", default: 0] += 1
    }
}

extension LifeRuntime {
    mutating func planCivicDuties() {
        guard world.isFormalHeroTown, world.agents.count >= 12,
              (780..<1080).contains(world.phase),
              world.foodCoverage >= 9500,
              world.heroTown?.city.supplyRecovery != true,
              world.foodEquivalent() >= Int64(world.agents.count) * 4_000 else { return }

        let population = world.agents.count
        for site in LifeCivicDutyContract.cleanSites.prefix(min(6, max(2, population / 10))) {
            let receipt = "civic.clean.\(site)"
            guard world.counters[receipt, default: -1] != Int(world.cycle) else { continue }
            guard assign(kind: "civic_clean", job: "handyman", subject: site, at: site,
                         work: LifeCivicDutyContract.shiftSeconds) != nil else { continue }
            world.counters[receipt] = Int(world.cycle)
        }

        let residences = world.heroTown!.city.plots
            .filter { $0.kind == "house" && $0.level > 0 && $0.service > 0 }
            .sorted { $0.id < $1.id }
        for plot in residences.prefix(min(12, max(2, (population + 3) / 4))) {
            let receipt = "civic.watch.\(plot.id)"
            guard world.counters[receipt, default: -1] != Int(world.cycle) else { continue }
            guard assign(kind: "civic_watch", job: "guard", subject: plot.id, at: plot.node,
                         work: LifeCivicDutyContract.shiftSeconds) != nil else { continue }
            world.counters[receipt] = Int(world.cycle)
        }

        guard world.heroTown!.city.civics["defense", default: 0] > 0 else { return }
        let homeSoldiers = world.campaign?.squads.values
            .filter { $0.cityID == "00" && $0.transferID == nil }
            .reduce(0, { $0 + $1.survivors }) ?? 0
        let rationReserve = Int64((homeSoldiers + 1) / 2 + 5) * 1_000
        for slot in 1...min(8, max(1, (population - 12) / 6)) {
            let receipt = "civic.drill.\(slot)"
            guard world.counters[receipt, default: -1] != Int(world.cycle),
                  world.amount(.rations, at: "warehouse", free: true) >=
                    rationReserve + LifeCivicDutyContract.drillRations else { continue }
            guard assign(kind: "civic_drill", job: "guard", subject: String(slot), at: "barracks",
                         work: LifeCivicDutyContract.shiftSeconds) != nil else { continue }
            world.use(["rations": LifeCivicDutyContract.drillRations], at: "warehouse")
            world.counters[receipt] = Int(world.cycle)
        }
    }

    mutating func finishCivicDuty(_ task: LifeTask) {
        switch task.kind {
        case "civic_clean":
            world.completeCivicDuty("clean")
            if !world.cleanedSites.contains(task.subject) { world.cleanedSites.append(task.subject) }
            world.record("civic", "\(world.agents[task.worker]?.name ?? task.worker)清理\(label(task.subject))；卫生维持至下一轮巡护。")
        case "civic_watch":
            world.completeCivicDuty("watch")
            world.record("civic", "\(world.agents[task.worker]?.name ?? task.worker)完成\(task.subject)里坊巡护；首都守力与安全感按实到岗计。")
        case "civic_drill":
            world.completeCivicDuty("drill")
            world.record("civic", "\(world.agents[task.worker]?.name ?? task.worker)完成防务操练；军粮已实耗，守备熟练度与本城守力增加。")
        default: break
        }
    }
}
