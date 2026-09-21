import Foundation

extension LifeRuntime {
    /// Explicit opt-in upgrades only this isolated life save, not a legacy city.
    /// Repeated authorization preserves bought animals and the spending meter.
    public mutating func authorizeHusbandry(herdTarget: Int = 2, purchaseLimit: Int64 = 40) throws {
        let rules = try world.husbandry?.rules ?? LifeHusbandryRules.bundled()
        let requested = try LifeHusbandry(at: world.time, herdTarget: herdTarget,
                                          purchaseLimit: purchaseLimit, rules: rules)
        var candidate = self
        if candidate.world.husbandry == nil {
            candidate.world.husbandry = requested
            candidate.world.format = 2
            candidate.world.rules = "life-0.7.2-v2"
            candidate.world.storages["pasture-in"] = .init(node: "pasture", capacity: 8_000_000)
            candidate.world.storages["meat-out"] = .init(node: "butcher", capacity: 24_000_000)
        } else {
            candidate.world.husbandry!.enabled = true
            candidate.world.husbandry!.herdTarget = requested.herdTarget
            candidate.world.husbandry!.purchaseLimit = requested.purchaseLimit
        }
        candidate.world.record("husbandry_authorized", "已授权改善饭食：最多\(herdTarget)头猪，每6模拟小时购猪不超过\(purchaseLimit)铜。基础饭食和100铜保护金优先，暂停恢复不刷新额度。")
        try candidate.world.validate()
        self = candidate
    }

    public mutating func pauseHusbandry(_ paused: Bool) throws {
        guard world.husbandry != nil else { throw LifeError.invalid("尚未授权养殖计划") }
        world.husbandry!.enabled = !paused
        world.record("husbandry_policy", paused ? "暂停新购幼猪与新出栏；已经在途、已签工程和已有动物照料继续。" : "恢复原有养殖计划，使用原额度，不补发铜钱。")
    }

    func husbandryNextEvent() -> Int64? {
        world.husbandry?.animals.values.compactMap(\.due).min()
    }

    mutating func settleHusbandry() {
        guard var h = world.husbandry else { return }
        for id in h.animals.keys.sorted() where h.animals[id]?.due == world.time {
            h.animals[id]!.due = nil
            switch h.animals[id]!.stage {
            case .inTransit:
                h.animals[id]!.stage = .atGate
                world.record("animal_arrival", "已付款幼猪\(id)抵达城门，等待牧工牵回；尚未产生肉料。")
            case .growing:
                h.animals[id]!.completedSegments += 1
                h.animals[id]!.stage = h.animals[id]!.completedSegments == h.rules.growthSegments ? .ready : .waitingForCare
                if h.animals[id]!.stage == .ready {
                    world.record("animal_ready", "\(id)完成全部6段成长，等待真实肉食订单；不会自动增加库存。")
                }
            default: break
            }
        }
        world.husbandry = h
    }

