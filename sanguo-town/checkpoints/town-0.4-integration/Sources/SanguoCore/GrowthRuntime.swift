import Foundation

/// Deterministic event-driven city growth. The UI and the planner use the same validated command transaction.
public enum GrowthRuntime {
    public static func newGame(wallUTC: Int64) -> WorldState {
        var world = Seed.oneCity(wallUTC: wallUTC)
        install(in: &world)
        return world
    }
    static func install(in world: inout WorldState) {
        guard world.growth == nil else { return }
        var growth = RealmGrowth()
        growth.nextPlanning = world.simulationTime
        growth.nextFiscal = (world.simulationTime / GrowthRules.fiscalPeriod + 1) * GrowthRules.fiscalPeriod
        growth.finance.period = world.simulationTime / GrowthRules.fiscalPeriod
        for id in world.cities.keys.sorted() {
            let city = world.cities[id]!
            var plan = DevelopmentPlan(initialHousing: city.population, initialStorage: city.inventory.capacity,
                nextPopulationCheck: (world.simulationTime / 7200 + 1) * 7200)
            for (kind,plot) in [(BuildingKind.hall,0),(.house,1),(.farm,4),(.granary,5)] {
                plan.buildings.append(.init(id:"\(id)-base-\(kind.rawValue)", kind:kind, plot:plot, level:1,
                    restored:kind != .hall, completedAt:world.simulationTime))
            }
            growth.cities[id] = plan
        }
        world.schemaVersion = 2; world.rulesVersion = GrowthRules.version; world.growth = growth
        // Migration never infers paid-for buildings from legacy jobCapacity demo fields.
        for id in world.cities.keys.sorted() { updateCapacities(id, world: &world) }
        for id in world.cities.keys.sorted() { remember(id, title:"初见\(world.cities[id]!.name)", key:"origin-\(id)", pinned:false, world:&world) }
        prepareBatches(world:&world)
    }
    static func freeCash(_ world: WorldState) -> Int64 {
        max(0, world.treasury - (world.growth?.reservedCash ?? 0) - (world.realm?.reservationCash ?? 0) - GrowthRules.protectedCash - (world.growth?.finance.protectedOperating ?? 0))
    }
    static func updateCapacities(_ id: String, world: inout WorldState) {
        guard let plan = world.growth?.cities[id], var city = world.cities[id] else { return }
        let buildings = plan.buildings.filter(\.isOperating)
        let farms = buildings.filter { $0.kind == .farm }.count
        let workshops = buildings.filter { $0.kind == .workshop }.count
        city.jobCapacity = ["grain":max(2,farms*2), "wood":2, "iron":2,
                            "wine":plan.level(.tavern)>0 ? 4 : 0, "tools":workshops*4]
        city.inventory.capacity = max(plan.initialStorage, Int64(max(1,plan.level(.granary)))*1_000_000)
        // Current in-flight batch has its own workers and outputs; capacity upgrades affect the NEXT batch only.
        if plan.batch == nil { city.jobs = [:] }
        world.cities[id] = city
    }
    static func handle(_ action: GameAction, principal: Principal, world: inout WorldState) throws {
        switch action {
        case .acceptDevelopment(let policy,let investment):
            guard principal == .player else { throw GameError.denied("长期治理须主公确认") }
            install(in:&world)
            world.policy = policy; world.growth!.enabled = true; world.growth!.investment = investment
            world.growth!.policyVersion += 1
            world.record("development", "已接受长期治理：\(policy.title)，\(investment.title)再投资；无每日续约。")
            for id in world.cities.keys.sorted() {
                if let b=world.growth!.cities[id]!.batch, b.startedAt == world.simulationTime {
                    for (k,v) in b.inputs { world.cities[id]!.inventory.reserved[k,default:0]-=v }
                    world.growth!.cities[id]!.batch=nil;world.cities[id]!.jobs=[:]
                }
            }
            try manage(world:&world)
            prepareBatches(world:&world)
        case .pauseDevelopment(let pause):
            guard principal == .player, world.growth != nil else { throw GameError.denied("治理暂停范围") }
            world.growth!.enabled = !pause
            world.record("development", pause ? "暂停新增自主建设；已开工项目与基础生产继续。" : "恢复长期治理；不会补发预算。")
            if !pause { try manage(world:&world) }
        case .setInvestment(let style):
            guard principal == .player, world.growth != nil else { throw GameError.denied("再投资须主公决定") }
            world.growth!.investment = style // Applies at next fixed fiscal boundary; no immediate new grant.
        case .lockPlot(let cityID,let plot,let locked):
            guard principal == .player, world.growth?.cities[cityID] != nil, (0..<16).contains(plot) else { throw GameError.denied("地块锁定") }
            var locks = Set(world.growth!.cities[cityID]!.lockedPlots)
            if locked { locks.insert(plot) } else { locks.remove(plot) }
            world.growth!.cities[cityID]!.lockedPlots = locks.sorted()
        case .startBuilding(let cityID,let kind,let plot):
            guard Governance.mayManage(principal, cityID:cityID, prefectAllowed:true, world:world) else { throw GameError.denied("城建范围") }
            try start(cityID:cityID,kind:kind,plot:plot,world:&world)
        case .pauseBuilding(let cityID,let projectID,let paused):
            guard Governance.mayManage(principal,cityID:cityID,prefectAllowed:true,world:world),
                  let index = world.growth?.cities[cityID]?.projects.firstIndex(where: { $0.id == projectID && $0.live }) else { throw GameError.denied("工程暂停范围") }
            world.growth!.cities[cityID]!.projects[index].status = paused ? .paused : .waiting
            world.growth!.cities[cityID]!.projects[index].builders = 0
            world.growth!.cities[cityID]!.projects[index].reason = paused ? "主公暂停，保留预留与进度" : "等待下一个劳力调度点"
        case .cancelBuilding(let cityID,let projectID):
            guard Governance.mayManage(principal,cityID:cityID,prefectAllowed:true,world:world) else { throw GameError.denied("取消范围") }
            try cancel(cityID:cityID,projectID:projectID,world:&world)
        case .authorizeLegion(let cityID,let capacity,let budget):
            guard principal == .player, world.growth != nil, world.cities[cityID] != nil,
                  [30,60,90].contains(capacity), (0...100_000).contains(budget) else { throw GameError.denied("军团须主公批准合法编制和总预算") }
            if world.realm != nil,world.growth!.legion == nil,let plan=world.growth!.cities[cityID],plan.level(.barracks)==0 {
                let occupied=Set(plan.buildings.map(\.plot))
                guard (0..<16).contains(where:{!occupied.contains($0) && !plan.lockedPlots.contains($0)}) else { throw GameError.denied("此城没有可建营地的空地；请先解除空地锁定或选择另一座城市，不会拆除既有建筑") }
            }
            if var legion = world.growth!.legion {
                guard legion.cityID == cityID, capacity >= max(legion.authorizedCapacity, legion.active), budget >= legion.budget else {
                    throw GameError.denied("本版只支持原军团提高编制／总预算；不迁营或删除现役")
                }
                legion.authorizedCapacity = capacity; legion.budget = budget; world.growth!.legion = legion
            } else {
                world.growth!.legion = .init(cityID:cityID,authorizedCapacity:capacity,budget:budget,
                    nextTraining:(world.simulationTime/3600+1)*3600)
            }
            world.growth!.proposals.removeAll { $0.id == "legion" }
            world.record("legion_authorized", "批准逐步整备\(capacity)人，军费总上限\(budget)铜；并未立即生成兵员或授权战争。")
            if world.growth!.enabled { try manage(world:&world) }
        case .rememberCity(let id):
            guard principal == .player, world.appearance(cityID:id) != nil else { throw GameError.denied("城景留影范围") }
            guard world.growth!.memories.filter(\.pinned).count < 20 else { throw GameError.invalid("已固定20张城景，请先导出；本版不自动覆盖") }
            let n = world.growth!.nextID; world.growth!.nextID += 1
            remember(id,title:"手动留影",key:"pinned-\(n)",pinned:true,world:&world)
        default: throw GameError.unsupported("未实现的成长命令")
        }
    }
    static func start(cityID: String, kind: BuildingKind, plot: Int, world: inout WorldState) throws {
        guard var plan = world.growth?.cities[cityID], var city = world.cities[cityID], (0..<16).contains(plot) else { throw GameError.invalid("城建地点") }
        guard !plan.lockedPlots.contains(plot) else { throw GameError.denied("地块已锁定") }
        guard plan.projects.filter(\.live).count < 2 else { throw GameError.denied("普通建设同时最多两项") }
        let existing = plan.buildings.first { $0.plot == plot }
        let isRepair = existing?.kind == .hall && existing?.restored == false
        let target = isRepair ? 1 : (existing?.level ?? 0) + 1
        if let existing {
            guard existing.kind == kind, !plan.projects.contains(where: { $0.buildingID == existing.id && $0.live }),
                  target <= 3, (isRepair || kind.upgradable), existing.level > 0 else { throw GameError.denied("不能替换建筑、重复开工或无效升级") }
        } else if !kind.repeatable && plan.buildings.contains(where: { $0.kind == kind }) {
            throw GameError.denied("此建筑全城唯一")
        }
        guard kind != .hall || isRepair else { throw GameError.denied("府署只能修缮现有实体") }
        let quote = BuildingCatalog.quote(kind:kind,level:target,repair:isRepair)
        guard world.growth!.finance.capital >= quote.cash, freeCash(world) >= quote.cash else { throw GameError.denied("发展额度或自由国库不足") }
        for (key,amount) in quote.materials {
            guard let resource = Resource(rawValue:key), city.inventory.free(resource) >= amount else { throw GameError.denied("材料不足：\(key)") }
        }
        let number = world.growth!.nextID
        let buildingID = existing?.id ?? "\(cityID)-building-\(number)"
        if existing == nil { plan.buildings.append(.init(id:buildingID,kind:kind,plot:plot,level:0,restored:true,completedAt:0)) }
        let project = ConstructionProject(id:"project-\(number)",buildingID:buildingID,targetLevel:target,isRepair:isRepair,
            status:.waiting,startedAt:world.simulationTime,requiredWork:quote.work,cashCost:quote.cash,
            materialCost:quote.materials,policyVersion:world.growth!.policyVersion,reason:"材料与现金已预留，等待劳力")
        for (key,amount) in quote.materials { city.inventory.reserved[key,default:0] += amount }
        plan.projects.append(project)
        world.growth!.finance.capital -= quote.cash; world.growth!.nextID += 1
        world.growth!.cities[cityID] = plan; world.cities[cityID] = city
        world.record("construction_start",actor:city.prefectID,"\(city.name)\(isRepair ? "修缮" : existing == nil ? "新建" : "升级")\(kind.title)：资源已预留，由太守安排施工。")
    }
    static func cancel(cityID: String, projectID: String, world: inout WorldState) throws {
        guard var plan = world.growth?.cities[cityID], let index = plan.projects.firstIndex(where: { $0.id == projectID && $0.live }) else { throw GameError.invalid("工程不存在或已结束") }
        var project = plan.projects[index]
        for (key,amount) in project.materialCost {
            world.cities[cityID]!.inventory.reserved[key,default:0] -= amount - project.materialSpent[key,default:0]
        }
        // Unused permission may be reused, but never mint or refund already-spent cash.
        world.growth!.finance.capital = min(4000,world.growth!.finance.capital + project.cashCost - project.cashSpent)
        project.status = .cancelled; project.builders = 0; project.finishedAt = world.simulationTime
        plan.projects[index] = project
        plan.buildings.removeAll { $0.id == project.buildingID && $0.level == 0 }
        plan.blockedReason = "已取消；已投入材料不返还。地块可锁定以阻止太守重新提案。"
        world.growth!.cities[cityID] = plan
        world.record("construction_cancel", "工程取消，只释放尚未消费的预留；既有建筑与已消费成本保留。")
    }
    static func progress(_ delta: Int64, world: inout WorldState) {
        guard delta > 0 else { return }
        for id in world.cities.keys.sorted() {
            var plan = world.growth!.cities[id]!
            for i in plan.projects.indices where plan.projects[i].status == .working && plan.projects[i].builders > 0 {
                var project = plan.projects[i]
                project.completedWork = min(project.requiredWork, project.completedWork + delta * Int64(project.builders))
                let paid = project.cashCost * project.completedWork / project.requiredWork
                let cashDelta = paid - project.cashSpent
                world.treasury -= cashDelta; world.growth!.finance.capitalSpent += cashDelta
                world.growth!.finance.lifetimeConstruction += cashDelta; project.cashSpent = paid
                for (key,amount) in project.materialCost {
                    let consumed = amount * project.completedWork / project.requiredWork
                    let d = consumed - project.materialSpent[key,default:0]
                    world.cities[id]!.inventory.amounts[key,default:0] -= d
                    world.cities[id]!.inventory.reserved[key,default:0] -= d
                    project.materialSpent[key] = consumed
                }
                plan.projects[i] = project
            }
            world.growth!.cities[id] = plan
        }
    }
    static func finishProjects(world: inout WorldState) -> Bool {
        var changed = false
        for id in world.cities.keys.sorted() {
            var plan = world.growth!.cities[id]!
            var done: [(String,String)] = []
            for i in plan.projects.indices where plan.projects[i].live && plan.projects[i].completedWork >= plan.projects[i].requiredWork {
                let project = plan.projects[i]
                guard let b = plan.buildings.firstIndex(where: { $0.id == project.buildingID }) else { continue }
                plan.buildings[b].level = project.targetLevel; plan.buildings[b].restored = true
                plan.buildings[b].completedAt = world.simulationTime
                plan.projects[i].status = .completed; plan.projects[i].builders = 0; plan.projects[i].finishedAt = world.simulationTime
                plan.projects[i].reason = "建设完成，自动投入运营"
                plan.completedCount += 1; changed = true
                done.append((project.id, "\(plan.buildings[b].kind.title)\(project.isRepair ? "修缮完成" : "\(project.targetLevel)级建成")"))
            }
            // Bounded terminal history; active projects are never discarded.
            if plan.projects.count > 96 { plan.projects = plan.projects.filter(\.live) + Array(plan.projects.filter { !$0.live }.suffix(80)) }
            world.growth!.cities[id] = plan
            if !done.isEmpty {
                updateCapacities(id,world:&world)
                for (key,title) in done {
                    world.record("construction_complete",actor:world.cities[id]!.prefectID,"\(world.cities[id]!.name)：\(title)，不需领取。")
                    remember(id,title:title,key:key,pinned:false,world:&world)
                }
            }
        }
        return changed
    }
    static func prepareBatches(world: inout WorldState) {
        for id in world.cities.keys.sorted() where world.growth!.cities[id]!.batch == nil {
            var city = world.cities[id]!, plan = world.growth!.cities[id]!
            var remaining = city.labor, jobs: [String:Int] = [:]
            func assign(_ resource: Resource, _ requested: Int) {
                let key = resource.rawValue, count = max(0,min(remaining, requested, city.jobCapacity[key,default:0] - jobs[key,default:0]))
                if count > 0 { jobs[key,default:0] += count; remaining -= count }
            }
            // Basic food is mandatory before building labor. Ordinary officials share the same protection rule.
            let urgent = city.inventory.free(.grain) < city.grainFloor
            assign(.grain,urgent ? city.jobCapacity["grain",default:2] : 2)
            let active = plan.projects.indices.filter { plan.projects[$0].live && plan.projects[$0].status != .paused }
            var builderPool = urgent ? 0 : min(active.count*2,max(0,remaining-2))
            for index in plan.projects.indices where plan.projects[index].live { plan.projects[index].builders = 0 }
            // Fair rounds avoid starving a second project behind a multi-day upgrade.
            for _ in 0..<2 { for index in active where builderPool > 0 {
                plan.projects[index].builders += 1; builderPool -= 1; remaining -= 1
            } }
            for index in active {
                plan.projects[index].status = plan.projects[index].builders > 0 ? .working : .waiting
                plan.projects[index].reason = plan.projects[index].builders > 0 ? "实际施工中" : "优先保供／等待可用劳力"
            }
            // The public-works team competes with production and ordinary builders; never creates free workers.
            if world.realm?.civic[id]?.project != nil {
                let count = urgent || world.realm!.civic[id]!.project!.paused ? 0 : min(2,max(0,remaining-2))
                world.realm!.civic[id]!.project!.workers=count;remaining-=count
            }
            assign(.wood,1); assign(.iron,1)
            let order: [Resource]
            switch world.policy(for:city) {
            case .trade: order = [.wine,.tools,.wood,.iron,.grain]
            case .industry,.military: order = [.tools,.wine,.iron,.wood,.grain]
            case .supply: order = [.grain,.tools,.wood,.iron,.wine]
            case .balanced: order = [.tools,.wine,.grain,.wood,.iron]
            }
            for r in order { assign(r,city.jobCapacity[r.rawValue,default:0]) }
            city.jobs = jobs
            var inputs: [String:Int64] = [:], outputs: [String:Int64] = [:], actual: [String:Int] = [:]
            func addOutput(_ r: Resource,_ amount:Int64) {
                let made = max(0,min(amount,city.inventory.capacity-city.inventory[r]-RealmRuntime.incoming(city:id,resource:r,world:world)))
                if made > 0 { outputs[r.rawValue] = made; actual[r.rawValue] = jobs[r.rawValue,default:0] }
            }
            let farmLevels = plan.buildings.filter { $0.kind == .farm && $0.isOperating }.map(\.level)
            let civicFarm = world.realm?.civic[id]?.level(.water) ?? 0
            let farmMultiplier = farmLevels.isEmpty ? 100 : farmLevels.reduce(0) { $0+100+($1-1)*25 } / farmLevels.count
            addOutput(.grain,Int64(jobs["grain",default:0])*5_000*city.grainRatePercent*Int64(farmMultiplier)*Int64(100+civicFarm*3)/1_000_000)
            addOutput(.wood,Int64(jobs["wood",default:0])*6_000)
            addOutput(.iron,Int64(jobs["iron",default:0])*2_000*city.ironRatePercent/100)
            let wineSpeed: Int64 = Int64(100 + max(0,plan.level(.tavern)-1)*25)
            let wines = min(Int64(jobs["wine",default:0])*1000*wineSpeed/100,
                max(0,city.inventory.free(.grain)-city.grainFloor)/5,(city.inventory.capacity-city.inventory[.wine]))
            if wines > 0 { inputs["grain"] = wines*5; addOutput(.wine,wines) }
            let civicIndustry: Int = world.realm?.civic[id]?.level(CivicTrack.industry) ?? 0
            let workshopLevel: Int = plan.level(BuildingKind.workshop)
            let workshopIncrease: Int = max(0,workshopLevel-1)*25
            var toolSpeed: Int64 = 100
            toolSpeed += Int64(workshopIncrease)
            toolSpeed += Int64(civicIndustry)*3
            let tools = min(Int64(jobs["tools",default:0])*500*toolSpeed/100,city.inventory.free(.wood)/4,city.inventory.free(.iron)/2,city.inventory.capacity-city.inventory[.tools])
            if tools > 0 { inputs["wood"] = tools*4; inputs["iron"] = tools*2; addOutput(.tools,tools) }
            for (key,amount) in inputs { city.inventory.reserved[key,default:0] += amount }
            plan.lastWorkKinds = actual.keys.sorted()
            plan.batch = .init(dueAt:world.simulationTime+600,startedAt:world.simulationTime,
                inputs:inputs,outputs:outputs,workers:jobs,population:city.population,prefectID:city.prefectID)
            world.cities[id] = city; world.growth!.cities[id] = plan
        }
    }
    static func finishBatches(world: inout WorldState) -> Bool {
        var didFinish = false
        for id in world.cities.keys.sorted() {
            guard var plan = world.growth?.cities[id], let batch = plan.batch, batch.dueAt <= world.simulationTime else { continue }
            var city = world.cities[id]!
            for (key,amount) in batch.inputs {
                city.inventory.reserved[key,default:0] -= amount; city.inventory.amounts[key,default:0] -= amount
            }
            for (key,amount) in batch.outputs { city.inventory.amounts[key,default:0] += amount }
            let numerator = Int64(batch.population)*500 + city.grainRemainder
            let need = numerator/6; city.grainRemainder = numerator%6
            let paid = min(need,city.inventory.free(.grain)); city.inventory[.grain] -= paid
            plan.residentsSupplySeconds = paid == need ? plan.residentsSupplySeconds+600 : 0
            if paid == need, world.people[batch.prefectID]?.office?.scope == id {
                let since = world.people[batch.prefectID]?.office?.since ?? world.simulationTime
                world.people[batch.prefectID]?.credit(.governance,seconds:Int(max(0,world.simulationTime-max(batch.startedAt,since))))
            }
            plan.batch = nil; city.jobs = [:]
            world.cities[id] = city; world.growth!.cities[id] = plan; didFinish = true
        }
        return didFinish
    }
    static func population(world: inout WorldState) {
        for id in world.cities.keys.sorted() where world.growth!.cities[id]!.nextPopulationCheck <= world.simulationTime {
            var plan = world.growth!.cities[id]!, city = world.cities[id]!
            if plan.residentsSupplySeconds >= 7200 && city.population < min(200,plan.housing) && city.inventory.free(.grain) >= city.grainFloor {
                city.population += 1
                world.record("population", "\(city.name)有新居民入住，现有\(city.population)人；住房来自已完工民居。")
            }
            plan.nextPopulationCheck = world.simulationTime + 7200*100/Int64(100+(world.realm?.civic[id]?.level(.gardens) ?? 0)*5)
            world.cities[id] = city; world.growth!.cities[id] = plan
        }
    }
    static func sellSurplus(world: inout WorldState) {
        guard world.growth!.enabled else { return }
        let prices: [String:Int64] = ["grain":2,"wood":3,"iron":8,"wine":14,"tools":40]
        let commerce=world.realm?.civic.values.map { $0.level(.commerce) }.max() ?? 0
        let demand: [String:Int64] = world.realm == nil ? ["grain":100,"wood":60,"iron":30,"wine":60,"tools":20] : ["grain":25,"wood":15,"iron":8,"wine":Int64(20+commerce*3),"tools":8]
        for id in world.cities.keys.sorted() {
            guard world.growth!.cities[id]!.level(.market)>0 else { continue }
            for r in Resource.allCases {
                let city = world.cities[id]!
                let keep: Int64
                switch r { case .grain: keep=max(city.grainFloor+50_000,150_000); case .wood:keep=120_000;case .iron:keep=60_000;case .wine:keep=5_000;case .tools:keep=12_000 }
                let limit = demand[r.rawValue]! - world.growth!.finance.sales[r.rawValue,default:0]
                let units = max(0,min(limit,(city.inventory.free(r)-keep)/1000))
                if units > 0 {
                    let cash = units*prices[r.rawValue]!
                    world.cities[id]!.inventory[r] -= units*1000; world.treasury += cash
                    world.growth!.finance.sales[r.rawValue,default:0] += units
                    world.growth!.finance.income += cash; world.growth!.finance.lifetimeSales += cash
                }
            }
        }
    }
    static func fiscal(world: inout WorldState) {
        guard world.growth!.nextFiscal <= world.simulationTime else { return }
        let old = world.growth!.finance
        let surplus = max(0,old.income-old.operatingSpent)
        let grant = min(4000, surplus*world.growth!.investment.percent/100 + min(4000,old.capital),freeCash(world))
        world.growth!.finance.period += 1; world.growth!.finance.capital = max(0,grant)
        world.growth!.finance.operating = 250*Int64(world.cities.count)
        world.growth!.finance.income = 0; world.growth!.finance.operatingSpent = 0; world.growth!.finance.sales = [:]
        world.growth!.nextFiscal += GrowthRules.fiscalPeriod
    }
    static func candidates(_ id:String, world:WorldState) -> [(BuildingKind,Int,String)] {
        let plan = world.growth!.cities[id]!, city = world.cities[id]!
        let policy = world.policy(for:city)
        var choices: [(BuildingKind,Int,String)] = []
        let unavailable = Set(plan.projects.filter(\.live).map(\.buildingID))
        func has(_ kind:BuildingKind)->Bool { plan.buildings.contains { $0.kind==kind } }
        func emptyPlot(_ kind:BuildingKind)->Int? {
            let occupied=Set(plan.buildings.map(\.plot)), locked=Set(plan.lockedPlots)
            let preferred=Array((kind.district*4)..<(kind.district*4+4))
            // Reserve sites for essential unique facilities, so cheap housing/farms cannot
            // permanently crowd out workshops, collection channels or a later optional camp.
            let reserved:[Int:BuildingKind] = [8:.market,9:.tavern,10:.workshop,12:.station,14:.stable,15:.barracks]
            let ownSites=reserved.filter{$0.value==kind}.keys.sorted()
            return (ownSites+preferred+Array(0..<16)).first {
                !occupied.contains($0) && !locked.contains($0) && (world.realm == nil || reserved[$0]==nil || reserved[$0]==kind)
            }
        }
        func add(_ kind:BuildingKind,_ why:String) {
            if (!has(kind) || kind.repeatable), let plot=emptyPlot(kind) { choices.append((kind,plot,why)) }
        }
        if let hall=plan.buildings.first(where:{$0.kind == .hall && !$0.restored && !unavailable.contains($0.id)}) { choices.append((.hall,hall.plot,"先修好府署与院落")) }
        if plan.housing < min(48,city.population+4) { add(.house,"住房接近满员，留出安居空间") }
        if !has(.market) { add(.market,"打通本地销售，形成建设现金来源") }
        if world.growth!.legion?.cityID == id && !has(.barracks) { add(.barracks,"为已批准军团建立实际营地") }
        let order:[BuildingKind]
        switch policy {
        case .trade: order=[.tavern,.station,.workshop,.stable]
        case .industry: order=[.workshop,.tavern,.station,.stable]
        case .military: order=[.workshop,.barracks,.tavern,.station,.stable]
        case .supply: order=[.farm,.workshop,.tavern,.stable,.station]
        case .balanced: order=[.workshop,.tavern,.station,.stable]
        }
        for kind in order {
            if kind == .farm {
                if plan.buildings.filter({$0.kind == .farm}).count < 2 { add(.farm,"增加粮食余量和农桑街区") }
            } else if !has(kind) { add(kind,"按\(policy.title)方针完善\(kind.title)") }
        }
        if plan.buildings.filter({$0.kind == .farm}).count < 2 { add(.farm,"为城市增长保留基本供给") }
        let preferred: [BuildingKind] = policy == .trade ? [.market,.tavern,.house,.granary,.workshop,.farm,.barracks] : policy == .industry ? [.workshop,.granary,.house,.farm,.market,.tavern,.barracks] : [.house,.farm,.granary,.workshop,.market,.tavern,.barracks]
        for kind in preferred {
            for b in plan.buildings.sorted(by:{$0.plot<$1.plot}) where b.kind==kind && b.level>0 && b.level<3 && !unavailable.contains(b.id) && !plan.lockedPlots.contains(b.plot) {
                choices.append((kind,b.plot,"改善既有\(kind.title)，不拆旧城"))
            }
        }
        if plan.housing < 48 { add(.house,"扩大安居街区") }
        if policy == .industry && plan.buildings.filter({$0.kind == .workshop}).count<3 { add(.workshop,"形成工造集群") }
        if policy == .supply && plan.buildings.filter({$0.kind == .farm}).count<4 { add(.farm,"扩展田仓街区") }
        return choices.filter { !plan.lockedPlots.contains($0.1) }
    }
    static func purchaseShortfall(_ id:String, materials:[String:Int64], world:inout WorldState) {
        // The mountain agreement establishes a supplier discount at the local depot.
        // This is a disclosed procurement abstraction, not a fictional completed shipment.
        let ironPrice:Int64 = world.realm?.completedGoals.contains(RegionalGoal.mountainTrade.rawValue) == true ? 10:12
        let prices:[String:Int64] = ["wood":5,"iron":ironPrice,"tools":55]
        // Only buy for an affordable selected construction, never arbitrary speculative purchasing.
        for key in materials.keys.sorted() {
            guard let r=Resource(rawValue:key), let price=prices[key] else { continue }
            let city=world.cities[id]!, need=max(0,materials[key]! - city.inventory.free(r))
            let futureOutput=world.growth!.cities[id]!.batch?.outputs[key,default:0] ?? 0
            let room=max(0,city.inventory.capacity-city.inventory[r]-futureOutput-RealmRuntime.incoming(city:id,resource:r,world:world))/1000
            let units=min((need+999)/1000, room, world.growth!.finance.operating/price,freeCash(world)/price)
            if units>0 {
                let cash=units*price
                world.cities[id]!.inventory[r] += units*1000; world.treasury -= cash
                world.growth!.finance.operating -= cash; world.growth!.finance.operatingSpent += cash
            }
        }
    }
    static func manage(world: inout WorldState) throws {
        guard world.growth!.enabled else { return }
        RealmRuntime.manage(world:&world)
        for id in world.cities.keys.sorted() {
            // After the basic town is viable, let a representative project accumulate its budget.
            // Ongoing construction and production continue; this is not a calendar unlock.
            if world.realm != nil, let civic=world.realm!.civic[id],civic.project==nil,civic.levelTotal<24,
               world.growth!.cities[id]!.completedCount>=8,
               [BuildingKind.market,.tavern,.workshop,.stable,.station].allSatisfy({world.growth!.cities[id]!.level($0)>0}),
               !(world.growth!.legion?.cityID == id && world.growth!.cities[id]!.level(.barracks)==0) { continue }
            for _ in 0..<2 {
                guard world.growth!.cities[id]!.projects.filter(\.live).count<2 else { break }
                let list=candidates(id,world:world)
                var started=false
                for (kind,plot,why) in list {
                    let plan=world.growth!.cities[id]!
                    let b=plan.buildings.first {$0.plot==plot}
                    let repair=b?.kind == .hall && b?.restored == false
                    let quote=BuildingCatalog.quote(kind:kind,level:repair ? 1 : (b?.level ?? 0)+1,repair:repair)
                    guard quote.cash <= world.growth!.finance.capital && quote.cash <= freeCash(world) else { continue }
                    // Reserve the future construction cash from the procurement freedom.
                    world.growth!.finance.protectedOperating = quote.cash
                    purchaseShortfall(id,materials:quote.materials,world:&world)
                    world.growth!.finance.protectedOperating = 0
                    do {
                        try start(cityID:id,kind:kind,plot:plot,world:&world)
                        world.growth!.cities[id]!.blockedReason = why
                        started=true;break
                    } catch GameError.denied(_) { continue }
                }
                if !started {
                    world.growth!.cities[id]!.blockedReason = list.isEmpty ? "当前城市已稳定；可继续观城或调整方向。" : "等待发展额度、材料或已锁地块；基础生产继续。"
                    break
                }
            }
        }
        RealmRuntime.manage(world:&world)
        startRecruitment(world:&world)
        propose(world:&world)
    }
    static func startRecruitment(world:inout WorldState) {
        guard var legion=world.growth!.legion, legion.batch==nil, world.realm?.operation?.goal != .securePass, (world.realm?.wounded ?? 0)==0 else { return }
        let plan=world.growth!.cities[legion.cityID]!, city=world.cities[legion.cityID]!
        if legion.active>=legion.authorizedCapacity { legion.pausedReason="已达批准编制，继续有限训练与维护";world.growth!.legion=legion;return }
        let period=world.simulationTime/86_400
        if period != legion.recruitPeriod { legion.recruitPeriod=period;legion.recruitsThisPeriod=0 }
        let n=min(5,legion.authorizedCapacity-legion.active,15-legion.recruitsThisPeriod)
        guard plan.level(.barracks)>0, n>0 else {
            legion.pausedReason=plan.level(.barracks)==0 ? "等待演武场完工" : "等待本地训练名额恢复"
            world.growth!.legion=legion;return
        }
        let cash=Int64(n)*12, grain=Int64(n)*4_000, tools=Int64(n)*500
        guard legion.spent+cash<=legion.budget,freeCash(world)>=cash,
              city.inventory.free(.grain)-grain>=city.grainFloor,city.inventory.free(.tools)>=tools else {
            legion.pausedReason="军需／批准总额不足：暂缓额外征募，民生与现役保留";world.growth!.legion=legion;return
        }
        world.cities[legion.cityID]!.inventory.reserved["grain",default:0]+=grain
        world.cities[legion.cityID]!.inventory.reserved["tools",default:0]+=tools
        legion.batch = .init(dueAt:world.simulationTime+14_400,number:n,cash:cash,grain:grain,tools:tools)
        legion.recruitsThisPeriod += n;legion.pausedReason="正在培养\(n)名新兵；尚未计入现役"
        world.growth!.legion=legion
    }
    static func finishRecruitment(world:inout WorldState, trainingAllowed:Bool = true) {
        guard var legion=world.growth!.legion else { return }
        if let batch=legion.batch, batch.dueAt<=world.simulationTime {
            world.treasury-=batch.cash;legion.spent+=batch.cash
            world.cities[legion.cityID]!.inventory[.grain]-=batch.grain
            world.cities[legion.cityID]!.inventory[.tools]-=batch.tools
            world.cities[legion.cityID]!.inventory.reserved["grain",default:0]-=batch.grain
            world.cities[legion.cityID]!.inventory.reserved["tools",default:0]-=batch.tools
            legion.active+=batch.number;legion.batch=nil
            world.growth!.legion=legion
            world.record("legion_recruit", "\(world.cities[legion.cityID]!.name)军团完成一批培养：\(legion.active)/\(legion.authorizedCapacity)人。")
            if legion.active%30==0 { remember(legion.cityID,title:"军团现役达到\(legion.active)人",key:"legion-\(legion.active)",pinned:false,world:&world) }
        }
        if trainingAllowed && legion.nextTraining<=world.simulationTime {
            if legion.active>0 && world.realm?.operation?.goal != .securePass && world.cities[legion.cityID]!.inventory.free(.grain)>=world.cities[legion.cityID]!.grainFloor { legion.trainedHours=min(216,legion.trainedHours+1) }
            legion.nextTraining=(world.simulationTime/3600+1)*3600
        }
        world.growth!.legion=legion
    }
    static func remember(_ id:String,title:String,key:String,pinned:Bool,world:inout WorldState) {
        guard let snapshot=world.appearance(cityID:id), !world.growth!.memories.contains(where:{$0.id==key}) else { return }
        world.growth!.memories.append(.init(id:key,title:title,pinned:pinned,snapshot:snapshot))
        while world.growth!.memories.filter({!$0.pinned}).count>60 {
            let i=world.growth!.memories.firstIndex { !$0.pinned && !$0.id.hasPrefix("origin") && !$0.id.hasPrefix("day-") } ?? world.growth!.memories.firstIndex {!$0.pinned}!
            world.growth!.memories.remove(at:i)
        }
    }
    static func checkpoints(world:inout WorldState) {
        while world.growth!.nextCheckpointIndex < world.growth!.pendingCheckpoints.count {
            let i=world.growth!.nextCheckpointIndex, day=world.growth!.pendingCheckpoints[i]
            guard world.growth!.normalGrowthSeconds>=day else { break }
            for id in world.cities.keys.sorted() { remember(id,title:"第\(day/86_400)成长日",key:"day-\(day)-\(id)",pinned:false,world:&world) }
            world.growth!.nextCheckpointIndex+=1
        }
    }
    static func propose(world:inout WorldState) {
        guard world.growth!.enabled, world.growth!.legion == nil,
              world.growth!.cities.values.contains(where:{$0.completedCount>=6}),
              !world.growth!.proposals.contains(where:{$0.id=="legion"}) else { return }
        let now=world.simulationTime
        world.growth!.proposalTimes.removeAll { now-$0>=168*3600 }
        guard world.growth!.proposalTimes.count<2,world.growth!.proposals.count<3,
              now-(world.growth!.proposalTimes.last ?? -259_200)>=259_200 else { return }
        world.growth!.proposalTimes.append(now)
        world.growth!.proposals.append(.init(id:"legion",title:"是否开始培养护送军团？",createdAt:now,
            detail:"城建已有基础。批准30／60／90目标后自动训练；不处理则继续养城，不自动开战。"))
    }
    @discardableResult
    public static func advance(to wallUTC:Int64,world:inout WorldState) throws -> AdvanceResult {
        guard wallUTC>world.lastWallUTC else { return .init(simulatedSeconds:0,restedSeconds:0,tickCount:0) }
        let elapsed=wallUTC-world.lastWallUTC,active=min(elapsed,GrowthRules.offlineLimit)
        let target=world.simulationTime+active
        guard target<=31_536_000_000 else { throw GameError.invalid("模拟时钟上限") }
        var draft=world,ticks=0
        while draft.simulationTime<target {
            let now=draft.simulationTime
            var next=RealmRuntime.nextEvent(draft,fallback:min(target,draft.growth!.nextPlanning,draft.growth!.nextFiscal))
            for p in draft.growth!.cities.values {
                next=min(next,p.nextPopulationCheck,p.batch?.dueAt ?? target)
                for b in p.projects where b.status == .working && b.builders>0 {
                    next=min(next,now+(b.requiredWork-b.completedWork+Int64(b.builders)-1)/Int64(b.builders))
                }
            }
            if let legion=draft.growth!.legion { next=min(next,legion.batch?.dueAt ?? target,legion.nextTraining) }
            let checkpointIndex=draft.growth!.nextCheckpointIndex
            if checkpointIndex<draft.growth!.pendingCheckpoints.count {
                next=min(next,now+max(0,draft.growth!.pendingCheckpoints[checkpointIndex]-draft.growth!.normalGrowthSeconds))
            }
            next=max(now,next)
            let delta=next-now
            RealmRuntime.progress(delta,world:&draft)
            progress(delta,world:&draft);draft.growth!.normalGrowthSeconds+=delta;draft.simulationTime=next
            var changed=finishProjects(world:&draft)
            RealmRuntime.finish(world:&draft,normal:true)
            if finishBatches(world:&draft) { changed=true; sellSurplus(world:&draft) }
            finishRecruitment(world:&draft)
            population(world:&draft)
            if draft.growth!.nextFiscal<=next { fiscal(world:&draft);changed=true }
            if draft.growth!.nextPlanning<=next {
                try Governance.govern(world:&draft)
                draft.growth!.nextPlanning=(next/1800+1)*1800;changed=true
            }
            if changed { try manage(world:&draft) }
            prepareBatches(world:&draft)
            checkpoints(world:&draft)
            // Revisions reflect deterministic simulation time, never number of UI refreshes.
            draft.revision+=delta
            ticks+=1
            guard ticks<2_000_000 else { throw GameError.invalid("事件循环超过安全上限") }
        }
        if elapsed>active {
            drain(seconds:elapsed-active,world:&draft)
            draft.record("rest","正常补算30日；仅已完全承诺的有限工程安全收尾，其余安全休整。")
        }
        draft.lastWallUTC=wallUTC
        try draft.validate();world=draft
        return .init(simulatedSeconds:active,restedSeconds:elapsed-active,tickCount:ticks)
    }
    static func drain(seconds:Int64,world:inout WorldState) {
        // No new production, budgets, population, proposals or chained projects beyond the cap.
        // Fully reserved, already assigned projects retain their workforce for bounded safe completion.
        let origin=world.simulationTime
        let end=origin+min(seconds,31_536_000_000-origin)
        var next=origin
        while next<end {
            var due=end;var any=false
            for plan in world.growth!.cities.values {
                if let b=plan.batch { due=min(due,b.dueAt);any=true }
                for p in plan.projects where p.status == .working && p.builders>0 {
                    due=min(due,next+(p.requiredWork-p.completedWork+Int64(p.builders)-1)/Int64(p.builders));any=true
                }
            }
            if let b=world.growth!.legion?.batch { due=min(due,b.dueAt);any=true }
            let realmDue=RealmRuntime.nextEvent(world,fallback:Int64.max,normal:false)
            if realmDue != Int64.max { due=min(due,realmDue);any=true }
            if !any { break }
            due=max(next,due);RealmRuntime.progress(due-next,world:&world);progress(due-next,world:&world);world.simulationTime=due
            RealmRuntime.finish(world:&world,normal:false)
            _=finishProjects(world:&world)
            // Complete reserved production outputs but no new batches or routine food demand in the rest segment.
            for id in world.cities.keys.sorted() {
                if let b=world.growth!.cities[id]!.batch,b.dueAt<=due {
                    for (k,v) in b.inputs { world.cities[id]!.inventory.reserved[k,default:0]-=v;world.cities[id]!.inventory.amounts[k,default:0]-=v }
                    for (k,v) in b.outputs { world.cities[id]!.inventory.amounts[k,default:0]+=v }
                    world.growth!.cities[id]!.batch=nil;world.cities[id]!.jobs=[:]
                }
            }
            if world.growth!.legion?.batch?.dueAt ?? Int64.max <= due { finishRecruitment(world:&world,trainingAllowed:false) }
            world.revision+=due-next;next=due
        }
        world.growth!.nextPlanning=world.simulationTime
        world.growth!.nextFiscal=(world.simulationTime/GrowthRules.fiscalPeriod+1)*GrowthRules.fiscalPeriod
        for id in world.cities.keys.sorted() { world.growth!.cities[id]!.nextPopulationCheck=world.simulationTime+7200 }
        if world.growth!.legion != nil { world.growth!.legion!.nextTraining=world.simulationTime+3600 }
        if world.realm != nil {
            world.realm!.nextRecovery=world.simulationTime+3600
            world.realm!.nextStudy=world.simulationTime+3600
            world.realm!.nextTrade=(world.simulationTime/7200+1)*7200
        }
        // On next normal advance, the standing plan resumes without renewing appointments.
    }
}
