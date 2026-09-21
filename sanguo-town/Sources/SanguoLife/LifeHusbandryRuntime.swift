import Foundation

extension LifeRuntime {
    /// A single lasting decision. No animals, food, money or completed buildings are granted.
    /// Explicit opt-in upgrades the isolated life save; the former client rejects format 2.
    public mutating func setHusbandry(enabled: Bool) throws {
        guard !world.isHeroPreview else {throw LifeError.invalid("五将试玩暂未开放养殖")}
        let newlyEnabled = world.husbandry == nil
        if newlyEnabled {
            guard enabled else { return }
            world.husbandry = LifeHusbandry()
            world.husbandry!.purchasePeriod = world.time / LifeHusbandryRules.fiscalSeconds
            world.storages["pasture-feed"] = .init(node: "pasture", capacity: 8_000_000)
            world.storages["butcher-out"] = .init(node: "butcher", capacity: 16_000_000)
            world.format = 2
            world.rules = "life-0.7.2-v2"
        }
        guard newlyEnabled || world.husbandry!.enabled != enabled else { return }
        world.husbandry!.enabled = enabled
        world.record("husbandry_policy", enabled
            ? "授权肉食供应：太守建牧栏/肉食台，常备2头；幼猪每6小时最多40铜，仍守民食和国库底线。"
            : "暂停新购幼猪；已有牲畜继续照料，在途和已开始工程安全完成，不出售或删除牲畜。")
        try world.validate()
    }

    mutating func settleHusbandry() {
        guard let h = world.husbandry else { return }
        for id in h.pigs.keys.sorted() {
            let before = world.husbandry!.pigs[id]!.phase
            world.husbandry!.pigs[id]!.advancePassive(to: world.time)
            if before == .inTransit && world.husbandry!.pigs[id]!.phase == .awaitingEscort {
                world.record("pig_delivery", "已付款幼猪抵达城门，等待牧工实际牵入牧栏；没有提前产肉。")
            }
            if before == .growing && world.husbandry!.pigs[id]!.phase == .ready {
                world.record("pig_mature", "一头猪完成六段成长，太守将按饭馆需求安排出栏。")
            }
        }
    }

    /// Runs after essential meal, crop and delivery planning. Paused acquisition does not neglect existing stock.
    mutating func planHusbandry() {
        guard world.husbandry != nil else { return }
        let period = world.time / LifeHusbandryRules.fiscalSeconds
        if world.husbandry!.purchasePeriod != period {
            world.husbandry!.purchasePeriod = period
            world.husbandry!.purchaseSpent = 0
        }
        let enabled = world.husbandry!.enabled
        let buildingBusy = world.projects.values.contains { !$0.completed && $0.kind != "seal" }
        if enabled && world.growthEnabled && !buildingBusy && world.buildings["tavern", default: 0] > 0 {
            if world.buildings["pasture", default: 0] == 0 {
                startProject(id: "pasture", kind: "pasture", node: "pasture", cash: 60,
                             work: 1800, materials: ["wood": 8000, "stone": 4000])
            } else if world.buildings["butcher", default: 0] == 0 {
                startProject(id: "butcher", kind: "butcher", node: "butcher", cash: 40,
                             work: 900, materials: ["wood": 3000, "stone": 2000])
            }
        }
        guard world.buildings["pasture", default: 0] > 0 else {
            world.husbandry!.status = "先完成基础饭馆与牧栏；暂无幼猪或饲养费用"
            return
        }
        // A purchased animal stays at the gate until an actual available resident leads it in.
        for id in world.husbandry!.pigs.keys.sorted() {
            let pig = world.husbandry!.pigs[id]!
            if pig.phase == .awaitingEscort {
                var tail: [LifeStep] = []
                if var walk = move("gate", "pasture") { walk.kind = "lead"; tail.append(walk) }
                tail.append(.init(kind: "arrive", seconds: 1))
                if let task = assign(kind: "pig_arrive", job: "herder", subject: id,
                                     at: "gate", work: 0, tail: tail) {
                    world.husbandry!.pigs[id]!.phase = .arriving
                    world.husbandry!.pigs[id]!.taskID = task
                }
            }
        }
        // Only one feed lot per imminent segment; no six-stage prepayment and no hidden fodder resource.
        let feed = LifeHusbandryRules.feedPerSegment
        let waiting = world.husbandry!.pigs.values.filter { $0.phase == .needsCare }.count
        if waiting > 0 && canSparePigFeed(feed) {
            supply(["grain": Int64(waiting) * feed], to: "pasture-feed")
        }
        for id in world.husbandry!.pigs.keys.sorted() {
            guard world.husbandry!.pigs[id]!.phase == .needsCare, canSparePigFeed(feed),
                  let parts = world.selection(.grain, quantity: feed, at: "pasture-feed") else { continue }
            if let task = assign(kind: "pig_care", job: "herder", subject: id, at: "pasture",
                                 work: LifeHusbandryRules.careWork) {
                for part in parts { world.lots[part.lotID]!.reserved += part.amount }
                world.tasks[task]!.reservations = parts
                // Preconditions above guarantee this transition; all loaded saves are validated.
                world.husbandry!.pigs[id]!.phase = .caring
                world.husbandry!.pigs[id]!.taskID = task
                if world.tasks[task]!.current.kind == "work" { beginHusbandryWork(task) }
            }
        }
        planPigProcessing()
        buyPigIfNeeded()
        let pigs = world.husbandry!.pigs.values
        let needsFeed = pigs.contains { $0.phase == .needsCare }
        if needsFeed && !canSparePigFeed(feed) {
            world.husbandry!.status = "民食优先：暂停饲养投入，猪安全等待，不挨饿减员"
        } else if !enabled {
            world.husbandry!.status = "停止新购；已有猪继续照料与合法出栏"
        } else if world.husbandry!.purchaseSpent >= world.husbandry!.purchaseLimit && pigs.count < 2 {
            world.husbandry!.status = "本期购猪预算已用完，等待下一固定财政期；不需重新授权"
        } else {
            world.husbandry!.status = "在养/在途\(pigs.count)头 · 等厨房需求出栏 · 本期实付\(world.husbandry!.purchaseSpent)/40铜"
        }
    }

