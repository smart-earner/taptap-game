import Foundation

extension LifeWorld {
    /// Two forthcoming basic meals per resident, plus the full quoted wood for
    /// unfinished projects. Prepared meals are deliberately not subtracted.
    public var goldFuelWoodReserve:Int64 {
        let forecast=Int64(gacha?.stars.count ?? agents.count)
        let committed=projects.values.filter{!$0.completed}
            .reduce(Int64(0)){$0+$1.materials["wood",default:0]}
        return forecast*250+committed
    }
}

extension LifeRuntime {
    mutating func setupGoldTown() {
        for (id,node,cap) in [("goldmine","goldmine",24),("smelter-in","smelter",64),("smelter-out","smelter",64),("mint","hall",64),("guest-meals","tavern",32)] {
            world.storages[id] = .init(node:node,capacity:Int64(cap)*1_000_000)
        }
        world.stations["smelter"] = .init(id:"smelter",node:"smelter",input:"smelter-in",output:"smelter-out",kind:"smelter")
        world.buildings["goldmine"]=1;world.buildings["smelter"]=1;world.buildings["tavern"]=1
        world.discovered=catalog.heroes.map(\.id)
    }
    mutating func settleHeroArrivals() {
        guard world.isGacha,let definition else{return}
        let arrivalOrder=world.gacha!.arrivals.keys.sorted {
            let lhs=world.gacha!.arrivals[$0]!,rhs=world.gacha!.arrivals[$1]!
            return lhs==rhs ? $0<$1 : lhs<rhs
        }
        for id in arrivalOrder where world.gacha!.arrivals[id]!<=world.time {
            let hasFormalUnit=(world.heroTown?.courtyard?.freeUnits ?? 0)>0
            let guestCount=world.agents.values.filter{$0.home=="tavern"}.count
            let canHouse=hasFormalUnit || guestCount<30
            let canFeed=world.foodCoverage>=9500 &&
                world.foodEquivalent()>=Int64(world.agents.count+1)*4_000
            if world.isFormalHeroTown &&
                (world.agents.count>=30+10*(world.gacha?.rosterPhase ?? 0) || !canHouse || !canFeed) {
                if var formal=world.heroTown,var owned=formal.ownedHeroes[id] {
                    owned.arrivalState="waiting_residency"
                    formal.ownedHeroes[id]=owned
                    world.heroTown=formal
                }
                break
            }
            let h=definition.hero(id)!
            let formalBed=world.isFormalHeroTown ? (formalReservedBed(for:id) ?? reserveFormalBed(for:id)):nil
            let hasBed=formalBed != nil || (!world.isFormalHeroTown && world.agents.values.filter{$0.home=="home"}.count<world.housing)
            let home=formalBed?.home ?? (hasBed ? "home":"tavern"),dining=formalBed?.dining ?? (hasBed ? "home-meals":"guest-meals")
            let job=["food":"farmer","supply":"miner","craft":"builder","logistics":"porter","trade":"clerk","guard":"handyman"][h.star_profile]!
            world.agents[id] = .init(id:id,name:h.name,job:job,node:"gate",home:home,dining:dining,heroID:id,origin:"recruited")
            if world.isFormalHeroTown,var formal=world.heroTown,var courtyard=formal.courtyard,courtyard.households[id]==nil {
                courtyard.households[id] = .init(id:"household:\(id)",memberPersonIDs:["hero:\(id)"],
                                                  residencePlotID:hasBed ? (formal.ownedHeroes[id]?.bedReservation ?? "tavern-1") : "tavern-1",
                                                  unitID:nil,createdAt:world.time)
                formal.courtyard=courtyard;world.heroTown=formal
            }
            world.gacha!.arrivals[id]=nil
            _=assign(kind:"home",job:"courier",subject:"arrival",at:home,work:0,tail:[.init(kind:"arrive",seconds:1)],only:id)
            world.record("arrival","\(h.name)抵达小城，\(hasBed ? "已安排住处":"暂住酒馆，太守将安排扩建")。")
        }
        var free=world.housing-world.agents.values.filter{$0.home != "tavern"}.count
        for id in world.agents.keys.sorted() where free>0 && world.agents[id]!.home=="tavern" && world.agents[id]!.taskID==nil {
            // Changing the destination does not teleport the agent or cargo; a real home trip follows.
            let formalBed=world.isFormalHeroTown ? reserveFormalBed(for:id):nil
            let home=formalBed?.home ?? "home",dining=formalBed?.dining ?? "home-meals"
            world.agents[id]!.home=home;world.agents[id]!.dining=dining;free-=1
            _=assign(kind:"home",job:"courier",subject:"move_house",at:home,work:0,tail:[.init(kind:"arrive",seconds:1)],only:id)
            world.record("housing","\(world.agents[id]!.name)从酒馆迁往新住处。")
        }
        if world.isFormalHeroTown,world.heroTown?.courtyard != nil {
            for id in world.heroTown!.courtyard!.legacyOccupiedLeases.keys.sorted() where free>0 {
                guard world.agents[id]?.taskID==nil,let destination=reserveFormalBed(for:id) else {continue}
                world.agents[id]!.home=destination.home
                world.agents[id]!.dining=destination.dining
                free-=1
                _=assign(kind:"home",job:"courier",subject:"move_courtyard",at:destination.home,
                         work:0,tail:[.init(kind:"arrive",seconds:1)],only:id)
                world.record("housing","\(world.agents[id]!.name)迁入共享院落，旧居名额已释放。")
            }
        }
        if world.isFormalHeroTown {syncFormalOwnedHeroes()}
    }

