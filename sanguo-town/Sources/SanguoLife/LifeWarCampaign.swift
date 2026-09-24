import Foundation

/// The war preview lives in the same save and resource ledger as the town. It is
/// intentionally opt-in at the runtime boundary so older v0.9 saves remain valid.
public enum LifeWarContract {
    public static let pointKinds = ["outer", "supply", "gate", "core"]
    public static func pointTitle(_ kind:String) -> String {
        ["outer":"外哨","supply":"粮寨","gate":"关门","core":"主城"][kind] ?? kind
    }
    public static let cityData: [(id:String,name:String,power:Int,wall:Int,tags:[String],unlock:String)] = [
        ("00","平川",0,0,["capital"],"capital"),
        ("01","青石城",120,20,["frontline","stone_wall"],"stone_transport"),
        ("02","丰谷城",135,10,["ranged"],"frontier_granary"),
        ("03","铁岭城",170,30,["heavy","mountain"],"rare_ore_mine"),
        ("04","北关城",165,55,["fortification","mountain"],"pass_watchtower"),
        ("05","江口城",155,25,["naval","port"],"shipyard"),
        ("06","炎陵城",180,15,["fire_guard","forest"],"fire_doctrine"),
        ("07","江北城",210,25,["naval","port"],"river_supply"),
        ("08","赤镇城",220,30,["ranged","flammable"],"refined_iron_forge"),
        ("09","北原城",245,35,["cavalry","plain"],"long_range_scouting"),
        ("10","东都城",260,50,["fortification","port"],"frontier_transfer"),
        ("11","王都城",320,60,["heavy","fortification"],"unification")
    ]
    public static let landEdges: [[String]] = [
        ["00","01"],["00","02"],["01","03"],["01","04"],["02","05"],["02","06"],
        ["03","08"],["04","09"],["06","08"],["07","10"],["08","09"],["08","10"],
        ["09","11"],["10","11"]
    ]
    public static let waterEdges: [[String]] = [["05","07"]]
    public static let facilityBuilds: [(kind:String,cityID:String,materials:[String:Int64],work:Int64,title:String)] = [
        ("frontier_granary","02",["wood":6_000,"stone":2_000],900,"丰谷前线粮仓"),
        ("pass_watchtower","04",["wood":6_000,"stone":4_000],900,"北关哨所"),
        ("river_supply","07",["wood":4_000,"tools":1_000],600,"江北水路补给"),
        ("long_range_scouting","09",["wood":4_000,"tools":1_000],600,"北原侦察站"),
        ("frontier_transfer","10",["wood":8_000,"stone":4_000],1_200,"东都转运站"),
        ("refined_iron_forge","08",["wood":8_000,"stone":4_000,"tools":2_000],1_800,"赤镇精铁炉")
    ]
    public static func warehouse(_ cityID:String) -> String { "war-\(cityID)" }
    public static func facilityActive(_ kind:String,in war:LifeWarState) -> Bool {
        guard let cityID=cityData.first(where:{$0.unlock==kind})?.id,let city=war.cities[cityID] else{return false}
        return city.owner=="player" && city.supplied && war.builtFacilities?.contains(kind)==true
    }
    public static func scoutingSeconds(in war:LifeWarState) -> Int64 {
        facilityActive("long_range_scouting",in:war) ? 300:600
    }
    public static func recoveryWaitReason(until:Int64,now:Int64) -> String {
        let hours=max(1,(max(0,until-now)+3_599)/3_600)
        return "连续失利后的保供修复中，约\(hours)小时后恢复远征；补给与备兵照常"
    }
    public static func frontRationCapacity(_ cityID:String,in war:LifeWarState) -> Int64 {
        cityID=="02" && facilityActive("frontier_granary",in:war) ? 32_000:8_000
    }
    public static func transportSeconds(from cityID:String,edges:Int,resource:LifeResource,in war:LifeWarState) -> Int64 {
        let basic=Int64(edges)*600
        return cityID=="10" && resource == .rations && facilityActive("frontier_transfer",in:war) ?
            (basic*80+99)/100:basic
    }
    public static func equipment(_ kind:String) -> [LifeResource:Int64] {
        switch kind {
        case "archer": return [.wood:2_000,.tools:1_000]
        case "sapper": return [.wood:2_000,.stone:2_000,.iron:1_000,.tools:1_000]
        default: return [.wood:1_000,.iron:1_000,.tools:1_000]
        }
    }
    /// Keep ten actual capital defenders, then form the strongest legal sortie.
    /// Old, depleted squads have small IDs after months of fighting, so ID order
    /// must never determine the twenty expedition slots.
    public static func sortieSquadIDs(_ squads:[LifeWarSquad],capacity:Int,needsSapper:Bool) -> [String] {
        let home=squads.filter{$0.cityID=="00" && $0.missionID==nil && $0.transferID==nil}
        var defenders=Set<String>(),held=0
        for squad in home.sorted(by:{a,b in
            a.survivors==b.survivors ? a.id<b.id:a.survivors<b.survivors
        }) where held<10 {
            defenders.insert(squad.id)
            held+=squad.survivors
        }
        var ready=home.filter{!defenders.contains($0.id)}
        if needsSapper {
            ready.sort {a,b in
                let asapper=a.kind=="sapper" && a.survivors==10
                let bsapper=b.kind=="sapper" && b.survivors==10
                if asapper != bsapper {return asapper}
                return a.power==b.power ? (a.survivors==b.survivors ? a.id<b.id:a.survivors>b.survivors):a.power>b.power
            }
        } else {
            ready.sort {a,b in
                a.power==b.power ? (a.survivors==b.survivors ? a.id<b.id:a.survivors>b.survivors):a.power>b.power
            }
        }
        var selected:[String]=[],deployed=0
        for squad in ready where selected.count<20 {
            if deployed+squad.survivors>capacity {continue}
            selected.append(squad.id)
            deployed+=squad.survivors
        }
        return selected
    }
    /// Both expedition and raid losses use largest-remainder apportionment.
    /// Equal fractional shares break by squad ID, independent of dictionary order.
    static func casualtyShares(_ squads:[LifeWarSquad],losses:Int) -> [String:Int] {
        let total=squads.reduce(0){$0+$1.survivors}
        guard total>0 else{return [:]}
        let budget=min(max(0,losses),total)
        guard budget>0 else{return [:]}
        var shares:[String:Int]=[:],assigned=0
        for squad in squads {
            let base=budget*squad.survivors/total
            shares[squad.id]=base;assigned+=base
        }
        let byRemainder=squads.sorted { left,right in
            let lhs=(budget*left.survivors)%total,rhs=(budget*right.survivors)%total
            return lhs==rhs ? left.id<right.id:lhs>rhs
        }
        for squad in byRemainder.prefix(budget-assigned) {shares[squad.id,default:0]+=1}
        return shares
    }
    public static func loot(_ point:String) -> [LifeResource:Int64] {
        switch point {
        case "outer": return [.wood:2_000,.stone:2_000]
        case "supply": return [.rations:4_000,.tools:1_000]
        case "gate": return [.iron:2_000]
        default: return [:]
        }
    }
    public static func lootBatchLimit(resource:LifeResource,city:LifeWarCity,war:LifeWarState) -> Int64 {
        if city.id=="01" && resource == .stone && facilityActive("stone_transport",in:war) {return 6_000}
        if city.id=="07" && resource == .rations && facilityActive("river_supply",in:war) {return 8_000}
        return 4_000
    }
}

public struct LifeWarCity: Codable, Equatable, Sendable, Identifiable {
    public var id:String
    public var name:String
    public var enemyPower:Int
    public var wall:Int
    public var tags:[String]
    public var unlock:String
    public var owner:String
    public var points:[String:String] = [:] // enemy/player
    public var firstCleared:Set<String> = []
    public var scouted = false
    public var supplied = false
    public var recruitPool = 0
    public var recruitLastUTC:Int64 = 0
    public init(id:String,name:String,enemyPower:Int,wall:Int,tags:[String],unlock:String,owner:String,startedUTC:Int64) {
        self.id=id;self.name=name;self.enemyPower=enemyPower;self.wall=wall;self.tags=tags;self.unlock=unlock;self.owner=owner
        self.recruitPool=id=="00" ? 40:0;self.recruitLastUTC=startedUTC
        if id != "00" {for kind in LifeWarContract.pointKinds {points[kind]="enemy"}}
    }
    public var nextPoint:String? {LifeWarContract.pointKinds.first {points[$0] != "player"}}
    public var capturedPoints:Int {LifeWarContract.pointKinds.filter{points[$0]=="player"}.count}
}

public struct LifeWarSquad: Codable, Equatable, Sendable, Identifiable {
    public var id:String
    public var kind:String
    public var survivors:Int
    public var cityID:String
    public var missionID:String? = nil
    public var transferID:String? = nil
    public var gearOrigin:String
    public var power:Int {survivors * (kind=="sapper" ? 1:2)}
    public init(id:String,kind:String,survivors:Int,cityID:String,missionID:String?=nil,
                transferID:String?=nil,gearOrigin:String) {
        self.id=id;self.kind=kind;self.survivors=survivors;self.cityID=cityID
        self.missionID=missionID;self.transferID=transferID;self.gearOrigin=gearOrigin
    }
}

public struct LifeWarTraining: Codable, Equatable, Sendable {
    public var kind:String
    public var workerID:String
    public var regionID:String
    public var startedSim:Int64
    public var dueSim:Int64
}

public struct LifeWarTransfer: Codable, Equatable, Sendable, Identifiable {
    public var id:String
    public var workerID:String
    public var squadID:String
    public var sourceCityID:String
    public var targetCityID:String
    public var startedSim:Int64
    public var dueSim:Int64
    /// A replacement officer can travel to an already manned city without
    /// withdrawing another ten soldiers from the capital. Nil in old saves.
    public var officerOnly:Bool? = nil
}

public struct LifeWarMission: Codable, Equatable, Sendable, Identifiable {
    public var id:String
    public var cityID:String
    public var sourceCityID:String
    public var pointIndex:Int
    public var heroIDs:[String]
    public var squadIDs:[String]
    public var stage:String
    public var dueSim:Int64
    public var siegeEquipment:Bool
}

public struct LifeWarReport: Codable, Equatable, Sendable, Identifiable {
    public var id:String
    public var simulationTime:Int64
    public var acceptedUTC:Int64
    public var kind:String
    public var cityID:String
    public var point:String?
    public var attack:Int
    public var defense:Int
    public var casualties:Int
    public var loot:[String:Int64]
    public var text:String
}

public struct LifeRaidWarning: Codable, Equatable, Sendable, Identifiable {
    public var id:String
    public var attackerCityID:String
    public var targetCityID:String
    public var warningUTC:Int64
    public var arrivalUTC:Int64
    public var counterattack:Bool
}