    /// Runs on the shared planner. No actor exists solely to justify a resource.
    mutating func planHusbandry() {
        guard let h = world.husbandry else { return }
        let rules = h.rules
        if h.period != world.time / rules.purchasePeriodSeconds {
            world.husbandry!.period = world.time / rules.purchasePeriodSeconds
            world.husbandry!.periodSpent = 0
        }
        // Existing city bootstrapping gets a revenue channel before optional food upgrades.
        if h.enabled, world.growthEnabled, world.buildings["market", default: 0] > 0,
           !world.projects.values.contains(where: { !$0.completed && $0.kind != "seal" }) {
            if world.buildings["pasture", default: 0] == 0 {
                startProject(id: "pasture-1", kind: "pasture", node: "pasture", cash: rules.pastureCash,
                             work: rules.pastureWorkSeconds, materials: rules.pastureMaterials)
            } else if world.buildings["butcher", default: 0] == 0 {
                startProject(id: "butcher-1", kind: "butcher", node: "butcher", cash: rules.butcherCash,
                             work: rules.butcherBenchWorkSeconds, materials: rules.butcherMaterials)
            }
        }
        for id in (world.husbandry?.animals.keys.sorted() ?? []) {
            guard let pig = world.husbandry?.animals[id], pig.taskID == nil else { continue }
            if pig.stage == .atGate {
                var tail: [LifeStep] = []
                if var walk = move("gate", "pasture", loaded: true) { walk.kind = "lead"; tail.append(walk) }
                tail.append(.init(kind: "work", seconds: 10))
                if let task = assign(kind: "pig_receive", job: "herder", subject: id, at: "gate", work: 10, tail: tail) {
                    world.husbandry!.animals[id]!.stage = .receiving
                    world.husbandry!.animals[id]!.taskID = task
                }
            } else if pig.stage == .waitingForCare {
                let committed = world.tasks.values.filter { $0.kind == "pig_care" }.flatMap(\.reservations).reduce(Int64(0)) { $0 + $1.amount }
                guard world.foodEquivalent() - (committed + rules.feedPerSegment) * 4 >= Int64(world.agents.count) * 4000 else {
                    world.husbandry!.lastReason = "先保障居民两周期口粮，已有猪安全等料"; continue
                }
                supply(["grain": rules.feedPerSegment], to: "pasture-in")
                guard let parts = world.selection(.grain, quantity: rules.feedPerSegment, at: "pasture-in"),
                      let task = assign(kind: "pig_care", job: "herder", subject: id, at: "pasture", work: rules.careWorkSeconds) else { continue }
                for p in parts { world.lots[p.lotID]!.reserved += p.amount }
                world.tasks[task]!.reservations = parts
                world.husbandry!.animals[id]!.stage = .caring
                world.husbandry!.animals[id]!.taskID = task
                beginHusbandryStep(task)
            } else if pig.stage == .ready, h.enabled, world.buildings["butcher", default: 0] > 0,
                      wantsMeatProduction, world.foodCoverage >= 9500,
                      world.freeSpace("meat-out") >= rules.meatPerAnimal * LifeResource.meat.volume {
                var tail: [LifeStep] = []
                if var walk = move("pasture", "butcher", loaded: true) { walk.kind = "lead"; tail.append(walk) }
                tail.append(.init(kind: "work", seconds: rules.butcherWorkSeconds))
                if let task = assign(kind: "pig_process", job: "butcher", subject: id, at: "pasture", work: 0, tail: tail) {
                    let space = rules.meatPerAnimal * LifeResource.meat.volume
                    world.tasks[task]!.target = "meat-out"
                    world.tasks[task]!.resource = .meat
                    world.tasks[task]!.quantity = rules.meatPerAnimal
                    world.tasks[task]!.space = space
                    world.storages["meat-out"]!.incoming += space
                    world.husbandry!.animals[id]!.stage = .leading
                    world.husbandry!.animals[id]!.taskID = task
                    break // One meat-processing work point, not one per free worker.
                }
            }
        }
        // Consume no new money merely because a period or a day changed.
        guard let now = world.husbandry, now.enabled else { return }
        guard world.buildings["pasture", default: 0] > 0, world.buildings["butcher", default: 0] > 0 else {
            world.husbandry!.lastReason = "等待牧栏与肉食台实际建成"; return
        }
        guard wantsMeatProduction else { world.husbandry!.lastReason = "当前菜品或肉料已够，暂停新增生产"; return }
        guard now.animals.count < min(now.herdTarget, rules.capacity) else {
            world.husbandry!.lastReason = "按已批准规模照料，等待成熟与出栏"; return
        }
        guard now.purchaseRemaining >= rules.purchasePrice,
              world.treasury - world.reservedCash - rules.purchasePrice >= 100 else {
            world.husbandry!.lastReason = "等待采购额度或真实余款，不透支"; return
        }
        let feedForecast = now.animals.values.reduce(Int64(rules.growthSegments) * rules.feedPerSegment) {
            $0 + Int64(rules.growthSegments - $1.fedSegments) * rules.feedPerSegment
        }
        guard world.foodCoverage >= 9500,
              world.foodEquivalent() - feedForecast * 4 >= Int64(world.agents.count) * 4000 else {
            world.husbandry!.lastReason = "新养殖须先留足居民口粮与后续饲料"; return
        }
        let id = world.next("pig")
        world.treasury -= rules.purchasePrice
        world.husbandry!.periodSpent += rules.purchasePrice
        world.husbandry!.lifetimePurchaseSpent += rules.purchasePrice
        world.husbandry!.purchasedCount += 1
        world.husbandry!.animals[id] = .init(id: id, purchasedAt: world.time, rules: rules)
        world.husbandry!.lastReason = "幼猪已付款，在途到货后由牧工牵回"
        world.record("animal_purchase", "购入幼猪\(id)，实际支付\(rules.purchasePrice)铜（含送至城门），\(rules.deliverySeconds)秒后到达。")
    }

