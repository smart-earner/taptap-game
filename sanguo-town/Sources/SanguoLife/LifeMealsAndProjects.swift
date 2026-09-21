import Foundation

extension LifeRuntime {
    mutating func updateMeals() {
        let phase=world.phase
        if phase==420 || phase==1800 {
            let at=world.cycle*2880+(phase==420 ? 600:1980), id="meal-\(at)"
            let extra=(try? LifeAbilities.resolve(catalog,sources:leaders(),metric:"happiness_rise_extra",coverage:world.foodCoverage)) ?? 0
            world.meals.append(.init(id:id,at:at,deadline:at+180,expected:world.agents.keys.sorted(),recoveryExtra:extra))
        }
        for index in world.meals.indices where !world.meals[index].closed {
            if world.time==world.meals[index].at {world.meals[index].expected=world.agents.keys.sorted()}
            guard world.time>=world.meals[index].at else{continue}
            for id in world.meals[index].expected where world.meals[index].served[id]==nil {
                guard let a=world.agents[id],a.taskID==nil,let storage=world.storages[a.dining],a.node==storage.node,
                      let parts=world.selection(.meal,quantity:1000,at:a.dining) else{continue}
                let quality=parts.reduce(Int64(0)){$0+$1.amount*(world.lots[$1.lotID]!.quality=="hearty" ? 100:40)}/1000
                guard world.consume(.meal,quantity:1000,at:a.dining) else{continue}
                world.meals[index].served[id]=Int(quality);world.counters["resident_meals_consumed",default:0]+=1
                _=assign(kind:"eat",job:"server",subject:world.meals[index].id,at:a.node,work:45,only:id)
            }
            if world.time>=world.meals[index].deadline {
                world.meals[index].closed=true
                let past=Array(world.meals.filter(\.closed).suffix(4)),expected=past.reduce(0){$0+$1.expected.count},served=past.reduce(0){$0+$1.served.count}
                world.foodCoverage=expected>0 ? served*10000/expected:10000
                let quality=served>0 ? past.reduce(0){$0+$1.served.values.reduce(0,+)}/served:0
                // V1 only reads completed service evidence; no decorative walking creates a service.
                let clean=min(100,40+world.cleanedSites.count*10)
                let security=world.counters["patrols",default:0]>0 ? 80:60
                let target=(world.foodCoverage/100*40+quality*10+100*15+clean*10+security*15+100*10)/100
                let change=max(-5,min(3+world.meals[index].recoveryExtra,target-world.happiness))
                world.happiness=max(0,min(100,world.happiness+change))
                let complete=world.meals[index].served.count==world.meals[index].expected.count
                world.counters["consecutive_full_meals"]=complete ? world.counters["consecutive_full_meals",default:0]+1:0
                world.record("meal","本餐实际供应\(world.meals[index].served.count)/\(world.meals[index].expected.count)人；\(world.coverageText())，满意度\(world.happiness)。")
            }
        }
        if world.meals.count>6 {world.meals.removeFirst(world.meals.count-6)}
    }
    mutating func planMealsAndRest() {
        for id in world.agents.keys.sorted() {
            let a=world.agents[id]!
            guard a.taskID==nil else{continue}
            if let meal=world.meals.last(where:{!$0.closed && $0.expected.contains(id) && $0.served[id]==nil}),world.time>=meal.at-180,
               let node=world.storages[a.dining]?.node,world.amount(.meal,at:a.dining)>=1000,a.node != node {
                _=assign(kind:"meal_trip",job:"server",subject:meal.id,at:node,work:0,tail:[.init(kind:"arrive",seconds:1)],only:id)
                continue
            }
            let sleeping=a.job=="guard_night" ? (900..<1740).contains(world.phase):world.phase>=2160
            if sleeping {
                if a.node != a.home {_=assign(kind:"home",job:"handyman",subject:"rest",at:a.home,work:0,tail:[.init(kind:"rest",seconds:1)],only:id)}
                else if a.restStart==nil {world.agents[id]!.restStart=world.time}
            } else if a.job=="prefect",a.node != "hall" {
                _=assign(kind:"office",job:"clerk",subject:"governance",at:"hall",work:30,only:id)
            }
        }
    }
    mutating func startProject(id:String,kind:String,node:String,cash:Int64,work:Int64,materials:[String:Int64]) {
        guard world.projects[id]==nil,world.treasury-world.reservedCash>=cash+100 else{return}
        world.projects[id] = .init(id:id,kind:kind,node:node,materials:materials,cash:cash,totalWork:work)
        // Dedicated site capacity is limited to the quoted materials, never a universal infinite warehouse.
        let volume=materials.reduce(Int64(0)){$0+$1.value*LifeResource(rawValue:$1.key)!.volume}
        world.storages["project-"+id] = .init(node:node,capacity:max(1_000_000,volume))
        world.reservedCash+=cash
    }
    func projectStage(_ p:LifeProject) -> (work:Int64,materials:[String:Int64],cash:Int64) {
        let cuts:[Int64]=[0,20,45,80,100],a=cuts[p.phase],b=cuts[p.phase+1]
        return (p.totalWork*b/100-p.totalWork*a/100,p.materials.mapValues{$0*b/100-$0*a/100},p.cash*b/100-p.cash*a/100)
    }
    mutating func finishProjectPhase(_ id:String) {
        guard var p=world.projects[id],!p.completed else{return}
        let threshold=p.totalWork*[20,45,80,100][p.phase]/100
        guard p.completedWork==threshold && p.allocatedWork==0 else{return}
        p.phase+=1;p.stageStarted=false
        if p.phase==4 {
            p.completed=true
            if p.kind=="seal" {world.owned.append("founders_seal");world.record("collection","开城木印已完成，已放入府署藏架。")}
            else if p.kind=="repair" {world.record("construction","府署修缮完成：材料已到场并实际消耗，四段施工完工。")}
            else {
                world.buildings[p.kind,default:0]+=1
                world.record("construction","\(buildingName(p.kind))建成，下一轮规划开始使用。")
                if p.kind=="house" {world.storages["home-meals"]!.capacity=Int64(world.housing)*1_000_000}
            }
        }
        world.projects[id]=p
    }
    mutating func planProjects() {
        if world.growthEnabled,world.projects["repair"]?.completed==true,
           !world.projects.values.contains(where:{!$0.completed && $0.kind != "seal"}) {
            let kind = world.housing<=world.agents.count ? "house" : (world.buildings["market",default:0]==0 ? "market":(world.buildings["workshop",default:0]==0 ? "workshop":(world.buildings["tavern",default:0]==0 ? "tavern":"")))
            if !kind.isEmpty,let q=catalog.buildings.first(where:{$0.id==kind}) {
                startProject(id:kind+"-\(world.buildings[kind,default:0]+1)",kind:kind,node:kind=="house" ? "home":kind,cash:q.cash,work:q.work_s,materials:q.materials_mU)
            }
        }
        for id in world.projects.keys.sorted() {
            let p=world.projects[id]!
            guard !p.completed else{continue}
            let stage=projectStage(p),target="project-"+id
            if !p.stageStarted {
                supply(stage.materials,to:target)
                guard world.has(stage.materials,at:target) else{continue}
            }
            if world.foodCoverage<9000 && p.kind != "repair" {continue}
            let threshold=p.totalWork*[20,45,80,100][p.phase]/100
            let outstanding=threshold-p.completedWork-p.allocatedWork
            guard outstanding>0 else{continue}
            let assigned=world.tasks.values.filter{$0.kind=="build" && $0.subject==id}.count
            guard assigned<2 else{continue}
            let contribution=min(outstanding,120)
            if let task=assign(kind:"build",job:p.kind=="seal" ? "carpenter":"builder",subject:id,at:p.node,work:contribution) {
                if !p.stageStarted {
                    world.use(stage.materials,at:target);world.reservedCash-=stage.cash;world.treasury-=stage.cash;world.projects[id]!.stageStarted=true
                }
                world.tasks[task]!.contribution=contribution;world.projects[id]!.allocatedWork+=contribution
            }
        }
        if world.time>0 && world.time%43200==0 && world.agents.count+2<=world.housing && world.agents.count<150 && world.foodCoverage>=9500 && world.happiness>=70 {
            for _ in 0..<2 {let id=world.next("resident");world.agents[id] = .init(id:id,name:"新邻\(world.agents.count+1)",job:"flex",node:"gate",home:"home",dining:"home-meals")}
            world.record("immigration","两名新居民抵达，床位与日常饭食需求已同步。")
        }
    }
    public func buildingName(_ kind:String)->String {
        ["hall":"府署","repair":"府署修缮","house":"民居","farm":"农庄","granary":"粮仓","market":"集市","workshop":"工造院","tavern":"饭馆","stable":"马厩","station":"驿站","barracks":"营地","seal":"开城木印"][kind] ?? kind
    }
}
