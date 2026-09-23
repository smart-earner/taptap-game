import Foundation

extension LifeRuntime {
    /// Optional last-priority academy practice. It never substitutes for a
    /// production order: a real tool fraction is consumed when the resident
    /// takes a seat, and only completed 300-second work raises job experience.
    mutating func planStudy() {
        guard world.isFormalHeroTown,
              let level=world.heroTown?.city.civics["academy"],level>0,
              (900...1380).contains(world.phase),
              world.foodCoverage>=9500,world.heroTown?.city.supplyRecovery != true,
              world.foodEquivalent()>=Int64(world.agents.count)*4_000 else{return}
        let committedTools=world.projects.values.filter{!$0.completed}
            .reduce(Int64(0)){$0+$1.materials["tools",default:0]}
        let toolReserve=max(2_000,committedTools)
        let seats=level*3
        var occupied=world.tasks.values.filter{$0.kind=="study"}.count
        guard occupied<seats else{return}
        let jobsByProfile:[String:[String]] = [
            "food":["farmer","cook"],"supply":["miner","logger"],
            "craft":["builder","smith"],"logistics":["porter","courier"],
            "trade":["clerk","smith"],"guard":["guard","porter"]
        ]
        for agent in world.agents.values.sorted(by:{$0.id<$1.id}) where occupied<seats {
            guard agent.taskID==nil,agent.id != world.prefect,
                  !["guard_day","guard_night"].contains(agent.job),
                  healthCondition(agent.id)==nil,
                  !world.warLockedHeroIDs.contains(agent.id),
                  world.counters["study-cycle.\(agent.id)",default:-1] != Int(world.cycle),
                  agent.origin=="founding" || world.heroTown?.ownedHeroes[agent.id]?.firstDuty?.effectiveAt != nil,
                  let profile=definition?.hero(agent.id)?.star_profile,
                  let jobs=jobsByProfile[profile] else{continue}
            let target=jobs.filter{catalog.weights[$0] != nil && agent.workSeconds[$0,default:0]<180_000}
                .min { left,right in
                    let l=agent.workSeconds[left,default:0],r=agent.workSeconds[right,default:0]
                    return l==r ? jobs.firstIndex(of:left)!<jobs.firstIndex(of:right)!:l<r
                }
            guard let target,world.amount(.tools,at:"warehouse",free:true)>=toolReserve+100 else{continue}
            // A fixed 300 actual seconds is one existing XP unit; work-rate
            // bonuses cannot turn a shorter animation into free experience.
            guard let task=assign(kind:"study",job:target,subject:target,at:"hall",work:0,
                                  tail:[.init(kind:"work",seconds:300)],eligible:[agent.id]) else{continue}
            world.use(["tools":100],at:"warehouse")
            world.counters["study-cycle.\(agent.id)"]=Int(world.cycle)
            world.tasks[task]!.contribution=300
            occupied+=1
        }
    }
}