public struct LifeWarState: Codable, Equatable, Sendable {
    public var startedUTC:Int64
    public var acceptedUTC:Int64
    public var lastUpkeepUTC:Int64
    public var lastCaptureUTC:Int64? = nil
    public var nextRaidUTC:Int64
    /// Optional for format-4 campaign saves written before visible warnings.
    public var raidWarning:LifeRaidWarning? = nil
    public var raidIndex = 0
    public var raidLossStreak = 0
    public var recoveryUntilUTC:Int64 = 0
    public var paused = false
    public var won = false
    public var cities:[String:LifeWarCity]
    public var squads:[String:LifeWarSquad] = [:]
    public var reservedHeroIDs:[String] = [] // Capital-based military staff; still eat and appear in town.
    public var training:LifeWarTraining? = nil
    public var mission:LifeWarMission? = nil
    /// Optional for saves created before physical garrison transfers.
    public var transfer:LifeWarTransfer? = nil
    /// A transferred, real officer remains at one supplied border city until
    /// recalled; older saves have no stationed officers.
    public var garrisonHeroByCity:[String:String]? = nil
    /// Escort and evacuated officers stay away for a timed return journey.
    public var returningGarrisonHeroes:[String:Int64]? = nil
    public var firstClearReceipts:Set<String> = []
    public var unlocked:Set<String> = []
    public var siegeEquipment = false
    /// Missing in older saves means the advanced upgrade has not been built.
    public var refinedSiegeEquipment:Bool? = nil
    public var shipBuilt = false
    public var fireDrilled = false
    /// Optional so campaign saves made before facilities were implemented still decode.
    public var builtFacilities:Set<String>? = nil
    /// Separate from the 200-entry town event ring; old saves decode as nil.
    public var reports:[LifeWarReport]? = nil
    public var waitReason = "等待太守准备兵源与装备"
    public init(startedUTC:Int64) {
        self.startedUTC=startedUTC;acceptedUTC=startedUTC;lastUpkeepUTC=startedUTC;nextRaidUTC=startedUTC+2_700
        cities=Dictionary(uniqueKeysWithValues:LifeWarContract.cityData.map { row in
            (row.id,LifeWarCity(id:row.id,name:row.name,enemyPower:row.power,wall:row.wall,tags:row.tags,
                                 unlock:row.unlock,owner:row.id=="00" ? "player":"enemy",startedUTC:startedUTC))
        })
        cities["00"]!.supplied=true
    }
    public var capturedEnemyCities:Int {cities.values.filter{$0.id != "00" && $0.owner=="player"}.count}
    public var soldierCount:Int {squads.values.reduce(0){$0+$1.survivors}}
    public var awayHeroIDs:Set<String> {
        Set(mission?.heroIDs ?? [])
            .union(training?.regionID == "00" ? [] : (training.map{[$0.workerID]} ?? []))
            .union(transfer.map{[$0.workerID]} ?? [])
            .union((garrisonHeroByCity ?? [:]).values)
            .union((returningGarrisonHeroes ?? [:]).keys)
    }
    public var lockedHeroIDs:Set<String> {Set(reservedHeroIDs).union(awayHeroIDs).union(training.map{[$0.workerID]} ?? [])}
}

extension LifeWorld {
    public var warAwayHeroIDs:Set<String> {
        (campaign?.awayHeroIDs ?? []).union(tasks.values.filter {
            $0.kind=="haul" && ($0.subject.hasPrefix("war-") || $0.target.hasPrefix("war-")) && $0.current.kind=="carry"
        }.map(\.worker))
    }
    var warLockedHeroIDs:Set<String> {campaign?.lockedHeroIDs ?? []}
    func validateWar() throws {
        guard let war=campaign else{return}
        func check(_ ok:Bool,_ message:String) throws {if !ok{throw LifeError.invalid(message)}}
        try check(war.cities.count==12 && war.cities["00"]?.owner=="player" && war.startedUTC<=war.acceptedUTC,"战争城市或时间无效")
        try check(!war.won || (war.capturedEnemyCities==11 &&
                  war.cities.values.allSatisfy { city in
                      city.owner=="player" && city.supplied &&
                      (city.id=="00" || LifeWarContract.pointKinds.allSatisfy{city.points[$0]=="player"})
                  }),"统一天下必须守住全部城市、据点和补给线")
        try check(war.cities.values.allSatisfy{$0.recruitPool>=0 && $0.recruitPool<=($0.id=="00" ? 40:20)},"地区兵源越界")
        try check(war.squads.values.allSatisfy{(1...10).contains($0.survivors) && ["infantry","archer","sapper"].contains($0.kind)},"士兵编队无效")
        try check(war.squads.values.allSatisfy{ squad in
            war.cities[squad.cityID] != nil &&
            squad.missionID.map{war.mission?.id==$0} != false &&
            squad.transferID.map{war.transfer?.id==$0} != false &&
            !(squad.missionID != nil && squad.transferID != nil)
        },"士兵位置或任务重复")
        try check(war.cities.values.filter{$0.id != "00"}.allSatisfy{Set($0.points.keys)==Set(LifeWarContract.pointKinds) && $0.points.values.allSatisfy{["enemy","player"].contains($0)}},"边防点状态无效")
        try check(war.firstClearReceipts.count<=44 && war.firstClearReceipts.allSatisfy{receipt in
            let pieces=receipt.split(separator:":");return pieces.count==2 && war.cities[String(pieces[0])]?.firstCleared.contains(String(pieces[1])) == true
        },"首胜回执无效")
        let buildable=Set(["stone_transport"]+LifeWarContract.facilityBuilds.map(\.kind))
        try check((war.builtFacilities ?? []).isSubset(of:buildable) &&
                  (war.builtFacilities ?? []).allSatisfy{war.unlocked.contains($0)},
                  "前线工程或许可状态无效")
        try check((war.reports ?? []).count<=256 &&
                  (war.reports ?? []).allSatisfy{report in
                      !report.id.isEmpty && war.cities[report.cityID] != nil &&
                      report.simulationTime<=time && report.acceptedUTC<=war.acceptedUTC &&
                      report.attack>=0 && report.defense>=0 && report.casualties>=0
                  },"战争战报内容或容量无效")
        if let warning=war.raidWarning {
            try check(warning.id=="raid:\(war.raidIndex+1)" &&
                      war.cities[warning.attackerCityID] != nil && war.cities[warning.targetCityID] != nil &&
                      warning.warningUTC>=war.startedUTC && warning.warningUTC<warning.arrivalUTC &&
                      warning.arrivalUTC==war.nextRaidUTC,
                      "袭扰预警目标或时点无效")
        }
        try check(war.lockedHeroIDs.allSatisfy{ heroID in
            guard let agent=agents[heroID] else{return false}
            if war.awayHeroIDs.contains(heroID) {return agent.taskID==nil}
            guard let taskID=agent.taskID else{return true}
            return ["meal_trip","eat","home"].contains(tasks[taskID]?.kind ?? "")
        },"出征/训练武将重复劳动")
        if let mission=war.mission {
            try check(war.cities[mission.cityID] != nil && (0..<4).contains(mission.pointIndex) && !mission.heroIDs.isEmpty && mission.heroIDs.count<=4 && mission.squadIDs.count<=20,"远征目标或编组无效")
            try check(Set(mission.heroIDs).count==mission.heroIDs.count && Set(mission.squadIDs).count==mission.squadIDs.count && mission.squadIDs.allSatisfy{war.squads[$0]?.missionID==mission.id},"远征身份重复")
            try check(mission.dueSim>=time && ["scouting","preparing","marching","battling","returning"].contains(mission.stage),"远征阶段无效")
        }
        if let training=war.training {
            try check(training.dueSim>=time && agents[training.workerID] != nil &&
                      (["infantry","archer","sapper","siege","refined_siege","ship","fire","stone_transport","quarry_stone","mine_rare_ore","refine_iron"] + LifeWarContract.facilityBuilds.map(\.kind)).contains(training.kind),
                      "募兵或前线劳动无效")
        }
        if let transfer=war.transfer {
            try check(transfer.startedSim<=time && transfer.dueSim>=time &&
                      war.cities[transfer.sourceCityID] != nil && war.cities[transfer.targetCityID] != nil &&
                      agents[transfer.workerID]?.taskID==nil &&
                      (transfer.officerOnly==true ? transfer.squadID.isEmpty :
                       war.squads[transfer.squadID]?.transferID==transfer.id &&
                       war.squads[transfer.squadID]?.cityID==transfer.sourceCityID),
                      "前线驻防调动的武将、编队或时点无效")
        }
        let officers=war.garrisonHeroByCity ?? [:],returns=war.returningGarrisonHeroes ?? [:]
        try check(Set(officers.values).count==officers.count &&
                  officers.allSatisfy{cityID,heroID in
                      cityID != "00" && war.cities[cityID]?.owner=="player" &&
                      agents[heroID] != nil && !returns.keys.contains(heroID)
                  } && returns.allSatisfy{heroID,due in agents[heroID] != nil && due>=time},
                  "驻防武将位置、返程或身份无效")
    }
}

extension LifeRuntime {
    private func pendingWarFacilityNeeds(_ war:LifeWarState) -> [(cityID:String,kind:String,materials:[String:Int64])] {
        let special:[(cityID:String,kind:String,materials:[String:Int64])] = [
            ("01","stone_transport",["wood":4_000,"stone":2_000]),
            ("05","ship",["wood":12_000,"iron":4_000,"tools":2_000]),
            ("06","fire",["wood":4_000,"tools":1_000])
        ]
        let ordinary:[(cityID:String,kind:String,materials:[String:Int64])] = LifeWarContract.facilityBuilds.map { ($0.cityID,$0.kind,$0.materials) }
        return (special+ordinary).filter { need in
            let permit=need.kind=="ship" ? "shipyard" : (need.kind=="fire" ? "fire_doctrine" : need.kind)
            guard let city=war.cities[need.cityID],city.owner=="player",city.supplied,
                  war.unlocked.contains(permit),warSupplyDistance(need.cityID,in:war) != nil else{return false}
            if need.kind=="ship" {return !war.shipBuilt}
            if need.kind=="fire" {return !war.fireDrilled}
            return war.builtFacilities?.contains(need.kind) != true
        }
    }

    /// Permit materials are carried to the actual captured-city warehouse.
    /// The construction clock may start only after every lot has been unloaded.
    mutating func planWarFacilityMaterials() {
        guard let war=world.campaign,world.heroTown?.city.supplyRecovery != true,
              world.foodCoverage>=9_500,world.foodEquivalent()>=Int64(world.agents.count)*4_000,
              !world.tasks.values.contains(where:{$0.kind=="haul" && $0.subject.hasPrefix("war-facility:")}) else{return}
        let needs=pendingWarFacilityNeeds(war)
        for need in needs {
            guard let edges=warSupplyDistance(need.cityID,in:war),edges>0 else{continue}
            let target=LifeWarContract.warehouse(need.cityID)
            for key in need.materials.keys.sorted() {
                guard let resource=LifeResource(rawValue:key),let destination=world.storages[target] else{continue}
                let inFlight=world.tasks.values.filter{$0.kind=="haul" && $0.target==target && $0.resource==resource}
                    .reduce(Int64(0)){$0+$1.quantity}
                let missing=max(0,need.materials[key]!-world.amount(resource,at:target,free:true)-inFlight)
                if missing==0 {continue}
                // Already approved civil works and the coming meal wood belong
                // to the town; front-line construction can use only surplus.
                let civil=world.projects.values.filter{!$0.completed}
                    .reduce(Int64(0)){$0+$1.materials[key,default:0]}
                let mealWood=resource == .wood ? Int64(world.agents.count)*500:0
                let surplus=max(0,world.amount(resource,at:"warehouse",free:true)-civil-mealWood)
                let quantity=min(missing,surplus,4_000,destination.capacity > 0 ? world.freeSpace(target)/resource.volume:0)
                guard quantity>0,let parts=world.selection(resource,quantity:quantity,at:"warehouse") else{continue}
                let travel=LifeWarContract.transportSeconds(from:need.cityID,edges:edges,resource:resource,in:war)
                let tail:[LifeStep]=[.init(kind:"load",seconds:10),
                                     .init(kind:"carry",seconds:travel,destination:"gate"),
                                     .init(kind:"unload",seconds:10)]
                guard let id=assign(kind:"haul",job:"porter",subject:"war-facility:\(need.kind)",at:"hall",work:0,tail:tail,longDuty:true) else{continue}
                world.tasks[id]!.reservations=parts
                world.tasks[id]!.target=target
                world.tasks[id]!.resource=resource
                world.tasks[id]!.quantity=quantity
                world.tasks[id]!.space=quantity*resource.volume
                for part in parts {world.lots[part.lotID]!.reserved+=part.amount}
                world.storages[target]!.incoming+=quantity*resource.volume
                world.record("war","太守安排\(world.agents[world.tasks[id]!.worker]!.name)将\(resource.title)\(Double(quantity)/1_000)份运往\(war.cities[need.cityID]!.name)的\(need.kind)工程；尚在途。")
                return
            }
        }
    }

