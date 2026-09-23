import Foundation
import SanguoLife
import SanguoLifeVisual
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A local, serialized adapter. Godot never owns a second economy or reads the native game's save.
enum GodotBridge {
    struct Input:Decodable {
        var operation:String="snapshot"
        var seconds:Int64=0
        var commandID:String?
        var count:Int?
        var hero:String?
        var target:Int?
        var card:String?
        var cards:[LifeCardSelection]?
        var locked:Bool?
        var confirmed:Bool?
        var previewHash:String?
        var realUTC:Int64?
    }
    static func run(_ json:String,saveDirectory:String?,base64Response:Bool=false) {
        func emit(_ bytes:Data) {
            print(base64Response ? bytes.base64EncodedString() : String(decoding:bytes,as:UTF8.self))
        }
        let debugDirectory=saveDirectory.map{URL(fileURLWithPath:$0,isDirectory:true)} ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SanguoTown-HeroTown09",isDirectory:true)
        do {
            let input=try JSONDecoder().decode(Input.self,from:Data(json.utf8))
            let directory=debugDirectory
            guard ["SanguoTown-HeroTown09","SanguoTown-GodotPreview"].contains(directory.lastPathComponent) || directory.lastPathComponent.hasPrefix("godot-fixture-") else {throw LifeError.invalid("Godot小城只能使用独立规则目录")}
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            DebugTrace.log(in:directory,event:"bridge_request",fields:["operation":input.operation,"seconds":input.seconds,"commandID":input.commandID ?? ""])
            let fd=open(directory.appendingPathComponent("bridge.lock").path,O_CREAT|O_RDWR,0o600)
            guard fd>=0 else{throw LifeError.invalid("无法获取独立存档锁")}
            defer{flock(fd,LOCK_UN);close(fd)}
            guard flock(fd,LOCK_EX)==0 else{throw LifeError.invalid("存档正在使用")}
            let store=LifeSaveStore(url:directory.appendingPathComponent("world.json"))
            let catalog=try LifeCatalog.bundled()
            var runtime:LifeRuntime
            var migratedCourtyard=false
            var migratedEconomy=false
            var migratedRoster=false
            if let saved=try store.load() {
                guard saved.isGacha else{throw LifeError.invalid("不是Godot玩法样板存档")}
                runtime=try LifeRuntime(catalog:catalog,world:saved)
                migratedCourtyard=saved.isFormalHeroTown && saved.heroTown?.courtyard == nil
                migratedEconomy=saved.isFormalHeroTown && saved.gacha?.goldRebalance == nil
                migratedRoster=saved.isFormalHeroTown && saved.gacha?.rosterPhase == nil
            } else {
                runtime=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true)
                // Enter daytime by actually running the engine; no asset gifts or fake progress.
                try runtime.advance(to:300)
            }
            try runtime.enableSharedCourtyards()
            let beforeWarClock=runtime.world
            if runtime.world.isFormalHeroTown {
                try runtime.enableWar(realUTC:input.realUTC ?? Int64(Date().timeIntervalSince1970))
                runtime.advanceWarClock(realUTC:input.realUTC ?? Int64(Date().timeIntervalSince1970))
            }
            guard (0...86400).contains(input.seconds) else{throw LifeError.invalid("单次推进超出样板限制")}
            let before=runtime.world
            var receipt:LifeGachaReceipt?
            switch input.operation {
            case "snapshot":guard input.seconds==0 else{throw LifeError.invalid("快照不能推进时间")}
            case "advance":try runtime.advance(to:runtime.world.time+input.seconds)
            case "pause_war","resume_war":
                guard input.seconds==0 else{throw LifeError.invalid("战争方针不能同时推进时间")}
                try runtime.setWarPaused(input.operation=="pause_war")
            case "draw","star","star_selected","decompose","decompose_batch","exchange","lock":
                guard input.seconds==0,let id=input.commandID,!id.isEmpty else{throw LifeError.invalid("需要唯一玩家命令ID")}
                let action:LifeGachaAction
                switch input.operation {
                case "draw":action = .draw(count:input.count ?? 1,pool:runtime.world.gacha!.poolVersion(formal:runtime.world.isFormalHeroTown))
                case "star":action = .starUp(hero:input.hero ?? "",target:input.target ?? 0)
                case "star_selected":action = .starUpSelected(hero:input.hero ?? "",target:input.target ?? 0,cards:input.cards ?? [])
                case "decompose":action = .disassemble(card:input.card ?? "",quantity:Int64(input.count ?? 1))
                case "decompose_batch":
                    let selections=input.cards ?? []
                    action = .disassembleMany(cards:selections,confirmed:input.confirmed ?? false,previewHash:input.previewHash ?? runtime.world.gacha!.cultivationPreviewHash(selections))
                case "exchange":action = .exchange(hero:input.hero ?? "",quantity:Int64(input.count ?? 1))
                default:action = .lock(card:input.card ?? "",locked:input.locked ?? true)
                }
                let request=runtime.world.gacha?.receipt(id)?.request ?? .player(id:id,revision:runtime.world.sequence,action:action)
                receipt=try runtime.performGacha(request)
            default:throw LifeError.invalid("不支持的Godot命令")
            }
            // Save before reporting any draw result. Failed writes expose no candidate snapshot.
            if migratedCourtyard || migratedEconomy || migratedRoster || runtime.world != beforeWarClock || runtime.world != before || !FileManager.default.fileExists(atPath:store.url.path) {try store.save(runtime.world)}
            let w=runtime.world,g=w.gacha!,d=runtime.definition!
            // The HUD shows workers the governor can dispatch now, not everyone
            // without a task (which would include the prefect and sleeping guards).
            let onDayShift=(240..<1920).contains(w.phase)
            let idlePersonnel=w.agents.values.filter { agent in
                onDayShift && agent.taskID == nil && agent.restStart == nil &&
                !["prefect","guard_day","guard_night"].contains(agent.job) &&
                w.campaign?.lockedHeroIDs.contains(agent.id) != true &&
                w.heroTown?.health?.treatments[agent.id] == nil &&
                w.heroTown?.health?.conditions[agent.id] == nil
            }.count
            DebugTrace.log(in:directory,event:"bridge_result",fields:["operation":input.operation,"seconds":input.seconds,"beforeTime":before.time,"afterTime":w.time,"beforeSequence":before.sequence,"afterSequence":w.sequence,"taskCount":w.tasks.count,"idleAgentCount":w.agents.values.filter{$0.taskID==nil}.count,"night":w.isNight])
            if DebugTrace.shouldWriteDetail(input:input,before:before,after:w) {
                DebugTrace.log(in:directory,event:"world_state",fields:DebugTrace.worldState(w))
            }
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            func object<T:Encodable>(_ value:T)throws->Any {try JSONSerialization.jsonObject(with:encoder.encode(value))}
            var heroes:[[String:Any]]=[]
            for (index,h) in d.heroes.enumerated() {
                var row:[String:Any] = ["id":h.id,"name":h.name,"rarity":h.rarity,"profile":h.star_profile,"star":g.stars[h.id,default:0],"cards":g.cardCount(h.id),"unlockedCards":g.cardCount(h.id,unlockedOnly:true),"arriving":g.arrivals[h.id] != nil,"poolOpen":index<g.rosterTarget]
                if let owned=w.heroTown?.ownedHeroes[h.id] {
                    if let duty=owned.firstDuty {
                        row["firstDuty"]=try object(duty)
                        row["arrivalStage"]=duty.effectiveAt != nil ? "contributed" :
                            (duty.arrivedAt != nil ? "working":"on_way")
                    } else {row["arrivalStage"]=owned.arrivalState=="waiting_residency" ? "waiting_residency" : (g.arrivals[h.id] != nil ? "arriving" :
                                (owned.sourceDrawID=="founding" ? "founding" :
                                 (w.agents[h.id]?.workSeconds.values.contains(where:{$0>0}) == true ? "legacy_untracked":"awaiting_duty")))}
                }
                row["skills"]=h.skills.map { skill -> [String:Any] in
                    ["id":skill.id,"unlockStar":skill.unlock_star,"kind":skill.kind,"jobs":skill.jobs ?? [],"values":skill.values_by_star ?? []]
                }
                if let a=w.agents[h.id] {
                    if w.warAwayHeroIDs.contains(h.id) {
                        row["awayAtWar"]=true
                        if let cityID=w.campaign?.garrisonHeroByCity?.first(where:{$0.value==h.id})?.key {
                            row["action"]="驻守\(w.campaign?.cities[cityID]?.name ?? "前线")"
                        } else if w.campaign?.returningGarrisonHeroes?[h.id] != nil {
                            row["action"]="从前线返程"
                        } else {
                            row["action"]=w.campaign?.transfer?.workerID==h.id ?
                                (w.campaign?.transfer?.officerOnly==true ? "赴前线接任驻防":"护送前线驻军") :
                                (w.campaign?.training?.kind=="quarry_stone" &&
                                 w.campaign?.training?.workerID==h.id ? "赴青石城采石":"随军出征")
                        }
                    }
                    else {
                        let f=LifeVisual.actor(a,world:w,at:Double(w.time)),task=a.taskID.flatMap{w.tasks[$0]}
                        row.merge(["x":f.position.x,"y":f.position.y,"sleeping":f.sleeping,"action":f.action,"job":a.job,"motion":f.motion.rawValue,"cargo":f.cargo?.rawValue ?? "","route":try object(task?.current.route ?? []),"started":task?.started ?? w.time,"due":task?.due ?? w.time]){_,new in new}
                        row["taskKind"]=task?.kind ?? ""
                        row["taskResource"]=task?.resource?.rawValue ?? ""
                        row["taskJob"]=task?.job ?? ""
                        row["taskRate"]=task?.rate ?? 10000
                        row["cargoAmount"]=f.quantity
                        if task == nil {
                            let reason:String
                            if let condition=w.heroTown?.health?.conditions[h.id] {
                                reason=condition.kind=="minor_work_injury" ? "轻伤休养中；待医舍或居家恢复后重新排班" : "劳损休养中；待医舍或居家恢复后重新排班"
                            } else if w.campaign?.lockedHeroIDs.contains(h.id)==true {
                                reason="军务岗位预留；等待都督下一项真实训练、调防或远征"
                            } else if f.sleeping || a.restStart != nil {
                                reason="按班次在家休息，下一工作日复查"
                            } else if ["prefect","guard_day","guard_night"].contains(a.job) {
                                reason="固定府署或值守岗位，不计入可派工空闲"
                            } else if !onDayShift {
                                reason="非白天派工时段，下一班次复查"
                            } else if a.busyCycle==w.cycle && a.serviceSeconds>=1920 {
                                reason="本日服务工时已满，明日再派工"
                            } else if w.projects.values.contains(where:{!$0.completed}) {
                                reason="可派工；现有工地可能已满员或待料，太守下一轮复查"
                            } else {
                                reason="可派工；当前无未完成工程，生产工位按需开动，等待新订单"
                            }
                            row["idleReason"]=reason
                        }
                    }
                }
                if let condition=w.heroTown?.health?.conditions[h.id] {
                    row["healthCondition"]=condition.kind
                    row["healthEvidence"]=condition.evidence
                    row["healthModifierBP"]=condition.workModifierBP
                    row["treatmentPhase"]=w.heroTown?.health?.treatments[h.id]?.phase ?? "waiting"
                }
                heroes.append(row)
            }
            var response:[String:Any] = ["ok":true,"time":w.time,"revision":w.sequence,"night":w.isNight,"coins":w.treasury,"idlePersonnel":idlePersonnel,"souls":g.souls,"pity":g.pity,"poolVersion":g.poolVersion(formal:w.isFormalHeroTown),"poolSize":g.rosterTarget,"residentCap":30+10*(g.rosterPhase ?? 0),"residentCount":w.agents.count,"waitingResidents":g.arrivals.filter{$0.value<=w.time}.count,"complete":g.isComplete,"minted":g.minted,"food":w.foodCoverage,"happiness":w.happiness,"housing":w.housing,"civicDuty":["clean":w.civicDutyCount("clean"),"watch":w.civicDutyCount("watch"),"drill":w.civicDutyCount("drill"),"capitalDefense":min(20,w.civicDutyCount("watch")+w.civicDutyCount("drill"))],"heroes":heroes,"buildings":w.buildings,"houseLevels":g.houseLevels,"projects":try object(w.projects.values.sorted{$0.id<$1.id}),"fields":try object(w.fields.values.sorted{$0.id<$1.id}),"stations":try object(w.stations),"cards":try object(g.cards.values.sorted{$0.id<$1.id}),"draws":try object(g.lastDraws),"resources":Dictionary(uniqueKeysWithValues:LifeResource.allCases.map{($0.rawValue,w.amount($0))}),"records":try object(Array(w.records.suffix(10))),"places":try object(LifeMap.places),"rules":w.rules,"savePath":store.url.path,"debugLogPath":DebugTrace.path(in:directory).path]
            if let formal=w.heroTown {
                response["contentHash"]=formal.contentHash
                response["layoutVersion"]=formal.city.layoutVersion
                var projectedPlots=formal.city.plots
                if let health=formal.health {
                    response["health"]=try object(health)
                    if health.clinicLevel>0 {
                        let occupiedBeds=health.treatments.values.filter{$0.phase != "arriving"}.count
                        projectedPlots.append(.init(id:"clinic-1",index:projectedPlots.count,kind:"clinic",node:"clinic",point:LifeHealthContract.clinicPoint,
                                                    level:health.clinicLevel,capacity:LifeHealthContract.clinicBeds[health.clinicLevel-1],
                                                    occupancy:occupiedBeds,service:10000,developmentPermit:true,identity:"clinic-1"))
                    }
                } else {response["health"]=["clinicLevel":0,"conditions":[:],"treatments":[:]]}
                response["plots"]=try object(projectedPlots)
                if let courtyard=formal.courtyard {
                    response["parcelRows"]=LifeLayout7.categoryRows
                    response["parcelByPlotID"]=courtyard.parcelByPlotID
                    response["unlockedGrid"]=["columns":courtyard.unlockedColumns,"rows":courtyard.unlockedRows]
                    response["courtyardUnits"]=try object(courtyard.units)
                    response["households"]=try object(courtyard.households)
                    response["formalHouseholdCapacity"]=courtyard.formalCapacity
                }
                response["civics"]=formal.city.civics
                response["landmarks"]=formal.city.landmarks
                response["attachments"]=formal.city.attachments
                response["supplyRecovery"]=formal.city.supplyRecovery
                response["fieldPlan"]=try object(LifeLayout6.fieldPoints)
            }
            if let campaign=w.campaign {
                response["campaign"]=try object(campaign)
                response["warReports"]=try object(campaign.reports ?? [])
                if campaign.reports == nil {
                    response["warReports"]=try object(Array(w.records.filter{$0.kind=="war"}.suffix(12)))
                }
                response["warStock"]=Dictionary(uniqueKeysWithValues:campaign.cities.keys.filter{$0 != "00"}.map { cityID in
                    (cityID,Dictionary(uniqueKeysWithValues:[LifeResource.wood,.stone,.iron,.tools,.rations,.rare_ore].map { resource in
                        (resource.rawValue,w.amount(resource,at:LifeWarContract.warehouse(cityID)))
                    }))
                })
            }
            response["treeReady"]=w.treeReady
            let goldRate=g.goldRebalance?.coinsPerNewIngot ?? 10
            let goldReason:String
            if g.isComplete {goldReason="武将已全部满星，酒馆停止新招募"}
            else if w.treasury>=100 {goldReason="金币已够单抽；是否招募由你决定"}
            else if w.heroTown?.city.supplyRecovery==true || w.foodCoverage<9500 {goldReason="太守先恢复供餐，金链暂缓"}
            else if w.amount(.gold_ingot)>0 {goldReason="金锭正等待运抵府署入库"}
            else if w.stations["smelter"]?.phase != "idle" {goldReason="冶金坊正在完成当前批次"}
            else if w.amount(.wood,free:true)<w.goldFuelWoodReserve+(runtime.catalog.recipe("smelt_gold")?.input_mU["wood"] ?? 500) {goldReason="木材低于民生与工程保护线，暂缓冶炼"}
            else if w.amount(.gold_ore)>0 {goldReason="矿石已采出，等待运输或冶炼工位"}
            else if w.tasks.values.contains(where:{$0.kind=="gather" && $0.target=="goldmine"}) {goldReason="正在金矿采掘"}
            else {goldReason="等待太守调配采矿、冶炼或搬运人手"}
            response["goldChain"]=[
                "atMine":w.amount(.gold_ore,at:"goldmine"),
                "atWarehouse":w.amount(.gold_ore,at:"warehouse"),
                "atFurnace":w.amount(.gold_ore,at:"smelter-in"),
                "readyIngots":w.amount(.gold_ingot,at:"smelter-out"),
                "deliveredIngots":w.consumed["gold_ingot",default:0],
                "mining":w.tasks.values.filter{$0.kind=="gather" && $0.target=="goldmine" && $0.current.route.isEmpty}.count,
                "inTransit":w.lots.values.filter{($0.resource == .gold_ore || $0.resource == .gold_ingot) && w.tasks[$0.location] != nil}.reduce(Int64(0)){$0+$1.amount},
                "coinsPerIngot":goldRate,
                "legacyIngots":g.goldRebalance?.historicalIngots ?? 0,
                "legacyCoins":g.goldRebalance?.historicalCoins ?? 0,
                "nextDrawMissing":max(0,100-w.treasury),
                "nextDrawReason":goldReason
            ]
            if let receipt {response["receipt"]=try object(receipt)}
            let bytes=try JSONSerialization.data(withJSONObject:response,options:[.sortedKeys])
            emit(bytes)
        } catch {
            DebugTrace.log(in:debugDirectory,event:"bridge_error",level:"error",fields:["error":error.localizedDescription,"detail":String(describing:error)])
            let bytes=try! JSONSerialization.data(withJSONObject:["ok":false,"error":error.localizedDescription,"detail":String(describing:error)])
            emit(bytes)
        }
    }
}
