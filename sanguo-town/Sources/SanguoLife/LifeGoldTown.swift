import Foundation

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
        for id in world.gacha!.arrivals.keys.sorted() where world.gacha!.arrivals[id]!<=world.time {
            let h=definition.hero(id)!
            let formalBed=world.isFormalHeroTown ? (formalReservedBed(for:id) ?? reserveFormalBed(for:id)):nil
            let hasBed=formalBed != nil || (!world.isFormalHeroTown && world.agents.values.filter{$0.home=="home"}.count<world.housing)
            let home=formalBed?.home ?? (hasBed ? "home":"tavern"),dining=formalBed?.dining ?? (hasBed ? "home-meals":"guest-meals")
            let job=["food":"farmer","supply":"miner","craft":"builder","logistics":"porter","trade":"clerk","guard":"handyman"][h.star_profile]!
            world.agents[id] = .init(id:id,name:h.name,job:job,node:"gate",home:home,dining:dining,heroID:id,origin:"recruited")
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
        if world.isFormalHeroTown {syncFormalOwnedHeroes()}
    }

    mutating func reserveFormalBed(for heroID:String)->(home:String,dining:String)? {
        guard var formal=world.heroTown else{return nil}
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
        let promised=world.amount(.gold_ingot)/1000*10 + world.amount(.gold_ore)/2000*10
            + Int64(world.stations["smelter"]?.phase != "idle" ? 10:0)
        return world.treasury+promised<2000
    }
    var canSmeltGold:Bool {
        let n=Int64(world.gacha?.stars.count ?? world.agents.count)
        let committed=world.projects.values.filter{!$0.completed}.reduce(Int64(0)){$0+$1.materials["wood",default:0]}
        let protectedWood=n*500+committed
        return goldDemand && world.heroTown?.city.supplyRecovery != true && world.foodEquivalent()>=n*4000 && world.amount(.wood,free:true)>=protectedWood+500
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
        let coins=amount/1000*10
        world.treasury+=coins;world.gacha!.minted+=coins
        world.record("mint","金锭已运抵府署并入库，获得\(coins)金币。")
    }
    mutating func planGoldHousing() {
        guard world.isGacha,world.projects["repair"]?.completed==true,!world.projects.values.contains(where:{!$0.completed}) else{return}
        if world.isFormalHeroTown {planFormalCityGrowth();return}
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
}
