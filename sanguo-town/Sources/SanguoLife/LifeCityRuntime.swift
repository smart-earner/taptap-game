import Foundation

extension LifeRuntime {
    mutating func planFormalCityGrowth() {
        guard world.isFormalHeroTown,var formal=world.heroTown,world.projects["repair"]?.completed==true else{return}
        while world.time>=formal.city.nextEconomyWindow {
            formal.city.economyWindows+=1
            formal.city.nextEconomyWindow+=21600
            let qualified=world.foodCoverage>=9500
            formal.city.qualifiedWindows["breakthrough.stable"] = qualified ? formal.city.qualifiedWindows["breakthrough.stable",default:0]+1 : 0
            for key in formal.city.civics.keys where qualified {formal.city.qualifiedWindows["civic.\(key)",default:0]+=1}
            formal.city.qualifiedWindows["clinic.stable"] = qualified ? formal.city.qualifiedWindows["clinic.stable",default:0]+1:0
            if var health=formal.health,health.clinicLevel>0 {
                let beds=LifeHealthContract.clinicBeds[health.clinicLevel-1]
                health.clinicDemandWindows = health.conditions.count>beds ? health.clinicDemandWindows+1:0
                formal.health=health
            }
        }
        world.heroTown=formal
        let optionalSlots=(world.gacha?.rosterPhase ?? 0)>=3 ? 2:1
        guard world.projects.values.filter({!$0.completed}).count<optionalSlots else{return}
        if planRaidDamageRepair() {return}
        if planClinicConstruction() {return}

        // An army cannot consume the last tool before the tool-making workshop
        // exists; otherwise recruitment creates a permanent construction lock.
        if world.campaign != nil,world.buildings["workshop",default:0]==0,
           world.projects["plot.workshop-1.L1"]==nil,
           let index=formal.city.plots.firstIndex(where:{$0.id=="workshop-1" && $0.level==0}) {
            startFormalPlot(index,targetLevel:1,demand:"war.tool_supply");return
        }

        // The first population breakthrough grants permission for eight more
        // real field beds, not a free harvest. Each level-two farm contributes
        // four beds only after its ordinary material/labour project completes.
        if (world.gacha?.rosterPhase ?? 0)>=1,world.gacha!.stars.count>=35 {
            for id in ["farm-1","farm-2"] {
                if world.projects["plot.\(id).L2"]==nil,
                   let index=formal.city.plots.firstIndex(where:{$0.id==id && $0.level==1}) {
                    startFormalPlot(index,targetLevel:2,demand:"population.field_beds.40");return
                }
            }
        }

        // One cook station becomes deadline-sensitive in the high thirties:
        // let the governor build the second with real materials after the
        // first breakthrough, instead of waiting for the 40-to-50 permit.
        if ((world.gacha?.rosterPhase ?? 0)>=2 ||
            ((world.gacha?.rosterPhase ?? 0)>=1 && world.gacha!.stars.count>=35)),
           formal.city.attachments["kitchen",default:0]==0,
           world.projects["attachment.kitchen.2"]==nil {
            startProject(id:"attachment.kitchen.2",kind:"attachment_kitchen",node:"kitchen",cash:0,work:1_200,
                         materials:["wood":8_000,"stone":4_000,"tools":1_000],targetLevel:1,
                         beneficiaryDemandID:"meals.population.50");return
        }

        if planFormalBreakthrough() {return}

        let owned=world.gacha?.stars.count ?? world.agents.count
        let guests=world.agents.values.filter{$0.home=="tavern"}.count
        let residentCap=30+10*(world.gacha?.rosterPhase ?? 0)
        let needsCapacity=owned>=residentCap && (formal.courtyard?.units.count ?? world.housing)<residentCap
        if guests>0 || needsCapacity || (world.housing-world.agents.count<2 && owned<=residentCap) {
            if let candidate=formalHouseCandidate() {startFormalPlot(candidate.index,targetLevel:candidate.level,demand:"housing.owned.\(owned)");return}
        }

        // Build visible production capacity before abstract civic upgrades. This
        // keeps the early desktop town changing while preserving real material and
        // labour costs for every building.
        for (plotID,demand) in [("farm-2","foundation.food_capacity"),("granary-2","foundation.storage"),("workshop-1","capacity.tools")] {
            if world.projects["plot.\(plotID).L1"]==nil,
               let index=world.heroTown!.city.plots.firstIndex(where:{$0.id==plotID && $0.level==0}) {
                startFormalPlot(index,targetLevel:1,demand:demand);return
            }
        }
        // A full shared granary prevents mined iron and felled wood from
        // reaching the forge even when their source plots still hold stock.
        // Expand real warehouse capacity before the final free space vanishes.
        if owned>=35,let warehouse=world.storages["warehouse"],
           (world.volume(at:"warehouse")+warehouse.incoming)*5>=warehouse.capacity*4,
           let index=formal.city.plots.indices.filter({formal.city.plots[$0].kind=="granary" &&
                                                       (1...2).contains(formal.city.plots[$0].level)})
            .sorted(by:{left,right in
                let a=formal.city.plots[left],b=formal.city.plots[right]
                return a.level==b.level ? a.id<b.id:a.level<b.level
            }).first {
            let plot=formal.city.plots[index],next=plot.level+1
            if world.projects["plot.\(plot.id).L\(next)"]==nil {
                startFormalPlot(index,targetLevel:next,demand:"storage.pressure");return
            }
        }
        if world.heroTown!.city.civics["water",default:0]==0,
           world.projects["civic.water.L1"]==nil {startFormalCivic("water",level:1,node:"farm");return}
        if owned>=25,world.heroTown!.city.civics["water",default:0]==1,
           world.heroTown!.city.qualifiedWindows["civic.water",default:0]>=2,
           world.projects["civic.water.L2"]==nil {
            startFormalCivic("water",level:2,node:"farm");return
        }
        for civic in ["housing","road","industry","garden","academy","defense"] {
            let level=world.heroTown!.city.civics[civic,default:0]
            guard level<3 else{continue}
            let next=level+1,requiredOwned=[5,8,12][next-1],requiredWindows=[0,2,4][next-1]
            if owned>=requiredOwned && world.heroTown!.city.qualifiedWindows["civic.\(civic)",default:0]>=requiredWindows &&
               world.projects["civic.\(civic).L\(next)"]==nil {
                let node=["housing":"home","road":"hall","industry":"workshop","garden":"home","academy":"hall","defense":"barracks"][civic] ?? "hall"
                startFormalCivic(civic,level:next,node:node);return
            }
        }

        if formal.city.supplyRecovery,let index=formal.city.plots.firstIndex(where:{$0.kind=="farm" && $0.level==0}) {
            if world.projects["plot.\(formal.city.plots[index].id).L1"]==nil {
                startFormalPlot(index,targetLevel:1,demand:"food.recovery");return
            }
        }
        if world.capitalGatheringStock(.tools)<2000,let index=formal.city.plots.firstIndex(where:{$0.kind=="workshop" && $0.level==0}) {
            if world.projects["plot.\(formal.city.plots[index].id).L1"]==nil {
                startFormalPlot(index,targetLevel:1,demand:"capacity.tools");return
            }
        }
        planFormalAttachmentsAndLandmarks(owned:owned)
    }

