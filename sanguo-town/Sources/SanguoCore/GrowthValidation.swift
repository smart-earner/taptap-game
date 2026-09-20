import Foundation

extension WorldState {
    func validateGrowth() throws {
        guard let growth else { return }
        func require(_ b:Bool,_ s:String) throws { if !b { throw GameError.invalid(s) } }
        try require(Set(growth.cities.keys)==Set(cities.keys),"城建城市归属")
        try require(growth.reservedCash >= 0 && (realm?.reservationCash ?? 0) >= 0 && growth.reservedCash + (realm?.reservationCash ?? 0) <= treasury,"工程和军需现金预留守恒")
        try require((0...1_000_000).contains(growth.finance.capital) && (0...1_000_000).contains(growth.finance.operating),"成长财政额度")
        try require(growth.nextID>0 && growth.policyVersion>=0,"成长版本／序列")
        try require(growth.normalGrowthSeconds>=0 && growth.normalGrowthSeconds<=simulationTime,"正常成长时钟")
        try require((0...4).contains(growth.nextCheckpointIndex) && growth.pendingCheckpoints == [7,30,60,90].map { Int64($0)*86_400 },"成长册时点")
        try require(growth.nextPlanning>=simulationTime && growth.nextFiscal>simulationTime,"成长调度时间")
        var reserved:[String:[String:Int64]] = [:]
        var ids=Set<String>()
        for (id,plan) in growth.cities {
            let city=cities[id]!
            try require(plan.buildings.count<=16 && Set(plan.buildings.map(\.plot)).count==plan.buildings.count,"建筑占地唯一")
            try require(Set(plan.lockedPlots).count==plan.lockedPlots.count && plan.lockedPlots.allSatisfy{(0..<16).contains($0)},"地块锁定范围")
            try require(plan.projects.count<=100 && plan.projects.filter(\.live).count<=2,"普通项目容量")
            try require(plan.initialHousing>=1 && plan.initialHousing<=200 && city.population<=plan.housing,"住房与真实入住")
            try require(plan.nextPopulationCheck>=simulationTime,"入住调度")
            let uniqueKinds=BuildingKind.allCases.filter{!$0.repeatable}
            for kind in uniqueKinds { try require(plan.buildings.filter{$0.kind==kind}.count<=1,"唯一建筑重复") }
            for b in plan.buildings {
                try require((0..<16).contains(b.plot) && (0...3).contains(b.level) && ids.insert(b.id).inserted,"建筑标识／等级")
                try require(b.completedAt>=0 && b.completedAt<=simulationTime,"建筑完工时间")
                if b.level==0 { try require(plan.projects.contains{$0.live && $0.buildingID==b.id},"零级建筑须有有效工地") }
            }
            let activeBuildingIDs=plan.projects.filter(\.live).map(\.buildingID)
            try require(Set(activeBuildingIDs).count==activeBuildingIDs.count,"同建筑重复施工")
            for p in plan.projects {
                try require(ids.insert(p.id).inserted && p.id.count<=120,"工程ID唯一")
                try require(p.startedAt>=0 && p.startedAt<=simulationTime,"工程开工时间")
                try require((1...3).contains(p.targetLevel) && (1...100_000_000).contains(p.requiredWork) && (0...p.requiredWork).contains(p.completedWork),"工程工时")
                try require((0...2).contains(p.builders) && (p.status == .working || p.builders==0),"工程劳力状态")
                try require((0...1_000_000).contains(p.cashCost) && p.cashSpent==p.cashCost*p.completedWork/p.requiredWork,"工程现金累计消费")
                for (key,cost) in p.materialCost {
                    try require(Resource(rawValue:key) != nil && (0...1_000_000_000).contains(cost),"材料成本范围")
                    let used=p.materialSpent[key,default:0]
                    try require(used==cost*p.completedWork/p.requiredWork,"材料累计消费")
                    if p.live { reserved[id,default:[:]][key,default:0]+=cost-used }
                }
                try require(Set(p.materialSpent.keys).isSubset(of:Set(p.materialCost.keys)),"未知工程消费")
                if p.live { try require(plan.buildings.contains{$0.id==p.buildingID},"工地关联建筑") }
                if p.status == .completed { try require(p.completedWork==p.requiredWork && p.finishedAt != nil,"完工只结算一次") }
            }
            if let batch=plan.batch {
                try require(batch.startedAt<=simulationTime && batch.dueAt>simulationTime && batch.dueAt-batch.startedAt==600,"生产批次时间")
                try require(batch.workers==city.jobs,"实际工作与批次一致")
                for (key,amount) in batch.inputs {
                    try require(Resource(rawValue:key) != nil && amount>=0,"生产输入")
                    reserved[id,default:[:]][key,default:0]+=amount
                }
                for (key,amount) in batch.outputs {
                    try require(Resource(rawValue:key) != nil && amount>=0 && city.inventory.amounts[key,default:0]+amount<=city.inventory.capacity,"生产输出容量预留")
                }
            }
        }
        if let legion=growth.legion {
            try require(cities[legion.cityID] != nil && [30,60,90].contains(legion.authorizedCapacity),"军团归属／授权")
            try require((0...legion.authorizedCapacity).contains(legion.active) && legion.spent>=0 && legion.budget>=legion.spent+(legion.batch?.cash ?? 0),"军需与编制")
            try require((0...216).contains(legion.trainedHours) && (0...15).contains(legion.recruitsThisPeriod),"军团训练边界")
            try require(legion.nextTraining>simulationTime,"训练调度时间")
            if let batch=legion.batch {
                try require(batch.dueAt>simulationTime && batch.number>0 && legion.active+batch.number<=legion.authorizedCapacity,"军团在训与现役不能重复")
                reserved[legion.cityID,default:[:]]["grain",default:0]+=batch.grain
                reserved[legion.cityID,default:[:]]["tools",default:0]+=batch.tools
            }
        }
        if let realm {
            for (id,civic) in realm.civic {
                if let p=civic.project {
                    for (key,cost) in p.materials { reserved[id,default:[:]][key,default:0] += cost-p.used[key,default:0] }
                }
            }
        }
        for (id,city) in cities { for r in Resource.allCases {
            try require(city.inventory.reserved[r.rawValue,default:0]==reserved[id]?[r.rawValue,default:0] ?? 0,"\(id)预留与工程／生产／军需账本不一致")
        } }
        try require(growth.memories.count<=80 && growth.memories.filter(\.pinned).count<=20 && growth.memories.filter{!$0.pinned}.count<=60,"成长册容量")
        try require(Set(growth.memories.map(\.id)).count==growth.memories.count,"成长册ID唯一")
        for m in growth.memories {
            try require(m.snapshot.version==1 && m.snapshot.time>=0 && m.snapshot.time<=simulationTime && cities[m.snapshot.cityID] != nil,"成长册历史状态")
            try require((1...200).contains(m.snapshot.population) && m.snapshot.buildings.count<=16 && m.snapshot.projects.count<=2,"成长册内容容量")
            try require(m.snapshot.buildings.allSatisfy{(0..<16).contains($0.plot) && (0...3).contains($0.level)},"成长册建筑范围")
            try require((0...90).contains(m.snapshot.legionActive) && m.snapshot.growthAgeSeconds>=0 && m.snapshot.growthAgeSeconds<=growth.normalGrowthSeconds,"成长册成长时钟")
        }
        try require(growth.proposals.count<=3 && Set(growth.proposals.map(\.id)).count==growth.proposals.count,"提案去重")
        let times=growth.proposalTimes.sorted()
        for i in times.indices where i>0 { try require(times[i]-times[i-1]>=72*3600,"提案最短间隔") }
    }
}
