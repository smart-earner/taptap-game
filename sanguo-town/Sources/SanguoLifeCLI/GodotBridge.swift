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
    }
    static func run(_ json:String,saveDirectory:String?) {
        do {
            let input=try JSONDecoder().decode(Input.self,from:Data(json.utf8))
            let directory=saveDirectory.map{URL(fileURLWithPath:$0,isDirectory:true)} ??
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SanguoTown-HeroTown09",isDirectory:true)
            guard ["SanguoTown-HeroTown09","SanguoTown-GodotPreview"].contains(directory.lastPathComponent) || directory.lastPathComponent.hasPrefix("godot-fixture-") else {throw LifeError.invalid("Godot小城只能使用独立规则目录")}
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let fd=open(directory.appendingPathComponent("bridge.lock").path,O_CREAT|O_RDWR,0o600)
            guard fd>=0 else{throw LifeError.invalid("无法获取独立存档锁")}
            defer{flock(fd,LOCK_UN);close(fd)}
            guard flock(fd,LOCK_EX)==0 else{throw LifeError.invalid("存档正在使用")}
            let store=LifeSaveStore(url:directory.appendingPathComponent("world.json"))
            let catalog=try LifeCatalog.bundled()
            var runtime:LifeRuntime
            if let saved=try store.load() {
                guard saved.isGacha else{throw LifeError.invalid("不是Godot玩法样板存档")}
                runtime=try LifeRuntime(catalog:catalog,world:saved)
            } else {
                runtime=try LifeRuntime(catalog:catalog,wallUTC:0,formalHeroTown:true)
                // Enter daytime by actually running the engine; no asset gifts or fake progress.
                try runtime.advance(to:300)
            }
            guard (0...86400).contains(input.seconds) else{throw LifeError.invalid("单次推进超出样板限制")}
            let before=runtime.world
            var receipt:LifeGachaReceipt?
            switch input.operation {
            case "snapshot":guard input.seconds==0 else{throw LifeError.invalid("快照不能推进时间")}
            case "advance":try runtime.advance(to:runtime.world.time+input.seconds)
            case "draw","star","star_selected","decompose","decompose_batch","exchange","lock":
                guard input.seconds==0,let id=input.commandID,!id.isEmpty else{throw LifeError.invalid("需要唯一玩家命令ID")}
                let action:LifeGachaAction
                switch input.operation {
                case "draw":action = .draw(count:input.count ?? 1,pool:runtime.definition!.gacha.pool_version)
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
            if runtime.world != before || !FileManager.default.fileExists(atPath:store.url.path) {try store.save(runtime.world)}
            let w=runtime.world,g=w.gacha!,d=runtime.definition!
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            func object<T:Encodable>(_ value:T)throws->Any {try JSONSerialization.jsonObject(with:encoder.encode(value))}
            var heroes:[[String:Any]]=[]
            for h in d.heroes {
                var row:[String:Any] = ["id":h.id,"name":h.name,"rarity":h.rarity,"profile":h.star_profile,"star":g.stars[h.id,default:0],"cards":g.cardCount(h.id),"unlockedCards":g.cardCount(h.id,unlockedOnly:true),"arriving":g.arrivals[h.id] != nil]
                row["skills"]=h.skills.map { skill -> [String:Any] in
                    ["id":skill.id,"unlockStar":skill.unlock_star,"kind":skill.kind,"jobs":skill.jobs ?? [],"values":skill.values_by_star ?? []]
                }
                if let a=w.agents[h.id] {
                    let f=LifeVisual.actor(a,world:w,at:Double(w.time)),task=a.taskID.flatMap{w.tasks[$0]}
                    row.merge(["x":f.position.x,"y":f.position.y,"sleeping":f.sleeping,"action":f.action,"job":a.job,"motion":f.motion.rawValue,"cargo":f.cargo?.rawValue ?? "","route":try object(task?.current.route ?? []),"started":task?.started ?? w.time,"due":task?.due ?? w.time]){_,new in new}
                    row["taskKind"]=task?.kind ?? ""
                    row["taskResource"]=task?.resource?.rawValue ?? ""
                    row["taskJob"]=task?.job ?? ""
                    row["taskRate"]=task?.rate ?? 10000
                    row["cargoAmount"]=f.quantity
                }
                heroes.append(row)
            }
            var response:[String:Any] = ["ok":true,"time":w.time,"revision":w.sequence,"night":w.isNight,"coins":w.treasury,"souls":g.souls,"pity":g.pity,"complete":g.isComplete,"minted":g.minted,"food":w.foodCoverage,"housing":w.housing,"heroes":heroes,"buildings":w.buildings,"houseLevels":g.houseLevels,"projects":try object(w.projects.values.sorted{$0.id<$1.id}),"fields":try object(w.fields.values.sorted{$0.id<$1.id}),"stations":try object(w.stations),"cards":try object(g.cards.values.sorted{$0.id<$1.id}),"draws":try object(g.lastDraws),"resources":Dictionary(uniqueKeysWithValues:LifeResource.allCases.map{($0.rawValue,w.amount($0))}),"records":try object(Array(w.records.suffix(10))),"places":try object(LifeMap.places),"rules":w.rules,"savePath":store.url.path]
            if let formal=w.heroTown {
                response["contentHash"]=formal.contentHash
                response["layoutVersion"]=formal.city.layoutVersion
                response["plots"]=try object(formal.city.plots)
                response["civics"]=formal.city.civics
                response["landmarks"]=formal.city.landmarks
                response["attachments"]=formal.city.attachments
                response["supplyRecovery"]=formal.city.supplyRecovery
                response["fieldPlan"]=try object(LifeLayout6.fieldPoints)
            }
            response["treeReady"]=w.treeReady
            response["goldChain"]=["atMine":w.amount(.gold_ore,at:"goldmine"),"atWarehouse":w.amount(.gold_ore,at:"warehouse"),"atFurnace":w.amount(.gold_ore,at:"smelter-in"),"readyIngots":w.amount(.gold_ingot,at:"smelter-out"),"deliveredIngots":w.consumed["gold_ingot",default:0],"mining":w.tasks.values.filter{$0.kind=="gather" && $0.target=="goldmine" && $0.current.route.isEmpty}.count,"inTransit":w.lots.values.filter{($0.resource == .gold_ore || $0.resource == .gold_ingot) && w.tasks[$0.location] != nil}.reduce(Int64(0)){$0+$1.amount}]
            if let receipt {response["receipt"]=try object(receipt)}
            let bytes=try JSONSerialization.data(withJSONObject:response,options:[.sortedKeys])
            print(String(decoding:bytes,as:UTF8.self))
        } catch {
            let bytes=try! JSONSerialization.data(withJSONObject:["ok":false,"error":error.localizedDescription,"detail":String(describing:error)])
            print(String(decoding:bytes,as:UTF8.self))
        }
    }
}
