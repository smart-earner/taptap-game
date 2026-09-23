import Foundation
import Darwin
import SanguoLife

/// A deliberately unfunded, reproducible play trace. The only player action
/// is spending actually minted coins on single draws; all construction and
/// resource logistics are left to the governor. This is an audit, not a pass
/// claim: a stalled city must be visible in the printed ledger.
enum NaturalGrowthAudit {
    // Bump this when simulation rules change; never resume a mixed-rule trace.
    private static let checkpointRevision=26
    static func run(seed:UInt64,days:Int,checkpointDirectory:String?=nil,linkedWarClock:Bool=false,
                    dailyDrawLimit:Int?=nil) throws {
        // At the default 2× town speed, 1,800 simulation days cover 30 real
        // days of the war clock. Allow a bounded post-horizon continuation to
        // verify that the final conquest is actually reachable.
        guard (1...3_600).contains(days) else {throw LifeError.invalid("--days must be 1...3600")}
        guard dailyDrawLimit.map({(1...100).contains($0)}) ?? true else {
            throw LifeError.invalid("--audit-daily-draws must be 1...100")
        }
        let catalog=try LifeCatalog.bundled()
        let clockMode=linkedWarClock ? "linked":"frozen"
        let drawMode=dailyDrawLimit.map{"-daily\($0)"} ?? ""
        let checkpoint=checkpointDirectory.map {
            LifeSaveStore(url:URL(fileURLWithPath:$0,isDirectory:true)
                .appendingPathComponent("natural-growth-r\(checkpointRevision)-\(clockMode)\(drawMode)-seed-\(seed).audit-save"))
        }
        let restored=try checkpoint?.load()
        var town:LifeRuntime
        if let restored {
            guard restored.isCurrentHeroTown,restored.campaign != nil,
                  restored.wallUTC==(linkedWarClock ? restored.time/2:0),
                  restored.time%2_880==0,restored.time<=Int64(days)*2_880 else {
                throw LifeError.invalid("审计检查点不属于当前战役时钟模式或已经超过目标天数")
            }
            town=try LifeRuntime(catalog:catalog,world:restored)
        } else {
            town=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true,rngSeed:seed)
            try town.enableFormalV12(realUTC:0)
        }
        var draws=Int(town.world.gacha?.drawCount ?? 0)
        var previousStudy=town.world.counters["study_completed",default:0]
        let completedDays=Int(town.world.time/2_880)
        print("NATURAL_GROWTH seed=\(seed) days=\(days) resumedDay=\(completedDays) simulation=\(days*2880)s wallUTC=\(clockMode) drawsPerRealDay=\(dailyDrawLimit.map(String.init) ?? "unlimited") initialStock=unmodified")
        if completedDays<days {for day in (completedDays+1)...days {
            let end=Int64(day)*2_880
            var noonIdle:Int?=nil
            while town.world.time<end {
                let permittedDraws=dailyDrawLimit.map{2+Int(town.world.time/172_800)*$0}
                if town.world.treasury>=100 && (permittedDraws.map{draws<$0} ?? true) {
                    let action=LifeGachaAction.draw(count:1,pool:town.world.gacha!.poolVersion(formal:true))
                    do {
                        _=try town.performGacha(.player(revision:town.world.sequence,action:action))
                        draws+=1
                    } catch {
                        print("DRAW_BLOCK day=\(day) coins=\(town.world.treasury) reason=\(error)")
                        break
                    }
                }
                let target=min(end,town.world.time+240)
                if linkedWarClock {town.advanceWarClock(realUTC:target/2)}
                let prior=town.world
                let before=prior.time
                try town.advance(to:target)
                let closeWorld=town.world
                if closeWorld.phase==1440 {
                    noonIdle=closeWorld.agents.values.filter { agent in
                        agent.taskID==nil && agent.restStart==nil &&
                        !["prefect","guard_day","guard_night"].contains(agent.job) &&
                        closeWorld.heroTown?.health?.treatments[agent.id]==nil &&
                        closeWorld.heroTown?.health?.conditions[agent.id]==nil
                    }.count
                }
                for meal in closeWorld.meals where meal.closed && meal.deadline>before && meal.deadline<=closeWorld.time &&
                        meal.served.count*100/max(1,meal.expected.count)<95 {
                    let missing=Set(meal.expected).subtracting(meal.served.keys)
                    for dining in Set(missing.compactMap{closeWorld.agents[$0]?.dining}).sorted() {
                        let waiting=closeWorld.tasks.values.filter{$0.kind=="haul" && $0.resource == .meal && $0.target==dining}
                            .sorted{$0.id<$1.id}
                            .map{"\($0.subject):\($0.quantity/1000):\($0.current.kind):due\($0.due)"}
                        let earlier=prior.tasks.values.filter{$0.kind=="haul" && $0.resource == .meal && $0.target==dining}
                            .sorted{$0.id<$1.id}
                            .map{"\($0.subject):\($0.quantity/1000):\($0.current.kind):due\($0.due)"}
                        let freeDepot=prior.storages.keys.filter{$0.hasPrefix("delivery-")}
                            .reduce(Int64(0)){$0+prior.amount(.meal,at:$1,free:true)}
                        let workingPorters=prior.tasks.values.filter{$0.job=="porter"}
                            .sorted{$0.id<$1.id}
                            .map{"\($0.worker):\($0.kind):\($0.subject)>\($0.target):due\($0.due)"}
                        let missedAgents=missing.filter{closeWorld.agents[$0]?.dining==dining}.sorted().map { heroID in
                            let agent=prior.agents[heroID]
                            let task=agent?.taskID.flatMap{prior.tasks[$0]}
                            return "\(heroID):node=\(agent?.node ?? "missing"):task=\(task?.kind ?? "idle"):job=\(task?.job ?? "none"):due=\(task?.due ?? 0)"
                        }
                        print("MEAL_CLOSE_GAP day=\(day) at=\(meal.at) dining=\(dining) missed=\(missing.filter{closeWorld.agents[$0]?.dining==dining}.count) hero=[\(missedAgents.joined(separator:","))] homeStock=\(closeWorld.amount(.meal,at:dining)/1000) incoming=[\(waiting.joined(separator:","))] kitchenStock=\(closeWorld.amount(.meal,at:"kitchen-out")/1000) depotStock=\(closeWorld.storages.keys.filter{$0.hasPrefix("delivery-")}.reduce(Int64(0)){$0+closeWorld.amount(.meal,at:$1)}/1000) prior=\(before):home\(prior.amount(.meal,at:dining)/1000):depotFree\(freeDepot/1000):incoming[\(earlier.joined(separator:","))]:porters[\(workingPorters.joined(separator:","))]")
                    }
                }
            }
            let w=town.world
            let war=w.campaign
            let open=w.gacha?.rosterPhase ?? -1
            let today=w.meals.filter{$0.closed && $0.at>=end-2_880 && $0.at<end}
            let coverage=today.map{$0.served.count*100/max(1,$0.expected.count)}.min() ?? 100
            if today.count != 2 {print("MEAL_WINDOW_GAP day=\(day) closed=\(today.count) expected=2")}
            let projects=w.projects.values.filter{!$0.completed}.sorted{$0.id<$1.id}.map{ $0.id+":\($0.completedWork)/\($0.totalWork)" }.joined(separator:",")
            let recruitPool=war?.cities.values.filter{$0.owner=="player"}.reduce(0){$0+$1.recruitPool} ?? 0
            let soldiersHome=war?.squads.values.filter{$0.cityID=="00" && $0.missionID==nil}.reduce(0){$0+$1.survivors} ?? 0
            let studyToday=w.counters["study_completed",default:0]-previousStudy
            previousStudy=w.counters["study_completed",default:0]
            print("DAY \(day) time=\(w.time) people=\(w.agents.count) cap=\(30+10*open) phase=\(open) draws=\(draws) coins=\(w.treasury) ore=\(w.amount(.gold_ore)/1000) ingots=\(w.amount(.gold_ingot)/1000) wood=\(w.amount(.wood)/1000) tools=\(w.amount(.tools,at:"warehouse",free:true)/1000) iron=\(w.amount(.iron,at:"warehouse",free:true)/1000) rations=\(w.amount(.rations,at:"warehouse",free:true)/1000) food=\(w.foodEquivalent()/1000) meal=\(coverage)% happiness=\(w.happiness) housing=\(w.housing) idleNoon=\(noonIdle ?? -1) study=\(studyToday) recovery=\(w.heroTown?.city.supplyRecovery ?? false) warCities=\(war?.capturedEnemyCities ?? 0) won=\(war?.won ?? false) soldiers=\(war?.soldierCount ?? 0) homeSoldiers=\(soldiersHome) recruits=\(recruitPool) reserved=\(war?.reservedHeroIDs.count ?? 0) raids=\(war?.raidIndex ?? 0) warWait=[\(war?.waitReason ?? "no-war")] projects=[\(projects)]")
            for meal in today where meal.served.count*100/max(1,meal.expected.count)<95 {
                let missing=Set(meal.expected).subtracting(meal.served.keys)
                let missingDining=missing.compactMap{w.agents[$0]?.dining}.sorted()
                let hauls=w.tasks.values.filter{$0.kind=="haul" && $0.resource == .meal}.count
                print("MEAL_GAP day=\(day) at=\(meal.at) coverage=\(meal.served.count*100/max(1,meal.expected.count))% mealAtDayEnd=\(w.amount(.meal)/1000) kitchen=\(w.stations["kitchen"]?.phase ?? "missing") kitchen2=\(w.stations["kitchen-2"]?.phase ?? "missing") hauls=\(hauls) missingDining=\(missingDining)")
            }
            if day%5==0 || day==days {try checkpoint?.save(w)}
            fflush(stdout)
        }}
        let phase=town.world.gacha?.rosterPhase ?? 0
        let missing=town.definition!.availableHeroes(phase:phase).filter{town.world.gacha?.stars[$0.id]==nil}
        print("MISSING phase=\(phase) count=\(missing.count) rarities=\(Dictionary(grouping:missing,by:\.rarity).mapValues(\.count))")
    }
}