    mutating func reserveFormalBed(for heroID:String)->(home:String,dining:String)? {
        guard var formal=world.heroTown else{return nil}
        if var courtyard=formal.courtyard {
            let candidates=formal.city.plots.indices.filter { index in
                let plot=formal.city.plots[index]
                return plot.kind=="house" && plot.level>0 && courtyard.unitID(plotID:plot.id) != nil
            }.sorted{formal.city.plots[$0].id<formal.city.plots[$1].id}
            guard let index=candidates.first,let unitID=courtyard.unitID(plotID:formal.city.plots[index].id) else{return nil}
            let plot=formal.city.plots[index],householdID="household:\(heroID)"
            courtyard.units[unitID]!.occupantHouseholdID=householdID
            courtyard.households[heroID] = .init(id:householdID,memberPersonIDs:["hero:\(heroID)"],
                                                  residencePlotID:plot.id,unitID:unitID,
                                                  createdAt:courtyard.households[heroID]?.createdAt ?? world.time)
            formal.city.plots[index].occupancy+=1
            if let oldPlot=courtyard.legacyOccupiedLeases.removeValue(forKey:heroID),
               let oldIndex=formal.city.plots.firstIndex(where:{$0.id==oldPlot}) {
                formal.city.plots[oldIndex].occupancy=max(0,formal.city.plots[oldIndex].occupancy-1)
            }
            let dining=plot.id=="house-1" ? "home-meals":"\(plot.id).meal"
            if world.storages[dining]==nil {world.storages[dining] = .init(node:plot.node,capacity:Int64([1:8,2:12,3:16][plot.level] ?? 8)*1_000_000)}
            if var owned=formal.ownedHeroes[heroID] {owned.bedReservation=plot.id;formal.ownedHeroes[heroID]=owned}
            formal.courtyard=courtyard;world.heroTown=formal
            return (plot.node,dining)
        }
        let candidates=formal.city.plots.indices.filter { index in
            let plot=formal.city.plots[index]
            return plot.kind=="house" && plot.level>0 && plot.occupancy<plot.capacity
        }.sorted{formal.city.plots[$0].id<formal.city.plots[$1].id}
        guard let index=candidates.first else{return nil}
        formal.city.plots[index].occupancy+=1
        let plot=formal.city.plots[index]
        let dining=plot.id=="house-1" ? "home-meals":"\(plot.id).meal"
        if world.storages[dining]==nil {world.storages[dining] = .init(node:plot.node,capacity:Int64([1:8,2:12,3:16][plot.level] ?? 8)*1_000_000)}
        if var owned=formal.ownedHeroes[heroID] {owned.bedReservation=plot.id;formal.ownedHeroes[heroID]=owned}
        world.heroTown=formal
        return (plot.node,dining)
    }