    @discardableResult mutating func planFormalBreakthrough()->Bool {
        guard let formal=world.heroTown,let courtyard=formal.courtyard,let gacha=world.gacha else{return false}
        let phase=gacha.rosterPhase ?? 0
        guard (0...2).contains(phase) else{return false}
        let resident=world.agents.count,owned=gacha.stars.count
        // City engineering must not require the last uncommon card in a pool.
        // Near-cap residents prove operational scale; full next-tier housing
        // still has to exist before the governor may start construction.
        let requiredResident=[28,38,48][phase],requiredOwned=[28,38,48][phase]
        let requiredHousing=[30,40,50][phase]
        let happiness=[65,68,72][phase],windows=[2,3,4][phase]
        let recent=world.meals.filter(\.closed).sorted{$0.at<$1.at}.suffix(4)
        guard recent.count==4,recent.allSatisfy({meal in
            meal.expected.isEmpty || meal.served.count*10000/meal.expected.count>=9500
        }),world.foodCoverage>=9500,world.happiness>=happiness,
              resident>=requiredResident,owned>=requiredOwned,
              formal.city.qualifiedWindows["breakthrough.stable",default:0]>=windows,
              courtyard.units.count>=requiredHousing,
              formal.city.plots.filter({$0.kind=="house"}).reduce(0,{$0+LifeLayout7.people(for:$1.level)})>=requiredHousing else{return false}
        switch phase {
        case 0: guard formal.city.civics["water",default:0]>=2 else{return false}
        case 1:
            guard formal.city.plots.filter({$0.kind=="granary"}).reduce(0,{$0+$1.capacity})>=512 else{return false}
        default:
            guard formal.city.civics["housing",default:0]>=3,formal.city.civics["road",default:0]>=2 else{return false}
        }
        let next=phase+1
        startProject(id:"breakthrough.\(next)",kind:"breakthrough_\(next)",node:"hall",cash:0,
                     work:[7200,10800,14400][phase],
                     materials:["wood":[24000,32000,48000][phase],
                                "stone":[16000,24000,32000][phase],
                                "tools":[4000,8000,12000][phase]],
                     targetLevel:next,beneficiaryDemandID:"population.\(requiredOwned)")
        return world.projects["breakthrough.\(next)"] != nil
    }