    /// Front-line spoils have their own real lot location. A healthy porter must
    /// reserve, load, travel along owned cities, and unload before the capital
    /// can spend them. The movement is a normal task, so it survives save/load.
    mutating func planWarLootTransport() {
        guard let war=world.campaign,world.tasks.values.allSatisfy({$0.kind != "haul" || !$0.subject.hasPrefix("war-")}) else{return}
        for city in war.cities.values.sorted(by:{$0.id<$1.id}) where city.id != "00" && city.points["outer"]=="player" {
            guard let edges=warSupplyDistance(city.id,in:war) else{continue}
            let source=LifeWarContract.warehouse(city.id),target="warehouse"
            for resource in [LifeResource.rations,.tools,.wood,.stone,.iron,.rare_ore] {
                // Held frontier food is reserved for local soldiers; returning
                // it immediately would create an endless two-way porter loop.
                if resource == .rations && city.owner=="player" &&
                    (city.id=="02" || war.squads.values.contains{$0.cityID==city.id}) {continue}
                let localNeed=pendingWarFacilityNeeds(war).filter{$0.cityID==city.id}
                    .reduce(Int64(0)){$0+$1.materials[resource.rawValue,default:0]}
                let free=max(0,world.amount(resource,at:source,free:true)-localNeed)
                let q=min(free,LifeWarContract.lootBatchLimit(resource:resource,city:city,war:war),
                          world.freeSpace(target)/resource.volume)
                guard q>0,let parts=world.selection(resource,quantity:q,at:source) else{continue}
                let travel=LifeWarContract.transportSeconds(from:city.id,edges:edges,resource:resource,in:war)
                let tail:[LifeStep]=[.init(kind:"load",seconds:10),.init(kind:"carry",seconds:travel,destination:target),.init(kind:"unload",seconds:10)]
                guard let id=assign(kind:"haul",job:"porter",subject:source,at:"hall",work:0,tail:tail,longDuty:true) else{continue}
                world.tasks[id]!.reservations=parts
                world.tasks[id]!.target=target
                world.tasks[id]!.resource=resource
                world.tasks[id]!.quantity=q
                world.tasks[id]!.space=q*resource.volume
                for part in parts {world.lots[part.lotID]!.reserved+=part.amount}
                world.storages[target]!.incoming+=q*resource.volume
                world.record("war","太守安排\(world.agents[world.tasks[id]!.worker]!.name)从\(city.name)运回\(resource.title)\(Double(q)/1_000)份；尚在途，不计首都库存。")
                return
            }
        }
    }

    /// The governor moves real ration lots to held garrisons. Feng Gu's built
    /// granary keeps its larger buffer; other fronts never receive phantom food.
    mutating func planWarFrontRations() {
        guard let war=world.campaign else{return}
        let homeSoldiers=war.squads.values.filter{$0.cityID=="00"}.reduce(0){$0+$1.survivors}
        let homeReserve=Int64(max(4,(homeSoldiers+1)/2+4))*1_000
        for city in war.cities.values.sorted(by:{$0.id<$1.id}) where city.id != "00" && city.owner=="player" && city.supplied {
            let soldiers=war.squads.values.filter{$0.cityID==city.id && $0.transferID==nil}.reduce(0){$0+$1.survivors}
            let officer=war.garrisonHeroByCity?[city.id] != nil
            guard soldiers>0 || officer || (city.id=="02" && LifeWarContract.facilityActive("frontier_granary",in:war)),
                  let edges=warSupplyDistance(city.id,in:war),edges>0 else{continue}
            let target=LifeWarContract.warehouse(city.id)
            guard !world.tasks.values.contains(where:{$0.kind=="haul" && $0.target==target && $0.resource == .rations}) else{continue}
            let capacity=LifeWarContract.frontRationCapacity(city.id,in:war)
            let desired=min(capacity,city.id=="02" && LifeWarContract.facilityActive("frontier_granary",in:war) ?
                capacity:Int64(max(4,soldiers+(officer ? 2:0)))*1_000)
            let incomingRations=world.inFlight(.rations,to:target)
            // Storage.incoming is total *volume*, including construction wood,
            // stone and tools. It cannot be treated as incoming food.
            let free=max(0,desired-world.amount(.rations,at:target)-incomingRations)
            let surplus=max(0,world.amount(.rations,at:"warehouse",free:true)-homeReserve)
            let quantity=min(free,surplus,4_000,world.freeSpace(target)/LifeResource.rations.volume)
            guard quantity>0,let parts=world.selection(.rations,quantity:quantity,at:"warehouse") else{continue}
            let tail:[LifeStep]=[.init(kind:"load",seconds:10),
                                 .init(kind:"carry",seconds:LifeWarContract.transportSeconds(from:city.id,edges:edges,resource:.rations,in:war),destination:"gate"),
                                 .init(kind:"unload",seconds:10)]
            guard let id=assign(kind:"haul",job:"porter",subject:"warehouse",at:"hall",work:0,tail:tail,longDuty:true) else{continue}
            world.tasks[id]!.reservations=parts
            world.tasks[id]!.target=target
            world.tasks[id]!.resource = .rations
            world.tasks[id]!.quantity=quantity
            world.tasks[id]!.space=quantity*LifeResource.rations.volume
            for part in parts {world.lots[part.lotID]!.reserved+=part.amount}
            world.storages[target]!.incoming+=quantity*LifeResource.rations.volume
            world.record("war","太守安排武将向\(city.name)运送军粮\(Double(quantity)/1_000)份；途中未计入前线可用库存。")
            return
        }
    }

    private func warSupplyDistance(_ destination:String,in war:LifeWarState) -> Int? {
        warDistance(from:"00",to:destination,in:war)
    }
    private func warDistance(from origin:String,to destination:String,in war:LifeWarState) -> Int? {
        let edges=LifeWarContract.landEdges+(war.shipBuilt ? LifeWarContract.waterEdges:[])
        var frontier=[origin],seen:Set<String>=[origin],distance=0
        while !frontier.isEmpty {
            if frontier.contains(destination) {return distance}
            var next:[String]=[]
            for here in frontier {
                for edge in edges where edge.contains(here) {
                    let other=edge[0]==here ? edge[1]:edge[0]
                    let heldRoute=war.cities[other]?.owner=="player" &&
                        (other=="00" || war.cities[other]?.points["outer"]=="player")
                    let attackDestination=other==destination && war.cities[other]?.owner=="enemy"
                    if !seen.contains(other) && (heldRoute || attackDestination) {
                        seen.insert(other);next.append(other)
                    }
                }
            }
            frontier=next;distance+=1
        }
        return nil
    }

    private mutating func scheduleWarGarrisonReturn(_ war:inout LifeWarState,cityID:String,
                                                     seconds:Int64,reason:String) {
        guard let heroID=war.garrisonHeroByCity?[cityID] else{return}
        war.garrisonHeroByCity?[cityID]=nil
        var returns=war.returningGarrisonHeroes ?? [:]
        returns[heroID]=world.time+max(1,seconds)
        war.returningGarrisonHeroes=returns
        world.record("war","\(world.agents[heroID]?.name ?? heroID)：\(reason)。")
    }

    /// A captured city is useful only while a held land/ship route reaches the
    /// capital. Recompute from ownership instead of trusting a sticky capture flag.
    private mutating func refreshWarSupply(_ war:inout LifeWarState) {
        for id in war.cities.keys.sorted() {
            let supplied=id=="00" || (war.cities[id]?.owner=="player" && warSupplyDistance(id,in:war) != nil)
            war.cities[id]!.supplied=supplied
        }
        for cityID in (war.garrisonHeroByCity ?? [:]).keys.sorted() where
            war.cities[cityID]?.owner != "player" || war.cities[cityID]?.supplied != true {
            scheduleWarGarrisonReturn(&war,cityID:cityID,seconds:1_200,
                                      reason:"前线失联，驻防武将撤往首都，返程需1200模拟秒")
        }
        for cityID in (war.garrisonHeroByCity ?? [:]).keys.sorted() {
            guard let heroID=war.garrisonHeroByCity?[cityID],
                  world.heroTown?.health?.conditions[heroID] != nil else{continue}
            scheduleWarGarrisonReturn(&war,cityID:cityID,seconds:1_200,
                                      reason:"驻防武将患病，撤回首都治疗，返程需1200模拟秒")
        }
        let united=war.capturedEnemyCities==11 && war.cities.values.allSatisfy { city in
            city.owner=="player" && city.supplied &&
            (city.id=="00" || LifeWarContract.pointKinds.allSatisfy{city.points[$0]=="player"})
        }
        if united && !war.won {
            world.record("war","王都决战后，十一座外城均已守住且补给线连通；天下统一。")
        }
        war.won=united
        if united {
            war.raidWarning=nil
            war.waitReason="天下统一；全城补给连通，敌军不再袭扰"
        }
    }

    /// Enables a war preview on a legacy formal save. The caller may then
    /// atomically promote the complete city and campaign to the v0.12 identity.
    public mutating func enableWar(realUTC:Int64) throws {
        guard world.isFormalHeroTown else{throw LifeError.invalid("只有正式城镇可开启战役")}
        guard world.campaign==nil else{return}
        let started=max(0,realUTC)
        world.campaign=LifeWarState(startedUTC:started)
        for city in LifeWarContract.cityData where city.id != "00" {
            world.storages[LifeWarContract.warehouse(city.id)] = .init(node:"hall",capacity:128_000_000)
        }
        world.wallUTC=started
        world.record("war","都督开始侦察天下。玩家继续在首都招贤，太守自动筹备军粮和士兵。")
        try world.validate()
    }

    /// The format-4 world is never rewritten until every optional city and war
    /// field has passed validation. SaveStore then backs up the old bytes and
    /// commits the promoted world atomically in the ordinary command path.
    public mutating func enableFormalV12(realUTC:Int64) throws {
        guard world.isFormalHeroTown else{throw LifeError.invalid("只有正式城镇可升级至 v0.12")}
        if world.isCurrentHeroTown {return}
        var candidate=self
        try candidate.enableSharedCourtyards()
        try candidate.enableWar(realUTC:max(candidate.world.wallUTC,realUTC))
        candidate.world.format=LifeV12Contract.format
        candidate.world.rules=LifeV12Contract.rules
        candidate.world.heroTown!.contentHash=LifeV12Contract.contentHash
        candidate.world.heroTown!.authority=LifeV12Contract.authority
        candidate.world.record("migration","旧版城镇与战役已无损升级至 v0.12；金币、武将、卡片、库存和战果保持原值。")
        try candidate.world.validate()
        self=candidate
    }

    public mutating func setWarPaused(_ value:Bool) throws {
        guard world.campaign != nil else{throw LifeError.invalid("战役尚未开启")}
        world.campaign!.paused=value
        world.record("war",value ? "已暂停新远征；驻防、补给和返程照常。":"都督恢复新远征。")
    }

