import Foundation

/// First playable slice of life-0.7.2. Uses one deterministic timeline, independent of rendering.
/// Older WorldState saves are intentionally not accepted or rewritten by this type.
public struct LifeRuntime: Sendable {
    public let catalog: LifeCatalog
    public let definition:LifeGachaDefinition?
    public let economy:LifeEconomyPacing?
    public internal(set) var world: LifeWorld
    public init(catalog:LifeCatalog,wallUTC:Int64,heroPreview:Bool=false,gachaMode:Bool=false,formalHeroTown:Bool=false,rngSeed:UInt64?=nil) throws {
        let gachaMode=gachaMode || formalHeroTown
        let heroPreview=heroPreview || gachaMode
        definition=gachaMode ? (formalHeroTown ? try .formalV12():try .bundled()):nil
        economy=formalHeroTown ? try .bundled():nil
        var selected=heroPreview ? catalog.heroPreviewCatalog() : catalog
        if let definition {
            selected.recipes=definition.recipes;selected.buildings=definition.buildings
            if formalHeroTown {selected=try selected.withV12Roster(using:definition)}
        }
        economy?.apply(to:&selected)
        self.catalog=selected;world=LifeWorld(wallUTC:wallUTC)
        if heroPreview { world.format=3;world.rules="hero-town-0.8-preview1";world.treasury=400;world.growthEnabled=false }
        if gachaMode {
            world.format=4;world.rules=formalHeroTown ? LifeHeroTownContract.rules:"hero-town-0.9-preview1"
            world.treasury=200;world.gacha = .init(rng:rngSeed ?? UInt64.random(in:UInt64.min...UInt64.max));world.growthEnabled=true
            if formalHeroTown {
                world.heroTown = .initial(wallUTC:wallUTC)
                world.gacha!.rosterPhase=0
                world.gacha!.goldRebalance = .init(historicalIngots:0,historicalCoins:0,
                                                  coinsPerNewIngot:economy!.coin_per_ingot)
            }
        }
        let assets:[(String,String,Int64,[LifeResource:Int64])] = [
            ("warehouse","warehouse",512,[.grain:56000,.wood:36000,.stone:12000,.iron:6000,.tools:4000]),
            ("kitchen-in","kitchen",64,[.grain:8000,.wood:4000]),("kitchen-out","kitchen",64,[:]),
            ("home-meals","home",16,[.meal:30000]),("hall-meals","hall",16,[.meal:2000]),
            ("trees","trees",24,[:]),("mine","mine",24,[:]),("quarry","quarry",24,[:]),
            ("forge-in","workshop",64,[:]),("forge-out","workshop",64,[:]),
            ("ration-in","ration",64,[:]),("ration-out","ration",64,[:]),("recruit","hall",64,[:])]
        for (id,node,cap,stock) in assets {
            world.storages[id] = .init(node:node,capacity:cap*1_000_000)
            let previewStock:[LifeResource:Int64] = id=="warehouse" ? [.grain:24000,.wood:20000,.stone:8000,.iron:4000,.tools:2000] : (id=="home-meals" ? [.meal:10000] : [:])
            for r in LifeResource.allCases {if let q=(heroPreview ? previewStock : stock)[r] {world.add(r,quantity:q,at:id,origin:"founding");world.initial[r.rawValue,default:0]+=q}}
        }
        if formalHeroTown {world.storages["clinic-meals"] = .init(node:"clinic",capacity:12_000_000)}
        let names=["阿禾","谷生","林生","石安","禾娘","阿担","阿车","阿运","木成","筑安","仓平","井清","卫平","夜安","阿勤"]
        let jobs=["farmer","farmer","logger","miner","cook","porter","porter","porter","builder","builder","clerk","handyman","guard_day","guard_night","flex"]
        for i in 0..<15 {let id=String(format:"r%02d",i+1);world.agents[id] = .init(id:id,name:names[i],job:jobs[i],node:"home",home:"home",dining:"home-meals")}
        world.agents["xunyu"] = .init(id:"xunyu",name:catalog.hero("xunyu")!.name,job:"prefect",node:"hall",home:"home",dining:"hall-meals",heroID:"xunyu")
        if heroPreview {
            world.agents=[:];world.owned=[];world.discovered=[]
            for (id,job,node) in [("xunyu","cook","kitchen"),("liubei","farmer","farm"),("zhangfei","logger","trees"),("zhaoyun","porter","warehouse"),("huangyueying","builder","hall")] {
                guard let hero=catalog.hero(id) else {throw LifeError.invalid("缺少开局武将：\(id)")}
                world.agents[id] = .init(id:id,name:hero.name,job:job,node:node,home:"home",dining:"home-meals",heroID:id,origin:"founding")
                world.owned.append(id);world.discovered.append(id)
                if gachaMode {world.gacha!.stars[id]=1}
            }
        }
        world.stations["kitchen"] = .init(id:"kitchen",node:"kitchen",input:"kitchen-in",output:"kitchen-out",kind:"kitchen")
        world.stations["forge"] = .init(id:"forge",node:"workshop",input:"forge-in",output:"forge-out",kind:"forge")
        world.stations["ration"] = .init(id:"ration",node:"ration",input:"ration-in",output:"ration-out",kind:"ration")
        for i in 0..<4 {let id="field-\(i)";world.fields[id] = .init(id:id,state:i==0 ? "growing2":"empty",due:i==0 ? 360:nil);world.storages[id] = .init(node:id,capacity:64_000_000)}
        if gachaMode {setupGoldTown()}
        if formalHeroTown {syncFormalCapacities()}
        startProject(id:"repair",kind:"repair",node:"hall",cash:gachaMode ? 0:20,work:600,materials:["wood":4000,"stone":2000])
        world.record("founding",heroPreview ? "五将共建一城：先收第一茬粮，再一起吃上热饭。偏好不是禁令，缺人时会互相帮忙。" : "荀彧接掌小城：先供好饭，再修好府署。30将图鉴已载入，只有荀彧已加入。")
        if formalHeroTown {
            world.heroTown!.city.plots[1].occupancy=5
            world.record("authority","玩家已一次授权太守自动经营；招募和培养资产仍只接受玩家命令。")
        }
        plan(); world.nextPlan=30
        try world.validate()
    }
    public init(catalog:LifeCatalog,world:LifeWorld) throws {
        var loaded=world
        if loaded.isFormalHeroTown,loaded.heroTown?.health == nil {loaded.heroTown!.health = .initial()}
        if loaded.isFormalHeroTown,loaded.gacha?.rosterPhase == nil {loaded.gacha!.rosterPhase=0}
        economy=loaded.isFormalHeroTown ? try .bundled():nil
        if let economy,loaded.gacha?.goldRebalance == nil {
            let ingots=loaded.consumed["gold_ingot",default:0]/1000
            loaded.gacha!.goldRebalance = .init(historicalIngots:ingots,historicalCoins:loaded.gacha!.minted,
                                               coinsPerNewIngot:economy.coin_per_ingot)
        }
        Self.synchronizeMealDepots(in:&loaded)
        try loaded.validate();definition=loaded.isGacha ? (loaded.isFormalHeroTown ? try .formalV12():try .bundled()):nil
        var selected=loaded.isHeroPreview ? catalog.heroPreviewCatalog():catalog
        if let definition {
            selected.recipes=definition.recipes;selected.buildings=definition.buildings
            if loaded.isFormalHeroTown {selected=try selected.withV12Roster(using:definition)}
        }
        economy?.apply(to:&selected)
        self.catalog=selected;self.world=loaded
    }
    public mutating func advance(to target:Int64) throws {
        guard target>=world.time, target-world.time<=2_592_000, target<=315_360_000 else {throw LifeError.invalid("模拟时间倒退或超出单次30天补算上限")}
        var candidate=self
        while candidate.world.time<target {
            let next=min(target,candidate.nextEvent())
            guard next>candidate.world.time else {throw LifeError.invalid("生活事件未前进")}
            candidate.world.time=next;candidate.settle()
        }
        try candidate.world.validate();self=candidate
    }
    func nextEvent() -> Int64 {
        var n=world.nextPlan
        if let due=world.campaign?.training?.dueSim {n=min(n,due)}
        if let due=world.campaign?.mission?.dueSim {n=min(n,due)}
        if let due=world.campaign?.transfer?.dueSim {n=min(n,due)}
        if let returns=world.campaign?.returningGarrisonHeroes {for due in returns.values {n=min(n,due)}}
        for t in world.tasks.values {n=min(n,t.due)}
        for f in world.fields.values {if let d=f.due {n=min(n,d)}}
        for s in world.stations.values {if let d=s.due {n=min(n,d)}}
        for r in world.recruits.values {if let d=r.due {n=min(n,d)}}
        for due in world.gacha?.arrivals.values ?? [:].values where due>world.time {n=min(n,due)}
        for pig in world.husbandry?.pigs.values ?? [:].values { if let due=pig.due { n=min(n,due) } }
        let base=world.time/2880*2880
        for o:Int64 in [240,420,600,780,1800,1920,1980,2160,2880] where base+o>world.time {n=min(n,base+o)}
        return n
    }
    mutating func settle() {
        // Deliveries and work completions precede consumption and deadlines at the same instant.
        for id in world.tasks.keys.sorted() where world.tasks[id]?.due == world.time {finishStep(id)}
        for id in world.fields.keys.sorted() {if world.fields[id]?.due==world.time {
            world.fields[id]!.due=nil
            world.fields[id]!.state=world.fields[id]!.state=="growing1" ? "water2":"ripe"
        }}
        for id in world.stations.keys.sorted() {if world.stations[id]?.due==world.time {world.stations[id]!.due=nil;world.stations[id]!.phase="finish"}}
        for id in world.recruits.keys.sorted() {if world.recruits[id]?.due==world.time {world.recruits[id]!.due=nil;world.recruits[id]!.state="finish"}}
        settleHusbandry()
        settleWar()
        if world.isFormalHeroTown,world.isNight {world.heroTown!.adminLease=nil;world.counters["admin_lease"]=0}
        updateMeals()
        settleHeroArrivals()
        if world.isFormalHeroTown {evaluateHealthCycle();recoverHealthAtHome()}
        if world.time==world.nextPlan {plan();world.nextPlan+=30}
    }
    public mutating func setPolicy(_ value:String) throws {
        guard ["supply","trade","industry","military","balanced"].contains(value) else{throw LifeError.invalid("未知方针")}
        world.policy=value;world.record("policy","已调整城市方向；在途货物和当前加工不撤销。")
    }
    public mutating func requestSeal() throws {
        guard !world.isGacha else {throw LifeError.invalid("酒馆版收藏工程由后续版本开放，不花招募金币")}
        guard !world.owned.contains("founders_seal"),world.projects["founders_seal"]==nil,world.treasury-world.reservedCash>=110 else{throw LifeError.invalid("木印已完成、正在制作或余款不足；未重复扣费")}
        startProject(id:"founders_seal",kind:"seal",node:"seal",cash:10,work:360,materials:["wood":2000])
        world.record("wish","已授权制作开城木印：10铜、木材2、360人工秒；完成后自动入藏。")
    }
    public mutating func requestRecruit(_ id:String?) throws {
        guard !world.isHeroPreview else {throw LifeError.invalid("五将试玩暂未开放新版招募")}
        if let id {guard catalog.hero(id) != nil,world.discovered.contains(id),!world.owned.contains(id) else{throw LifeError.invalid("该人物尚未发现或已经加入")}}
        world.wish=id
        if let id,world.recruits[id]==nil {world.recruits[id] = .init()}
    }
    func profile(_ agent:LifeAgent,role:String="worker") -> LifeAbilitySource {
        let h=agent.heroID.flatMap{catalog.hero($0)} ?? .init(id:agent.id,name:agent.name,starting:false,attributes:["administration":50,"strategy":50,"valor":50,"command":50],skill_ids:[])
        return .init(h,role:role,eligible:true)
    }
    func leaders() -> [LifeAbilitySource] {
        if world.isHeroPreview && (world.isNight || world.counters["admin_lease",default:0]<=world.time) {return []}
        return world.agents[world.prefect].map{[profile($0,role:"prefect")]} ?? []
    }
    func rate(_ agent:LifeAgent,job:String) -> Int {
        if world.isGacha {
            let base=job=="physician" ? physicianWorkRate(agent):starWorkRate(agent,job:job)
            let pacingBonus=world.isFormalHeroTown && LifeTownPacingContract.resourceJobs.contains(job)
                ? LifeTownPacingContract.formalResourceWorkRateBonusBP:0
            let happinessBonus=world.isFormalHeroTown ?
                LifeHappinessContract.workModifierBP(happiness:world.happiness,job:job):0
            return min(14000,max(8000,base+healthWorkModifier(agent.id)+pacingBonus+happinessBonus))
        }
        let seconds=agent.workSeconds[job,default:0], xp=seconds/300
        let level=1+[60,180,360,600].filter{xp>=Int64($0)}.count
        return (try? LifeAbilities.workRate(catalog,worker:profile(agent),job:job,leaders:leaders().filter{$0.id != agent.id},level:level)) ?? 10000
    }
    func protectedConstructionHeroID() -> String? {
        guard world.isFormalHeroTown,
              world.foodCoverage>=LifeTownPacingContract.protectedBuilderFoodCoverageBP,
              world.heroTown?.city.supplyRecovery != true,
              world.projects.values.contains(where:{!$0.completed}) else{return nil}
        var bestID:String?
        var bestRate=Int.min
        for agent in world.agents.values {
            guard agent.job != "prefect",agent.job != "guard_night",agent.job != "guard_day",
                  healthAllows(heroID:agent.id,job:"builder") else{continue}
            let workRate=rate(agent,job:"builder")
            if workRate>bestRate || (workRate==bestRate && (bestID.map{agent.id<$0} ?? true)) {
                bestID=agent.id
                bestRate=workRate
            }
        }
        return bestID
    }
    func move(_ from:String,_ to:String,loaded:Bool=false) -> LifeStep? {
        guard from != to else{return nil}
        let path=LifeMap.path(from,to)
        return .init(kind:loaded ? "carry":"walk",seconds:max(1,Int64(ceil(LifeMap.length(path)/(loaded ? 32:48)))),route:path,destination:to)
    }
    mutating func assign(kind:String,job:String,subject:String,at node:String,work:Int64,tail:[LifeStep]=[],only:String?=nil,eligible:Set<String>?=nil,longDuty:Bool=false,necessaryService:Bool=false) -> String? {
        let phase=world.phase
        let protectedBuilder=only==nil && job != "builder" ? protectedConstructionHeroID():nil
        let available=world.agents.values.filter {a in
            guard a.taskID==nil else{return false}
            // A clinic admission reserves the person, not just each small
            // treatment task. Otherwise another planner can dispatch the
            // patient during the gap between clinical phases.
            guard world.heroTown?.health?.treatments[a.id]==nil || job=="patient" else{return false}
            // A capital-based officer may still eat and sleep while reserved for
            // military duty. Expedition heroes are physically away and cannot.
            guard !world.warAwayHeroIDs.contains(a.id) else{return false}
            if world.warLockedHeroIDs.contains(a.id) && !["meal_trip","eat","home"].contains(kind) {return false}
            guard healthAllows(heroID:a.id,job:job),job != "physician" || healthCondition(a.id)==nil else{return false}
            if let eligible,!eligible.contains(a.id) {return false}
            if let only {return a.id==only}
            if a.id==protectedBuilder {return false}
            guard a.job != "prefect",a.job != "guard_night",a.job != "guard_day",phase >= (world.isHeroPreview ? 0 : 240),phase < (necessaryService ? 2160:1920) else{return false}
            if let meal=world.meals.last(where:{!$0.closed && $0.expected.contains(a.id) && $0.served[a.id]==nil}),world.time>=meal.at-120 {
                if world.amount(.meal,at:a.dining)>=1000 || !["cook","porter"].contains(job) {return false}
            }
            return true
        }.sorted { a,b in
            let pa=a.job==job ? 0:(a.job=="flex" ? 1:2),pb=b.job==job ? 0:(b.job=="flex" ? 1:2)
            if pa != pb{return pa<pb}
            let da=LifeMap.length(LifeMap.path(a.node,node)),db=LifeMap.length(LifeMap.path(b.node,node))
            return da==db ? a.id<b.id:da<db
        }
        if world.isFormalHeroTown,only==nil,["build","survey"].contains(kind) || (kind=="gather" && subject=="goldmine") || (kind=="prepare" && subject=="smelter") {
            guard available.count>2 else{return nil}
        }
        for a in available {
            let r=rate(a,job:job);var steps:[LifeStep]=[]
            if let m=move(a.node,node){steps.append(m)}
            if work>0 {steps.append(.init(kind:"work",seconds:max(1,(work*10000+Int64(r)-1)/Int64(r))))}
            steps+=tail
            if steps.isEmpty {continue}
            let duration=steps.reduce(Int64(0)){$0+$1.seconds}
            let endNode=steps.last(where:{!$0.destination.isEmpty})?.destination ?? node
            let returnHome=world.isGacha ? (move(endNode,a.home)?.seconds ?? 0):0
            if only==nil,let meal=world.meals.last(where:{!$0.closed && !world.warAwayHeroIDs.contains(a.id) && $0.served[a.id]==nil}),
               let dining=world.storages[a.dining],
               world.time+duration+(move(endNode,dining.node)?.seconds ?? 0)+31>meal.deadline,
               !necessaryService {
                // A dispatch may start before the old fixed 120-second meal
                // cutoff yet finish after the real deadline. Keep this worker
                // available to walk home and eat. Reserve one 30-second
                // planning cadence plus the arrival step after work finishes;
                // otherwise a miner can finish just before the deadline but
                // miss it while waiting for the next meal-trip assignment.
                // Real last-mile meal delivery
                // may still take precedence when others depend on it.
                continue
            }
            if only==nil && !longDuty && (phase+duration+returnHome>2160 || (a.serviceSeconds+duration+returnHome>1920 && a.busyCycle==world.cycle)){continue}
            let id=world.next("task")
            world.tasks[id] = .init(id:id,worker:a.id,kind:kind,job:job,subject:subject,steps:steps,started:world.time,due:world.time+steps[0].seconds,rate:r)
            if world.isFormalHeroTown,let star=world.gacha?.stars[a.id],let skills=definition?.hero(a.id)?.skills {
                let active=skills.filter{$0.unlock_star<=star && $0.jobs?.contains(job)==true}.map(\.id)
                let retained=max(0,r-10000)
                let snapshot=LifeSkillSnapshot(id:"skill-\(id)",contentHash:LifeHeroTownContract.contentHash,heroID:a.id,star:star,skillIDs:active,metric:"work_rate_bp",value:r,retainedValue:retained,eventID:id)
                world.tasks[id]!.skillSnapshot=snapshot
                world.heroTown!.skillSnapshots.append(snapshot)
                if world.heroTown!.skillSnapshots.count>10000 {world.heroTown!.skillSnapshots.removeFirst(world.heroTown!.skillSnapshots.count-10000)}
            }
            world.agents[a.id]!.taskID=id
            if let rest=world.agents[a.id]!.restStart,world.time-rest>=600 {world.agents[a.id]!.restedCycle=world.cycle}
            world.agents[a.id]!.restStart=nil
            if world.agents[a.id]!.busyCycle != world.cycle {world.agents[a.id]!.busyCycle=world.cycle;world.agents[a.id]!.serviceSeconds=0}
            world.agents[a.id]!.serviceSeconds+=duration
            if !["home","meal_trip","eat"].contains(kind) {
                noteFirstDutyAssigned(heroID:a.id,taskID:id,job:job,destination:label(node),
                                      atWork:!["walk","carry"].contains(steps[0].kind))
            }
            return id
        }
        return nil
    }
    mutating func finishStep(_ id:String) {
        guard var task=world.tasks[id] else{return}
        if !task.current.destination.isEmpty {world.agents[task.worker]!.node=task.current.destination}
        if ["work","load","unload"].contains(task.current.kind) && !["eat","home","meal_trip"].contains(task.kind) {world.agents[task.worker]!.workSeconds[task.job,default:0]+=task.current.seconds}
        if ["haul","export"].contains(task.kind) && task.current.kind=="load" {
            for p in task.reservations {
                let lot=world.lots[p.lotID]!
                world.lots[p.lotID]!.amount-=p.amount;world.lots[p.lotID]!.reserved-=p.amount
                world.add(lot.resource,quantity:p.amount,at:id,quality:lot.quality,origin:lot.origin)
            }
            task.reservations=[];world.pruneLots()
        }
        if task.kind=="haul",task.current.kind=="unload",task.target.hasPrefix("war-"),
           let cityID=task.target.split(separator:"-").last.map(String.init),
           let city=world.campaign?.cities[cityID],(city.owner != "player" || !city.supplied) {
            // The destination was lost while this physical cargo was on the
            // road. Do not credit an enemy/isolated warehouse: turn the same
            // porter and lot around, preserving them across save/load.
            if world.freeSpace("warehouse")>=task.space {
                let abandoned=task.target
                world.storages[abandoned]!.incoming-=task.space
                world.storages["warehouse"]!.incoming+=task.space
                let returnSeconds=task.steps.filter{$0.kind=="carry"}.last?.seconds ?? 600
                task.target="warehouse"
                task.steps.insert(.init(kind:"carry",seconds:returnSeconds,destination:"hall"),at:task.step)
                task.started=world.time
                task.due=world.time+returnSeconds
                world.tasks[id]=task
                world.record("war","\(city.name)补给线中断；\(world.agents[task.worker]!.name)携在途\(task.resource!.title)原路返回首都，未计入失联城库存。")
                return
            }
            task.due=world.time+300
            world.tasks[id]=task
            return
        }
        if task.kind=="haul" && task.current.kind=="unload" {
            for key in world.lots.keys.sorted() where world.lots[key]!.location==id {world.lots[key]!.location=task.target}
            world.storages[task.target]!.incoming-=task.space
            world.counters["deliveries",default:0]+=1
            world.record("delivery","\(world.agents[task.worker]!.name)将\(String(format:"%.2f",Double(task.quantity)/1000))份\(task.resource!.title)送达\(label(task.target))。")
            if world.isGacha,task.target=="mint" {mintDeliveredGold()}
        }
        if task.kind=="export" && task.current.kind=="external_sale" {
            _=world.consume(task.resource!,quantity:task.quantity,at:task.id)
        }
        task.step+=1
        if task.step<task.steps.count {
            task.started=world.time;task.due=world.time+task.current.seconds;world.tasks[id]=task
            if !["walk","carry"].contains(task.current.kind) {noteFirstDutyArrived(heroID:task.worker,taskID:id)}
            if task.kind=="prepare",task.current.kind=="work" {
                world.beginReservedInputs(id)
                if let s=world.stations[task.subject],let recipe=s.recipe {
                    world.stations[task.subject]!.foodInProcess=catalog.recipe(recipe)!.output_mU["meal",default:0]
                }
            }
            if task.current.kind=="work" { beginHusbandryWork(id) }
            return
        }
        world.tasks[id]=nil;world.agents[task.worker]!.taskID=nil
        finishTask(task)
    }
    mutating func finishTask(_ t:LifeTask) {
        switch t.kind {
        case "survey":
            world.projects[t.subject]!.materials["wood"]=t.contribution
            world.gacha!.surveyedProjects.insert(t.subject)
            world.record("skill","\(world.agents[t.worker]!.name)完成现场勘测，工程木材报价减少10%。")
        case "star_patrol":
            world.counters["patrols",default:0]+=1
            world.counters["star_patrol_cycle"]=Int(world.cycle)
            if t.contribution==5 {world.counters["star_environment_until"]=Int((world.cycle+1)*2880)}
        case "administration":
            world.counters["admin_lease"]=Int(world.time+600)
            if world.isFormalHeroTown {world.heroTown!.adminLease = .init(sourceHeroID:t.worker,taskID:t.id,completedAt:world.time,expiresAt:world.time+600)}
            world.record("administration","\(world.agents[t.worker]!.name)处理完城务，治理加成持续600秒；随后继续参与日常劳动。")
        case "pig_arrive", "pig_care", "pig_process": finishHusbandryTask(t)
        case "export":
            world.treasury+=t.contribution;world.counters["external_transactions",default:0]+=1
            world.record("trade","商旅交货返城，实际回款\(t.contribution)铜；居民吃饭不产生铜钱。")
        case "sow":world.fields[t.subject]!.state="water1";world.fields[t.subject]!.taskID=nil
        case "water":
            let c=catalog.crops.first{$0.id==world.fields[t.subject]!.crop}!
            world.fields[t.subject]!.state=world.fields[t.subject]!.state=="watering1" ? "growing1":"growing2"
            world.fields[t.subject]!.due=world.time+c.mature_s/2;world.fields[t.subject]!.taskID=nil
        case "harvest":
            let c=catalog.crops.first{$0.id==world.fields[t.subject]!.crop}!
            for (key,q) in c.output_mU {world.storages[t.subject]!.incoming-=q*LifeResource(rawValue:key)!.volume;world.add(LifeResource(rawValue:key)!,quantity:q,at:t.subject,origin:t.id,production:true)}
            world.fields[t.subject]!.state="empty";world.fields[t.subject]!.taskID=nil;world.fields[t.subject]!.cycle+=1
            world.counters["harvests",default:0]+=1
            world.record("harvest","\(world.agents[t.worker]!.name)完成收割，食粮已在田边，等待搬运；粮仓尚未收到。")
        case "replant":world.treeReady[Int(t.subject)!]=world.time+7200
        case "gather":
            if t.resource == .wood {world.treeReady[Int(t.subject)!] = -2}
            world.storages[t.target]!.incoming-=t.space
            world.add(t.resource!,quantity:t.quantity,at:t.target,origin:t.id,production:true)
            world.counters["gathered",default:0]+=1
        case "prepare":
            let r=catalog.recipe(world.stations[t.subject]!.recipe!)!
            world.stations[t.subject]!.taskID=nil
            if r.passive_s>0 {world.stations[t.subject]!.phase="passive";world.stations[t.subject]!.due=world.time+r.passive_s}
            else {world.stations[t.subject]!.phase="finish"}
        case "finish":
            let s=world.stations[t.subject]!,r=catalog.recipe(s.recipe!)!
            world.storages[s.output]!.incoming-=s.outputSpace
            for key in r.output_mU.keys.sorted(){world.add(LifeResource(rawValue:key)!,quantity:r.output_mU[key]!,at:s.output,quality:r.meal_quality ?? "basic",origin:t.id,production:true)}
            world.stations[t.subject]!.phase="idle";world.stations[t.subject]!.recipe=nil;world.stations[t.subject]!.taskID=nil;world.stations[t.subject]!.outputSpace=0;world.stations[t.subject]!.foodInProcess=0
            world.counters[r.id+"_completed",default:0]+=1
            world.record("cooking",r.job=="cook" ? "\(world.agents[t.worker]!.name)做出一锅饭菜，等待送到住区。":"工坊完成\(r.id)，成品等待交付。")
        case "build":
            world.projects[t.subject]!.completedWork+=t.contribution;world.projects[t.subject]!.allocatedWork-=t.contribution
            finishProjectPhase(t.subject)
        case "recruit_prepare":
            let r=catalog.recruitment.first{$0.hero==t.subject}!,i=world.recruits[t.subject]!.stage
            world.recruits[t.subject]!.state="passive";world.recruits[t.subject]!.due=world.time+r.stages[i].passive_s
        case "recruit_finish":
            world.recruits[t.subject]!.stage+=1;world.recruits[t.subject]!.state="waiting"
            if world.recruits[t.subject]!.stage==3 {
                let h=catalog.hero(t.subject)!
                world.owned.append(h.id);world.agents[h.id] = .init(id:h.id,name:h.name,job:"flex",node:"gate",home:"home",dining:"home-meals",heroID:h.id)
                world.recruits[t.subject]!.state="owned";if world.wish==h.id{world.wish=nil}
                world.record("recruit","\(h.name)正式入城，开始新生活；不需要点击领取。")
            }
        case "patrol":world.counters["patrols",default:0]+=1
        case "study":
            world.counters["study_completed",default:0]+=1
            world.record("study","\(world.agents[t.worker]!.name)在书院完成300秒\(t.subject)研习；熟练工时已入档，没有产出物资。")
        case "civic_clean", "civic_watch", "civic_drill":finishCivicDuty(t)
        case "home":world.agents[t.worker]!.restStart=world.time
        case "clinic_arrive", "clinic_consult", "clinic_prepare", "clinic_rest", "clinic_finish", "clinic_patient_wait":finishHealthTask(t)
        default:break
        }
        finishFirstDutyIfNeeded(t)
        maybeTriggerHealthCondition(after:t)
    }
    public func label(_ location:String) -> String {
        if world.isGacha,let label=["goldmine":"金矿","smelter-in":"冶金坊","smelter-out":"金锭出货台","mint":"府署金库","guest-meals":"酒馆客房餐点"][location] {return label}
        if location.hasPrefix("field"){return "田边"};if location.hasPrefix("project"){return "工地"}
        return ["pasture-feed":"牧栏饲料点","butcher-out":"肉食台出货区","warehouse":"粮仓","kitchen-in":"厨房","kitchen-out":"厨房出餐台","home-meals":"住宅餐点","hall-meals":"官署餐点","trees":"林地","quarry":"采石点","mine":"矿点","forge-in":"工坊","forge-out":"工坊","recruit":"官署接待点","ration-in":"制粮台","ration-out":"军粮架"][location] ?? location
    }
}