    func formalReservedBed(for heroID:String)->(home:String,dining:String)? {
        guard let formal=world.heroTown,let reservation=formal.ownedHeroes[heroID]?.bedReservation,
              reservation != "tavern-1.guest",let plot=formal.city.plots.first(where:{$0.id==reservation && $0.level>0}) else{return nil}
        if let courtyard=formal.courtyard,courtyard.households[heroID]?.unitID == nil {return nil}
        return (plot.node,plot.id=="house-1" ? "home-meals":"\(plot.id).meal")
    }
    func starProfile(_ id:String)->String? {definition?.hero(id)?.star_profile}
    func hasSignature(_ id:String,_ profile:String)->Bool {world.gacha?.stars[id]==5 && starProfile(id)==profile}
    func starWorkRate(_ agent:LifeAgent,job:String)->Int {
        guard let weights=catalog.weights[job],let h=catalog.hero(agent.id),let skills=definition?.hero(agent.id)?.skills else{return 10000}
        let ability=weights.reduce(0){$0+h.attributes[$1.key,default:0]*$1.value}/10000
        let personal=min(1000,max(0,ability-50)*20)
        let xp=agent.workSeconds[job,default:0]/300
        let levelBonus=[60,180,360,600].filter{xp>=Int64($0)}.count*100
        var leader=0
        if agent.id != world.prefect,world.counters["admin_lease",default:0]>world.time,!world.isNight,let p=catalog.hero(world.prefect) {
            let a=weights.reduce(0){$0+p.attributes[$1.key,default:0]*$1.value}/10000
            leader=min(500,max(0,a-50)*10)
        }
        let star=world.gacha!.stars[agent.id]!
        let bonus=skills.filter{$0.unlock_star<=star && $0.jobs?.contains(job)==true}.reduce(0){$0+($1.values_by_star?[star-1] ?? 0)}
        return min(14000,max(8000,10000+personal+levelBonus+leader+min(1200,bonus)))
    }
    var goldDemand:Bool {
        guard let g=world.gacha,!g.isComplete else{return false}
        let coinsPerIngot=g.goldRebalance?.coinsPerNewIngot ?? 10
        let promised=world.amount(.gold_ingot)/1000*coinsPerIngot + world.amount(.gold_ore)/2000*coinsPerIngot
            + Int64(world.stations["smelter"]?.phase != "idle" ? coinsPerIngot:0)
        return world.treasury+promised<2000
    }
    var canSmeltGold:Bool {
        let n=Int64(world.gacha?.stars.count ?? world.agents.count)
        // Ore is only a mining promise, not spendable money. Including it in
        // this gate permanently stalls smelting once the mine fills its 40-ore
        // buffer (2,000 nominal future coins) and leaves the player at zero.
        let coinsPerIngot=world.gacha?.goldRebalance?.coinsPerNewIngot ?? 10
        let payable=world.treasury+world.amount(.gold_ingot)/1000*coinsPerIngot
        return world.gacha?.isComplete==false && payable<2000 &&
            world.heroTown?.city.supplyRecovery != true && world.foodEquivalent()>=n*4000 &&
            world.amount(.wood,free:true)>=world.goldFuelWoodReserve+500
    }
    mutating func planGoldTown() {
        guard world.isGacha else{return}
        if world.amount(.gold_ingot,at:"smelter-out")>0 {_=haul(.gold_ingot,quantity:world.amount(.gold_ingot,at:"smelter-out"),to:"mint")}
        if world.amount(.gold_ore,at:"goldmine")>0 {_=haul(.gold_ore,quantity:world.amount(.gold_ore,at:"goldmine"),to:"warehouse")}
        guard goldDemand,world.heroTown?.city.supplyRecovery != true,world.foodCoverage>=9500,world.amount(.gold_ore)<40000,
              !world.tasks.values.contains(where:{$0.kind=="gather" && $0.target=="goldmine"}),world.freeSpace("goldmine")>=2_200_000 else{return}
        if let id=assign(kind:"gather",job:"miner",subject:"goldmine",at:"goldmine",work:60) {
            let qty:Int64=hasSignature(world.tasks[id]!.worker,"supply") ? 2200:2000
            world.tasks[id]!.target="goldmine";world.tasks[id]!.resource = .gold_ore
            world.tasks[id]!.quantity=qty;world.tasks[id]!.space=qty*1000;world.storages["goldmine"]!.incoming+=qty*1000
        }
    }
    mutating func mintDeliveredGold() {
        guard world.isGacha else{return}
        let amount=world.amount(.gold_ingot,at:"mint",free:true)/1000*1000
        guard amount>0,world.consume(.gold_ingot,quantity:amount,at:"mint") else{return}
        let coins=amount/1000*(world.gacha!.goldRebalance?.coinsPerNewIngot ?? 10)
        world.treasury+=coins;world.gacha!.minted+=coins
        world.record("mint","金锭已运抵府署并入库，获得\(coins)金币。")
    }
    mutating func planGoldHousing() {
        guard world.isGacha,world.projects["repair"]?.completed==true else{return}
        if world.isFormalHeroTown {planFormalCityGrowth();return}
        guard !world.projects.values.contains(where:{!$0.completed}) else{return}
        let population=world.gacha!.stars.count
        if world.housing<min(30,population+2) {
            let q=catalog.buildings.first{$0.id=="house"}!
            if world.gacha!.houseLevels.count<4 {
                startProject(id:"home-\(world.gacha!.houseLevels.count+1)",kind:"house",node:"home",cash:0,work:q.work_s,materials:q.materials_mU)
            } else if let i=world.gacha!.houseLevels.firstIndex(where:{$0<3}) {
                let scale:Int64=world.gacha!.houseLevels[i]==1 ? 2:4
                startProject(id:"home-upgrade-\(i)-\(world.gacha!.houseLevels[i]+1)",kind:"house_upgrade",node:"home",cash:0,work:q.work_s*scale,materials:q.materials_mU.mapValues{$0*scale})
            }
        } else if world.buildings["workshop",default:0]==0,let q=catalog.buildings.first(where:{$0.id=="workshop"}) {
            startProject(id:"workshop-1",kind:"workshop",node:"workshop",cash:0,work:q.work_s,materials:q.materials_mU)
        }
    }
    mutating func planStarPatrol() {
        guard world.agents.count>=8,world.phase>=2040,world.phase<2160,world.counters["star_patrol_cycle",default:-1] != world.cycle,!world.tasks.values.contains(where:{$0.kind=="star_patrol"}) else{return}
        for a in world.agents.values.sorted(by:{$0.id<$1.id}) where a.taskID==nil {
            let outward=move(a.node,"gate")?.seconds ?? 0,back=move("gate",a.home)?.seconds ?? 0
            let work=max(1,120-outward-back)
            guard outward+back<120,world.phase+120<=2160,a.serviceSeconds+120<=1920 else{continue}
            var tail:[LifeStep]=[];if let m=move("gate",a.home){tail.append(m)}
            if let task=assign(kind:"star_patrol",job:"guard",subject:"gate",at:"gate",work:work,tail:tail,only:a.id) {
                world.tasks[task]!.contribution=hasSignature(a.id,"guard") ? 5:0
                break
            }
        }
    }