    public mutating func advanceWarClock(realUTC:Int64) {
        guard var war=world.campaign else{return}
        let now=max(war.acceptedUTC,realUTC)
        war.acceptedUTC=now;world.wallUTC=now
        for id in war.cities.keys.sorted() {
            guard var city=war.cities[id],city.owner=="player" else{continue}
            let days=max(Int64(0),(now-city.recruitLastUTC)/86_400)
            if days>0 {
                let rate=city.id=="00" ? 4:2,cap=city.id=="00" ? 40:20
                city.recruitPool=min(cap,city.recruitPool+Int(min(days,Int64(cap)))*rate)
                city.recruitLastUTC+=days*86_400;war.cities[id]=city
            }
        }
        let upkeepDays=max(Int64(0),(now-war.lastUpkeepUTC)/86_400)
        if upkeepDays>0 {
            for _ in 0..<min(upkeepDays,365) {settleWarUpkeep(&war)}
            war.lastUpkeepUTC+=upkeepDays*86_400
        }
        refreshWarSupply(&war)
        if war.raidWarning==nil && now>=war.nextRaidUTC-1_800 && !war.won,
           let warning=makeRaidWarning(in:war) {
            war.raidWarning=warning
            world.record("war","敌军将从\(war.cities[warning.attackerCityID]!.name)于\(warning.arrivalUTC)袭扰\(war.cities[warning.targetCityID]!.name)；都督正在自动备防。")
        }
        if now>=war.nextRaidUTC && !war.won {
            settleWarRaid(&war,at:now)
            war.raidWarning=nil
            // Seven deterministic offsets cover the contracted 12–18 hour
            // interval. Multiplying by seven before modulo seven made every
            // interval exactly twelve hours in existing campaign saves.
            war.nextRaidUTC=now+43_200+Int64((war.raidIndex*5)%7)*3_600
        }
        refreshWarSupply(&war)
        world.campaign=war
        planWar()
    }

    mutating func settleWar() {
        guard var war=world.campaign else{return}
        for heroID in (war.returningGarrisonHeroes ?? [:]).keys.sorted() where
            (war.returningGarrisonHeroes?[heroID] ?? Int64.max)<=world.time {
            war.returningGarrisonHeroes?[heroID]=nil
            world.agents[heroID]?.node="gate"
            world.record("war","\(world.agents[heroID]?.name ?? heroID)结束前线返程，已抵达首都城门。")
        }
        if let training=war.training,training.dueSim<=world.time {
            var quarryProduced=false
            if training.kind=="siege" {
                war.siegeEquipment=true
                world.agents[training.workerID]?.workSeconds["builder",default:0]+=1_200
                world.record("war","工造院完成攻城器械；木六、铁二、工具一已在开工时实耗。")
            } else if training.kind=="refined_siege" {
                war.refinedSiegeEquipment=true
                world.agents[training.workerID]?.workSeconds["builder",default:0]+=900
                world.record("war","精铁攻城器械升级完成；一份精铁和一份工具已实耗。")
            } else if training.kind=="ship" {
                war.shipBuilt=true
                world.agents[training.workerID]?.workSeconds["builder",default:0]+=2_400
                world.record("war","江口船坞完成首艘船；05—07 水路现已开放。")
            } else if training.kind=="fire" {
                war.fireDrilled=true
                world.agents[training.workerID]?.workSeconds["guard",default:0]+=1_800
                world.record("war","炎陵火攻演练完成；仅易燃且非防火目标可使用，逐战另耗木与工具。")
            } else if training.kind=="stone_transport" || LifeWarContract.facilityBuilds.contains(where:{$0.kind==training.kind}) {
                let completed=war.cities[training.regionID]?.owner=="player" && warSupplyDistance(training.regionID,in:war) != nil
                if completed {
                    war.builtFacilities = (war.builtFacilities ?? []).union([training.kind])
                    world.record("war",training.kind=="stone_transport" ?
                                 "青石城石运工程完工；从青石运回石材的单次上限由四份增至六份，仍须武将实搬。" :
                                 "\(LifeWarContract.facilityBuilds.first(where:{$0.kind==training.kind})!.title)完工；本城有补给且仍归我方时能力生效。")
                } else {world.record("war","前线工程期间失城或断路，已投材料不凭空返还；许可保留，太守待复通后重建。")}
                world.agents[training.workerID]?.workSeconds["builder",default:0]+=training.dueSim-training.startedSim
            } else if training.kind=="quarry_stone" {
                world.agents[training.workerID]?.node="gate"
                world.agents[training.workerID]?.workSeconds["miner",default:0]+=1_200
                if war.cities["01"]?.owner=="player" && war.cities["01"]?.supplied==true &&
                    warSupplyDistance("01",in:war) != nil {
                    world.add(.stone,quantity:6_000,at:LifeWarContract.warehouse("01"),
                              origin:"war-quarry:\(training.startedSim)",production:true)
                    quarryProduced=true
                    world.record("war","青石城采石完成：实得石材六份，暂存当地；承运武将返城后另行运回。")
                } else {world.record("war","青石城采石途中断路或失城，武将返城；未凭空产出石材。")}
            } else if training.kind=="mine_rare_ore" {
                world.agents[training.workerID]?.node="gate"
                world.agents[training.workerID]?.workSeconds["miner",default:0]+=1_200
                if war.cities["03"]?.owner=="player" && war.cities["03"]?.supplied==true &&
                    warSupplyDistance("03",in:war) != nil &&
                    world.freeSpace(LifeWarContract.warehouse("03"))>=LifeResource.rare_ore.volume*1_000 {
                    world.add(.rare_ore,quantity:1_000,at:LifeWarContract.warehouse("03"),
                              origin:"rare-mine:\(training.startedSim)",production:true)
                    quarryProduced=true
                    world.record("war","铁岭矿务实产稀有矿石一份，暂存当地；尚需承运到首都炉点。")
                } else {world.record("war","铁岭矿务途中断路、失城或仓满；未生成矿石。")}
            } else if training.kind=="refine_iron" {
                world.agents[training.workerID]?.workSeconds["smith",default:0]+=1_200
                world.add(.refined_iron,quantity:1_000,at:"warehouse",
                          origin:"refined-iron:\(training.startedSim)",production:true)
                world.record("war","工造院把两份铁岭矿石与一份木材冶成精铁一份，已入首都实仓。")
            } else {
                let id=world.next("squad")
                // Regional conscripts travelled to the capital during the timed
                // training mission; no soldier appears before that arrival.
                war.squads[id] = .init(id:id,kind:training.kind,survivors:10,cityID:"00",gearOrigin:"war-train:\(id)")
                world.agents[training.workerID]?.workSeconds["guard",default:0]+=600
                world.record("war","太守完成一队十名\(training.kind=="infantry" ? "步卒":training.kind=="archer" ? "弓手":"工兵")的训练，装备已实耗。")
            }
            noteFirstDutyEffective(heroID:training.workerID,taskID:warTrainingDutyID(training),
                                   effect:training.kind=="stone_transport" ? "建成青石城石运工程" :
                                   training.kind=="quarry_stone" ? (quarryProduced ? "在青石城采得石材六份":"完成青石出差并安全返城，未产出石材") :
                                   training.kind=="mine_rare_ore" ? (quarryProduced ? "在铁岭采得稀有矿石一份":"完成铁岭出差，未产出矿石") :
                                   training.kind=="refine_iron" ? "冶成精铁一份" :
                                   training.kind=="refined_siege" ? "完成精铁攻城器械升级" :
                                   LifeWarContract.facilityBuilds.first(where:{$0.kind==training.kind}).map{"建成\($0.title)"} ??
                                   training.kind=="ship" ? "建成江口船坞和首船" :
                                   training.kind=="fire" ? "完成火攻演练" :
                                   training.kind=="siege" ? "制成攻城器械" : "练成十名\(training.kind)士兵")
            war.training=nil
        }
        if let mission=war.mission,mission.dueSim<=world.time {completeWarStage(&war)}
        if let transfer=war.transfer,transfer.dueSim<=world.time {
            if transfer.sourceCityID != "00" && transfer.targetCityID == "00" {
                // A recall escort has already walked to the frontier and back.
                // Its soldiers were marked in transit and excluded from both
                // garrison bills; they become capital troops only at arrival.
                if war.squads[transfer.squadID]?.transferID==transfer.id {
                    war.squads[transfer.squadID]!.cityID="00"
                    war.squads[transfer.squadID]!.transferID=nil
                    noteFirstDutyEffective(heroID:transfer.workerID,taskID:transfer.id,
                                           effect:"护送过量驻军从\(war.cities[transfer.sourceCityID]!.name)实地返城")
                    world.record("war","\(war.cities[transfer.sourceCityID]!.name)过量驻军计时返抵首都；同一批士兵现在才可参与新远征。")
                }
                war.reservedHeroIDs.removeAll{$0==transfer.workerID}
                war.transfer=nil
                world.campaign=war
                return
            }
            if war.cities[transfer.targetCityID]?.owner=="player" &&
               war.cities[transfer.targetCityID]?.supplied==true &&
               (transfer.officerOnly==true || war.squads[transfer.squadID]?.transferID==transfer.id) {
                if transfer.officerOnly != true {
                    war.squads[transfer.squadID]!.cityID=transfer.targetCityID
                    war.squads[transfer.squadID]!.transferID=nil
                    world.record("war","\(war.cities[transfer.targetCityID]!.name)收到一队真实驻军；调动中的士兵此前未同时驻防两城。")
                }
                noteFirstDutyEffective(heroID:transfer.workerID,taskID:transfer.id,
                                       effect:transfer.officerOnly==true ? "抵达\(war.cities[transfer.targetCityID]!.name)接任驻防" : "护送士兵到达\(war.cities[transfer.targetCityID]!.name)驻防")
                if war.garrisonHeroByCity?[transfer.targetCityID]==nil {
                    var officers=war.garrisonHeroByCity ?? [:]
                    officers[transfer.targetCityID]=transfer.workerID
                    war.garrisonHeroByCity=officers
                    war.reservedHeroIDs.removeAll{$0==transfer.workerID}
                    world.record("war","\(world.agents[transfer.workerID]!.name)随军留守\(war.cities[transfer.targetCityID]!.name)；离城期间不在主城工作或用餐。")
                } else {
                    let travel=max(600,transfer.dueSim-transfer.startedSim)
                    var returns=war.returningGarrisonHeroes ?? [:]
                    returns[transfer.workerID]=world.time+travel
                    war.returningGarrisonHeroes=returns
                    war.reservedHeroIDs.removeAll{$0==transfer.workerID}
                }
            } else {
                if transfer.officerOnly != true {war.squads[transfer.squadID]?.transferID=nil}
                let travel=max(600,transfer.dueSim-transfer.startedSim)
                var returns=war.returningGarrisonHeroes ?? [:]
                returns[transfer.workerID]=world.time+travel
                war.returningGarrisonHeroes=returns
                war.reservedHeroIDs.removeAll{$0==transfer.workerID}
                world.record("war","前线路断或失城，驻防调动取消；\(transfer.officerOnly==true ? "原有士兵仍在前线" : "士兵留在出发城")，武将计时返程；已用军粮不返还。")
            }
            war.transfer=nil
        }
        world.campaign=war
    }