    func canSparePigFeed(_ feed: Int64) -> Bool {
        let committed = world.tasks.values.filter { $0.kind == "pig_care" }
            .reduce(Int64(0)) { $0 + $1.reservations.reduce(0) { $0 + $1.amount } }
        return world.foodCoverage >= 9500 &&
            world.foodEquivalent() - 4 * (committed + feed) >= Int64(world.agents.count) * 4000
    }

    mutating func buyPigIfNeeded() {
        guard let h = world.husbandry, h.enabled, world.phase >= 240, world.phase < 1920,
              world.buildings["market", default: 0] > 0,
              world.buildings["butcher", default: 0] > 0,
              h.occupiedPlaces < h.targetCount,
              h.purchaseSpent + LifeHusbandryRules.juvenilePrice <= h.purchaseLimit,
              world.treasury - world.reservedCash >= 100 + LifeHusbandryRules.juvenilePrice,
              world.amount(.meat) < 8000,
              canSparePigFeed(LifeHusbandryRules.feedPerSegment * Int64(LifeHusbandryRules.growthSegments)) else { return }
        let id = world.next("pig")
        world.husbandry!.pigs[id] = LifePig(id: id, orderedAt: world.time)
        world.treasury -= LifeHusbandryRules.juvenilePrice
        world.husbandry!.purchaseSpent += LifeHusbandryRules.juvenilePrice
        world.husbandry!.purchasedTotal += 1
        world.record("pig_order", "通过集市实付20铜订购幼猪，300秒后抵城；在途占牧栏名额，不赠肉料。")
    }

    mutating func planPigProcessing() {
        guard world.buildings["butcher", default: 0] > 0,
              !world.tasks.values.contains(where: { $0.kind == "pig_process" }),
              world.policy != "military", world.amount(.meat) < 8000,
              world.freeSpace("butcher-out") >= LifeHusbandryRules.meatPerPig * LifeResource.meat.volume,
              let pig = world.husbandry?.pigs.values.filter({ $0.phase == .ready }).sorted(by: { $0.id < $1.id }).first else { return }
        var tail: [LifeStep] = []
        if var walk = move("pasture", "butcher") { walk.kind = "lead"; tail.append(walk) }
        tail.append(.init(kind: "work", seconds: LifeHusbandryRules.butcherWork))
        guard let task = assign(kind: "pig_process", job: "butcher", subject: pig.id,
                                at: "pasture", work: 0, tail: tail) else { return }
        let index = world.tasks[task]!.steps.count - 1
        let r = Int64(world.tasks[task]!.rate)
        world.tasks[task]!.steps[index].seconds = (LifeHusbandryRules.butcherWork * 10000 + r - 1) / r
        world.tasks[task]!.target = "butcher-out"
        world.tasks[task]!.space = LifeHusbandryRules.meatPerPig * LifeResource.meat.volume
        world.storages["butcher-out"]!.incoming += world.tasks[task]!.space
        world.husbandry!.pigs[pig.id]!.phase = .leading
        world.husbandry!.pigs[pig.id]!.taskID = task
    }

    /// At-arrival hook: a resident cannot consume feed remotely while still walking.
    mutating func beginHusbandryWork(_ taskID: String) {
        guard let task = world.tasks[taskID] else { return }
        if task.kind == "pig_care" && !task.reservations.isEmpty {
            let otherCommitted = world.tasks.values.filter { $0.kind == "pig_care" && $0.id != taskID }
                .reduce(Int64(0)) { $0 + $1.reservations.reduce(0) { $0 + $1.amount } }
            let protected = world.foodEquivalent() - 4 * (otherCommitted + LifeHusbandryRules.feedPerSegment)
            if protected < Int64(world.agents.count) * 4000 || world.foodCoverage < 9500 {
                for part in task.reservations { world.lots[part.lotID]!.reserved -= part.amount }
                world.husbandry!.pigs[task.subject]!.phase = .needsCare
                world.husbandry!.pigs[task.subject]!.taskID = nil
                world.agents[task.worker]!.taskID = nil
                world.tasks[taskID] = nil
                return
            }
            for part in task.reservations {
                world.lots[part.lotID]!.reserved -= part.amount
                world.lots[part.lotID]!.amount -= part.amount
                world.consumed[LifeResource.grain.rawValue, default: 0] += part.amount
            }
            world.pruneLots()
            world.tasks[taskID]!.reservations = []
            world.husbandry!.pigs[task.subject]!.feedConsumed = true
        } else if task.kind == "pig_process" {
            world.husbandry!.pigs[task.subject]!.phase = .processing
        }
    }