    @discardableResult mutating func planRaidDamageRepair()->Bool {
        guard let plot=world.heroTown?.city.plots.filter({$0.level>0 && $0.service==0}).sorted(by:{$0.id<$1.id}).first,
              let quote=catalog.buildings.first(where:{$0.id==plot.kind}) else{return false}
        let multiplier:Int64=[1,2,4][plot.level-1]
        let materials=quote.materials_mU.mapValues{max(1,($0*multiplier+3)/4)}
        let work=max(1,(quote.work_s*multiplier+3)/4)
        let raidIndex=world.campaign?.raidIndex ?? 0
        let id="raid-repair.\(raidIndex).\(plot.id)"
        guard world.projects[id]==nil else{return false}
        startProject(id:id,kind:"damage_repair",node:plot.node,cash:0,work:work,
                     materials:materials,targetPlotID:plot.id,targetLevel:plot.level,
                     beneficiaryDemandID:"raid.damage.\(plot.id)")
        if world.projects[id] != nil {
            world.record("construction","太守安排修复\(plot.id)：投入原建筑该级报价25%的真实材料和工时，完工前生产服务暂停。")
        }
        return world.projects[id] != nil
    }

    func formalHouseCandidate()->(index:Int,level:Int)? {
        guard let city=world.heroTown?.city else{return nil}
        var candidates:[(Int,Int,Int64,String)]=[]
        guard let quote=catalog.buildings.first(where:{$0.id=="house"}) else{return nil}
        for index in city.plots.indices where city.plots[index].kind=="house" && city.plots[index].developmentPermit {
            let level=city.plots[index].level
            guard level<3 else{continue}
            let next=level+1,multiplier:Int64=[1,2,4][next-1]
            guard world.projects["plot.\(city.plots[index].id).L\(next)"]==nil else{continue}
            candidates.append((index,next,quote.work_s*multiplier,city.plots[index].id))
        }
        return candidates.sorted{$0.2==$1.2 ? $0.3<$1.3:$0.2<$1.2}.first.map{($0.0,$0.1)}
    }

    mutating func startFormalPlot(_ index:Int,targetLevel:Int,demand:String) {
        guard let city=world.heroTown?.city,index>=0,index<city.plots.count else{return}
        let plot=city.plots[index]
        guard plot.developmentPermit,targetLevel==plot.level+1,targetLevel<=3,
              let quote=catalog.buildings.first(where:{$0.id==plot.kind}) else{return}
        let multiplier:Int64=[1,2,4][targetLevel-1]
        startProject(id:"plot.\(plot.id).L\(targetLevel)",kind:plot.kind,node:plot.node,cash:0,
                     work:quote.work_s*multiplier,materials:quote.materials_mU.mapValues{$0*multiplier},
                     targetPlotID:plot.id,targetLevel:targetLevel,beneficiaryDemandID:demand)
    }