    mutating func planWar() {
        guard var war=world.campaign,!war.won else{return}
        if let trip=war.training,trip.kind=="quarry_stone" {
            let arrival=trip.startedSim+(trip.dueSim-trip.startedSim-1_200)/2
            if world.time>=arrival {noteFirstDutyArrived(heroID:trip.workerID,taskID:warTrainingDutyID(trip))}
        }
        world.rationTarget=max(world.rationTarget,Int64(4+(war.soldierCount+1)/2)*1_000)
        if world.buildings["workshop",default:0]==0 {
            war.waitReason="太守正在建造工造院，保留工具以免募兵后无法再生产装备"
            world.campaign=war;return
        }
        if war.training==nil && war.mission==nil {
            let away=war.awayHeroIDs
            war.reservedHeroIDs.removeAll{world.agents[$0] == nil || world.heroTown?.health?.conditions[$0] != nil || away.contains($0)}
            let fresh=world.agents.values.filter { agent in
                agent.taskID==nil && !war.reservedHeroIDs.contains(agent.id) && agent.job != "prefect" &&
                !["guard_day","guard_night"].contains(agent.job) && world.heroTown?.health?.conditions[agent.id]==nil &&
                !war.awayHeroIDs.contains(agent.id)
            }.sorted { a,b in
                let aa=catalog.hero(a.id)?.attributes ?? [:],bb=catalog.hero(b.id)?.attributes ?? [:]
                let ac=aa["command",default:0],bc=bb["command",default:0]
                return ac==bc ? a.id<b.id:ac>bc
            }
            let militaryPosts=world.agents.count>=8 ? 2:1
            for agent in fresh where war.reservedHeroIDs.count<min(militaryPosts,max(0,world.agents.count-3)) {war.reservedHeroIDs.append(agent.id)}
        }
        if war.training != nil || war.mission != nil || war.transfer != nil {world.campaign=war;return}
        let available=warAvailableHeroes(war)
        guard !available.isEmpty else{war.waitReason="都督正在等待健康武将完成城务并接任军职";world.campaign=war;return}
        if startWarGarrisonRecall(&war,workerID:available.last!.id) {world.campaign=war;return}
        if startWarGarrisonTransfer(&war,workerID:available.last!.id) {world.campaign=war;return}
        if war.unlocked.contains("stone_transport") && war.builtFacilities?.contains("stone_transport") != true &&
           war.cities["01"]?.owner=="player",
           startWarFacility(&war,kind:"stone_transport",workerID:available.last!.id,regionID:"01",
                            materials:["wood":4_000,"stone":2_000],work:600) {
            world.campaign=war;return
        }
        if war.unlocked.contains("shipyard") && !war.shipBuilt && war.cities["05"]?.owner=="player",
           startWarFacility(&war,kind:"ship",workerID:available.last!.id,regionID:"05",
                            materials:["wood":12_000,"iron":4_000,"tools":2_000],work:2_400) {
            world.campaign=war;return
        }
        if war.unlocked.contains("fire_doctrine") && !war.fireDrilled && war.cities["06"]?.owner=="player",
           startWarFacility(&war,kind:"fire",workerID:available.last!.id,regionID:"06",
                            materials:["wood":4_000,"tools":1_000],work:1_800) {
            world.campaign=war;return
        }
        for build in LifeWarContract.facilityBuilds where war.unlocked.contains(build.kind) &&
            !LifeWarContract.facilityActive(build.kind,in:war) && war.builtFacilities?.contains(build.kind) != true &&
            war.cities[build.cityID]?.owner=="player" {
            if startWarFacility(&war,kind:build.kind,workerID:available.last!.id,regionID:build.cityID,
                                materials:build.materials,work:build.work) {world.campaign=war;return}
        }
        if startQingShiQuarry(&war,workerID:available.last!.id) {world.campaign=war;return}
        if startRefinedSiegeUpgrade(&war,workerID:available.last!.id) {world.campaign=war;return}
        if startRareOreMining(&war,workerID:available.last!.id) {world.campaign=war;return}
        if startIronRefinement(&war,workerID:available.last!.id) {world.campaign=war;return}
        let reachableCities=war.cities.values.filter{$0.id != "00" && $0.nextPoint != nil && reachable($0.id,in:war)}.sorted {a,b in
            let ad=warDistance(from:"00",to:a.id,in:war) ?? Int.max
            let bd=warDistance(from:"00",to:b.id,in:war) ?? Int.max
            return ad==bd ? a.id<b.id:ad<bd
        }
        let coreWaiting=war.lastCaptureUTC.map{war.acceptedUTC-$0<259_200} ?? false
        let eligibleCities=reachableCities.filter{$0.nextPoint != "core" || !coreWaiting}
        guard let priorityCity=eligibleCities.first else {
            if coreWaiting,let previous=war.lastCaptureUTC {
                war.waitReason="下一次主城决战还需 \((259_200-(war.acceptedUTC-previous)+3_599)/3_600) 小时；其他边防点已推进至当前战力上限"
            } else {war.waitReason="等待前线道路、船坞或已占城市补给"}
            world.campaign=war;return
        }
        let reserve=war.squads.values.filter{$0.cityID=="00" && $0.missionID==nil}.reduce(0){$0+$1.survivors}
        if reserve<40 {
            let kind=priorityCity.tags.contains("fortification") && !war.squads.values.contains{$0.kind=="sapper" && $0.survivors==10} ? "sapper" :
                (war.squads.values.filter{$0.kind=="archer"}.count*3<war.squads.values.filter{$0.kind=="infantry"}.count ? "archer":"infantry")
            // Iron can run out before the iron-producing frontier is held.
            // A real archer batch paid with wood and tools is a legal fallback.
            for option in [kind,"archer","infantry"] {
                if startWarTraining(&war,kind:option,workerID:available.last!.id) {world.campaign=war;return}
            }
        }
        // Pausing the campaign, or entering recovery after losses, stops only
        // fresh offensive missions. Already committed logistics, local permits,
        // repairs and replacement troop training remain eligible above.
        if war.paused {war.waitReason="玩家已暂停新远征；补给、修复与备兵照常进行";world.campaign=war;return}
        if war.acceptedUTC<war.recoveryUntilUTC {
            war.waitReason=LifeWarContract.recoveryWaitReason(until:war.recoveryUntilUTC,now:war.acceptedUTC)
            world.campaign=war;return
        }
        let heroes=Array(available.prefix(2)).map(\.id)
        let commandCapacity=heroes.reduce(0) { total,heroID in
            total+20+2*(catalog.hero(heroID)?.attributes["command"] ?? 50)
        }
        let send=LifeWarContract.sortieSquadIDs(Array(war.squads.values),capacity:min(200,commandCapacity),
            needsSapper:eligibleCities.contains{$0.tags.contains("fortification")})
        guard !send.isEmpty else{war.waitReason="需要装备士兵；首都先保留十名驻军";world.campaign=war;return}
        let deployed=send.reduce(0){$0+(war.squads[$1]?.survivors ?? 0)}
        guard deployed<=min(200,commandCapacity) else {
            war.waitReason="出征士兵\(deployed)人超过武将统率容量\(min(200,commandCapacity))人"
            world.campaign=war;return
        }
        let options=eligibleCities.map { candidate -> (city:LifeWarCity,point:String,index:Int,attack:Int,safeDefense:Int) in
            let target=candidate.nextPoint!
            let position=LifeWarContract.pointKinds.firstIndex(of:target)!
            let attack=warAttack(war,heroes:heroes,squads:send,city:candidate,siege:war.siegeEquipment,
                                 fire:canFire(candidate,point:target,in:war))
            let defense=warDefense(war,candidate,point:target,siege:war.siegeEquipment,
                                   hasSapper:send.contains{war.squads[$0]?.kind=="sapper" && war.squads[$0]?.survivors==10})
            let safe=position>0 || candidate.scouted ? defense:((defense/50)*50+49)
            return (candidate,target,position,attack,safe)
        }
        let feasible=options.first{$0.attack>$0.safeDefense &&
            ($0.city.id != "07" || world.amount(.wood,at:"warehouse",free:true)>=1_000)}
        let target=feasible ?? options.min { left,right in
            let ld=max(0,left.safeDefense+1-left.attack),rd=max(0,right.safeDefense+1-right.attack)
            if ld != rd{return ld<rd}
            let le=warDistance(from:"00",to:left.city.id,in:war) ?? Int.max
            let re=warDistance(from:"00",to:right.city.id,in:war) ?? Int.max
            return le==re ? left.city.id<right.city.id:le<re
        }!
        let city=target.city,point=target.point,index=target.index,attack=target.attack,safeDefense=target.safeDefense
        guard attack>safeDefense else {
            if !war.siegeEquipment && world.has(["wood":6_000,"iron":2_000,"tools":1_000],at:"warehouse") {
                world.use(["wood":6_000,"iron":2_000,"tools":1_000],at:"warehouse")
                war.training = .init(kind:"siege",workerID:available.last!.id,regionID:"00",startedSim:world.time,dueSim:world.time+1_200)
                noteFirstDutyAssigned(heroID:available.last!.id,taskID:warTrainingDutyID(war.training!),job:"builder",
                                      destination:"工造院",atWork:true)
                war.waitReason="工造院正在制作攻城器械（1200 模拟秒）"
                world.record("war","太守实耗木六、铁二、工具一，工造院开始制作攻城器械。")
            } else if reserve<210 && (["infantry","archer"].contains { kind in
                startWarTraining(&war,kind:kind,workerID:available.last!.id)
            }) {
                war.waitReason="\(city.name)\(point) 攻力 \(attack)，需超过守力 \(safeDefense)；太守正增募有实材装备的士兵"
            } else {
                let recruits=war.cities.values.filter{$0.owner=="player" && warSupplyDistance($0.id,in:war) != nil}
                    .map(\.recruitPool).max() ?? 0
                let wood=world.amount(.wood,at:"warehouse",free:true)/1_000
                let iron=world.amount(.iron,at:"warehouse",free:true)/1_000
                let tools=world.amount(.tools,at:"warehouse",free:true)/1_000
                war.waitReason="\(city.name)\(point) 攻力 \(attack)，需超过守力 \(safeDefense)；可用兵源 \(recruits)/10，木 \(wood)/2、铁 \(iron)/1、工具 \(tools)/1，待补齐后募兵或转攻可行边防点"
            }
            world.campaign=war;return
        }
        let water=city.id=="07"
        let frontRoute=warDistance(from:"02",to:city.id,in:war).map { distance in
            distance+1 <= (warSupplyDistance(city.id,in:war) ?? Int.max)
        } ?? false
        let front=LifeWarContract.facilityActive("frontier_granary",in:war) && frontRoute &&
            world.amount(.rations,at:LifeWarContract.warehouse("02"),free:true)>=2_000
        let homeRations:Int64=front ? 2_000:4_000
        guard world.amount(.rations,at:"warehouse",free:true)>=homeRations,world.amount(.tools,at:"warehouse",free:true)>=1_000,
              !water || world.amount(.wood,at:"warehouse",free:true)>=1_000 else {
            war.waitReason="远征需要首都实仓军粮\(homeRations/1_000)份、工具一份\(water ? "及渡江修船木一份":"")";world.campaign=war;return
        }
        guard world.consume(.rations,quantity:homeRations,at:"warehouse"),world.consume(.tools,quantity:1_000,at:"warehouse") else{return}
        if front {precondition(world.consume(.rations,quantity:2_000,at:LifeWarContract.warehouse("02")))}
        if water {precondition(world.consume(.wood,quantity:1_000,at:"warehouse"))}
        let id=world.next("expedition")
        for squadID in send {war.squads[squadID]!.missionID=id}
        war.mission = .init(id:id,cityID:city.id,sourceCityID:"00",pointIndex:index,heroIDs:heroes,squadIDs:send,
                          stage:city.scouted ? "preparing":"scouting",dueSim:world.time+(city.scouted ? 300:LifeWarContract.scoutingSeconds(in:war)),siegeEquipment:war.siegeEquipment)
        for heroID in heroes {
            noteFirstDutyAssigned(heroID:heroID,taskID:id,job:"commander",destination:city.name,atWork:false)
        }
        war.waitReason="都督前往\(city.name)\(point)，逐点推进"
        world.campaign=war
        world.record("war","都督领兵出征\(city.name)；军粮\(front ? "首都二份与丰谷前线二份":"首都四份")、工具一份已从实仓扣除。")
    }