    mutating func finishHusbandryTask(_ task: LifeTask) {
        guard var pig = world.husbandry?.pigs[task.subject], pig.taskID == task.id else { return }
        switch task.kind {
        case "pig_arrive":
            pig.phase = .needsCare
            pig.taskID = nil
            world.husbandry!.pigs[pig.id] = pig
            world.record("pig_admitted", "\(world.agents[task.worker]!.name)将幼猪从城门牵入牧栏，开始按需照料。")
        case "pig_care":
            precondition(pig.feedConsumed && pig.phase == .caring)
            pig.segmentsFed += 1
            pig.phase = .growing
            pig.taskID = nil
            pig.feedConsumed = false
            pig.due = world.time + LifeHusbandryRules.segmentSeconds
            world.husbandry!.pigs[pig.id] = pig
            world.counters["pig_care_completed", default: 0] += 1
        case "pig_process":
            precondition(pig.phase == .processing && pig.segmentsFed == 6)
            world.husbandry!.pigs[pig.id] = nil
            world.husbandry!.processedTotal += 1
            world.storages["butcher-out"]!.incoming -= task.space
            world.add(.meat, quantity: LifeHusbandryRules.meatPerPig, at: "butcher-out",
                      origin: "livestock:" + pig.id, production: true)
            world.counters["pigs_processed", default: 0] += 1
            world.record("butchery", "\(world.agents[task.worker]!.name)完成出栏加工，8份肉料在肉食台等待搬运；同一头猪不再留在栏内。")
        default: break
        }
    }
}

extension LifeWorld {
    func validateHusbandry() throws {
        guard let h = husbandry else { return }
        guard h.targetCount == 2, h.pigs.count <= h.targetCount,
              h.purchasePeriod >= 0, h.purchasePeriod <= time / LifeHusbandryRules.fiscalSeconds,
              h.purchaseSpent >= 0, h.purchaseSpent <= h.purchaseLimit,
              h.purchasedTotal >= 0, h.processedTotal >= 0,
              h.purchasedTotal - h.processedTotal == Int64(h.pigs.count),
              h.processedTotal <= 1_000_000,
              storages["pasture-feed"] != nil, storages["butcher-out"] != nil else {
            throw LifeError.invalid("养殖来源、预算、名额或库位错误")
        }
        for (id, pig) in h.pigs {
            guard id == pig.id else { throw LifeError.invalid("重复的牲畜身份") }
            try pig.validate(at: time)
            if let taskID = pig.taskID {
                guard let task = tasks[taskID], task.subject == id,
                      ["pig_care", "pig_arrive", "pig_process"].contains(task.kind) else {
                    throw LifeError.invalid("牲畜没有实际照料或承运人员")
                }
                if task.kind == "pig_arrive" && pig.phase != .arriving {
                    throw LifeError.invalid("到货牵引阶段与牲畜状态不一致")
                }
                if task.kind == "pig_process" {
                    guard [.leading, .processing].contains(pig.phase),
                          (task.current.kind == "work") == (pig.phase == .processing),
                          task.target == "butcher-out", task.space == LifeHusbandryRules.meatPerPig * LifeResource.meat.volume else {
                        throw LifeError.invalid("出栏任务与牲畜/出货区状态不一致")
                    }
                }
                if task.kind == "pig_care" {
                    let reserved = task.reservations.reduce(Int64(0)) { $0 + $1.amount }
                    guard pig.phase == .caring,
                          reserved == (pig.feedConsumed ? 0 : LifeHusbandryRules.feedPerSegment),
                          (task.current.kind == "work") == pig.feedConsumed,
                          task.reservations.allSatisfy({ lots[$0.lotID]?.resource == .grain && lots[$0.lotID]?.location == "pasture-feed" }) else {
                        throw LifeError.invalid("照料饲料重复收费或来源不合法")
                    }
                }
            }
        }
        for task in tasks.values where task.kind.hasPrefix("pig_") {
            guard h.pigs[task.subject]?.taskID == task.id else { throw LifeError.invalid("牲畜任务失去唯一实体") }
        }
        let processing = tasks.values.filter { $0.kind == "pig_process" }
        guard processing.count <= 1,
              storages["butcher-out"]!.incoming == processing.reduce(Int64(0), { $0 + $1.space }),
              produced["meat", default: 0] == h.processedTotal * LifeHusbandryRules.meatPerPig else {
            throw LifeError.invalid("出栏台容量或肉料唯一来源不合法")
        }
    }
}