    mutating func startFormalCivic(_ id:String,level:Int,node:String) {
        guard id != "trade",let current=world.heroTown?.city.civics[id],level==current+1,(1...3).contains(level) else{return}
        let multiplier=Int64(level)
        startProject(id:"civic.\(id).L\(level)",kind:"civic_\(id)",node:node,cash:0,
                     work:[3600,7200,14400][level-1],
                     materials:["wood":12000*multiplier,"stone":6000*multiplier,"tools":1000*multiplier],
                     targetLevel:level,beneficiaryDemandID:"civic.\(id).qualified")
    }

    mutating func planFormalAttachmentsAndLandmarks(owned:Int) {
        guard let formal=world.heroTown else{return}
        if owned>=10,formal.city.attachments["cart",default:0]<2 {
            let next=formal.city.attachments["cart",default:0]+1
            if world.projects["attachment.cart.\(next)"] == nil {
                startProject(id:"attachment.cart.\(next)",kind:"attachment_cart",node:"workshop",cash:0,work:300,
                             materials:["wood":6000,"tools":1000],targetLevel:next,beneficiaryDemandID:"logistics.population.\(owned)");return
            }
        }
        let deliveryLimit=(world.gacha?.rosterPhase ?? 0)>=2 ? 3:2
        if owned>=12,formal.city.attachments["delivery",default:1]<deliveryLimit {
            let next=formal.city.attachments["delivery",default:1]+1
            if world.projects["attachment.delivery.\(next)"] == nil {
                startProject(id:"attachment.delivery.\(next)",kind:"attachment_delivery",node:"home",cash:0,work:600,
                             materials:["wood":3000,"stone":2000],targetLevel:next,beneficiaryDemandID:"meals.population.\(owned)");return
            }
        }
        let ordered=[("welfare",8),("industry",12),("military",18)]
        for (id,minimum) in ordered where owned>=minimum {
            let level=formal.city.landmarks[id,default:0]
            guard level<3 else{continue}
            let next=level+1,requiredWindows=[0,2,4][next-1]
            guard formal.city.economyWindows>=requiredWindows else{continue}
            if id=="military",formal.city.attachments["ration",default:0]==0 {
                if world.projects["attachment.ration.1"] == nil {
                    startProject(id:"attachment.ration.1",kind:"attachment_ration",node:"ration",cash:0,work:600,
                                 materials:["wood":3000,"stone":2000],targetLevel:1,beneficiaryDemandID:"landmark.military");return
                }
                continue
            }
            guard world.projects["landmark.\(id).L\(next)"] == nil else{continue}
            let materials:[String:Int64]=[
                "wood":[16000,24000,40000][next-1],"stone":[8000,16000,24000][next-1],"tools":[1000,2000,4000][next-1]
            ]
            startProject(id:"landmark.\(id).L\(next)",kind:"landmark_\(id)",node:id=="industry" ? "workshop":(id=="military" ? "barracks":"home"),cash:0,
                         work:[7200,14400,28800][next-1],materials:materials,targetLevel:next,beneficiaryDemandID:"landmark.\(id).population.\(owned)");return
        }
    }

    mutating func finishFormalProject(_ project:LifeProject) {
        guard world.isFormalHeroTown,var formal=world.heroTown else{return}
        if let plotID=project.targetPlotID,let target=project.targetLevel,
           let index=formal.city.plots.firstIndex(where:{$0.id==plotID}) {
            let wasBuilt=formal.city.plots[index].level>0
            formal.city.plots[index].level=target
            formal.city.plots[index].service=10000
            if let capacity=catalog.buildings.first(where:{$0.id==formal.city.plots[index].kind})?.capacity,capacity.indices.contains(target-1) {
                formal.city.plots[index].capacity=capacity[target-1]
            }
            if !wasBuilt {world.buildings[formal.city.plots[index].kind,default:0]+=1}
        } else if project.kind.hasPrefix("civic_"),let level=project.targetLevel {
            formal.city.civics[String(project.kind.dropFirst(6))]=level
        } else if project.kind.hasPrefix("attachment_"),let level=project.targetLevel {
            let attachment=String(project.kind.dropFirst(11))
            formal.city.attachments[attachment]=level
            if attachment=="kitchen",level==1,world.stations["kitchen-2"]==nil {
                world.stations["kitchen-2"] = .init(id:"kitchen-2",node:"kitchen",input:"kitchen-in",output:"kitchen-out",kind:"kitchen")
            }
        } else if project.kind.hasPrefix("landmark_"),let level=project.targetLevel {
            formal.city.landmarks[String(project.kind.dropFirst(9))]=level
        } else if project.kind=="clinic",let level=project.targetLevel,(1...3).contains(level) {
            var health=formal.health ?? .initial();health.clinicLevel=level;health.clinicDemandWindows=0;formal.health=health
            world.buildings["clinic"]=level
        } else if project.kind=="breakthrough_\(project.targetLevel ?? -1)",
                  let level=project.targetLevel,(1...3).contains(level),
                  world.gacha?.rosterPhase==level-1,var courtyard=formal.courtyard {
            courtyard.unlockedColumns=[8,10,10,12][level]
            courtyard.unlockedRows=[5,5,6,7][level]
            let permitted=[8,10,13,15][level]
            for index in formal.city.plots.indices where formal.city.plots[index].kind=="house" {
                if let number=Int(formal.city.plots[index].id.dropFirst(6)) {
                    formal.city.plots[index].developmentPermit=number<=permitted
                }
            }
            formal.courtyard=courtyard
            world.gacha!.rosterPhase=level
            world.record("breakthrough","城市突破完成：常住上限\(30+level*10)，开放新院落及常驻招募池第\(level)期。")
        }
        world.heroTown=formal
        syncFormalCapacities()
    }