    mutating func noteFirstDutyAssigned(heroID:String,taskID:String,job:String,destination:String,atWork:Bool) {
        guard world.isFormalHeroTown,var owned=world.heroTown?.ownedHeroes[heroID],
              owned.sourceDrawID != "founding",owned.firstDuty == nil,
              world.agents[heroID]?.workSeconds.values.allSatisfy({$0==0}) == true else{return}
        owned.firstDuty = .init(taskID:taskID,job:job,destination:destination,assignedAt:world.time,
                                arrivedAt:atWork ? world.time:nil,effectiveAt:nil,effect:nil)
        world.heroTown!.ownedHeroes[heroID]=owned
        world.record("arrival","\(world.agents[heroID]?.name ?? heroID)接到首份差事：\(job)，前往\(destination)。")
    }

    mutating func noteFirstDutyArrived(heroID:String,taskID:String) {
        guard var owned=world.heroTown?.ownedHeroes[heroID],var duty=owned.firstDuty,
              duty.taskID==taskID,duty.arrivedAt==nil else{return}
        duty.arrivedAt=world.time;owned.firstDuty=duty;world.heroTown!.ownedHeroes[heroID]=owned
    }

    mutating func noteFirstDutyEffective(heroID:String,taskID:String,effect:String) {
        guard var owned=world.heroTown?.ownedHeroes[heroID],var duty=owned.firstDuty,
              duty.taskID==taskID,duty.effectiveAt==nil else{return}
        duty.arrivedAt=duty.arrivedAt ?? world.time
        duty.effectiveAt=world.time;duty.effect=effect;owned.firstDuty=duty
        world.heroTown!.ownedHeroes[heroID]=owned
        world.record("first_impact","\(world.agents[heroID]?.name ?? heroID)入城后的首项贡献：\(effect)。")
    }

    mutating func finishFirstDutyIfNeeded(_ task:LifeTask) {
        let detail:String
        switch task.kind {
        case "gather":
            guard let resource=task.resource,task.quantity>0 else{return}
            detail="采得\(resource.title)\(Double(task.quantity)/1_000)份，留在\(label(task.target))"
        case "haul":
            guard let resource=task.resource,task.quantity>0 else{return}
            detail="运送\(resource.title)\(Double(task.quantity)/1_000)份到\(label(task.target))"
        case "harvest":detail="收成已落在田边，等待入仓"
        case "sow":detail="播种了一块田"
        case "water":detail="给一块田完成浇水"
        case "prepare":detail="为\(task.subject)备料并开工"
        case "finish":detail="完成\(task.subject)的一批成品"
        case "build":detail="为\(task.subject)完成\(task.contribution)工秒施工"
        case "survey":detail="完成工程勘测并节省材料"
        case "administration":detail="完成一轮城务治理"
        case "star_patrol","patrol":detail="完成一次真实巡防"
        case "civic_clean":detail="完成公共场所清洁，提高城镇卫生"
        case "civic_watch":detail="完成里坊巡护，提高首都守力与安全感"
        case "civic_drill":detail="实耗军粮完成防务操练，提高守备熟练度"
        case "replant":detail="补种一株林木"
        default:return
        }
        noteFirstDutyEffective(heroID:task.worker,taskID:task.id,effect:detail)
    }
}