    private func warAvailableHeroes(_ war:LifeWarState) -> [LifeAgent] {
        war.reservedHeroIDs.compactMap{world.agents[$0]}.filter { agent in
            agent.taskID==nil && world.heroTown?.health?.conditions[agent.id]==nil && !war.awayHeroIDs.contains(agent.id)
        }.sorted { a,b in
            let aa=catalog.hero(a.id)?.attributes ?? [:],bb=catalog.hero(b.id)?.attributes ?? [:]
            let ac=aa["command",default:0],bc=bb["command",default:0]
            if ac != bc{return ac>bc}
            let ascore=aa["strategy",default:0],bscore=bb["strategy",default:0]
            return ascore==bscore ? a.id<b.id:ascore>bscore
        }
    }
    private func desiredWarGarrison(_ city:LifeWarCity,in war:LifeWarState) -> Int {
        let edges=LifeWarContract.landEdges+(war.shipBuilt ? LifeWarContract.waterEdges:[])
        let isBorder=edges.contains { edge in
            edge.contains(city.id) && war.cities[edge[0]==city.id ? edge[1]:edge[0]]?.owner=="enemy"
        }
        guard isBorder else{return 0}
        let rationCapacity=Int(LifeWarContract.frontRationCapacity(city.id,in:war)/1_000)
        // Store volume is not a troop requirement. Keep a bounded defensive
        // squad and preserve enough capital force for the next offensive.
        return min(16,max(0,2*(rationCapacity-1)))
    }
    private mutating func startWarGarrisonRecall(_ war:inout LifeWarState,workerID:String)->Bool {
        let excess=war.cities.values.filter{$0.id != "00" && $0.owner=="player" && $0.supplied &&
            warSupplyDistance($0.id,in:war) != nil}.compactMap { city -> (LifeWarCity,Int)? in
            let stationed=war.squads.values.filter{$0.cityID==city.id && $0.missionID==nil && $0.transferID==nil}
                .reduce(0){$0+$1.survivors}
            let surplus=stationed-desiredWarGarrison(city,in:war)
            return surplus>0 ? (city,surplus):nil
        }.sorted { left,right in left.1==right.1 ? left.0.id<right.0.id:left.1>right.1 }
        guard let (city,surplus)=excess.first,
              let distance=warSupplyDistance(city.id,in:war),distance>0,
              world.amount(.rations,at:LifeWarContract.warehouse(city.id),free:true)>=2_000 else{return false}
        let eligibleSquads=war.squads.values.filter {
            $0.cityID==city.id && $0.missionID==nil && $0.transferID==nil
        }.sorted { a,b in
            a.survivors==b.survivors ? a.id<b.id:a.survivors>b.survivors
        }
        guard let squad=eligibleSquads.first else{return false}
        let count=min(10,surplus,squad.survivors)
        guard count>0,world.consume(.rations,quantity:2_000,at:LifeWarContract.warehouse(city.id)) else{return false}
        let id=world.next("garrison-recall")
        let movingSquadID:String
        if count==squad.survivors {
            movingSquadID=squad.id
            war.squads[squad.id]!.transferID=id
        } else {
            war.squads[squad.id]!.survivors-=count
            movingSquadID=world.next("squad")
            war.squads[movingSquadID] = .init(id:movingSquadID,kind:squad.kind,survivors:count,
                                               cityID:city.id,transferID:id,gearOrigin:squad.gearOrigin)
        }
        war.transfer = .init(id:id,workerID:workerID,squadID:movingSquadID,sourceCityID:city.id,
                             targetCityID:"00",startedSim:world.time,dueSim:world.time+Int64(distance)*1_200)
        noteFirstDutyAssigned(heroID:workerID,taskID:id,job:"guard",destination:city.name,atWork:false)
        war.waitReason="太守从\(city.name)召回\(count)名超过防线需求的实兵；先耗当地军粮两份，武将往返护送中"
        world.record("war",war.waitReason)
        return true
    }
    private mutating func startWarGarrisonTransfer(_ war:inout LifeWarState,workerID:String)->Bool {
        let edges=LifeWarContract.landEdges+(war.shipBuilt ? LifeWarContract.waterEdges:[])
        let targets=war.cities.values.filter { city in
            guard city.id != "00" && city.owner=="player" && city.supplied &&
                edges.contains(where:{edge in edge.contains(city.id) &&
                    war.cities[edge[0]==city.id ? edge[1]:edge[0]]?.owner=="enemy"}) else{return false}
            let stationed=war.squads.values.filter{$0.cityID==city.id && $0.missionID==nil && $0.transferID==nil}
                .reduce(0){$0+$1.survivors}
            let rationCapacity=Int(LifeWarContract.frontRationCapacity(city.id,in:war)/1_000)
            let soldierCap=desiredWarGarrison(city,in:war)
            if war.garrisonHeroByCity?[city.id]==nil && stationed>0 {
                let dailyNeed=(stationed+1)/2+1
                return dailyNeed<=rationCapacity &&
                    world.amount(.rations,at:LifeWarContract.warehouse(city.id),free:true)>=Int64(dailyNeed)*1_000
            }
            return war.garrisonHeroByCity?[city.id]==nil || stationed<soldierCap
        }.sorted{$0.id<$1.id}
        guard let target=targets.first,let distance=warSupplyDistance(target.id,in:war),distance>0,
              world.amount(.rations,at:"warehouse",free:true)>=2_000 else{return false}
        let stationed=war.squads.values.filter{$0.cityID==target.id && $0.missionID==nil && $0.transferID==nil}
            .reduce(0){$0+$1.survivors}
        let rationCapacity=Int(LifeWarContract.frontRationCapacity(target.id,in:war)/1_000)
        let soldierCap=desiredWarGarrison(target,in:war)
        let officerOnly=stationed>0 && war.garrisonHeroByCity?[target.id]==nil
        if officerOnly {
            let dailyNeed=(stationed+1)/2+1
            guard dailyNeed<=rationCapacity,
                  world.amount(.rations,at:LifeWarContract.warehouse(target.id),free:true)>=Int64(dailyNeed)*1_000 else{return false}
        }
        let capital=war.squads.values.filter{$0.cityID=="00" && $0.missionID==nil && $0.transferID==nil}
            .sorted{a,b in a.survivors==b.survivors ? a.id<b.id:a.survivors>b.survivors}
        let dispatch=min(10,max(0,soldierCap-stationed),capital.first?.survivors ?? 0)
        let homeCount=capital.reduce(0){$0+$1.survivors}
        let needsFirstDefense=stationed==0 && war.garrisonHeroByCity?[target.id]==nil
        guard officerOnly || (dispatch>0 && homeCount-dispatch >= (needsFirstDefense ? 10:40)) else{return false}
        guard world.consume(.rations,quantity:2_000,at:"warehouse") else{return false}
        let id=world.next("garrison-transfer")
        var movingSquadID=""
        if !officerOnly,let squad=capital.first {
            if squad.survivors==dispatch {
                movingSquadID=squad.id
                war.squads[squad.id]!.transferID=id
            } else {
                war.squads[squad.id]!.survivors-=dispatch
                movingSquadID=world.next("squad")
                war.squads[movingSquadID] = .init(id:movingSquadID,kind:squad.kind,survivors:dispatch,
                                                   cityID:"00",transferID:id,gearOrigin:squad.gearOrigin)
                world.record("war","从\(squad.id)实兵中拆出\(dispatch)人赴\(target.name)驻防；首都原编队同步减员，不新增免费士兵。")
            }
        }
        war.transfer = .init(id:id,workerID:workerID,squadID:movingSquadID,sourceCityID:"00",
                             targetCityID:target.id,startedSim:world.time,
                             dueSim:world.time+Int64(distance)*600)
        war.transfer!.officerOnly=officerOnly
        noteFirstDutyAssigned(heroID:workerID,taskID:id,job:"guard",destination:target.name,atWork:false)
        war.waitReason=officerOnly ? "\(target.name)原驻军仍在，健康武将单独行军接防；首都军粮两份已实耗" :
            "\(target.name)边境驻军调动\(dispatch)人；首都军粮两份已实耗，士兵尚在路上"
        world.record("war",war.waitReason)
        return true
    }
    private mutating func startWarTraining(_ war:inout LifeWarState,kind:String,workerID:String) -> Bool {
        let protectedFood=Int64(world.agents.count)*4_000
        let equipment=LifeWarContract.equipment(kind)
        guard world.foodEquivalent()>=protectedFood,
              equipment.allSatisfy({world.amount($0.key,at:"warehouse",free:true)>=$0.value}) else{return false}
        let region=war.cities.values.filter{$0.owner=="player" && $0.recruitPool>=10 && warSupplyDistance($0.id,in:war) != nil}
            .sorted { a,b in
                let da=warSupplyDistance(a.id,in:war)!,db=warSupplyDistance(b.id,in:war)!
                return da==db ? a.id<b.id:da<db
            }.first
        guard let region,let edges=warSupplyDistance(region.id,in:war) else{return false}
        for resource in equipment.keys.sorted(by:{$0.rawValue<$1.rawValue}) {
            precondition(world.consume(resource,quantity:equipment[resource]!,at:"warehouse"))
        }
        war.cities[region.id]!.recruitPool-=10
        war.training = .init(kind:kind,workerID:workerID,regionID:region.id,
                             startedSim:world.time,dueSim:world.time+600+Int64(edges)*600)
        noteFirstDutyAssigned(heroID:workerID,taskID:warTrainingDutyID(war.training!),job:"guard",
                              destination:"兵营",atWork:true)
        war.waitReason="从\(region.name)招募十名士兵，途中并训练 \(600+edges*600) 模拟秒"
        world.record("war","太守从\(region.name)兵源池征募十人，实耗装备，武将带兵回首都训练。")
        return true
    }
    private mutating func startWarFacility(_ war:inout LifeWarState,kind:String,workerID:String,regionID:String,
                                           materials:[String:Int64],work:Int64) -> Bool {
        let localWarehouse=LifeWarContract.warehouse(regionID)
        guard (["ship","fire","stone_transport"] + LifeWarContract.facilityBuilds.map(\.kind)).contains(kind),
              world.has(materials,at:localWarehouse),
              warSupplyDistance(regionID,in:war) != nil else{return false}
        world.use(materials,at:localWarehouse)
        war.training = .init(kind:kind,workerID:workerID,regionID:regionID,startedSim:world.time,dueSim:world.time+work)
        noteFirstDutyAssigned(heroID:workerID,taskID:warTrainingDutyID(war.training!),
                              job:kind=="fire" ? "guard":"builder",destination:war.cities[regionID]?.name ?? "前线",atWork:true)
        switch kind {
        case "ship":war.waitReason="江口船坞正造首船（2400 模拟秒）"
        case "fire":war.waitReason="炎陵正在火攻演练（1800 模拟秒）"
        case "stone_transport":war.waitReason="青石城石运工程施工中（600 模拟秒）"
        default:war.waitReason="\(LifeWarContract.facilityBuilds.first(where:{$0.kind==kind})!.title)施工中（\(work) 模拟秒）"
        }
        world.record("war",war.waitReason+"；材料已从当地实仓扣除，来自可追踪的前线运输。")
        return true
    }
    private func warTrainingDutyID(_ training:LifeWarTraining) -> String {
        "war-training:\(training.workerID):\(training.kind):\(training.startedSim)"
    }
    private mutating func startQingShiQuarry(_ war:inout LifeWarState,workerID:String) -> Bool {
        guard war.builtFacilities?.contains("stone_transport") == true,
              war.cities["01"]?.owner=="player",war.cities["01"]?.supplied==true,
              let edges=warSupplyDistance("01",in:war),
              world.amount(.stone,at:"warehouse",free:true)<12_000,
              world.amount(.stone,at:LifeWarContract.warehouse("01"))==0,
              !world.tasks.values.contains(where:{$0.kind=="haul" && $0.subject==LifeWarContract.warehouse("01") && $0.resource == .stone}),
              world.freeSpace(LifeWarContract.warehouse("01"))>=6_000*LifeResource.stone.volume,
              world.foodCoverage>=9_500,world.foodEquivalent()>=Int64(world.agents.count)*4_000,
              world.consume(.rations,quantity:1_000,at:"warehouse") else{return false}
        war.training = .init(kind:"quarry_stone",workerID:workerID,regionID:"01",startedSim:world.time,
                             dueSim:world.time+1_200+Int64(edges)*1_200)
        noteFirstDutyAssigned(heroID:workerID,taskID:warTrainingDutyID(war.training!),job:"miner",
                              destination:"青石城石场",atWork:false)
        war.waitReason="武将赴青石城采石；已耗军粮一份，采得后仍需另行运回"
        world.record("war",war.waitReason)
        return true
    }
    private mutating func startRareOreMining(_ war:inout LifeWarState,workerID:String) -> Bool {
        guard war.unlocked.contains("rare_ore_mine"),war.cities["03"]?.owner=="player",
              war.cities["03"]?.supplied==true,let edges=warSupplyDistance("03",in:war),
              world.amount(.rare_ore,at:LifeWarContract.warehouse("03"))<2_000,
              world.amount(.rare_ore,at:"warehouse")<2_000,
              world.freeSpace(LifeWarContract.warehouse("03"))>=LifeResource.rare_ore.volume*1_000,
              world.foodCoverage>=9_500,world.foodEquivalent()>=Int64(world.agents.count)*4_000,
              world.consume(.rations,quantity:1_000,at:"warehouse") else{return false}
        war.training = .init(kind:"mine_rare_ore",workerID:workerID,regionID:"03",startedSim:world.time,
                             dueSim:world.time+1_200+Int64(edges)*1_200)
        noteFirstDutyAssigned(heroID:workerID,taskID:warTrainingDutyID(war.training!),job:"miner",
                              destination:"铁岭矿脉",atWork:false)
        war.waitReason="武将赴铁岭采矿；实耗军粮一份，矿石须另行运回"
        world.record("war",war.waitReason)
        return true
    }
    private mutating func startIronRefinement(_ war:inout LifeWarState,workerID:String) -> Bool {
        guard LifeWarContract.facilityActive("refined_iron_forge",in:war),
              world.buildings["workshop",default:0]>0,
              world.amount(.refined_iron,at:"warehouse")<2_000,
              world.has(["rare_ore":2_000,"wood":1_000],at:"warehouse"),
              world.freeSpace("warehouse")>=LifeResource.refined_iron.volume*1_000 else{return false}
        world.use(["rare_ore":2_000,"wood":1_000],at:"warehouse")
        war.training = .init(kind:"refine_iron",workerID:workerID,regionID:"00",startedSim:world.time,
                             dueSim:world.time+1_200)
        noteFirstDutyAssigned(heroID:workerID,taskID:warTrainingDutyID(war.training!),job:"smith",
                              destination:"工造院精铁炉点",atWork:true)
        war.waitReason="精铁冶炼中（1200 模拟秒）；已实耗矿石二份、木材一份"
        world.record("war",war.waitReason)
        return true
    }
    private mutating func startRefinedSiegeUpgrade(_ war:inout LifeWarState,workerID:String) -> Bool {
        guard war.siegeEquipment,war.refinedSiegeEquipment != true,
              LifeWarContract.facilityActive("refined_iron_forge",in:war),
              world.has(["refined_iron":1_000,"tools":1_000],at:"warehouse") else{return false}
        world.use(["refined_iron":1_000,"tools":1_000],at:"warehouse")
        war.training = .init(kind:"refined_siege",workerID:workerID,regionID:"00",startedSim:world.time,
                             dueSim:world.time+900)
        noteFirstDutyAssigned(heroID:workerID,taskID:warTrainingDutyID(war.training!),job:"builder",
                              destination:"工造院攻城器械",atWork:true)
        war.waitReason="精铁器械升级中（900 模拟秒）；已实耗精铁一份、工具一份"
        world.record("war",war.waitReason)
        return true
    }
    private func canFire(_ city:LifeWarCity,point:String,in war:LifeWarState) -> Bool {
        war.fireDrilled && city.tags.contains("flammable") && !city.tags.contains("fire_guard") &&
        point=="core" && world.has(["wood":2_000,"tools":1_000],at:"warehouse")
    }
    private func reachable(_ id:String,in war:LifeWarState) -> Bool {
        (LifeWarContract.landEdges+(war.shipBuilt ? LifeWarContract.waterEdges:[])).contains { edge in
            (edge[0]==id && war.cities[edge[1]]?.supplied==true) ||
            (edge[1]==id && war.cities[edge[0]]?.supplied==true)
        }
    }
    private func warHeroSupport(_ heroID:String) -> Int {
        let attributes=catalog.hero(heroID)?.attributes ?? [:]
        let base=(4*attributes["command",default:50]+4*attributes["valor",default:50]+2*attributes["strategy",default:50])/20
        let star=world.gacha?.stars[heroID] ?? 1
        return base*(100+10*max(0,star-1))/100
    }
    private func warGarrisonSupport(_ war:LifeWarState,cityID:String) -> Int {
        guard let heroID=war.garrisonHeroByCity?[cityID],world.agents[heroID] != nil,
              world.heroTown?.health?.conditions[heroID]==nil else{return 0}
        return warHeroSupport(heroID)
    }
    private func warAttack(_ war:LifeWarState,heroes:[String],squads:[String],city:LifeWarCity,siege:Bool,fire:Bool=false) -> Int {
        var result=squads.reduce(0){$0+(war.squads[$1]?.power ?? 0)}
        for heroID in heroes {result+=warHeroSupport(heroID)}
        if siege {result+=20;if war.refinedSiegeEquipment==true {result+=10}}
        if fire {result+=40}
        if city.id=="07" && war.shipBuilt {result+=30}
        if city.tags.contains("mountain") {result=max(0,result-20)}
        return result
    }
    private func warDefense(_ war:LifeWarState,_ city:LifeWarCity,point:String,siege:Bool,hasSapper:Bool=false) -> Int {
        var value:Int
        switch point {
        case "outer":value=city.enemyPower/4
        case "supply":value=city.enemyPower*35/100
        case "gate":value=city.enemyPower*45/100+(city.wall+1)/2
        default:value=city.enemyPower*90/100+max(0,city.wall-(city.points["gate"]=="player" ? 30:0))
        }
        if city.tags.contains("heavy") && war.refinedSiegeEquipment != true {value+=20}
        if city.tags.contains("ranged") && !siege {value+=15}
        if city.tags.contains("cavalry") && !LifeWarContract.facilityActive("long_range_scouting",in:war) {value+=20}
        if city.tags.contains("fortification") && !hasSapper {value+=20}
        if city.id=="07" && city.tags.contains("naval") {value+=20}
        return value
    }
    private func appendWarReport(_ war:inout LifeWarState,_ report:LifeWarReport) {
        var reports=war.reports ?? []
        guard !reports.contains(where:{$0.id==report.id}) else{return}
        reports.append(report)
        if reports.count>256 {reports.removeFirst(reports.count-256)}
        war.reports=reports
    }
    private mutating func completeWarStage(_ war:inout LifeWarState) {
        guard var mission=war.mission else{return}
        switch mission.stage {
        case "scouting":
            war.cities[mission.cityID]!.scouted=true
            mission.stage="preparing";mission.dueSim=world.time+300
        case "preparing":mission.stage="marching";mission.dueSim=world.time+600
        case "marching":mission.stage="battling";mission.dueSim=world.time+(mission.pointIndex==3 ? 1_200:600)
        case "battling":
            let city=war.cities[mission.cityID]!,point=LifeWarContract.pointKinds[mission.pointIndex]
            for heroID in mission.heroIDs {noteFirstDutyArrived(heroID:heroID,taskID:mission.id)}
            let fire=canFire(city,point:point,in:war)
            if fire {world.use(["wood":2_000,"tools":1_000],at:"warehouse")}
            let attack=warAttack(war,heroes:mission.heroIDs,squads:mission.squadIDs,city:city,siege:mission.siegeEquipment,fire:fire)
            let defense=warDefense(war,city,point:point,siege:mission.siegeEquipment,
                                   hasSapper:mission.squadIDs.contains{war.squads[$0]?.kind=="sapper" && war.squads[$0]?.survivors==10})
            let won=attack>defense
            for heroID in mission.heroIDs {
                noteFirstDutyEffective(heroID:heroID,taskID:mission.id,
                                       effect:"参与\(city.name)\(LifeWarContract.pointTitle(point))\(won ? "取胜":"攻坚")，战力\(attack) 对守力\(defense)")
            }
            let percent=won ? [5,8,12,20][mission.pointIndex]:25
            let soldiers=mission.squadIDs.reduce(0){$0+(war.squads[$1]?.survivors ?? 0)}
            let losses=min(soldiers,(soldiers*percent+99)/100)
            let shares=LifeWarContract.casualtyShares(mission.squadIDs.compactMap{war.squads[$0]},losses:losses)
            for id in shares.keys.sorted() {war.squads[id]!.survivors-=shares[id]!}
            for id in mission.squadIDs where war.squads[id]?.survivors==0 {war.squads[id]=nil}
            mission.squadIDs.removeAll{war.squads[$0]==nil}
            var granted:[String:Int64]=[:]
            if won {
                war.cities[city.id]!.points[point]="player"
                let receipt="\(city.id):\(point)"
                if !war.firstClearReceipts.contains(receipt) {
                    war.firstClearReceipts.insert(receipt);war.cities[city.id]!.firstCleared.insert(point)
                    for (resource,quantity) in LifeWarContract.loot(point) {
                        world.add(resource,quantity:quantity,at:LifeWarContract.warehouse(city.id),origin:"war-loot:\(receipt)",production:true)
                        granted[resource.rawValue]=quantity
                    }
                }
                if point=="core" {
                    war.cities[city.id]!.owner="player";war.cities[city.id]!.supplied=true
                    war.cities[city.id]!.recruitPool=20;war.cities[city.id]!.recruitLastUTC=war.acceptedUTC
                    war.unlocked.insert(city.unlock);war.lastCaptureUTC=war.acceptedUTC
                    refreshWarSupply(&war)
                }
                let reward=point=="core" ? "解锁\(city.unlock)与地区兵源":"缴获\(LifeWarContract.loot(point).map{"\($0.key.title)\($0.value/1_000)"}.sorted().joined(separator:"、"))，存于前线"
                let next=mission.pointIndex<3 ? "下一目标：\(LifeWarContract.pointTitle(LifeWarContract.pointKinds[mission.pointIndex+1]))" : "该城边防与主城已打通"
                world.record("war","\(city.name)\(LifeWarContract.pointTitle(point))获胜：攻\(attack) > 守\(defense)，损兵\(losses)，\(reward)；\(next)。")
                if let nextKind=war.cities[city.id]?.nextPoint,
                   let nextIndex=LifeWarContract.pointKinds.firstIndex(of:nextKind),
                   mission.squadIDs.contains(where:{war.squads[$0] != nil}) {
                    mission.pointIndex=nextIndex
                    let nextCity=war.cities[city.id]!
                    let nextAttack=warAttack(war,heroes:mission.heroIDs,squads:mission.squadIDs,city:nextCity,siege:mission.siegeEquipment,
                                             fire:canFire(nextCity,point:nextKind,in:war))
                    let nextDefense=warDefense(war,nextCity,point:nextKind,siege:mission.siegeEquipment,
                                                hasSapper:mission.squadIDs.contains{war.squads[$0]?.kind=="sapper" && war.squads[$0]?.survivors==10})
                    if nextAttack>nextDefense && !(nextKind=="core" && war.lastCaptureUTC.map{war.acceptedUTC-$0<259_200} == true) {
                        mission.stage="preparing";mission.dueSim=world.time+300
                    } else {mission.stage="returning";mission.dueSim=world.time+600}
                } else {mission.stage="returning";mission.dueSim=world.time+600}
            } else {
                war.waitReason="\(city.name)\(LifeWarContract.pointTitle(point))战败；需补兵/器械并休整"
                world.record("war","\(city.name)\(LifeWarContract.pointTitle(point))失利：攻\(attack) ≤ 守\(defense)，损兵\(losses)；太守将补兵与器械。")
                mission.stage="returning";mission.dueSim=world.time+1_800
            }
            let gainText=won && point=="core" ? "解锁\(city.unlock)与地区兵源" :
                (granted.isEmpty ? "无新增首胜物资" : "首胜物资\(granted.map{"\($0.key)\($0.value/1_000)"}.sorted().joined(separator:"、"))存于本城前线仓")
            let resultText="\(city.name)\(LifeWarContract.pointTitle(point))\(won ? "取胜":"失利")：攻\(attack) \(won ? ">" : "≤") 守\(defense)，战损\(losses)；" +
                gainText +
                (won ? "；下一步由都督按补给与战力选择" : "；休整后补兵或更换器械")
            appendWarReport(&war,.init(id:"\(mission.id):\(point)",simulationTime:world.time,acceptedUTC:war.acceptedUTC,
                                      kind:won ? "battle_win":"battle_loss",cityID:city.id,point:point,
                                      attack:attack,defense:defense,casualties:losses,loot:granted,text:resultText))
        case "returning":
            for id in mission.squadIDs where war.squads[id] != nil {war.squads[id]!.missionID=nil;war.squads[id]!.cityID="00"}
            war.mission=nil
            world.record("war","远征队安全返城；太守继续安排补给与下一目标。")
            return
        default:return
        }
        war.mission=mission
    }
    private mutating func settleWarUpkeep(_ war:inout LifeWarState) {
        for cityID in war.cities.keys.sorted() {
            // The two rations paid when a squad departed cover its march.
            // While in transit it is in neither city's daily garrison bill.
            let ids=war.squads.values.filter{$0.cityID==cityID && $0.transferID==nil}.map(\.id).sorted(by:>)
            let number=ids.reduce(0){$0+(war.squads[$1]?.survivors ?? 0)}
            let officer=war.garrisonHeroByCity?[cityID] != nil
            guard number>0 || officer else{continue}
            let soldierRequired=(number+1)/2
            let required=soldierRequired+(officer ? 1:0)
            let store=cityID=="00" ? "warehouse":LifeWarContract.warehouse(cityID)
            let stock=Int(world.amount(.rations,at:store,free:true)/1_000)
            let paid=min(required,stock)
            if paid>0 {_=world.consume(.rations,quantity:Int64(paid)*1_000,at:store)}
            let missingSoldier=max(0,soldierRequired-paid)
            let officerUnfed=officer && paid<required
            if officerUnfed {
                scheduleWarGarrisonReturn(&war,cityID:cityID,seconds:1_200,
                                          reason:"驻地军粮不足，武将停止驻防并安全返程1200模拟秒")
            }
            if missingSoldier>0 {
                var loss=min(number,missingSoldier*2)
                for id in ids where loss>0 {
                    let n=min(loss,war.squads[id]!.survivors)
                    war.squads[id]!.survivors-=n;loss-=n
                }
                for id in ids where war.squads[id]?.survivors==0 {war.squads[id]=nil}
                if let transfer=war.transfer,transfer.officerOnly != true,war.squads[transfer.squadID]==nil {
                    let travel=max(600,transfer.dueSim-transfer.startedSim)
                    var returns=war.returningGarrisonHeroes ?? [:]
                    returns[transfer.workerID]=world.time+travel
                    war.returningGarrisonHeroes=returns
                    war.reservedHeroIDs.removeAll{$0==transfer.workerID}
                    war.transfer=nil
                    world.record("war","调动中的驻军因军粮断供散失，护送武将计时返程首都。")
                }
                if cityID=="00",var mission=war.mission {
                    mission.squadIDs.removeAll{war.squads[$0]==nil}
                    mission.stage="returning";mission.dueSim=max(world.time+600,mission.dueSim)
                    war.mission=mission
                }
                world.record("war","\(war.cities[cityID]!.name)驻军缺粮：应耗\(required)份、实耗\(paid)份，散失\(min(number,missingSoldier*2))人；未动用其他城市或民用粮。")
            } else {world.record("war","\(war.cities[cityID]!.name)驻军日耗军粮\(paid)份，现役\(number)人\(officer ? "、驻防武将一人":"")。")}
        }
    }
    private func makeRaidWarning(in war:LifeWarState) -> LifeRaidWarning? {
        let edges=LifeWarContract.landEdges+(war.shipBuilt ? LifeWarContract.waterEdges:[])
        var borders:[(attacker:String,target:String,cut:Int,defense:Int)]=[]
        for edge in edges {
            for (attacker,target) in [(edge[0],edge[1]),(edge[1],edge[0])] where
                war.cities[attacker]?.owner=="enemy" && war.cities[target]?.owner=="player" &&
                war.cities[target]?.supplied==true {
                var cutWar=war
                if target != "00" {cutWar.cities[target]!.owner="enemy"}
                let cut=target=="00" ? -1:war.cities.keys.filter { cityID in
                    cityID != target && cityID != "00" && war.cities[cityID]?.supplied==true &&
                    warSupplyDistance(cityID,in:cutWar)==nil
                }.count
                let civicDefense=target=="00" ? min(20,world.civicDutyCount("watch")+world.civicDutyCount("drill")):0
                let defense=war.squads.values.filter{$0.cityID==target && $0.missionID==nil && $0.transferID==nil}.reduce(20){$0+$1.power} + warGarrisonSupport(war,cityID:target) + civicDefense
                borders.append((attacker,target,cut,defense))
            }
        }
        guard let selected=borders.sorted(by:{ left,right in
            if left.cut != right.cut {return left.cut>right.cut}
            let leftGap=left.defense-(war.cities[left.attacker]?.enemyPower ?? 0)/2
            let rightGap=right.defense-(war.cities[right.attacker]?.enemyPower ?? 0)/2
            if leftGap != rightGap {return leftGap<rightGap}
            return left.target==right.target ? left.attacker<right.attacker:left.target<right.target
        }).first else{return nil}
        let next=war.raidIndex+1
        return .init(id:"raid:\(next)",attackerCityID:selected.attacker,targetCityID:selected.target,
                     warningUTC:war.nextRaidUTC-1_800,arrivalUTC:war.nextRaidUTC,
                     counterattack:next%3==0 && selected.target != "00")
    }
    private mutating func damageCapitalProductionPlot()->String? {
        guard var formal=world.heroTown else{return nil}
        let preferred=["workshop-1","farm-2","workshop-2","granary-2","house-2","house-3","house-4"]
        guard let plotID=preferred.first(where:{id in
            formal.city.plots.contains{$0.id==id && $0.level>0 && $0.service>0}
        }),let index=formal.city.plots.firstIndex(where:{$0.id==plotID}) else{return nil}
        formal.city.plots[index].service=0
        world.heroTown=formal
        world.record("war","\(plotID)遭袭受损，服务暂停；太守将按原建筑该级报价的四分之一实材实工修复。")
        return plotID
    }
    private mutating func settleWarRaid(_ war:inout LifeWarState,at now:Int64) {
        war.raidIndex+=1
        guard let warning=war.raidWarning,
              let enemy=war.cities[warning.attackerCityID],enemy.owner=="enemy",
              let target=war.cities[warning.targetCityID],target.owner=="player" else {
            world.record("war","本次敌军袭扰因边界改变而取消，未造成损失。")
            return
        }
        if now<war.recoveryUntilUTC {
            let summary="\(enemy.name)对\(target.name)的袭扰处于防螺旋恢复期，本次未造成损失。"
            appendWarReport(&war,.init(id:warning.id,simulationTime:world.time,acceptedUTC:now,
                                      kind:"raid_recovery",cityID:target.id,point:nil,attack:0,defense:0,
                                      casualties:0,loot:[:],text:summary))
            world.record("war",summary)
            return
        }
        let attack=enemy.enemyPower/2
        let defenders=war.squads.values.filter{$0.cityID==target.id && $0.missionID==nil && $0.transferID==nil}
        let watched=target.id=="04" && LifeWarContract.facilityActive("pass_watchtower",in:war)
        let officerSupport=warGarrisonSupport(war,cityID:target.id)
        let civicDefense=target.id=="00" ? min(20,world.civicDutyCount("watch")+world.civicDutyCount("drill")):0
        let defense=defenders.reduce(20){$0+$1.power}+officerSupport+(watched ? 40:0)+civicDefense
        let win=defense>=attack
        let number=defenders.reduce(0){$0+$1.survivors}
        let casualtyTotal=min(number,(number*(win ? 5:25)+99)/100)
        let shares=LifeWarContract.casualtyShares(defenders,losses:casualtyTotal)
        for id in shares.keys.sorted() {war.squads[id]!.survivors-=shares[id]!}
        for id in war.squads.keys.sorted() where war.squads[id]?.survivors==0 {war.squads[id]=nil}
        if win {
            war.raidLossStreak=0
            let summary="\(enemy.name)袭扰\(target.name)被击退：守\(defense) ≥ 攻\(attack)，守军战损\(casualtyTotal)\(officerSupport>0 ? "；驻防武将+\(officerSupport)":"")\(watched ? "；北关哨所+40":"")。"
            world.record("war",summary)
            appendWarReport(&war,.init(id:warning.id,simulationTime:world.time,acceptedUTC:now,
                                      kind:"raid_defended",cityID:target.id,point:nil,attack:attack,defense:defense,
                                      casualties:casualtyTotal,loot:[:],text:summary))
        }
        else {
            war.raidLossStreak+=1
            var taken:[String]=[]
            var lost:[String:Int64]=[:]
            let store=target.id=="00" ? "warehouse":LifeWarContract.warehouse(target.id)
            for resource:LifeResource in [.grain,.wood,.stone,.iron,.tools] {
                let available=world.amount(resource,at:store,free:true)
                let protected=resource == .grain && target.id=="00" ? Int64(world.agents.count)*4_000:0
                let surplus=max(0,available-protected)
                let quantity=min(surplus/4,available/10)
                if quantity>0 && world.consume(resource,quantity:quantity,at:store) {
                    taken.append("\(resource.title)\(Double(quantity)/1_000)")
                    lost[resource.rawValue]=quantity
                }
            }
            var pointLost=false
            if warning.counterattack,target.id != "00",war.cities[target.id]?.points["outer"]=="player" {
                war.cities[target.id]!.points["outer"]="enemy"
                pointLost=true
            }
            let damaged=target.id=="00" ? damageCapitalProductionPlot():nil
            let summary="\(enemy.name)袭扰\(target.name)得手：守\(defense) < 攻\(attack)，守军战损\(casualtyTotal)；损失\(taken.isEmpty ? "无可掠物资":taken.joined(separator:"、"))" +
                (pointLost ? "；反攻夺回外哨，首胜物资不会重发":"") +
                (damaged.map{"；\($0)停工待修"} ?? "") + "。"
            world.record("war",summary)
            appendWarReport(&war,.init(id:warning.id,simulationTime:world.time,acceptedUTC:now,
                                      kind:pointLost ? "raid_counterattack":"raid_lost",cityID:target.id,
                                      point:pointLost ? "outer":nil,attack:attack,defense:defense,
                                      casualties:casualtyTotal,loot:lost,text:summary))
            if war.raidLossStreak>=2 {
                war.recoveryUntilUTC=now+129_600;war.raidLossStreak=0
                world.record("war","都督进入36小时防螺旋恢复期，暂停新进攻并优先补给。")
            }
        }
    }
}