    mutating func syncFormalCapacities() {
        guard let city=world.heroTown?.city else{return}
        Self.synchronizeMealDepots(in:&world)
        if var formal=world.heroTown,var courtyard=formal.courtyard {
            for plot in city.plots where plot.kind=="house" && plot.level>0 {
                guard let parcel=courtyard.parcelByPlotID[plot.id] else {continue}
                for slot in 1...LifeLayout7.units(for:plot.level) {
                    let id="house:\(parcel):\(slot)"
                    if courtyard.units[id]==nil {
                        courtyard.units[id] = .init(id:id,parcelID:parcel,plotID:plot.id,occupantHouseholdID:nil)
                    }
                }
            }
            formal.courtyard=courtyard
            world.heroTown=formal
        }
        world.gacha!.houseLevels=city.plots.filter{$0.kind=="house" && $0.level>0}.sorted{$0.id<$1.id}.map(\.level)
        let fieldCount=min(24,city.plots.filter{$0.kind=="farm"}.reduce(0){$0+$1.capacity})
        for index in 0..<fieldCount {
            let id="field-\(index)"
            if world.fields[id]==nil {world.fields[id] = .init(id:id);world.storages[id] = .init(node:id,capacity:64_000_000)}
        }
        let granaryCapacity=city.plots.filter{$0.kind=="granary"}.reduce(0){$0+$1.capacity}
        if granaryCapacity>0 {world.storages["warehouse"]!.capacity=Int64(granaryCapacity)*1_000_000}
        for plot in city.plots where plot.kind=="house" && plot.level>0 {
            let dining=plot.id=="house-1" ? "home-meals":"\(plot.id).meal"
            let base=[1:8,2:12,3:16][plot.level] ?? 8
            let bonus=world.heroTown?.city.civics["housing",default:0] ?? 0
            if world.storages[dining]==nil {world.storages[dining] = .init(node:plot.node,capacity:Int64(base+bonus*2)*1_000_000)}
            else {world.storages[dining]!.capacity=max(world.volume(at:dining),Int64(base+bonus*2)*1_000_000)}
        }
    }

    /// A built delivery attachment is a physical 16-volume meal container, not
    /// merely a level counter. Reconstruct missing empty containers when an
    /// older save is opened; never mint meals or overwrite existing lots.
    static func synchronizeMealDepots(in world:inout LifeWorld) {
        guard world.isFormalHeroTown else{return}
        // Medical admissions eat at the clinic. Older saves receive an empty
        // physical pantry, never free prepared food.
        if world.storages["clinic-meals"]==nil {
            world.storages["clinic-meals"] = .init(node:"clinic",capacity:12_000_000)
        }
        guard let count=world.heroTown?.city.attachments["delivery"],count>0 else{return}
        for index in 1...min(3,count) {
            let id="delivery-\(index)"
            if world.storages[id]==nil {world.storages[id] = .init(node:id,capacity:16_000_000)}
        }
    }
}
