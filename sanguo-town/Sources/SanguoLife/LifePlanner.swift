import Foundation

extension LifeRuntime {
    mutating func plan() {
        planMealsAndRest()
        planStations(finishingOnly:true)
        planFields(harvestOnly:true)
        planFoodSupply()
        planStations(finishingOnly:false)
        planFields(harvestOnly:false)
        planProjects()
        planRecruitment()
        planGathering()
        planTrade()
        discoverHeroes()
        planPatrol()
        if world.phase>=2160 {planMealsAndRest()}
    }
    mutating func planFields(harvestOnly:Bool) {
        for id in world.fields.keys.sorted() {
            let f=world.fields[id]!, c=catalog.crops.first{$0.id==f.crop}!
            guard f.taskID==nil else{continue}
            if f.state=="ripe" {
                let space=c.output_mU.reduce(Int64(0)){$0+$1.value*LifeResource(rawValue:$1.key)!.volume}
                guard world.freeSpace(id)>=space else{continue}
                if let task=assign(kind:"harvest",job:"farmer",subject:id,at:id,work:c.harvest_s) {
                    world.fields[id]!.taskID=task;world.fields[id]!.state="harvesting";world.storages[id]!.incoming+=space
                }
            } else if !harvestOnly && (f.state=="water1" || f.state=="water2") {
                var tail:[LifeStep]=[]
                if let step=move("well",id){tail.append(step)}
                // Water is an actual service trip, not a hidden resource inventory.
                tail.append(.init(kind:"work",seconds:c.water_work_s))
                if let task=assign(kind:"water",job:"farmer",subject:id,at:"well",work:0,tail:tail) {
                    let r=Int64(world.tasks[task]!.rate)
                    let last=world.tasks[task]!.steps.count-1
                    world.tasks[task]!.steps[last].seconds=max(1,(c.water_work_s*10000+r-1)/r)
                    world.fields[id]!.taskID=task;world.fields[id]!.state=f.state=="water1" ? "watering1":"watering2"
                }
            } else if !harvestOnly && f.state=="empty" && world.amount(.grain)<Int64(world.agents.count*2000) {
                guard world.freeSpace(id)>=c.output_mU.reduce(Int64(0),{$0+$1.value*LifeResource(rawValue:$1.key)!.volume}) else{continue}
                if let task=assign(kind:"sow",job:"farmer",subject:id,at:id,work:c.sow_s) {world.fields[id]!.taskID=task;world.fields[id]!.state="sowing"}
            }
        }
    }
    /// Parent demand never locks an idle worker. Only a feasible single trip reserves stock and destination volume.
    @discardableResult mutating func haul(_ resource:LifeResource,quantity:Int64,to target:String) -> Bool {
        guard quantity>0,let destination=world.storages[target] else{return false}
        let inFlight=world.tasks.values.filter{$0.kind=="haul" && $0.target==target && $0.resource==resource}.reduce(Int64(0)){$0+$1.quantity}
        let needed=max(0,quantity-inFlight)
        guard needed>0 else{return false}
        let valid=Set(["warehouse","trees","mine","quarry","kitchen-out","forge-out","ration-out"]+Array(world.fields.keys))
        let sources=world.storages.keys.filter{$0 != target && valid.contains($0) && world.amount(resource,at:$0,free:true)>0}.sorted { a,b in
            let da=LifeMap.length(LifeMap.path(world.storages[a]!.node,destination.node)),db=LifeMap.length(LifeMap.path(world.storages[b]!.node,destination.node))
            return da==db ? a<b:da<db
        }
        for source in sources {
            let node=world.storages[source]!.node
            let q=min(needed,world.amount(resource,at:source,free:true),4_000_000/resource.volume,world.freeSpace(target)/resource.volume)
            guard q>0,let parts=world.selection(resource,quantity:q,at:source) else{continue}
            var tail=[LifeStep(kind:"load",seconds:10)]
            if let m=move(node,destination.node,loaded:true){tail.append(m)}
            tail.append(.init(kind:"unload",seconds:10))
            guard let id=assign(kind:"haul",job:"porter",subject:source,at:node,work:0,tail:tail) else{continue}
            world.tasks[id]!.reservations=parts;world.tasks[id]!.target=target;world.tasks[id]!.resource=resource;world.tasks[id]!.quantity=q;world.tasks[id]!.space=q*resource.volume
            for p in parts {world.lots[p.lotID]!.reserved+=p.amount}
            world.storages[target]!.incoming+=q*resource.volume
            return true
        }
        return false
    }
    mutating func supply(_ inputs:[String:Int64],to target:String) {
        for key in inputs.keys.sorted() {
            let r=LifeResource(rawValue:key)!,missing=max(0,inputs[key]!-world.amount(r,at:target,free:true))
            if missing>0 {_=haul(r,quantity:missing,to:target)}
        }
    }
    mutating func planFoodSupply() {
        let targets=["home-meals":Int64(world.agents.values.filter{$0.dining=="home-meals"}.count*2000),"hall-meals":Int64(world.agents.values.filter{$0.dining=="hall-meals"}.count*2000)]
        for key in targets.keys.sorted() {
            let need=max(0,targets[key]!-world.amount(.meal,at:key))
            if need>0 {for _ in 0..<3{if !haul(.meal,quantity:need,to:key){break}}}
        }
        if world.stations["kitchen"]!.phase=="idle" && world.amount(.meal)<Int64(world.agents.count*2000) {
            let useMeat=world.policy != "military" && world.amount(.meat)>=2000
            let r=catalog.recipe(useMeat ? "cook_meat":"cook_basic")!
            supply(r.input_mU,to:"kitchen-in")
        }
        for id in world.fields.keys.sorted() where world.amount(.grain,at:id)>0 {_=haul(.grain,quantity:world.amount(.grain,at:id),to:"warehouse")}
    }
    mutating func planStations(finishingOnly:Bool) {
        for id in world.stations.keys.sorted() {
            let s=world.stations[id]!
            if s.phase=="finish",s.taskID==nil,let recipe=s.recipe,let r=catalog.recipe(recipe) {
                if let task=assign(kind:"finish",job:r.job,subject:id,at:s.node,work:r.finish_s){world.stations[id]!.taskID=task;world.stations[id]!.phase="finishing"}
                continue
            }
            guard !finishingOnly,s.phase=="idle" else{continue}
            var recipeID:String?
            if id=="kitchen",world.amount(.meal)<Int64(world.agents.count*2000) {
                recipeID=world.policy != "military" && world.amount(.meat,at:s.input)>=2000 ? "cook_meat":"cook_basic"
            }
            if id=="forge",world.buildings["workshop",default:0]>0,world.amount(.tools)<6000 {recipeID="forge"}
            if id=="ration",world.rationTarget>world.amount(.rations),world.foodEquivalent()>=Int64(world.agents.count*4000+16000) {recipeID="ration_plain"}
            guard let recipeID,let r=catalog.recipe(recipeID) else{continue}
            supply(r.input_mU,to:s.input)
            let space=r.output_mU.reduce(Int64(0)){$0+$1.value*LifeResource(rawValue:$1.key)!.volume}
            guard world.has(r.input_mU,at:s.input),world.freeSpace(s.output)>=space else{continue}
            if let task=assign(kind:"prepare",job:r.job,subject:id,at:s.node,work:r.prepare_s) {
                let parts=r.input_mU.keys.sorted().flatMap { world.selection(LifeResource(rawValue:$0)!,quantity:r.input_mU[$0]!,at:s.input)! }
                for part in parts {world.lots[part.lotID]!.reserved+=part.amount}
                world.tasks[task]!.reservations=parts
                world.storages[s.output]!.incoming+=space
                world.stations[id]!.recipe=recipeID;world.stations[id]!.phase="preparing";world.stations[id]!.taskID=task;world.stations[id]!.outputSpace=space;world.stations[id]!.foodInProcess=0
                if world.tasks[task]!.current.kind=="work" {
                    world.beginReservedInputs(task);world.stations[id]!.foodInProcess=r.output_mU["meal",default:0]
                }
            }
        }
        if !finishingOnly {
            for (r,source) in [(LifeResource.tools,"forge-out"),(.rations,"ration-out")] where world.amount(r,at:source)>0 {_=haul(r,quantity:world.amount(r,at:source),to:"warehouse")}
        }
    }
    mutating func planGathering() {
        let pending=world.projects.values.filter{!$0.completed}.reduce(into:[String:Int64]()){sum,p in for(k,q)in p.materials{sum[k,default:0]+=q}}
        for (source,job,resource,qty,seconds,bufferTarget) in [("trees","logger",LifeResource.wood,Int64(4000),Int64(105),Int64(16000)),("quarry","miner",.stone,4000,135,6000),("mine","miner",.iron,2000,300,4000)] {
            if world.amount(resource,at:source)>0 {_=haul(resource,quantity:world.amount(resource,at:source),to:"warehouse")}
            guard world.amount(resource)<bufferTarget+pending[resource.rawValue,default:0],world.freeSpace(source)>=qty*resource.volume,
                  !world.tasks.values.contains(where:{$0.kind=="gather" && $0.target==source}) else{continue}
            if source=="trees" {
                guard let index=world.treeReady.firstIndex(where:{$0>=0 && $0<=world.time}) else{continue}
                if let task=assign(kind:"gather",job:job,subject:String(index),at:source,work:seconds) {
                    world.treeReady[index] = -1;world.tasks[task]!.target=source;world.tasks[task]!.resource=resource;world.tasks[task]!.quantity=qty;world.tasks[task]!.space=qty*resource.volume;world.storages[source]!.incoming+=qty*resource.volume
                }
            } else if let task=assign(kind:"gather",job:job,subject:source,at:source,work:seconds) {
                world.tasks[task]!.target=source;world.tasks[task]!.resource=resource;world.tasks[task]!.quantity=qty;world.tasks[task]!.space=qty*resource.volume;world.storages[source]!.incoming+=qty*resource.volume
            }
        }
        for i in world.treeReady.indices where world.treeReady[i] == -2 {
            if let _=assign(kind:"replant",job:"logger",subject:String(i),at:"trees",work:30){world.treeReady[i] = -3}
        }
    }
    mutating func planPatrol() {
        for id in world.agents.keys.sorted() {
            let a=world.agents[id]!
            if world.meals.contains(where:{!$0.closed && $0.expected.contains(id) && $0.served[id]==nil}) {continue}
            guard a.taskID==nil,(a.job=="guard_night" && world.phase>=2160) || (a.job=="guard_day" && (240..<1800).contains(world.phase)) else{continue}
            var tail:[LifeStep]=[]
            if let m=move("gate","warehouse"){tail.append(m)}
            tail.append(.init(kind:"work",seconds:30))
            if let m=move("warehouse","gate"){tail.append(m)}
            _=assign(kind:"patrol",job:"guard",subject:"nightwatch",at:"gate",work:10,tail:tail,only:id)
        }
    }
    func metric(_ key:String)->Int {
        if key=="population" {return world.agents.count}
        if key.hasPrefix("building."){return world.buildings[String(key.dropFirst(9)),default:0]}
        if key.hasPrefix("counter."){return world.counters[String(key.dropFirst(8)),default:0]}
        return 0
    }
    mutating func discoverHeroes() {
        for r in catalog.recruitment where !world.discovered.contains(r.hero) && r.unlock.allSatisfy({c in c.op==">=" ? metric(c.metric)>=c.amount:metric(c.metric)==c.amount}) {
            world.discovered.append(r.hero);world.record("discovery","发现\(catalog.hero(r.hero)!.name)的常驻线索，可在宝鉴中查看；不必立即回应。")
        }
    }
    mutating func planRecruitment() {
        for id in world.recruits.keys.sorted() {
            let progress=world.recruits[id]!,route=catalog.recruitment.first{$0.hero==id}!
            if progress.state=="finish" {
                if assign(kind:"recruit_finish",job:"courier",subject:id,at:"hall",work:30) != nil {world.recruits[id]!.state="finishing"}
            } else if progress.state=="waiting" && world.wish==id && progress.stage<3 {
                let stage=route.stages[progress.stage]
                let reservedBedCount=world.recruits.values.filter{$0.stage==2 && $0.state != "waiting" && $0.state != "owned"}.count
                guard world.treasury-world.reservedCash-stage.cash>=100,
                      progress.stage<2 || world.agents.count+reservedBedCount<world.housing else{continue}
                let foodCost=stage.materials_mU["grain",default:0]*4+stage.materials_mU["meal",default:0]
                if foodCost>0 && world.foodEquivalent()-foodCost<Int64(world.agents.count*4000){continue}
                supply(stage.materials_mU,to:"recruit")
                guard world.has(stage.materials_mU,at:"recruit") else{continue}
                if assign(kind:"recruit_prepare",job:"courier",subject:id,at:"hall",work:60) != nil {
                    world.use(stage.materials_mU,at:"recruit");world.treasury-=stage.cash
                    world.recruits[id]!.spent+=stage.cash;world.recruits[id]!.state="preparing"
                }
            }
        }
    }
}
