import Foundation

/// First playable slice of life-0.7.2. Uses one deterministic timeline, independent of rendering.
/// Older WorldState saves are intentionally not accepted or rewritten by this type.
public struct LifeRuntime: Sendable {
    public let catalog: LifeCatalog
    public internal(set) var world: LifeWorld
    public init(catalog:LifeCatalog,wallUTC:Int64) throws {
        self.catalog=catalog;world=LifeWorld(wallUTC:wallUTC)
        let assets:[(String,String,Int64,[LifeResource:Int64])] = [
            ("warehouse","warehouse",512,[.grain:56000,.wood:36000,.stone:12000,.iron:6000,.tools:4000]),
            ("kitchen-in","kitchen",64,[.grain:8000,.wood:4000]),("kitchen-out","kitchen",64,[:]),
            ("home-meals","home",16,[.meal:30000]),("hall-meals","hall",16,[.meal:2000]),
            ("trees","trees",24,[:]),("mine","mine",24,[:]),("quarry","quarry",24,[:]),
            ("forge-in","workshop",64,[:]),("forge-out","workshop",64,[:]),
            ("ration-in","ration",64,[:]),("ration-out","ration",64,[:]),("recruit","hall",64,[:])]
        for (id,node,cap,stock) in assets {
            world.storages[id] = .init(node:node,capacity:cap*1_000_000)
            for r in LifeResource.allCases {if let q=stock[r] {world.add(r,quantity:q,at:id,origin:"founding");world.initial[r.rawValue,default:0]+=q}}
        }
        let names=["阿禾","谷生","林生","石安","禾娘","阿担","阿车","阿运","木成","筑安","仓平","井清","卫平","夜安","阿勤"]
        let jobs=["farmer","farmer","logger","miner","cook","porter","porter","porter","builder","builder","clerk","handyman","guard_day","guard_night","flex"]
        for i in 0..<15 {let id=String(format:"r%02d",i+1);world.agents[id] = .init(id:id,name:names[i],job:jobs[i],node:"home",home:"home",dining:"home-meals")}
        world.agents["xunyu"] = .init(id:"xunyu",name:catalog.hero("xunyu")!.name,job:"prefect",node:"hall",home:"home",dining:"hall-meals",heroID:"xunyu")
        world.stations["kitchen"] = .init(id:"kitchen",node:"kitchen",input:"kitchen-in",output:"kitchen-out",kind:"kitchen")
        world.stations["forge"] = .init(id:"forge",node:"workshop",input:"forge-in",output:"forge-out",kind:"forge")
        world.stations["ration"] = .init(id:"ration",node:"ration",input:"ration-in",output:"ration-out",kind:"ration")
        for i in 0..<4 {let id="field-\(i)";world.fields[id] = .init(id:id,state:i==0 ? "growing2":"empty",due:i==0 ? 360:nil);world.storages[id] = .init(node:id,capacity:64_000_000)}
        startProject(id:"repair",kind:"repair",node:"hall",cash:20,work:600,materials:["wood":4000,"stone":2000])
        world.record("founding","荀彧接掌小城：先供好饭，再修好府署。30将图鉴已载入，只有荀彧已加入。")
        plan(); world.nextPlan=30
        try world.validate()
    }
    public init(catalog:LifeCatalog,world:LifeWorld) throws {try world.validate();self.catalog=catalog;self.world=world}
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
        for t in world.tasks.values {n=min(n,t.due)}
        for f in world.fields.values {if let d=f.due {n=min(n,d)}}
        for s in world.stations.values {if let d=s.due {n=min(n,d)}}
        for r in world.recruits.values {if let d=r.due {n=min(n,d)}}
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
        updateMeals()
        if world.time==world.nextPlan {plan();world.nextPlan+=30}
    }
    public mutating func setPolicy(_ value:String) throws {
        guard ["supply","trade","industry","military","balanced"].contains(value) else{throw LifeError.invalid("未知方针")}
        world.policy=value;world.record("policy","已调整城市方向；在途货物和当前加工不撤销。")
    }
    public mutating func requestSeal() throws {
        guard !world.owned.contains("founders_seal"),world.projects["founders_seal"]==nil,world.treasury-world.reservedCash>=110 else{throw LifeError.invalid("木印已完成、正在制作或余款不足；未重复扣费")}
        startProject(id:"founders_seal",kind:"seal",node:"seal",cash:10,work:360,materials:["wood":2000])
        world.record("wish","已授权制作开城木印：10铜、木材2、360人工秒；完成后自动入藏。")
    }
    public mutating func requestRecruit(_ id:String?) throws {
        if let id {guard catalog.hero(id) != nil,world.discovered.contains(id),!world.owned.contains(id) else{throw LifeError.invalid("该人物尚未发现或已经加入")}}
        world.wish=id
        if let id,world.recruits[id]==nil {world.recruits[id] = .init()}
    }
    func profile(_ agent:LifeAgent,role:String="worker") -> LifeAbilitySource {
        let h=agent.heroID.flatMap{catalog.hero($0)} ?? .init(id:agent.id,name:agent.name,starting:false,attributes:["administration":50,"strategy":50,"valor":50,"command":50],skill_ids:[])
        return .init(h,role:role,eligible:true)
    }
    func leaders() -> [LifeAbilitySource] {world.agents[world.prefect].map{[profile($0,role:"prefect")]} ?? []}
    func rate(_ agent:LifeAgent,job:String) -> Int {
        let seconds=agent.workSeconds[job,default:0], xp=seconds/300
        let level=1+[60,180,360,600].filter{xp>=Int64($0)}.count
        return (try? LifeAbilities.workRate(catalog,worker:profile(agent),job:job,leaders:leaders(),level:level)) ?? 10000
    }
    func move(_ from:String,_ to:String,loaded:Bool=false) -> LifeStep? {
        guard from != to else{return nil}
        let path=LifeMap.path(from,to)
        return .init(kind:loaded ? "carry":"walk",seconds:max(1,Int64(ceil(LifeMap.length(path)/(loaded ? 32:48)))),route:path,destination:to)
    }
    mutating func assign(kind:String,job:String,subject:String,at node:String,work:Int64,tail:[LifeStep]=[],only:String?=nil) -> String? {
        let phase=world.phase
        let available=world.agents.values.filter {a in
            guard a.taskID==nil else{return false}
            if let only {return a.id==only}
            guard a.job != "prefect",a.job != "guard_night",a.job != "guard_day",phase>=240,phase<1920 else{return false}
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
        for a in available {
            let r=rate(a,job:job);var steps:[LifeStep]=[]
            if let m=move(a.node,node){steps.append(m)}
            if work>0 {steps.append(.init(kind:"work",seconds:max(1,(work*10000+Int64(r)-1)/Int64(r))))}
            steps+=tail
            if steps.isEmpty {continue}
            let duration=steps.reduce(Int64(0)){$0+$1.seconds}
            if only==nil && (phase+duration>2160 || (a.serviceSeconds+duration>1920 && a.busyCycle==world.cycle)){continue}
            let id=world.next("task")
            world.tasks[id] = .init(id:id,worker:a.id,kind:kind,job:job,subject:subject,steps:steps,started:world.time,due:world.time+steps[0].seconds,rate:r)
            world.agents[a.id]!.taskID=id
            if let rest=world.agents[a.id]!.restStart,world.time-rest>=600 {world.agents[a.id]!.restedCycle=world.cycle}
            world.agents[a.id]!.restStart=nil
            if world.agents[a.id]!.busyCycle != world.cycle {world.agents[a.id]!.busyCycle=world.cycle;world.agents[a.id]!.serviceSeconds=0}
            world.agents[a.id]!.serviceSeconds+=duration
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
        if task.kind=="haul" && task.current.kind=="unload" {
            for key in world.lots.keys.sorted() where world.lots[key]!.location==id {world.lots[key]!.location=task.target}
            world.storages[task.target]!.incoming-=task.space
            world.counters["deliveries",default:0]+=1
            world.record("delivery","\(world.agents[task.worker]!.name)将\(String(format:"%.1f",Double(task.quantity)/1000))份\(task.resource!.title)送达\(label(task.target))。")
        }
        if task.kind=="export" && task.current.kind=="external_sale" {
            _=world.consume(task.resource!,quantity:task.quantity,at:task.id)
        }
        task.step+=1
        if task.step<task.steps.count {
            task.started=world.time;task.due=world.time+task.current.seconds;world.tasks[id]=task
            if task.kind=="prepare",task.current.kind=="work" {
                world.beginReservedInputs(id)
                if let s=world.stations[task.subject],let recipe=s.recipe {
                    world.stations[task.subject]!.foodInProcess=catalog.recipe(recipe)!.output_mU["meal",default:0]
                }
            }
            return
        }
        world.tasks[id]=nil;world.agents[task.worker]!.taskID=nil
        finishTask(task)
    }
    mutating func finishTask(_ t:LifeTask) {
        switch t.kind {
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
        case "home":world.agents[t.worker]!.restStart=world.time
        default:break
        }
    }
    public func label(_ location:String) -> String {
        if location.hasPrefix("field"){return "田边"};if location.hasPrefix("project"){return "工地"}
        return ["warehouse":"粮仓","kitchen-in":"厨房","kitchen-out":"厨房出餐台","home-meals":"住宅餐点","hall-meals":"官署餐点","trees":"林地","quarry":"采石点","mine":"矿点","forge-in":"工坊","forge-out":"工坊","recruit":"官署接待点","ration-in":"制粮台","ration-out":"军粮架"][location] ?? location
    }
}