    var wantsMeatProduction: Bool {
        guard let h = world.husbandry, h.enabled, heartyTargetBP > 0 else { return false }
        let pending = world.tasks.values.filter { $0.kind == "pig_process" }.reduce(Int64(0)) { $0 + $1.quantity }
        return world.amount(.meat) + pending < max(8000, Int64(world.agents.count) * 250)
            && !world.tasks.values.contains(where: { $0.kind == "pig_process" })
    }
    var heartyTargetBP: Int { ["supply": 5000, "trade": 2500, "industry": 0, "military": 0, "balanced": 2500][world.policy, default: 0] }
    var prefersHeartyMeal: Bool {
        guard let h = world.husbandry else { return world.policy != "military" }
        guard h.enabled, heartyTargetBP > 0 else { return false }
        let recent = h.recentMeals
        return recent.filter { $0 }.count * 10000 < (recent.count + 1) * heartyTargetBP
    }

    /// Called once on entry to a step, including the initial step of a new task.
    mutating func beginHusbandryStep(_ id: String) {
        guard let task = world.tasks[id], task.current.kind == "work",
              world.husbandry?.animals[task.subject] != nil else { return }
        if task.kind == "pig_care", !task.reservations.isEmpty {
            let feed = task.reservations.reduce(Int64(0)) { $0 + $1.amount }
            world.beginReservedInputs(id)
            world.husbandry!.animals[task.subject]!.fedSegments += 1
            world.husbandry!.consumedFeed += feed
        } else if task.kind == "pig_process" {
            world.husbandry!.animals[task.subject]!.stage = .processing
            world.husbandry!.animals[task.subject]!.node = "butcher"
        }
    }
    mutating func finishHusbandryTask(_ task: LifeTask) {
        guard let h = world.husbandry, h.animals[task.subject] != nil else { return }
        switch task.kind {
        case "pig_receive":
            world.husbandry!.animals[task.subject]!.stage = .waitingForCare
            world.husbandry!.animals[task.subject]!.node = "pasture"
            world.husbandry!.animals[task.subject]!.taskID = nil
        case "pig_care":
            world.husbandry!.animals[task.subject]!.stage = .growing
            world.husbandry!.animals[task.subject]!.taskID = nil
            world.husbandry!.animals[task.subject]!.due = world.time + h.rules.segmentSeconds
        case "pig_process":
            world.husbandry!.animals[task.subject] = nil
            world.husbandry!.processedCount += 1
            world.storages[task.target]!.incoming -= task.space
            world.add(.meat, quantity: task.quantity, at: task.target, origin: task.subject, production: true)
            world.record("meat_produced", "\(world.agents[task.worker]!.name)完成院内加工：\(task.subject)已出栏，\(task.quantity / 1000)筐肉料等待送往厨房。")
        default: break
        }
    }
}
