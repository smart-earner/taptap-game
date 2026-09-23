import Foundation

extension LifeWorld {
    /// Gathering buffers represent material physically available to the
    /// capital, not stock in a conquered city or a cross-city courier's pack.
    public func capitalGatheringStock(_ resource:LifeResource) -> Int64 {
        lots.values.reduce(Int64(0)) { total,lot in
            guard lot.resource==resource,!lot.location.hasPrefix("war-") else{return total}
            if let task=tasks[lot.location],task.kind=="haul",
               task.subject.hasPrefix("war-") || task.target.hasPrefix("war-") {return total}
            return total+lot.amount
        }
    }
}

extension LifeRuntime {
    mutating func plan() {
        planMealsAndRest()
        planHealth()
        planStations(finishingOnly:true)
        planFields(harvestOnly:true)
        planFoodSupply()
        planWarFrontRations()
        planWarFacilityMaterials()
        planWar()
        planWarLootTransport()
        planHeroAdministration()
        planStations(finishingOnly:false)
        planFields(harvestOnly:false)
        planHusbandry()
        planProjects()
        planRecruitment()
        planGathering()
        planGoldTown()
        if !world.isGacha {planTrade();discoverHeroes()}
        planPatrol()
        planStudy()
        planCivicDuties()
        if world.phase>=2160 {planMealsAndRest()}
    }
    mutating func planFields(harvestOnly:Bool) {
        // Count crops already committed in the fields. Checking only stored
        // grain let every empty bed sow in one planning pass, then flood the
        // shared granary when all those harvests matured together.
        var growingGrain:Int64=0
        if !harvestOnly {
            growingGrain=world.fields.values.filter{$0.state != "empty"}.reduce(0) { sum,field in
                sum+(catalog.crops.first{$0.id==field.crop}?.output_mU["grain"] ?? 0)
            }
        }
        let storedGrain=harvestOnly ? 0:world.amount(.grain)
        for id in world.fields.keys.sorted() {
            if world.isFormalHeroTown,let index=Int(id.dropFirst(6)),
               let city=world.heroTown?.city,
               index>=(city.plot("farm-1")?.capacity ?? 4) &&
               city.plot("farm-2")?.service==0 {continue}
            let f=world.fields[id]!
            var crop=f.crop
            if f.state=="empty",world.isFormalHeroTown,world.heroTown?.city.civics["water",default:0] ?? 0 > 0,
               world.foodEquivalent()>=Int64((world.gacha?.stars.count ?? world.agents.count)*4000) {
                let rice=world.fields.values.filter{$0.crop=="rice" && $0.state != "empty"}.count
                if rice<max(1,world.fields.count/2) {crop="rice"}
            }
            let c=catalog.crops.first{$0.id==crop}!
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
            } else if !harvestOnly && f.state=="empty" &&
                        storedGrain+growingGrain<Int64(world.agents.count*(world.isFormalHeroTown ? 8000:2000)) {
                guard world.freeSpace(id)>=c.output_mU.reduce(Int64(0),{$0+$1.value*LifeResource(rawValue:$1.key)!.volume}) else{continue}
                if let task=assign(kind:"sow",job:"farmer",subject:id,at:id,work:c.sow_s) {
                    world.fields[id]!.crop=crop;world.fields[id]!.taskID=task;world.fields[id]!.state="sowing"
                    growingGrain+=c.output_mU["grain",default:0]
                }
            }
        }
    }
    /// Parent demand never locks an idle worker. Only a feasible single trip reserves stock and destination volume.
    func mealDining(for agent:LifeAgent) -> String {
        world.heroTown?.health?.treatments[agent.id] != nil ? "clinic-meals":agent.dining
    }
    @discardableResult mutating func haul(_ resource:LifeResource,quantity:Int64,to target:String) -> Bool {
        guard quantity>0,let destination=world.storages[target] else{return false}
        let inFlight=world.tasks.values.filter{$0.kind=="haul" && $0.target==target && $0.resource==resource}.reduce(Int64(0)){$0+$1.quantity}
        let needed=max(0,quantity-inFlight)
        guard needed>0 else{return false}
        var valid=Set(["warehouse","trees","mine","quarry","kitchen-out","forge-out","ration-out","butcher-out","pasture-feed","goldmine","smelter-out"]+Array(world.fields.keys))
        if resource == .meal {
            if target.hasPrefix("delivery-") {
                // Depot replenishment must come from cooked output; do not
                // strip a family's two-meal reserve to fill another shelf.
                valid=Set(["kitchen-out"])
            } else {
                valid.formUnion(world.storages.keys.filter{$0=="home-meals" || $0=="hall-meals" || $0=="guest-meals" || $0=="clinic-meals" || $0.hasSuffix(".meal") || $0.hasPrefix("delivery-")})
            }
        }
        func exportable(_ source:String)->Int64 {
            let free=world.amount(resource,at:source,free:true)
            guard resource == .meal,world.agents.values.contains(where:{mealDining(for:$0)==source}) else{return free}
            // A home may share genuine surplus, but must keep two meals for
            // each resident. Without this floor, porters shuttle the same
            // portions back and forth between houses before supper.
            let reserve=Int64(world.agents.values.filter{mealDining(for:$0)==source}.count)*2_000
            return max(0,free-reserve)
        }
        let sources=world.storages.keys.filter{$0 != target && valid.contains($0) && exportable($0)>0}.sorted { a,b in
            let da=LifeMap.length(LifeMap.path(world.storages[a]!.node,destination.node)),db=LifeMap.length(LifeMap.path(world.storages[b]!.node,destination.node))
            return da==db ? a<b:da<db
        }
        for source in sources {
            let node=world.storages[source]!.node
            var q=min(needed,exportable(source),4_000_000/resource.volume,world.freeSpace(target)/resource.volume)
            guard q>0,var parts=world.selection(resource,quantity:q,at:source) else{continue}
            var tail=[LifeStep(kind:"load",seconds:10)]
            if let m=move(node,destination.node,loaded:true){tail.append(m)}
            tail.append(.init(kind:"unload",seconds:10))
            let mealService=resource == .meal && !target.hasPrefix("delivery-")
            guard let id=assign(kind:"haul",job:"porter",subject:source,at:node,work:0,tail:tail,
                                necessaryService:mealService) else{continue}
            if world.isGacha,hasSignature(world.tasks[id]!.worker,"logistics") {
                q=min(needed,exportable(source),5_000_000/resource.volume,world.freeSpace(target)/resource.volume)
                parts=world.selection(resource,quantity:q,at:source)!
            }
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
        var targets:[String:Int64]=[:]
        for agent in world.agents.values {targets[mealDining(for:agent),default:0]+=2000}
        for key in targets.keys.sorted() {
            let need=max(0,targets[key]!-world.amount(.meal,at:key))
            if need>0 {for _ in 0..<3{if !haul(.meal,quantity:need,to:key){break}}}
        }
        // A delivery attachment is a real 16-volume forward meal container.
        // Stock it only after household orders have first claim on cooked food.
        let depots=world.storages.keys.filter{$0.hasPrefix("delivery-")}.sorted()
        if !depots.isEmpty {
            var staging:[String:Int64]=[:]
            for agent in world.agents.values where (agent.dining=="home-meals" || agent.dining.hasSuffix(".meal")) && mealDining(for:agent) != "clinic-meals" {
                guard let dining=world.storages[agent.dining] else{continue}
                let nearest=depots.min { left,right in
                    let a=LifeMap.length(LifeMap.path(world.storages[left]!.node,dining.node))
                    let b=LifeMap.length(LifeMap.path(world.storages[right]!.node,dining.node))
                    return a==b ? left<right:a<b
                }!
                staging[nearest,default:0]+=1_000
            }
            for depot in depots {
                let target=min(staging[depot,default:0],world.storages[depot]!.capacity/LifeResource.meal.volume)
                let missing=max(0,target-world.amount(.meal,at:depot))
                if missing>0 {for _ in 0..<3{if !haul(.meal,quantity:missing,to:depot){break}}}
            }
        }
        if (world.isGacha || world.stations["kitchen"]!.phase=="idle") && world.amount(.meal)<desiredMealStock() {
            let useMeat=world.policy != "military" && world.amount(.meat)>=2000
            let r=catalog.recipe(useMeat ? "cook_meat":"cook_basic")!
            let batches:Int64=world.isGacha ? max(1,(Int64(world.gacha!.stars.count)*2+3)/4):1
            supply(r.input_mU.mapValues{$0*batches},to:"kitchen-in")
        }
        for id in world.fields.keys.sorted() where world.amount(.grain,at:id)>0 {_=haul(.grain,quantity:world.amount(.grain,at:id),to:"warehouse")}
    }
    func desiredMealStock() -> Int64 {
        let residential=world.storages.keys.contains(where:{$0.hasPrefix("delivery-")}) ?
            world.agents.values.filter{$0.dining=="home-meals" || $0.dining.hasSuffix(".meal")}.count:0
        return Int64(world.agents.count)*2_000+Int64(residential)*1_000
    }
    mutating func planStations(finishingOnly:Bool) {
        for id in world.stations.keys.sorted() {
            let s=world.stations[id]!
            if s.phase=="finish",s.taskID==nil,let recipe=s.recipe,let r=catalog.recipe(recipe) {
                let eligible:Set<String>?=recipe=="cook_feast" ? Set(world.agents.keys.filter{hasSignature($0,"food")}):nil
                if let task=assign(kind:"finish",job:r.job,subject:id,at:s.node,work:r.finish_s,eligible:eligible){world.stations[id]!.taskID=task;world.stations[id]!.phase="finishing"}
                continue
            }
            guard !finishingOnly,s.phase=="idle" else{continue}
            var recipeID:String?
            if s.kind=="kitchen",world.amount(.meal)<desiredMealStock() {
                recipeID=world.policy != "military" && world.amount(.meat,at:s.input)>=2000 ? "cook_meat":"cook_basic"
                if world.isGacha,world.agents.keys.contains(where:{hasSignature($0,"food") && world.agents[$0]!.taskID==nil}),world.foodEquivalent()>Int64(world.agents.count*4000),world.amount(.meal)>Int64(world.agents.count*1000) {recipeID="cook_feast"}
            }
            let workingForge=world.isFormalHeroTown ?
                (world.heroTown?.city.plots.contains{$0.kind=="workshop" && $0.level>0 && $0.service>0} == true):
                world.buildings["workshop",default:0]>0
            if id=="forge",workingForge,world.capitalGatheringStock(.tools)<6000 {recipeID="forge"}
            if id=="ration",world.rationTarget>world.capitalGatheringStock(.rations),world.foodEquivalent()>=Int64(world.agents.count*4000+16000) {recipeID="ration_plain"}
            if world.isGacha,id=="smelter",canSmeltGold {recipeID="smelt_gold"}
            guard let recipeID,var r=catalog.recipe(recipeID) else{continue}
            var eligible:Set<String>?=recipeID=="cook_feast" ? Set(world.agents.keys.filter{hasSignature($0,"food")}):nil
            if recipeID=="smelt_gold" {
                let specialists=Set(world.agents.keys.filter{hasSignature($0,"trade") && world.agents[$0]?.taskID==nil})
                if !specialists.isEmpty {r.input_mU["wood"]=450;eligible=specialists}
            }
            supply(r.input_mU,to:s.input)
            let space=r.output_mU.reduce(Int64(0)){$0+$1.value*LifeResource(rawValue:$1.key)!.volume}
            guard world.has(r.input_mU,at:s.input),world.freeSpace(s.output)>=space else{continue}
            if let task=assign(kind:"prepare",job:r.job,subject:id,at:s.node,work:r.prepare_s,eligible:eligible) {
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
        for (source,job,resource,qty,seconds,bufferTarget) in [("trees","logger",LifeResource.wood,Int64(4000),Int64(105),Int64(world.isGacha ? max(16000,world.agents.count*2000):16000)),("quarry","miner",.stone,4000,135,6000),("mine","miner",.iron,2000,300,4000)] {
            if world.amount(resource,at:source)>0 {_=haul(resource,quantity:world.amount(resource,at:source),to:"warehouse")}
            guard world.capitalGatheringStock(resource)<bufferTarget+pending[resource.rawValue,default:0],world.freeSpace(source)>=(world.isGacha ? qty*11/10:qty)*resource.volume,
                  !world.tasks.values.contains(where:{$0.kind=="gather" && $0.target==source}) else{continue}
            if source=="trees" {
                guard let index=world.treeReady.firstIndex(where:{$0>=0 && $0<=world.time}) else{continue}
                if let task=assign(kind:"gather",job:job,subject:String(index),at:source,work:seconds) {
                    let qty=world.isGacha && hasSignature(world.tasks[task]!.worker,"supply") ? qty*11/10:qty
                    world.treeReady[index] = -1;world.tasks[task]!.target=source;world.tasks[task]!.resource=resource;world.tasks[task]!.quantity=qty;world.tasks[task]!.space=qty*resource.volume;world.storages[source]!.incoming+=qty*resource.volume
                }
            } else if let task=assign(kind:"gather",job:job,subject:source,at:source,work:seconds) {
                let qty=world.isGacha && hasSignature(world.tasks[task]!.worker,"supply") ? qty*11/10:qty
                world.tasks[task]!.target=source;world.tasks[task]!.resource=resource;world.tasks[task]!.quantity=qty;world.tasks[task]!.space=qty*resource.volume;world.storages[source]!.incoming+=qty*resource.volume
            }
        }
        for i in world.treeReady.indices where world.treeReady[i] == -2 {
            if let _=assign(kind:"replant",job:"logger",subject:String(i),at:"trees",work:30){world.treeReady[i] = -3}
        }
    }
    mutating func planPatrol() {
        if world.isGacha {planStarPatrol();return}
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
        guard !world.isGacha else{return}
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
