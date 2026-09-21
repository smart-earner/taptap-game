import Foundation

extension LifeRuntime {
    mutating func planFormalCityGrowth() {
        guard world.isFormalHeroTown,var formal=world.heroTown,world.projects["repair"]?.completed==true else{return}
        while world.time>=formal.city.nextEconomyWindow {
            formal.city.economyWindows+=1
            formal.city.nextEconomyWindow+=21600
            let qualified=world.foodCoverage>=9500
            for key in formal.city.civics.keys where qualified {formal.city.qualifiedWindows["civic.\(key)",default:0]+=1}
        }
        world.heroTown=formal
        guard !world.projects.values.contains(where:{!$0.completed}) else{return}

        let owned=world.gacha?.stars.count ?? world.agents.count
        let guests=world.agents.values.filter{$0.home=="tavern"}.count
        if guests>0 || (world.housing-world.agents.count<2 && owned<30) {
            if let candidate=formalHouseCandidate() {startFormalPlot(candidate.index,targetLevel:candidate.level,demand:"housing.owned.\(owned)");return}
        }

        // Level-one water, a real workshop, housing services and roads are the first
        // non-emergency city investments in the PRD's fixed priority order.
        if world.heroTown!.city.civics["water",default:0]==0 {startFormalCivic("water",level:1,node:"farm");return}
        if let index=world.heroTown!.city.plots.firstIndex(where:{$0.id=="workshop-1" && $0.level==0}) {
            startFormalPlot(index,targetLevel:1,demand:"capacity.tools");return
        }
        for civic in ["housing","road","industry","garden","academy","defense"] {
            let level=world.heroTown!.city.civics[civic,default:0]
            guard level<3 else{continue}
            let next=level+1,requiredOwned=[5,8,12][next-1],requiredWindows=[0,2,4][next-1]
            if owned>=requiredOwned && world.heroTown!.city.qualifiedWindows["civic.\(civic)",default:0]>=requiredWindows {
                let node=["housing":"home","road":"hall","industry":"workshop","garden":"home","academy":"hall","defense":"barracks"][civic] ?? "hall"
                startFormalCivic(civic,level:next,node:node);return
            }
        }

        if formal.city.supplyRecovery,let index=formal.city.plots.firstIndex(where:{$0.kind=="farm" && $0.level==0}) {
            startFormalPlot(index,targetLevel:1,demand:"food.recovery");return
        }
        if world.amount(.tools)<2000,let index=formal.city.plots.firstIndex(where:{$0.kind=="workshop" && $0.level==0}) {
            startFormalPlot(index,targetLevel:1,demand:"capacity.tools");return
        }
        planFormalAttachmentsAndLandmarks(owned:owned)
    }

    func formalHouseCandidate()->(index:Int,level:Int)? {
        guard let city=world.heroTown?.city else{return nil}
        var candidates:[(Int,Int,Int64,String)]=[]
        guard let quote=catalog.buildings.first(where:{$0.id=="house"}) else{return nil}
        for index in city.plots.indices where city.plots[index].kind=="house" {
            let level=city.plots[index].level
            guard level<3 else{continue}
            let next=level+1,multiplier:Int64=[1,2,4][next-1]
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
            startProject(id:"attachment.cart.\(next)",kind:"attachment_cart",node:"workshop",cash:0,work:300,
                         materials:["wood":6000,"tools":1000],targetLevel:next,beneficiaryDemandID:"logistics.population.\(owned)");return
        }
        if owned>=12,formal.city.attachments["delivery",default:1]<3 {
            let next=formal.city.attachments["delivery",default:1]+1
            startProject(id:"attachment.delivery.\(next)",kind:"attachment_delivery",node:"home",cash:0,work:600,
                         materials:["wood":3000,"stone":2000],targetLevel:next,beneficiaryDemandID:"meals.population.\(owned)");return
        }
        let ordered=[("welfare",8),("industry",12),("military",18)]
        for (id,minimum) in ordered where owned>=minimum {
            let level=formal.city.landmarks[id,default:0]
            guard level<3 else{continue}
            let next=level+1,requiredWindows=[0,2,4][next-1]
            guard formal.city.economyWindows>=requiredWindows else{continue}
            if id=="military",formal.city.attachments["ration",default:0]==0 {
                startProject(id:"attachment.ration.1",kind:"attachment_ration",node:"ration",cash:0,work:600,
                             materials:["wood":3000,"stone":2000],targetLevel:1,beneficiaryDemandID:"landmark.military");return
            }
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
            formal.city.attachments[String(project.kind.dropFirst(11))]=level
        } else if project.kind.hasPrefix("landmark_"),let level=project.targetLevel {
            formal.city.landmarks[String(project.kind.dropFirst(9))]=level
        }
        world.heroTown=formal
        syncFormalCapacities()
    }

    mutating func syncFormalCapacities() {
        guard let city=world.heroTown?.city else{return}
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
}
