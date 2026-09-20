import Foundation

public enum RealmRuntime {
    static func handle(_ action:RealmAction, principal:Principal, world:inout WorldState) throws {
        guard principal == .player else { throw GameError.denied("此项长期发展授权由主公决定") }
        if case .adoptIdentity(let policy,let investment) = action {
            try CityIdentityRuntime.adopt(policy:policy,investment:investment,world:&world)
            return
        }
        if case .adopt(let policy,let investment) = action {
            // The enclosing command saves a complete candidate atomically. Never resets existing balances.
            try GrowthRuntime.handle(.acceptDevelopment(policy:policy,investment:investment),principal:principal,world:&world)
            if world.realm == nil {
                var realm=RealmDevelopment(nextRecovery:(world.simulationTime/3600+1)*3600,
                    nextStudy:(world.simulationTime/3600+1)*3600,nextTrade:(world.simulationTime/7200+1)*7200)
                for id in world.cities.keys.sorted() { realm.civic[id]=CivicCity() }
                for item in CollectionCatalog.all where item.kind == .person && world.people[item.id] != nil {
                    realm.collections[item.id] = .init(stage:item.stages.count,cityID:world.people[item.id]!.cityID,
                        completedAt:world.simulationTime,history:["沿用已拥有的人物，未重复招募"],inherited:true)
                }
                world.realm=realm;world.schemaVersion=3;world.rulesVersion=RealmRules.version
                world.record("realm_adopt","已接受长期街区发展：太守按方针逐步改善八类公共设施；不自动开战、扩城或改收藏心愿。")
            }
            return
        }
        guard world.realm != nil else { throw GameError.denied("请先接受长期街区发展") }
        switch action {
        case .adopt, .adoptIdentity: break
        case .collection(let id):
            if let id {
                guard let item=CollectionCatalog.item(id),world.realm!.collections[id]?.completedAt == nil else { throw GameError.invalid("未知或已经获得的收藏") }
                let city=world.cities.keys.sorted().first!
                if world.realm!.collections[id] == nil { world.realm!.collections[id] = .init(cityID:city) }
                world.record("collection_goal","心愿改为\(item.name)。只支出已展示的路径成本，完成自动入藏；未完成其他目标保留进度。")
            }
            world.realm!.collectionGoal=id
            startCollection(world:&world)
        case .equip(let itemID,let personID):
            guard let item=CollectionCatalog.item(itemID),item.kind != .person,
                  world.realm!.collections[itemID]?.completedAt != nil else { throw GameError.denied("只能使用实际已拥有的兵器或坐骑") }
            if let personID {
                guard world.people[personID] != nil,!world.realm!.journeys.contains(where:{$0.personID==personID}),world.realm!.operation?.goal != .securePass else { throw GameError.denied("人物不存在或有在途／军事快照") }
                guard world.realm!.equipment[itemID] == nil || world.realm!.equipment[itemID] == personID else { throw GameError.denied("此唯一物品已借给他人，请先收回") }
                for (other,holder) in world.realm!.equipment where holder==personID && CollectionCatalog.item(other)?.kind==item.kind { world.realm!.equipment.removeValue(forKey:other) }
                world.realm!.equipment[itemID]=personID
            } else {
                guard world.realm!.operation?.goal != .securePass,
                      !world.realm!.journeys.contains(where:{$0.personID==world.realm!.equipment[itemID]}) else { throw GameError.denied("在途装备锁定") }
                world.realm!.equipment.removeValue(forKey:itemID)
            }
        case .pauseCivic(let cityID,let paused):
            guard world.realm!.civic[cityID]?.project != nil else { throw GameError.invalid("此城没有街区工程") }
            world.realm!.civic[cityID]!.project!.paused=paused
            world.realm!.civic[cityID]!.project!.workers=0
        case .removeMemory(let id):
            guard world.growth!.memories.contains(where:{$0.id==id && $0.pinned}) else { throw GameError.denied("只移除自己固定的快照，不删除里程碑") }
            world.growth!.memories.removeAll{$0.id==id && $0.pinned}
        case .regional(let goal): try beginRegion(goal,world:&world)
        case .movePerson(let id,let destination):
            guard var person=world.people[id],world.cities[destination] != nil,person.cityID != destination,
                  !person.locked,person.office?.kind != .governor,
                  !world.realm!.journeys.contains(where:{$0.personID==id}) else { throw GameError.denied("调任需非都督、未锁定且不在途的人物") }
            let source=person.cityID
            if person.office?.kind == .prefect {
                let proxy="npc-\(source)-relief"
                if world.people[proxy] == nil { guard world.people.count < 64 else { throw GameError.denied("人物容量不足，不能生成交接代理") }; world.people[proxy] = .init(id:proxy,name:"\(world.cities[source]!.name)代理官吏",cityID:source,isProxy:true) }
                guard (world.people[proxy]!.office == nil || world.cities[source]!.prefectID == proxy) && !world.realm!.journeys.contains(where:{$0.personID==proxy}) else { throw GameError.denied("代理官吏正在其他岗位") }
                guard id != proxy else { throw GameError.denied("代理留守，不参加跨城调任") }
                world.people[proxy]!.office = .init(kind:.prefect,scope:source,since:world.simulationTime)
                world.cities[source]!.prefectID=proxy;person.office=nil;world.people[id]=person
            }
            world.realm!.journeys.append(.init(personID:id,destination:destination,arriveAt:world.simulationTime+travel(source,destination,world)))
            world.record("person_travel",actor:id,"\(person.name)已交接并前往\(world.cities[destination]!.name)，途中不提供两城加成。")
        }
    }
    static func nextEvent(_ world:WorldState,fallback:Int64,normal:Bool = true)->Int64 {
        guard let realm=world.realm else { return fallback }
        var next=normal ? min(fallback,realm.nextRecovery,realm.nextStudy,realm.nextTrade) : fallback
        for civic in realm.civic.values {
            if let p=civic.project,p.workers>0,!p.paused {
                next=min(next,world.simulationTime+(p.requiredWork-p.work+Int64(p.workers)-1)/Int64(p.workers))
            }
        }
        for p in realm.collections.values { if let t=p.dueAt { next=min(next,t) } }
        for trip in realm.trips { next=min(next,trip.delivered ? trip.returnAt : trip.arriveAt) }
        for j in realm.journeys { next=min(next,j.arriveAt) }
        if let op=realm.operation { next=min(next,op.dueAt) }
        return next
    }
    static func incoming(city:String,resource:Resource,world:WorldState)->Int64 {
        world.realm?.trips.filter{!$0.delivered && $0.destination==city && $0.resource==resource}.reduce(0){$0+$1.quantity} ?? 0
    }
    static func progress(_ delta:Int64,world:inout WorldState) {
        guard world.realm != nil,delta>0 else { return }
        for id in world.cities.keys.sorted() {
            guard var project=world.realm!.civic[id]?.project,project.workers>0,!project.paused else { continue }
            project.work=min(project.requiredWork,project.work+delta*Int64(project.workers))
            let cost=project.cash*project.work/project.requiredWork,paid=cost-project.spent
            world.treasury-=paid;world.realm!.civicCashSpent+=paid;project.spent=cost
            for (key,total) in project.materials {
                let used=total*project.work/project.requiredWork,d=used-project.used[key,default:0]
                world.cities[id]!.inventory.amounts[key,default:0]-=d
                world.cities[id]!.inventory.reserved[key,default:0]-=d;project.used[key]=used
            }
            world.realm!.civic[id]!.project=project
        }
    }
    /// Completes only committed events. In safety rest it never starts a next stage or produces new income.
    static func finish(world:inout WorldState,normal:Bool) {
        guard world.realm != nil else { return }
        for id in world.cities.keys.sorted() {
            if let p=world.realm!.civic[id]?.project,p.work>=p.requiredWork {
                world.realm!.civic[id]!.levels[p.track.rawValue]=p.level
                world.realm!.civic[id]!.completedAt["\(p.track.rawValue)-\(p.level)"]=world.simulationTime
                world.realm!.civic[id]!.project=nil
                CityIdentityRuntime.completed(city:id,project:p,world:&world)
                if p.track == .homes { world.growth!.cities[id]!.initialHousing+=4 }
                world.record("civic_complete","\(world.cities[id]!.name)：\(p.track.title)第\(p.level)阶段完成，街区和服务实际改善。")
                GrowthRuntime.remember(id,title:"\(p.track.title)·\(p.level)",key:"civic-\(id)-\(p.track.rawValue)-\(p.level)",pinned:false,world:&world)
            }
        }
        for id in world.realm!.collections.keys.sorted() {
            guard var p=world.realm!.collections[id],let due=p.dueAt,due<=world.simulationTime,let item=CollectionCatalog.item(id) else { continue }
            p.history.append("\(world.cities[p.cityID]!.name)：\(item.stages[p.stage].title)于第\(world.growth!.normalGrowthSeconds/86_400)日完成")
            p.stage+=1;p.dueAt=nil
            if p.stage==item.stages.count {
                p.completedAt=world.simulationTime
                if item.kind == .person && world.people[id] == nil {
                    world.people[id] = .init(id:id,name:item.name,cityID:p.cityID,attributes:CollectionCatalog.attributes(id))
                    // The player has delegated use of newly hired, unlocked people in this district.
                    if let district=world.cities[p.cityID]?.districtID { world.districts[district]!.talentIDs.append(id) }
                }
                if world.realm!.collectionGoal==id { world.realm!.collectionGoal=nil }
                world.record("collection_acquired","\(item.name)已在\(world.cities[p.cityID]!.name)入藏／定居，不需领取，经历保存在宝鉴。")
            }
            world.realm!.collections[id]=p
        }
        for i in world.realm!.trips.indices {
            var t=world.realm!.trips[i]
            if !t.delivered && t.arriveAt<=world.simulationTime {
                // Capacity was reserved against new production and procurement throughout transit.
                if t.externalReceipt == nil { world.cities[t.destination]!.inventory[t.resource]+=t.quantity };t.delivered=true
                world.record("cargo_arrived","货物已送抵\(world.cities[t.destination]?.name ?? "渡口商盟")，承运队返程中。")
            }
            world.realm!.trips[i]=t
        }
        for t in world.realm!.trips where t.delivered && t.returnAt<=world.simulationTime {
            if let receipt=t.externalReceipt { world.treasury+=receipt;world.realm!.routeIncome+=receipt;world.growth!.finance.income+=receipt }
        }
        world.realm!.trips.removeAll{$0.delivered && $0.returnAt<=world.simulationTime}
        let arrivals=world.realm!.journeys.filter{$0.arriveAt<=world.simulationTime}
        for j in arrivals {
            world.people[j.personID]!.cityID=j.destination
            if let d=world.cities[j.destination]?.districtID,!world.districts[d]!.talentIDs.contains(j.personID) {world.districts[d]!.talentIDs.append(j.personID)}
            world.record("person_arrived",actor:j.personID,"\(world.people[j.personID]!.name)抵达\(world.cities[j.destination]!.name)，可由都督任用。")
        }
        world.realm!.journeys.removeAll{$0.arriveAt<=world.simulationTime}
        if let op=world.realm!.operation,op.dueAt<=world.simulationTime { finishRegion(op,world:&world) }
        if normal {
            if world.realm!.nextRecovery<=world.simulationTime {
                if world.realm!.wounded>0 {
                    let n=min(5,world.realm!.wounded);world.realm!.wounded-=n;world.growth!.legion!.active+=n
                }
                world.realm!.nextRecovery=(world.simulationTime/3600+1)*3600
            }
            if world.realm!.nextStudy<=world.simulationTime {
                if world.growth!.enabled {
                    for id in world.people.keys.sorted() where world.people[id]!.office == nil && !world.people[id]!.isProxy && !world.realm!.journeys.contains(where:{$0.personID==id}) {
                        let person=world.people[id]!,academy=world.realm!.civic[person.cityID]?.level(.academy) ?? 0
                        let field:Profession=person.attributes.prefectScore>=70 ? .governance : .military
                        world.people[id]?.credit(field,seconds:600+academy*120)
                    }
                }
                world.realm!.nextStudy=(world.simulationTime/3600+1)*3600
            }
            if world.realm!.nextTrade<=world.simulationTime {
                if world.growth!.enabled { tradeAndShip(world:&world) }
                world.realm!.nextTrade=(world.simulationTime/7200+1)*7200
            }
        }
    }
    static func manage(world:inout WorldState) {
        guard world.realm != nil,world.growth!.enabled else { return }
        startCollection(world:&world)
        if world.realm?.identity != nil { CityIdentityRuntime.manage(world:&world); return }
        for id in world.cities.keys.sorted() {
            guard world.realm!.civic[id]?.project==nil,world.growth!.cities[id]!.completedCount>=6,
                  [BuildingKind.market,.tavern,.workshop,.stable,.station].allSatisfy({world.growth!.cities[id]!.level($0)>0}) else { continue }
            let civic=world.realm!.civic[id]!,plan=world.growth!.cities[id]!,order=CivicTrack.order(for:world.policy(for:world.cities[id]!))
            let tiers=(1...3).flatMap { tier in order.filter { civic.level($0)==tier-1 }.map { ($0,tier) } }
            for (track,level) in tiers {
                if track == .commerce && plan.level(.market)==0 || track == .industry && plan.level(.workshop)==0 { continue }
                let cash:Int64=[1800,3000,4000][level-1]
                guard world.growth!.finance.capital>=cash,GrowthRuntime.freeCash(world)>=cash else { break }
                let multiplier=Int64(level)
                let materials:[String:Int64]=["wood":100_000*multiplier,"iron":60_000*multiplier,"tools":8_000*multiplier]
                world.growth!.finance.protectedOperating=cash
                GrowthRuntime.purchaseShortfall(id,materials:materials,world:&world)
                world.growth!.finance.protectedOperating=0
                guard materials.allSatisfy({world.cities[id]!.inventory.free(Resource(rawValue:$0.key)!) >= $0.value}) else { break }
                for (key,v) in materials { world.cities[id]!.inventory.reserved[key,default:0]+=v }
                let days:Int64=[2,4,6][level-1]
                world.realm!.civic[id]!.project = .init(track:track,level:level,startedAt:world.simulationTime,requiredWork:days*RealmRules.day*2,cash:cash,materials:materials)
                world.growth!.finance.capital-=cash
                world.record("civic_start","\(world.cities[id]!.name)开始\(track.title)第\(level)阶段；资源已预留，施工与生产共享劳力。")
                break
            }
        }
    }
    static func startCollection(world:inout WorldState) {
        guard world.growth!.enabled,let id=world.realm?.collectionGoal,let item=CollectionCatalog.item(id),var p=world.realm!.collections[id],
              p.completedAt==nil,p.dueAt==nil,p.stage<item.stages.count,
              !world.realm!.collections.values.contains(where:{$0.dueAt != nil}) else { return }
        if world.growth!.cities[p.cityID]!.level(item.building)==0 {
            guard let host=world.cities.keys.sorted().first(where:{world.growth!.cities[$0]!.level(item.building)>0}) else {return}
            p.cityID=host
        }
        let step=item.stages[p.stage],city=world.cities[p.cityID]!
        // Optional collecting must not consume the last cash needed to open the first market.
        // Otherwise the town has no sales channel and can never finance the next stage.
        let plan = world.growth!.cities[p.cityID]!
        let marketFunded = plan.buildings.contains { b in b.kind == .market && (b.isOperating || plan.projects.contains { $0.live && $0.buildingID == b.id }) }
        let bootstrapReserve: Int64 = marketFunded ? 0 : BuildingCatalog.quote(kind:.market,level:1,repair:false).cash
        guard GrowthRuntime.freeCash(world)>=step.cash+bootstrapReserve,step.materials.allSatisfy({city.inventory.free(Resource(rawValue:$0.key)!)-$0.value >= ($0.key=="grain" ? city.grainFloor : 0)}) else { return }
        world.treasury-=step.cash;p.spent+=step.cash
        for (key,value) in step.materials { world.cities[p.cityID]!.inventory.amounts[key,default:0]-=value }
        p.dueAt=world.simulationTime+step.seconds;world.realm!.collections[id]=p
        world.record("collection_stage","为\(item.name)进行\(step.title)，本阶段成本已支付；切换心愿仍完成本段，不重复扣款。")
    }
    static func travel(_ a:String,_ b:String,_ world:WorldState)->Int64 {
        let base:Int64=(a=="plain" || b=="plain") ? (a=="river" || b=="river" ? 900 : 1200) : 2100
        let level=world.realm?.civic[a]?.level(.streets) ?? 0
        return base*Int64(100-level*5)/100
    }
    static func tradeAndShip(world:inout WorldState) {
        guard world.realm != nil else { return }
        // One carrier per city, goods are removed once at dispatch and reserved at destination.
        for dest in world.cities.keys.sorted() where world.realm!.trips.count<3 {
            let demand=world.cities[dest]!
            guard demand.inventory.free(.grain)<demand.grainFloor+100_000,
                  incoming(city:dest,resource:.grain,world:world)==0 else { continue }
            guard let source=world.cities.keys.sorted().first(where:{id in id != dest && !world.realm!.trips.contains(where:{$0.source==id}) && world.cities[id]!.inventory.free(.grain)>world.cities[id]!.grainFloor+200_000}) else { continue }
            let pending=world.growth!.cities[dest]!.batch?.outputs["grain",default:0] ?? 0
            let amount=min(100_000,demand.inventory.capacity-demand.inventory[.grain]-pending)
            let time=travel(source,dest,world), fee=max(1,(time+599)/600)
            guard amount>0,GrowthRuntime.freeCash(world)>=fee,world.growth!.finance.operating>=fee else { continue }
            world.treasury-=fee;world.growth!.finance.operatingSpent+=fee;world.growth!.finance.operating-=fee
            world.cities[source]!.inventory[.grain]-=amount
            let id="shipment-\(world.growth!.nextID)";world.growth!.nextID+=1
            world.realm!.trips.append(.init(id:id,source:source,destination:dest,resource:.grain,quantity:amount,arriveAt:world.simulationTime+time,returnAt:world.simulationTime+time*2))
        }
        // One two-hour demand batch for the whole realm. Physical carrier returns before receiving payment.
        if world.realm!.trips.count<3 && (world.realm!.completedGoals.contains(RegionalGoal.riverTrade.rawValue) || world.realm!.completedGoals.contains(RegionalGoal.securePass.rawValue)) {
            if let id=world.cities.keys.sorted().first(where:{ id in world.cities[id]!.inventory.free(.wine)>=25_000 && !world.realm!.trips.contains(where:{$0.source==id}) }),GrowthRuntime.freeCash(world)>=10,world.growth!.finance.operating>=10 {
                let inland = id == "river" ? 0 : travel(id,"river",world)
                let fee = 10 + max(0,(inland+599)/600)
                guard GrowthRuntime.freeCash(world)>=fee, world.growth!.finance.operating>=fee else { return }
                world.cities[id]!.inventory[.wine]-=20_000;world.treasury-=fee;world.growth!.finance.operatingSpent+=fee;world.growth!.finance.operating-=fee
                let tripID="export-\(world.growth!.nextID)";world.growth!.nextID+=1
                world.realm!.trips.append(.init(id:tripID,source:id,destination:"external-river",resource:.wine,quantity:20_000,arriveAt:world.simulationTime+inland+900,returnAt:world.simulationTime+2*(inland+900),externalReceipt:360))
            }
        }
    }

