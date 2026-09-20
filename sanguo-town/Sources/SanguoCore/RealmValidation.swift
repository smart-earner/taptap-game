import Foundation
extension WorldState {
    func validateRealm() throws {
        guard let realm else { return }
        func check(_ value:Bool,_ message:String) throws { if !value { throw GameError.invalid(message) } }
        try check(realm.version==1 && realm.civic.keys.sorted()==cities.keys.sorted(),"街区规则／城市关联")
        try check(realm.nextStudy>simulationTime && realm.nextRecovery>simulationTime && realm.nextTrade>simulationTime,"城市群调度时间")
        for (id,c) in realm.civic {
            try check(c.levels.keys.allSatisfy{CivicTrack(rawValue:$0) != nil} && c.levels.values.allSatisfy{(1...3).contains($0)},"街区层级")
            try check(c.completedAt.values.allSatisfy{(0...simulationTime).contains($0)},"街区历史")
            if let p=c.project {
                try check(p.level==c.level(p.track)+1 && (1...3).contains(p.level),"同一街区不能跳级")
                try check(p.requiredWork>0 && p.requiredWork<=10_000_000 && (0..<p.requiredWork).contains(p.work),"街区工时")
                try check((0...2).contains(p.workers) && (!p.paused || p.workers==0),"街区人力")
                try check(p.startedAt<=simulationTime && (1...10_000).contains(p.cash) && p.spent==p.cash*p.work/p.requiredWork,"街区预算／进度")
                try check(Set(p.used.keys).isSubset(of:Set(p.materials.keys)),"未知材料消费")
                for (r,v) in p.materials { try check(Resource(rawValue:r) != nil && (0...1_000_000_000).contains(v) && p.used[r,default:0]==v*p.work/p.requiredWork,"街区材料账本") }
            }
            let city=cities[id]!
            for resource in Resource.allCases {
                let batch=growth!.cities[id]!.batch?.outputs[resource.rawValue,default:0] ?? 0
                try check(city.inventory[resource]+batch+RealmRuntime.incoming(city:id,resource:resource,world:self)<=city.inventory.capacity,"在途和产出容量不可双花")
            }
        }
        try check(realm.civicCashSpent>=0 && realm.regionalCashSpent>=0 && realm.routeIncome>=0,"实际累计支出／回款")
        try check(realm.collections.count<=16 && realm.equipment.count<=10,"收藏容量")
        for (id,p) in realm.collections {
            guard let definition=CollectionCatalog.item(id) else { throw GameError.invalid("未知收藏") }
            try check(p.history.count<=4 && p.history.allSatisfy{$0.count<=500},"收藏履历容量")
            try check(cities[p.cityID] != nil && (0...definition.stages.count).contains(p.stage),"收藏进度")
            let paidStages=p.stage+(p.dueAt == nil ? 0:1)
            try check(p.spent==(p.inherited == true ? 0 : definition.stages.prefix(paidStages).reduce(0){$0+$1.cash}),"收藏支出不能重复")
            if let due=p.dueAt { try check(due>simulationTime && p.stage<definition.stages.count,"收藏在途时间") }
            if let complete=p.completedAt { try check(complete<=simulationTime && p.stage==definition.stages.count && p.dueAt==nil,"收藏完成状态") }
            if definition.kind == .person && p.completedAt != nil { try check(people[id] != nil,"人物收藏必须存在实体") }
        }
        try check(realm.collections.values.filter{$0.dueAt != nil}.count<=1,"寻访只占一条路径，不复制使者")
        var slots=Set<String>()
        for (item,person) in realm.equipment {
            guard let def=CollectionCatalog.item(item) else { throw GameError.invalid("未知装备") }
            try check(def.kind != .person && realm.collections[item]?.completedAt != nil && people[person] != nil,"装备所有权")
            try check(slots.insert(person+def.kind.rawValue).inserted,"一人重复同类装备")
        }
        if let goal=realm.collectionGoal { try check(CollectionCatalog.item(goal) != nil && realm.collections[goal]?.completedAt==nil,"心愿目标") }
        try check(realm.trips.count<=3 && Set(realm.trips.map(\.id)).count==realm.trips.count && Set(realm.trips.map(\.source)).count==realm.trips.count,"运力唯一")
        for t in realm.trips {
            try check(cities[t.source] != nil && (cities[t.destination] != nil || t.destination=="external-river") && t.source != t.destination,"运单端点")
            try check(t.quantity>0 && t.quantity<=100_000 && t.arriveAt<t.returnAt && t.returnAt>simulationTime,"运单时间／容量")
            try check(t.delivered || t.arriveAt>simulationTime,"货物只到一次")
            if t.destination=="external-river" { try check(t.externalReceipt==360 && t.resource == .wine && t.quantity==20_000,"外贸条款锁定") }
            else { try check(t.externalReceipt==nil,"内部运输不能创造现金") }
        }
        try check(realm.journeys.count<=64 && Set(realm.journeys.map(\.personID)).count==realm.journeys.count,"人物在途唯一")
        for j in realm.journeys { try check(people[j.personID]?.office==nil && cities[j.destination] != nil && j.arriveAt>simulationTime,"人物交接／到任") }
        try check((0...90).contains(realm.wounded) && (growth!.legion?.active ?? 0)+realm.wounded<=(growth!.legion?.authorizedCapacity ?? 0),"伤兵不能当新兵重复招募")
        try check(Set(realm.completedGoals).count==realm.completedGoals.count && realm.completedGoals.allSatisfy{RegionalGoal(rawValue:$0) != nil},"地区目标唯一")
        if let op=realm.operation { try check(op.dueAt>simulationTime && cities[op.source] != nil && (0...90).contains(op.strength) && (0...3).contains(op.training) && (0...3).contains(op.fortificationLevel),"地区区专项时间／地点／快照")
            if op.goal == .securePass { try check(growth?.legion != nil && op.strength>=30,"军事快照须有真实军团") } }
        try check(realm.operationAttempts.keys.allSatisfy{RegionalGoal(rawValue:$0) != nil},"未知地区尝试")
        try check(realm.operationAttempts.values.allSatisfy{(1...2).contains($0)},"地区尝试次数")
    }
}
