import Foundation

extension LifeWorld {
    /// Quantity of one resource in committed transport tasks. Warehouse
    /// `incoming` is aggregate volume and must not stand in for this ledger.
    public func inFlight(_ resource:LifeResource,to location:String) -> Int64 {
        tasks.values.filter{$0.kind=="haul" && $0.target==location && $0.resource==resource}
            .reduce(Int64(0)){$0+$1.quantity}
    }
    func freeSpace(_ location:String) -> Int64 {
        guard let s=storages[location] else {return 0}
        return max(0,s.capacity-s.incoming-volume(at:location))
    }
    mutating func add(_ resource:LifeResource,quantity:Int64,at location:String,quality:String="basic",origin:String,production:Bool=false) {
        guard quantity>0 else{return}
        // Merge only identical provenance, quality and location; reservation remains part of stock.
        if let id=lots.keys.sorted().first(where:{lots[$0]!.resource==resource && lots[$0]!.location==location && lots[$0]!.origin==origin && lots[$0]!.quality==quality}) {
            lots[id]!.amount+=quantity
        } else { let id=next("lot");lots[id] = .init(id:id,origin:origin,location:location,resource:resource,amount:quantity,quality:quality) }
        if production {produced[resource.rawValue,default:0]+=quantity}
    }
    func selection(_ resource:LifeResource,quantity:Int64,at location:String,quality:String?=nil) -> [LifeReservation]? {
        var left=quantity;var chosen:[LifeReservation]=[]
        for lot in lots.values.sorted(by:{$0.id<$1.id}) where lot.location==location && lot.resource==resource && (quality == nil || lot.quality==quality) {
            let q=min(left,lot.amount-lot.reserved)
            if q>0 {chosen.append(.init(lotID:lot.id,amount:q));left-=q}
            if left==0 {break}
        }
        return left==0 ? chosen:nil
    }
    mutating func consume(_ resource:LifeResource,quantity:Int64,at location:String) -> Bool {
        guard let parts=selection(resource,quantity:quantity,at:location) else{return false}
        for part in parts {lots[part.lotID]!.amount-=part.amount}
        consumed[resource.rawValue,default:0]+=quantity; pruneLots(); return true
    }
    func has(_ inputs:[String:Int64],at location:String) -> Bool { inputs.allSatisfy{ key,qty in amount(LifeResource(rawValue:key)!,at:location,free:true)>=qty} }
    mutating func use(_ inputs:[String:Int64],at location:String) {
        precondition(has(inputs,at:location))
        for key in inputs.keys.sorted() {precondition(consume(LifeResource(rawValue:key)!,quantity:inputs[key]!,at:location))}
    }
    mutating func beginReservedInputs(_ taskID:String) {
        guard let task=tasks[taskID], task.kind=="prepare", !task.reservations.isEmpty else{return}
        for part in task.reservations {
            guard let lot=lots[part.lotID] else{preconditionFailure("reserved input missing")}
            lots[part.lotID]!.reserved-=part.amount; lots[part.lotID]!.amount-=part.amount
            consumed[lot.resource.rawValue,default:0]+=part.amount
        }
        tasks[taskID]!.reservations=[]; pruneLots()
    }
    mutating func pruneLots() {for id in Array(lots.keys) where lots[id]!.amount==0 {lots[id]=nil}}
    public func validate() throws {
        func check(_ b:Bool,_ text:String) throws {if !b{throw LifeError.invalid(text)}}
        try validateWar()
        try check((format==1 && rules=="life-0.7.2-v1" && husbandry==nil && gacha==nil) || (format==2 && rules=="life-0.7.2-v2" && husbandry != nil && gacha==nil) || (format==3 && rules=="hero-town-0.8-preview1" && husbandry==nil && gacha==nil) || (format==4 && isGacha && gacha != nil && husbandry==nil),"存档版本不受支持，未重建存档")
        if isGacha {try validateGacha()}
        if isFormalHeroTown {
            guard let formal=heroTown else{throw LifeError.invalid("正式v0.9存档缺少规则身份")}
            try check(formal.contentHash==LifeHeroTownContract.contentHash && formal.authority==LifeHeroTownContract.authority,"正式v0.9内容哈希或自动治理授权不匹配")
            let courtyard=formal.courtyard
            try check(!formal.saveID.isEmpty && formal.city.layoutVersion==(courtyard == nil ? LifeHeroTownContract.layout : 7),"正式存档或布局版本无效")
            let plotCount=courtyard == nil ? 18:29
            try check(formal.city.plots.count==plotCount && Set(formal.city.plots.map(\.id)).count==plotCount && formal.city.plots.map(\.index).sorted()==Array(0..<plotCount),"功能地块编号或数量无效")
            try check(formal.city.plots.allSatisfy{(0...3).contains($0.level) && $0.capacity>=0 && $0.occupancy>=0 && $0.occupancy<=$0.capacity},"地块容量、占用或等级无效")
            if let courtyard {
                let phase=gacha?.rosterPhase ?? 0
                try check((0...3).contains(phase) &&
                          courtyard.unlockedColumns==[8,10,10,12][phase] &&
                          courtyard.unlockedRows==[5,5,6,7][phase] &&
                          courtyard.parcelByPlotID.count==30 &&
                          agents.count<=30+10*phase &&
                          (phase==0 || (1...phase).allSatisfy{projects["breakthrough.\($0)"]?.completed==true}) &&
                          formal.city.plots.filter{$0.kind=="house"}.allSatisfy{plot in
                              guard let number=Int(plot.id.dropFirst(6)) else{return false}
                              return plot.developmentPermit == (number<=[8,10,13,15][phase])
                          },
                          "共享院落阶段或地块映射无效")
                try check(Set(courtyard.parcelByPlotID.values).count==courtyard.parcelByPlotID.count &&
                          courtyard.parcelByPlotID.allSatisfy{plotID,parcel in
                              guard (0..<84).contains(parcel) else {return false}
                              let category=LifeLayout7.categoryRows[parcel/12][LifeLayout7.categoryRows[parcel/12].index(LifeLayout7.categoryRows[parcel/12].startIndex,offsetBy:parcel%12)]
                              let kind=plotID=="clinic-1" ? "clinic":(formal.city.plot(plotID)?.kind ?? "")
                              return category==LifeLayout7.category(for:kind)
                          },"共享院落类别或地块重复")
                try check(Set(courtyard.households.keys)==Set(agents.keys) && courtyard.households.allSatisfy{heroID,household in
                    household.id=="household:\(heroID)" && household.memberPersonIDs==["hero:\(heroID)"] &&
                    (household.unitID == nil && household.residencePlotID=="tavern-1" ||
                     household.unitID.map{unitID in
                         courtyard.units[unitID].map{$0.plotID==household.residencePlotID && $0.occupantHouseholdID==household.id} == true ||
                         unitID=="legacy:\(heroID)" && courtyard.legacyOccupiedLeases[heroID]==household.residencePlotID
                     } == true)
                },"共享院落家庭归属无效")
                try check(courtyard.units.count==formal.city.plots.filter{$0.kind=="house"}.reduce(0){$0+LifeLayout7.units(for:$1.level)} &&
                          courtyard.units.allSatisfy{id,unit in
                              id==unit.id && courtyard.parcelByPlotID[unit.plotID]==unit.parcelID &&
                              unit.occupantHouseholdID.map{householdID in courtyard.households.values.contains{$0.id==householdID && $0.unitID==id}} != false
                          },"共享院落户位容量或占用无效")
                try check(courtyard.legacyOccupiedLeases.allSatisfy{heroID,plotID in
                    courtyard.households[heroID]?.unitID=="legacy:\(heroID)" && courtyard.households[heroID]?.residencePlotID==plotID
                },"旧住户过渡租约无效")
            }
            try check(Set(formal.city.civics.keys)==Set(["road","water","housing","trade","industry","academy","garden","defense"]) && formal.city.civics.values.allSatisfy{(0...3).contains($0)},"八街区状态无效")
            try check((0...1).contains(formal.city.attachments["kitchen",default:0]) &&
                      (formal.city.attachments["kitchen",default:0]==1) == (stations["kitchen-2"] != nil) &&
                      (stations["kitchen-2"] == nil || (gacha?.rosterPhase ?? 0)>=1),
                      "第二厨房工程或工位状态无效")
            try check(formal.city.civics["trade"]==0,"v0.9首批商街必须关闭")
            try check(Set(formal.ownedHeroes.keys)==Set(gacha!.stars.keys) && formal.ownedHeroes.allSatisfy{$0.key==$0.value.heroID && $0.value.star==gacha!.stars[$0.key]},"OwnedHero权益与星级状态不一致")
            try check(formal.ownedHeroes.values.allSatisfy { owned in
                guard let duty=owned.firstDuty else{return true}
                return owned.sourceDrawID != "founding" && !duty.taskID.isEmpty &&
                    duty.assignedAt>=0 && duty.assignedAt<=time &&
                    duty.arrivedAt.map{$0>=duty.assignedAt && $0<=time} != false &&
                    duty.effectiveAt.map{$0>=(duty.arrivedAt ?? duty.assignedAt) && $0<=time && duty.effect?.isEmpty==false} != false
            },"新武将首项贡献的阶段或时间无效")
            try check(formal.skillSnapshots.count<=10000 && formal.city.memories.filter(\.pinned).count<=20 && formal.city.memories.filter{!$0.pinned}.count<=60,"快照或成长册超过安全上限")
            if let health=formal.health {
                try check((0...3).contains(health.clinicLevel) && worldClinicLevelMatches(health.clinicLevel),"医舍等级与建筑状态不一致")
                try check(Set(health.conditions.keys).isSubset(of:Set(agents.keys)) && health.conditions.allSatisfy{$0.key==$0.value.heroID && ["overwork_strain","minor_work_injury"].contains($0.value.kind)},"健康状态身份或类型无效")
                try check(Set(health.treatments.keys).isSubset(of:Set(health.conditions.keys)) && health.treatments.allSatisfy{$0.key==$0.value.patientHeroID},"治疗记录与患者状态不一致")
                let phases:Set<String>=["arriving","waiting_doctor","preparing","treating","rest_ready","resting","finish_ready","finishing"]
                let treatmentEntitiesValid=health.treatments.values.allSatisfy{ treatment in
                    phases.contains(treatment.phase) && agents[treatment.patientHeroID] != nil
                    && treatment.doctorHeroID.map{$0 != treatment.patientHeroID && agents[$0] != nil && health.conditions[$0]==nil} != false
                    && (treatment.phase=="arriving" || agents[treatment.patientHeroID]?.node=="clinic")
                }
                if !treatmentEntitiesValid {
                    let details=health.treatments.values.sorted{$0.patientHeroID<$1.patientHeroID}.map { treatment in
                        let doctor=treatment.doctorHeroID ?? "none"
                        return "\(treatment.patientHeroID):\(treatment.phase):patientNode=\(agents[treatment.patientHeroID]?.node ?? "missing"):doctor=\(doctor):doctorCondition=\(health.conditions[doctor]?.kind ?? "none")"
                    }.joined(separator:",")
                    throw LifeError.invalid("治疗阶段、医生或患者实体无效：\(details)")
                }
                let capacity=health.clinicLevel>0 ? LifeHealthContract.clinicBeds[health.clinicLevel-1]:0
                try check(health.treatments.count<=capacity && (health.clinicLevel>0 || health.treatments.isEmpty) && health.overworkStreak.values.allSatisfy{(0...2).contains($0)},"诊床或劳损计数越界")
                try check(Set(health.homeRecoveryProgress.keys).isSubset(of:Set(health.conditions.keys)) && health.homeRecoveryProgress.values.allSatisfy{$0>=0},"居家恢复进度无效")
                try check(Set(health.homeRecoveryLastAt.keys).isSubset(of:Set(health.conditions.keys)) && health.homeRecoveryLastAt.values.allSatisfy{$0>=0 && $0<=time},"居家恢复时点无效")
            }
        } else {
            try check(heroTown==nil,"预览或旧版本不得携带正式v0.9状态")
        }
        if isHeroPreview && !isGacha {
            try check(agents.count==5 && Set(agents.values.compactMap(\.heroID)).count==5 && agents.values.allSatisfy{$0.heroID==$0.id && owned.contains($0.id)},"五将试玩身份错误")
        }
        try validateHusbandry()
        try check(time>=0 && time<=315_360_000 && sequence>0 && sequence<Int64.max/2,"时间或序列越界")
        try check(agents.count<=256 && tasks.count<=2048 && lots.count<=50000,"实体数量超过安全上限")
        try check(treasury>=0 && reservedCash>=0 && reservedCash<=treasury,"国库预留不合法")
        try check(storages.count<=512 && fields.count<=24 && stations.count<=100 && projects.count<=512 && meals.count<=8,"容器或工作点超过上限")
        try check([initial,produced,consumed].allSatisfy { $0.values.allSatisfy{ $0>=0 && $0<=1_000_000_000_000_000 } },"资源总账越界")
        try check(storages.values.allSatisfy{LifeMap.places[$0.node] != nil},"仓库位置无效")
        let cropStates:Set<String>=["empty","sowing","water1","watering1","growing1","water2","watering2","growing2","ripe","harvesting"]
        for f in fields.values {try check(["rice","millet"].contains(f.crop) && cropStates.contains(f.state) && (f.due == nil || f.due!>=time),"农田阶段不受支持")}
        let stationStates:Set<String>=["idle","preparing","passive","finish","finishing"]
        for s in stations.values {
            try check(stationStates.contains(s.phase) && (s.recipe == nil || (["cook_basic","cook_meat","ration_plain","forge"]+(isGacha ? ["smelt_gold","cook_feast"]:[])).contains(s.recipe!)),"加工阶段不受支持")
            try check(storages[s.input] != nil && storages[s.output] != nil && (s.due == nil || s.due!>=time),"设备库存或时点错误")
        }
        for p in projects.values {try check(p.totalWork>0 && p.completedWork>=0 && p.completedWork<=p.totalWork && (p.completed ? p.phase==4:(0..<4).contains(p.phase)),"工程工作量或阶段错误")}
        if isFormalHeroTown {try check(projects.values.allSatisfy{$0.beneficiaryDemandID?.isEmpty==false},"正式工程必须绑定真实受益需求")}

        for (id,lot) in lots {
            try check(lot.id==id && lot.amount>0 && lot.amount<=1_000_000_000 && lot.reserved>=0 && lot.reserved<=lot.amount,"批次数量不合法")
            try check(storages[lot.location] != nil || tasks[lot.location] != nil,"批次失去仓库或承运者")
            try check(lot.quality=="basic" || lot.quality=="hearty","餐食品质不合法")
        }
        for (id,s) in storages {try check(s.capacity>=0 && s.capacity<=1_000_000_000_000 && s.incoming>=0 && volume(at:id)+s.incoming<=s.capacity,"\(id)仓储超额")}
        for r in LifeResource.allCases {try check(initial[r.rawValue,default:0]+produced[r.rawValue,default:0]-consumed[r.rawValue,default:0]==amount(r),"\(r.title)来源/消费不守恒")}
        var workers=Set<String>();var reserved:[String:Int64]=[:]
        for (id,t) in tasks {
            try check(t.id==id && t.step>=0 && t.step<t.steps.count && t.due>=time && t.started<=time,"任务时点错误")
            try check(agents[t.worker]?.taskID==id && workers.insert(t.worker).inserted,"工人重复占用或失联")
            try check(t.steps.allSatisfy{$0.seconds>0 && $0.seconds<31_536_000},"无效阶段时长")
            for p in t.reservations {reserved[p.lotID,default:0]+=p.amount}
        }
        for a in agents.values {if let id=a.taskID {try check(tasks[id]?.worker==a.id,"人物关联错误")};try check(LifeMap.places[a.node] != nil,"人物位置无效")}
        for lot in lots.values {try check(lot.reserved==reserved[lot.id,default:0],"资源预留不是唯一任务占用")}
        for meal in meals {try check(Set(meal.expected).count==meal.expected.count && Set(meal.served.keys).isSubset(of:Set(meal.expected)),"餐次消费者错误")}
        try check(Set(owned).count==owned.count && Set(discovered).count==discovered.count,"收藏身份重复")
    }

    private func worldClinicLevelMatches(_ level:Int)->Bool {
        if level==0 {return buildings["clinic",default:0]==0}
        return buildings["clinic"]==level
    }
}