    static func beginRegion(_ goal:RegionalGoal,world:inout WorldState) throws {
        guard world.realm!.operation == nil,!world.realm!.completedGoals.contains(goal.rawValue) else { throw GameError.denied("已有地区专项或此目标已完成") }
        let source=world.growth!.legion?.cityID ?? world.cities.keys.sorted().first!
        let city=world.cities[source]!,plan=world.growth!.cities[source]!
        guard plan.level(.station)>0 else { throw GameError.denied("先由太守建成驿站，再开展区域合作") }
        if goal == .settleStone || goal == .settleRiver {
            guard world.cities.count<3,world.cities[goal == .settleStone ? "stone":"river"]==nil else { throw GameError.denied("城市已存在或达到首版三城上限") }
        }
        let legion=world.growth!.legion
        if goal == .securePass {
            guard let legion,legion.active>=30,legion.batch==nil,world.realm!.wounded==0,world.realm!.operationAttempts[goal.rawValue,default:0]<2,
                  legion.active+legion.trainingLevel*10 > world.realm!.lastFailedStrength else { throw GameError.denied("需至少30现役且无待恢复伤兵；失利后需实质整备，最多两次尝试") }
        }
        guard GrowthRuntime.freeCash(world)>=goal.cash,goal.materials.allSatisfy({city.inventory.free(Resource(rawValue:$0.key)!)-$0.value >= ($0.key=="grain" ? city.grainFloor : 0)}) else { throw GameError.denied("区域专项的自由现金／材料不足，民生预留不可动用") }
        // Explicit prepaid regional service costs: escrow not duplicated into destination inventories.
        world.treasury-=goal.cash;world.realm!.regionalCashSpent+=goal.cash
        for (key,v) in goal.materials { world.cities[source]!.inventory.amounts[key,default:0]-=v }
        world.realm!.operation = .init(goal:goal,source:source,dueAt:world.simulationTime+goal.hours*3600,strength:legion?.active ?? 0,training:legion?.trainingLevel ?? 0,fortificationLevel:world.realm!.civic[source]?.level(.ramparts) ?? 0)
        world.realm!.operationAttempts[goal.rawValue,default:0]+=1
        world.record("regional_start","已批准\(goal.title)，\(goal.cash)铜及材料用于承包／军需；本次不追加费用，不扩大目标。")
    }
    static func finishRegion(_ op:RegionalOperation,world:inout WorldState) {
        world.realm!.operation=nil
        if op.goal == .securePass {
            let score=op.strength+op.training*10+op.fortificationLevel*5
            let win=score>=55
            let injured=min(op.strength,win ? 5:12)
            world.growth!.legion!.active-=injured;world.realm!.wounded+=injured
            if !win {
                world.realm!.lastFailedStrength=op.strength+op.training*10
                world.record("regional_result","护送遭阻，\(injured)名伤兵安全返营；未取得通行。需增加编制或训练后才可用新授权尝试一次，亦可和平交涉。")
                return
            }
            world.record("regional_result","护送完成，取得东部通行；\(injured)名伤兵返营恢复。没有毁城或丢收藏。")
        }
        world.realm!.completedGoals.append(op.goal.rawValue)
        if op.goal == .settleStone || op.goal == .settleRiver {
            let id=op.goal == .settleStone ? "stone":"river",name=op.goal == .settleStone ? "白石":"南渡",npc="npc-\(op.goal == .settleStone ? "stone":"river")"
            var city=City(id:id,name:name,prefectID:npc)
            city.inventory=Inventory(grain:80_000,wood:20_000,iron:20_000)
            city.inventory[.tools]=0
            if id=="stone" { city.grainRatePercent=80;city.ironRatePercent=125 }
            world.people[npc] = .init(id:npc,name:"\(name)代理太守",cityID:id,office:.init(kind:.prefect,scope:id,since:world.simulationTime),isProxy:true)
            if let districtID=world.districts.keys.sorted().first {
                city.districtID=districtID
                world.districts[districtID]!.cityIDs.append(id)
                world.districts[districtID]!.cityIDs.sort()
                world.districts[districtID]!.talentIDs.append(npc)
            }
            world.cities[id]=city
            var plan=DevelopmentPlan(initialHousing:8,initialStorage:1_000_000,nextPopulationCheck:(world.simulationTime/7200+1)*7200)
            for (kind,plot) in [(BuildingKind.hall,0),(.house,1),(.farm,4),(.granary,5)] {
                plan.buildings.append(.init(id:"\(id)-base-\(kind.rawValue)",kind:kind,plot:plot,level:1,restored:true,completedAt:world.simulationTime))
            }
            world.growth!.cities[id]=plan;world.realm!.civic[id]=CivicCity()
            GrowthRuntime.updateCapacities(id,world:&world)
            GrowthRuntime.remember(id,title:"\(name)交接",key:"origin-\(id)",pinned:false,world:&world)
            world.record("city_joined","\(name)合作建城完成，交接基础建筑和聚落原有库存；不复制国库，新城代理维持供给。")
        } else { world.record("regional_complete","\(op.goal.title)完成，地区合作结果永久保留。") }
    }
}
