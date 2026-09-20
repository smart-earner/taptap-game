import Foundation

/// Single authoritative task clock. Rendering never credits production or resolves arrivals.
public enum LifeEngine {
    public static func newGame(wallUTC:Int64, rules r:LifeRules) throws -> LifeState {
        var s=LifeState(lastWallUTC:wallUTC,treasury:r.start.treasury,housing:r.start.housing,satisfaction:r.satisfaction.initial)
        for f in r.facilities { s.stores[f.id]=[:] }
        for (site,stock) in r.start.stocks { s.stores[site]=stock; for (k,v) in stock { s.ledger.initial[k,default:0]+=v } }
        for (i,role) in r.start.roles.enumerated() {
            s.agents.append(.init(id:String(format:"resident-%03d",i),name:i==0 ? "宋宁·代理太守":"居民\(i+1)",role:role,site:"home"))
        }
        for (site,crop) in r.start.farmCrops { s.fields[site] = .init(crop:crop) }
        s.nextMeal=r.clock.meals[0]
        s.record("founded","16位居民在此安家。先把田里的一袋粮，变成每个人的一餐饭。")
        try advance(&s,to:0,rules:r); return s
    }
    public static func advanceWall(_ s:inout LifeState,to wall:Int64,rules r:LifeRules) throws {
        guard wall>s.lastWallUTC else { return }
        let seconds=min(wall-s.lastWallUTC,r.clock.offlineLimit)
        try advance(&s,to:s.time+seconds,rules:r)
        if wall-s.lastWallUTC>r.clock.offlineLimit { s.record("rest","离线超过30日，只补算30日。余下时间安全休整，没有罚单。") }
        s.lastWallUTC=wall
    }
    public static func changeCrop(_ s:inout LifeState,site:String,crop:String,rules r:LifeRules) throws {
        guard r.crop(crop) != nil,var field=s.fields[site] else { throw LifeError.invalid("未知田块或作物") }
        if field.phase=="empty" && field.task==nil { field.crop=crop;field.nextCrop=nil }
        else { field.nextCrop=crop }
        s.fields[site]=field;s.record("crop_choice","\(site)下一茬改种\(r.crop(crop)!.name)，在长作物与已投入材料保持原样。")
    }
    public static func advance(_ s:inout LifeState,to end:Int64,rules r:LifeRules) throws {
        guard end>=s.time,end-s.time<=90*86_400 else { throw LifeError.invalid("模拟区间无效或超过单次90日限制") }
        while true {
            if s.nextForestRenewal<=s.time { s.forestRemaining=120;s.nextForestRenewal+=14_400 }
            // At the same time, finish commitments before meal closure and new reservations.
            let ids=s.tasks.filter{$0.due<=s.time}.map(\.id).sorted()
            for id in ids { try finishPhase(id,state:&s,rules:r) }
            if s.nextMeal==s.time { startMeal(&s,rules:r) }
            closeMeals(&s,rules:r)
            if s.nextPlan<=s.time { plan(&s,rules:r);s.nextPlan+=r.clock.planning }
            if s.time==end { break }
            var next=min(end,s.nextPlan,s.nextMeal,s.nextForestRenewal)
            for t in s.tasks { if t.due>s.time { next=min(next,t.due) } }
            for m in s.meals where !m.closed && m.deadline>s.time { next=min(next,m.deadline) }
            guard next>s.time else { throw LifeError.invalid("事件时钟未前进") }
            s.time=next
        }
        try s.validate(r)
    }
    static func startMeal(_ s:inout LifeState,rules r:LifeRules) {
        let n=s.nextMealID
        s.meals.append(.init(id:n,starts:s.time,deadline:s.time+r.clock.mealGrace,expected:s.agents.map(\.id)))
        for i in s.agents.indices { s.agents[i].meal=n }
        s.nextMealID+=1
        let phase=s.time%r.clock.cycle,base=s.time-phase
        s.nextMeal=r.clock.meals.first(where:{$0>phase}).map{base+$0} ?? (base+r.clock.cycle+r.clock.meals[0])
        s.record("meal_open","开饭了：本餐\(s.population)人，饭菜要真正送到里坊才可食用。")
    }
    static func closeMeals(_ s:inout LifeState,rules r:LifeRules) {
        for index in s.meals.indices where !s.meals[index].closed && s.meals[index].deadline<=s.time {
            let meal=s.meals[index],n=meal.expected.count
            if n>0 {
                let coverage=meal.served.count*10000/n, quality=meal.hearty*10000/max(1,meal.served.count)
                // floor division for the signed coverage term, not truncation toward zero.
                let coverageTerm=Int(floor(Double(r.satisfaction.coverageWeight*(coverage-10000))/10000))
                let target=max(0,min(100,r.satisfaction.base+coverageTerm+r.satisfaction.qualityWeight*quality/10000))
                s.satisfaction+=max(-r.satisfaction.fallCap,min(r.satisfaction.riseCap,target-s.satisfaction))
                s.record("meal_closed","本餐\(meal.served.count)/\(n)人吃饱；满意度\(s.satisfaction)。短缺先保供，不处罚基础工种。")
                if meal.served.count==n && !s.achievements.contains("first-meal") {
                    s.achievements.append("first-meal");s.record("collection","图录入藏：乡里第一餐。居民真正吃到了饭，不是定时发奖。")
                }
            }
            s.meals[index].closed=true
            for i in s.agents.indices where s.agents[i].meal==meal.id { s.agents[i].meal=nil }
            let recent=s.meals.filter(\.closed).suffix(2)
            if recent.count==2 && recent.allSatisfy({!$0.expected.isEmpty && $0.served.count==$0.expected.count}),s.satisfaction>=r.satisfaction.immigrationFloor,s.population<s.housing,s.population<r.limits.people {
                let n=s.population
                s.agents.append(.init(id:String(format:"resident-%03d",n),name:"新居民\(n+1)",role:"porter",site:"home"))
                s.record("resident","新居民在空余住宅安家，没有额外赠送资源；从下一餐开始就餐。")
            }
        }
        if s.meals.count>8 { s.meals.removeFirst(s.meals.count-8) }
    }
    static func start(_ task:LifeTask,agent:Int,state s:inout LifeState) {
        var t=task;t.id=s.nextID;s.nextID+=1
        s.agents[agent].task=t.id;s.agents[agent].activity=activity(t)
        s.tasks.append(t)
    }
    static func finishPhase(_ id:Int,state s:inout LifeState,rules r:LifeRules) throws {
        guard let ti=s.tasks.firstIndex(where:{$0.id==id}),let ai=s.agents.firstIndex(where:{$0.id==s.tasks[ti].actor}) else { throw LifeError.invalid("任务人物缺失") }
        var t=s.tasks[ti]
        if t.kind=="haul" {
            switch t.phase {
            case "approach":
                s.agents[ai].site=t.source;t.phase="load";t.phaseFrom=t.source;t.began=s.time;t.due=s.time+r.movement.loadSeconds
            case "load":
                guard s.stock(t.source,t.key)>=t.quantity else { throw LifeError.invalid("已预留货物不见了") }
                s.stores[t.source]![t.key,default:0]-=t.quantity;t.cargo=t.quantity
                t.phase="loaded";t.phaseFrom=t.source;t.began=s.time;t.due=s.time+max(1,r.travel(t.source,t.destination,loaded:true))
            case "loaded":
                s.agents[ai].site=t.destination;t.phase="unload";t.phaseFrom=t.destination;t.began=s.time;t.due=s.time+r.movement.unloadSeconds
            case "unload":
                s.stores[t.destination]![t.key,default:0]+=t.cargo;t.cargo=0
                s.record("delivered","\(t.quantity)\(r.resources.first{$0.id==t.key}?.unit ?? "份")\(r.resources.first{$0.id==t.key}?.name ?? t.key)送抵\(r.facilities.first{$0.id==t.destination}?.name ?? t.destination)。")
                complete(t,agent:ai,state:&s);return
            default: throw LifeError.invalid("未知运输阶段")
            }
        } else if t.phase=="approach" {
            s.agents[ai].site=t.destination
            if t.kind=="return" || t.kind=="patrol" { complete(t,agent:ai,state:&s);return }
            for (key,value) in t.inputs {
                guard s.stock(t.destination,key)>=value else { throw LifeError.invalid("已预留加工原料缺失") }
                s.stores[t.destination]![key,default:0]-=value
            }
            t.inputsTaken=true;t.phase="work";t.phaseFrom=t.destination;t.began=s.time;t.due=s.time+t.work
            if t.kind=="build" { guard s.treasury>=r.construction.cash else { throw LifeError.invalid("工程预算不足") }; s.treasury-=r.construction.cash }
        } else if t.phase=="work" {
            for (key,value) in t.inputs { s.ledger.consumed[key,default:0]+=value }
            for (key,value) in t.outputs { s.stores[t.destination]![key,default:0]+=value;s.ledger.produced[key,default:0]+=value }
            switch t.kind {
            case "sow":
                guard let crop=r.crop(t.key) else { throw LifeError.invalid("未知作物") }
                s.fields[t.destination]!.phase="growing";s.fields[t.destination]!.maturesAt=s.time+crop.grow;s.fields[t.destination]!.plantedAt=s.time;s.fields[t.destination]!.task=nil
                s.record("sown","\(crop.name)播种完成，\(crop.grow)秒自然生长，成熟后还需农人采收。")
            case "harvest":
                s.fields[t.destination]!.phase="empty";s.fields[t.destination]!.maturesAt=nil;s.fields[t.destination]!.task=nil
                if let crop=s.fields[t.destination]!.nextCrop { s.fields[t.destination]!.crop=crop;s.fields[t.destination]!.nextCrop=nil }
                s.record("harvest","\(r.crop(t.key)?.name ?? t.key)采收完成，产物在田边等待真实搬运。")
            case "recipe":
                if t.key=="cut-wood" { s.forestRemaining-=6 }
                s.record("processed","\(r.recipe(t.key)?.name ?? t.key)完成一批，成品留在工作点待运。")
            case "eat":
                if let index=s.meals.firstIndex(where:{$0.id==t.mealID && !$0.closed}),!s.meals[index].served.contains(t.actor) {
                    s.meals[index].served.append(t.actor);if t.key=="feast" {s.meals[index].hearty+=1};s.totalServed+=1
                }
                s.agents[ai].meal=nil
            case "build":
                s.constructionCount+=1;s.housing+=r.construction.housingAdded;s.record("built","里坊新居建成，增加4个真实住房位。")
            default: throw LifeError.invalid("未知工作种类")
            }
            complete(t,agent:ai,state:&s);return
        } else { throw LifeError.invalid("未知任务阶段") }
        s.tasks[ti]=t;s.agents[ai].activity=activity(t)
    }
    static func complete(_ t:LifeTask,agent:Int,state s:inout LifeState) {
        s.tasks.removeAll{$0.id==t.id};s.agents[agent].task=nil;s.agents[agent].activity="等下一项工作";s.completedTasks+=1
    }
    public static func activity(_ t:LifeTask)->String {
        if t.kind=="haul" { switch t.phase { case "approach": return "空手去取\(t.key)";case "load":return "装货";case "loaded":return "搬运\(t.quantity)份\(t.key)";default:return "卸货" } }
        if t.kind=="return" { return "收工回家" }
        if t.kind=="patrol" { return "沿街巡查" }
        if t.phase=="approach" { return t.kind=="eat" ? "回里坊吃饭":"前往工作点" }
        switch t.kind { case "sow":return "播种";case "harvest":return "收割成袋";case "eat":return "吃饭";case "build":return "修建新居";default:return t.key }
    }
    static func plan(_ s:inout LifeState,rules r:LifeRules) {
        for ai in s.agents.indices {
            guard s.agents[ai].task==nil,s.tasks.count<r.limits.activeTasks else { continue }
            if tryMeal(ai,state:&s,rules:r) { continue }
            let role=s.agents[ai].role,phase=s.time%r.clock.cycle
            if role=="patrol-night" && phase>=r.clock.duskEnd || role=="patrol-day" && phase<r.clock.dayEnd {
                let dest=s.agents[ai].site=="gate" ? "warehouse":"gate"
                move(ai,to:dest,kind:"patrol",state:&s,rules:r);continue
            }
            if phase>=r.clock.dayEnd || role=="patrol-night" {
                if s.agents[ai].site != "home" { move(ai,to:"home",kind:"return",state:&s,rules:r) }
                else {s.agents[ai].activity="回家休息"}
                continue
            }
            var did=false
            switch role {
            case "farmer":
                did=farm(ai,state:&s,rules:r)
                if !did {did=recipe("mulch",ai:ai,state:&s,rules:r)}
            case "porter","warehouse": did=haul(ai,state:&s,rules:r)
            case "cook":
                if s.stock("kitchen","meal")+s.pendingOutput("kitchen","meal")<max(48,s.population*3) {did=recipe("cook",ai:ai,state:&s,rules:r)}
            case "miller":
                if s.stock("mill","grain")+s.pendingOutput("mill","grain")<32 {did=recipe("mill",ai:ai,state:&s,rules:r)}
            case "waterman":
                if s.stock("well","water")+s.pendingOutput("well","water")<60 {did=recipe("draw-water",ai:ai,state:&s,rules:r)}
            case "forester":
                if s.forestRemaining>=6 && s.stock("forest","wood")+s.pendingOutput("forest","wood")<24 {did=recipe("cut-wood",ai:ai,state:&s,rules:r)}
            case "builder":
                if s.constructionCount<r.construction.maxCount && s.treasury>=r.construction.cash && s.stock("home","meal")>=s.population && !s.tasks.contains(where:{$0.kind=="build"}) {
                    did=work(ai,kind:"build",key:r.construction.id,site:"construction",duration:r.construction.work,inputs:r.construction.inputs,outputs:[:],state:&s,rules:r)
                }
            default: break
            }
            if !did { s.agents[ai].activity=role=="prefect" ? "安排保供与建设":role=="smith" ? "研习（铁坊尚未启用）":"等原料、需求或下一班" }
        }
    }
    static func move(_ ai:Int,to:String,kind:String,state s:inout LifeState,rules r:LifeRules) {
        let a=s.agents[ai]
        start(.init(id:0,actor:a.id,kind:kind,phase:"approach",source:a.site,destination:to,key:"",phaseFrom:a.site,began:s.time,due:s.time+max(1,r.travel(a.site,to))),agent:ai,state:&s)
    }
    static func canFinish(_ work:Int64,from:String,to:String,state s:LifeState,rules r:LifeRules)->Bool { s.time%r.clock.cycle+r.travel(from,to)+work<=r.clock.duskEnd }
    static func work(_ ai:Int,kind:String,key:String,site:String,duration:Int64,inputs:[String:Int],outputs:[String:Int],state s:inout LifeState,rules r:LifeRules,mealID:Int?=nil)->Bool {
        guard inputs.allSatisfy({s.free(site,$0.key)>=$0.value}),outputs.allSatisfy({s.stock(site,$0.key)+s.incoming(site,$0.key)+s.pendingOutput(site,$0.key)+$0.value<=r.limits.storePerResource}) else {return false}
        let a=s.agents[ai]
        if kind != "eat" && !canFinish(duration,from:a.site,to:site,state:s,rules:r) {return false}
        let t=LifeTask(id:0,actor:a.id,kind:kind,phase:"approach",source:a.site,destination:site,key:key,phaseFrom:a.site,began:s.time,due:s.time+max(1,r.travel(a.site,site)),inputs:inputs,outputs:outputs,work:duration,mealID:mealID)
        start(t,agent:ai,state:&s);return true
    }
    static func tryMeal(_ ai:Int,state s:inout LifeState,rules r:LifeRules)->Bool {
        guard let id=s.agents[ai].meal,let meal=s.meals.first(where:{$0.id==id && !$0.closed}),s.time+r.travel(s.agents[ai].site,"home")+r.clock.eatSeconds<meal.deadline else {return false}
        let key=s.free("home","feast")>0 ? "feast":"meal"
        return work(ai,kind:"eat",key:key,site:"home",duration:r.clock.eatSeconds,inputs:[key:1],outputs:[:],state:&s,rules:r,mealID:id)
    }
    static func recipe(_ id:String,ai:Int,state s:inout LifeState,rules r:LifeRules)->Bool {
        guard let row=r.recipe(id),row.stage=="l1",row.passive==0 else {return false}
        let cap=row.facility=="kitchen" ? 2:1
        guard s.tasks.filter({$0.kind=="recipe" && $0.destination==row.facility}).count<cap else {return false}
        return work(ai,kind:"recipe",key:id,site:row.facility,duration:row.work,inputs:row.inputs,outputs:row.outputs,state:&s,rules:r)
    }
    static func farm(_ ai:Int,state s:inout LifeState,rules r:LifeRules)->Bool {
        let sites=s.fields.keys.sorted { a,b in
            let ar=s.fields[a]?.maturesAt.map{$0<=s.time} ?? false,br=s.fields[b]?.maturesAt.map{$0<=s.time} ?? false
            return ar != br ? ar : a<b
        }
        for site in sites {
            guard let field=s.fields[site],field.task==nil,let crop=r.crop(field.crop) else {continue}
            if field.phase=="growing",let due=field.maturesAt,due<=s.time {
                if work(ai,kind:"harvest",key:crop.id,site:site,duration:crop.harvest,inputs:[:],outputs:crop.outputs,state:&s,rules:r) {s.fields[site]!.task=s.agents[ai].task;return true}
            } else if field.phase=="empty" {
                if work(ai,kind:"sow",key:crop.id,site:site,duration:crop.sow,inputs:crop.inputs,outputs:[:],state:&s,rules:r) {s.fields[site]!.task=s.agents[ai].task;return true}
            }
        }
        return false
    }
    static func haul(_ ai:Int,state s:inout LifeState,rules r:LifeRules)->Bool {
        // Destination demands are service priorities, not extra periodic production.
        var demands:[(String,String,Int)]=[("home","meal",max(64,s.population*4)),("kitchen","grain",max(12,s.population)),("kitchen","water",max(12,s.population)),("kitchen","wood",max(4,(s.population+3)/4)),("mill","paddy",24)]
        for site in s.fields.keys.sorted() {
            if let field=s.fields[site],let crop=r.crop(field.crop) { for key in crop.inputs.keys.sorted() { demands.append((site,key,crop.inputs[key]!)) } }
        }
        demands.append(("field","fodder",r.targets["fieldFodder",default:16]))
        if s.constructionCount<r.construction.maxCount { demands += [("construction","wood",12),("construction","stone",6)] }
        demands += [("warehouse","wood",60),("warehouse","grain",s.population*4),("warehouse","vegetable",32),("warehouse","fodder",32)]
        for (destination,key,target) in demands {
            let gap=target-s.stock(destination,key)-s.incoming(destination,key)-s.pendingOutput(destination,key)
            guard gap>0,let resource=r.resources.first(where:{$0.id==key}) else {continue}
            let sources=s.stores.keys.filter { site in
                guard site != destination else {return false}
                // Never circulate service stock back into other stores or steal kitchen supply.
                if destination=="warehouse" {return ["forest","mill","garden"].contains(site)}
                if key=="meal" {return site=="kitchen"}
                if key=="grain" {return ["warehouse","mill"].contains(site)}
                if key=="paddy" {return site=="field" || site=="garden"}
                if key=="water" {return ["warehouse","well"].contains(site)}
                if key=="wood" {return ["warehouse","forest"].contains(site)}
                if key=="fodder" {return ["mill","warehouse"].contains(site)}
                if key=="seed" {return site=="warehouse"}
                return site=="warehouse"
            }.filter{s.free($0,key)>0}.sorted {a,b in
                let da=r.travel(a,destination,loaded:true),db=r.travel(b,destination,loaded:true);return da==db ? a<b:da<db
            }
            guard let source=sources.first else {continue}
            let capacity=r.limits.storePerResource-s.stock(destination,key)-s.incoming(destination,key)-s.pendingOutput(destination,key)
            let amount=min(gap,resource.carry,s.free(source,key),capacity)
            let a=s.agents[ai],duration=r.travel(a.site,source)+r.movement.loadSeconds+r.travel(source,destination,loaded:true)+r.movement.unloadSeconds
            guard amount>0,s.time%r.clock.cycle+duration<=r.clock.duskEnd else {continue}
            start(.init(id:0,actor:a.id,kind:"haul",phase:"approach",source:source,destination:destination,key:key,phaseFrom:a.site,began:s.time,due:s.time+max(1,r.travel(a.site,source)),quantity:amount),agent:ai,state:&s)
            return true
        }
        return false
    }
}
