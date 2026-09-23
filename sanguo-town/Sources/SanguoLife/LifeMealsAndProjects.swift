import Foundation

public enum LifeHappinessContract {
    /// A shared city mood is intentionally used instead of sixty mutable
    /// person-level mood ledgers. The task snapshots still retain each
    /// worker's own health and skill modifiers independently.
    public static func workModifierBP(happiness: Int, job: String) -> Int {
        let modifier = happiness >= 85 ? 500 : happiness >= 70 ? 0 :
            happiness >= 50 ? -500 : happiness >= 30 ? -1_000 : -1_500
        // The minimum civilian food-and-care chain cannot spiral into a
        // slower recovery solely because the city is already unhappy.
        if modifier < 0 && ["farmer", "cook", "porter", "physician"].contains(job) { return 0 }
        return modifier
    }
}

extension LifeRuntime {
    mutating func updateMeals() {
        let phase=world.phase
        if phase==420 || phase==1800 {
            let at=world.cycle*2880+(phase==420 ? 600:1980), id="meal-\(at)"
            let extra=(try? LifeAbilities.resolve(catalog,sources:leaders(),metric:"happiness_rise_extra",coverage:world.foodCoverage)) ?? 0
            world.meals.append(.init(id:id,at:at,deadline:at+180,expected:world.agents.keys.filter{!world.warAwayHeroIDs.contains($0)}.sorted(),recoveryExtra:extra))
        }
        for index in world.meals.indices where !world.meals[index].closed {
            if world.time==world.meals[index].at {world.meals[index].expected=world.agents.keys.filter{!world.warAwayHeroIDs.contains($0)}.sorted()}
            guard world.time>=world.meals[index].at else{continue}
            for id in world.meals[index].expected where world.meals[index].served[id]==nil {
                guard let a=world.agents[id] else{continue}
                let admitted=world.heroTown?.health?.treatments[id] != nil && a.node=="clinic"
                let dining=admitted ? "clinic-meals":a.dining
                guard (a.taskID==nil || admitted),let storage=world.storages[dining],a.node==storage.node,
                      let parts=world.selection(.meal,quantity:1000,at:dining) else{continue}
                let quality=parts.reduce(Int64(0)){$0+$1.amount*(world.lots[$1.lotID]!.quality=="hearty" ? 100:40)}/1000
                guard world.consume(.meal,quantity:1000,at:dining) else{continue}
                world.meals[index].served[id]=Int(quality);world.counters["resident_meals_consumed",default:0]+=1
                if quality==100 { world.counters["hearty_meals_consumed",default:0]+=1 }
                if !admitted {_=assign(kind:"eat",job:"server",subject:world.meals[index].id,at:a.node,work:45,only:id)}
            }
            if world.time>=world.meals[index].deadline {
                world.meals[index].closed=true
                let past=Array(world.meals.filter(\.closed).suffix(4)),expected=past.reduce(0){$0+$1.expected.count},served=past.reduce(0){$0+$1.served.count}
                world.foodCoverage=expected>0 ? served*10000/expected:10000
                let quality=served>0 ? past.reduce(0){$0+$1.served.values.reduce(0,+)}/served:0
                // V1 only reads completed service evidence; no decorative walking creates a service.
                let clean=min(100,40+world.civicDutyCount("clean")*10+(world.counters["star_environment_until",default:0]>world.time ? 5:0))
                let security=min(100,60+(world.counters["patrols",default:0]>0 ? 20:0)+world.civicDutyCount("watch")*2)
                let legalGuestBeds=world.isGacha ? world.agents.values.filter{$0.home=="tavern"}.count:0
                let housing=min(100,(world.housing+legalGuestBeds)*100/max(1,world.agents.count))
                let rested=world.agents.values.filter{a in a.restedCycle>=world.cycle-1 || a.restStart.map{world.time-$0>=600} == true}.count
                let rest=world.cycle==0 ? 100:rested*100/max(1,world.agents.count)
                let target=(world.foodCoverage/100*40+quality*10+housing*15+clean*10+security*15+rest*10)/100
                let change=max(-5,min(3+world.meals[index].recoveryExtra,target-world.happiness))
                world.happiness=max(0,min(100,world.happiness+change))
                let complete=world.meals[index].served.count==world.meals[index].expected.count
                world.counters["consecutive_full_meals"]=complete ? world.counters["consecutive_full_meals",default:0]+1:0
                if world.isFormalHeroTown {
                    let singleExpected=world.meals[index].expected.count
                    let singleCoverage=singleExpected>0 ? world.meals[index].served.count*10000/singleExpected:10000
                    if singleCoverage<9000 {world.heroTown!.city.lowMealStreak+=1;world.heroTown!.city.goodMealStreak=0}
                    else if singleCoverage>=9500 {world.heroTown!.city.goodMealStreak+=1;world.heroTown!.city.lowMealStreak=0}
                    else {world.heroTown!.city.lowMealStreak=0;world.heroTown!.city.goodMealStreak=0}
                    if world.heroTown!.city.lowMealStreak>=2 {world.heroTown!.city.supplyRecovery=true}
                    if world.heroTown!.city.goodMealStreak>=2 {world.heroTown!.city.supplyRecovery=false}
                }
                world.record("meal","本餐实际供应\(world.meals[index].served.count)/\(world.meals[index].expected.count)人；\(world.coverageText())，满意度\(world.happiness)。")
            }
        }
        if world.meals.count>6 {world.meals.removeFirst(world.meals.count-6)}
    }
    mutating func planMealsAndRest() {
        for id in world.agents.keys.sorted() {
            let a=world.agents[id]!
            guard a.taskID==nil else{continue}
            // A patient with an active admission owns a clinic bed even between
            // the arrival, diagnosis and rest tasks. Do not send them home for
            // an ordinary meal or sleep while the treatment record is active.
            if world.heroTown?.health?.treatments[id] != nil {continue}
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
    mutating func startProject(id:String,kind:String,node:String,cash:Int64,work:Int64,materials:[String:Int64],targetPlotID:String?=nil,targetLevel:Int?=nil,beneficiaryDemandID:String?=nil) {
        guard world.projects[id]==nil,world.isGacha ? cash==0 : world.treasury-world.reservedCash>=cash+100 else{return}
        world.projects[id] = .init(id:id,kind:kind,node:node,materials:materials,cash:cash,totalWork:work)
        world.projects[id]!.targetPlotID=targetPlotID
        world.projects[id]!.targetLevel=targetLevel
        world.projects[id]!.beneficiaryDemandID=beneficiaryDemandID ?? (world.isFormalHeroTown ? "system.\(id)":nil)
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
            else if world.isFormalHeroTown {
                finishFormalProject(p)
                world.record("construction","\(buildingName(p.kind))项目完成，容量、道路服务与城市状态已提交。")
            }
            else {
                if world.isGacha,p.kind=="house_upgrade",let index=Int(p.id.split(separator:"-")[2]) {
                    world.gacha!.houseLevels[index]+=1
                }
                if world.isGacha,p.kind=="house" {world.gacha!.houseLevels.append(1)}
                world.buildings[p.kind,default:0]+=1
                world.record("construction","\(buildingName(p.kind))建成，下一轮规划开始使用。")
                if p.kind=="house" {world.storages["home-meals"]!.capacity=Int64(world.housing)*1_000_000}
            }
        }
        world.projects[id]=p
    }
    mutating func planProjects() {
        planGoldHousing()
        if !world.isGacha,world.growthEnabled,world.projects["repair"]?.completed==true,
           !world.projects.values.contains(where:{!$0.completed && $0.kind != "seal"}) {
            let kind = world.housing<=world.agents.count ? "house" : (world.buildings["market",default:0]==0 ? "market":(world.buildings["workshop",default:0]==0 ? "workshop":(world.buildings["tavern",default:0]==0 ? "tavern":"")))
            if !kind.isEmpty,let q=catalog.buildings.first(where:{$0.id==kind}) {
                startProject(id:kind+"-\(world.buildings[kind,default:0]+1)",kind:kind,node:kind=="house" ? "home":kind,cash:q.cash,work:q.work_s,materials:q.materials_mU)
            }
        }
        for id in world.projects.keys.sorted() {
            let p=world.projects[id]!
            guard !p.completed else{continue}
            if world.isGacha,p.phase==0,!p.stageStarted,!world.gacha!.surveyedProjects.contains(id),world.agents.keys.contains(where:{hasSignature($0,"craft")}) {
                if !world.tasks.values.contains(where:{$0.kind=="survey" && $0.subject==id}) {
                    let eligible=Set(world.agents.keys.filter{hasSignature($0,"craft")})
                    if let task=assign(kind:"survey",job:"builder",subject:id,at:p.node,work:30,eligible:eligible) {world.tasks[task]!.contribution=(p.materials["wood",default:0]*9000+9999)/10000}
                }
                continue
            }
            let stage=projectStage(p),target="project-"+id
            if !p.stageStarted {
                supply(stage.materials,to:target)
                guard world.has(stage.materials,at:target) else{continue}
            }
            let necessaryHousing=world.isFormalHeroTown && p.kind=="house" && world.agents.values.contains{$0.home=="tavern"}
            let necessaryWarWorkshop=world.campaign != nil && p.kind=="workshop" && world.buildings["workshop",default:0]==0
                && world.foodCoverage>=8000 && world.foodEquivalent()>=Int64(world.agents.count)*4_000
            let necessaryFoodCapacity=world.isFormalHeroTown &&
                ["attachment_kitchen","attachment_delivery","farm","granary","civic_water"].contains(p.kind) &&
                world.foodEquivalent()>=Int64(world.agents.count)*2_000
            if (world.foodCoverage<9000 || world.heroTown?.city.supplyRecovery==true) &&
                p.kind != "repair" && p.kind != "damage_repair" && !necessaryHousing && !necessaryWarWorkshop && !necessaryFoodCapacity {continue}
            let threshold=p.totalWork*[20,45,80,100][p.phase]/100
            let outstanding=threshold-p.completedWork-p.allocatedWork
            guard outstanding>0 else{continue}
            let assigned=world.tasks.values.filter{$0.kind=="build" && $0.subject==id}.count
            let allBuilders=world.tasks.values.filter{$0.kind=="build"}.count
            let concurrentCivic=world.isFormalHeroTown && (world.gacha?.rosterPhase ?? 0)>=3 &&
                world.projects.values.filter{!$0.completed}.count>1
            let preserveFoodLabor=world.isFormalHeroTown &&
                (world.foodCoverage<9000 || world.heroTown?.city.supplyRecovery==true)
            guard assigned<2 && allBuilders<(concurrentCivic || preserveFoodLabor ? 1:2) else{continue}
            let contribution=min(outstanding,120)
            if let task=assign(kind:"build",job:p.kind=="seal" ? "carpenter":"builder",subject:id,at:p.node,work:contribution) {
                if !p.stageStarted {
                    world.use(stage.materials,at:target);world.reservedCash-=stage.cash;world.treasury-=stage.cash;world.projects[id]!.stageStarted=true
                }
                world.tasks[task]!.contribution=contribution;world.projects[id]!.allocatedWork+=contribution
            }
        }
        if !world.isHeroPreview && world.time>0 && world.time%43200==0 && world.agents.count+2<=world.housing && world.agents.count<150 && world.foodCoverage>=9500 && world.happiness>=70 {
            for _ in 0..<2 {let id=world.next("resident");world.agents[id] = .init(id:id,name:"新邻\(world.agents.count+1)",job:"flex",node:"gate",home:"home",dining:"home-meals")}
            world.record("immigration","两名新居民抵达，床位与日常饭食需求已同步。")
        }
    }
    public func buildingName(_ kind:String)->String {
        ["pasture":"牧栏","butcher":"肉食台","hall":"府署","repair":"府署修缮","house":"民居","farm":"农庄","granary":"粮仓","market":"集市","workshop":"工造院","tavern":"饭馆","stable":"马厩","station":"驿站","barracks":"营地","clinic":"医舍","seal":"开城木印"][kind] ?? kind
    }
}
