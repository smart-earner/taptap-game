import Foundation
import SanguoCore

/// Original modular town art driven by actual BuildingInstances; no timer-based city skin swaps.
public enum GrowthTownArt {
    public static func position(_ plot:Int)->VPoint { .init(65+Double(plot%8)*115,plot<8 ? 190 : 65) }
    public static var roads:RoadGraph {
        var points:[String:VPoint] = ["gate":.init(950,40),"upper-end":.init(950,160)]
        var edges:[(String,String)] = [("gate","upper-end")]
        for plot in 0..<16 {
            let p=position(plot), road="road-\(plot)"
            points["plot-\(plot)"]=p;points[road] = .init(p.x,plot<8 ? 160 : 40)
            edges.append((road,"plot-\(plot)"))
            if plot%8>0 { edges.append(("road-\(plot-1)",road)) }
        }
        edges += [("road-7","upper-end"),("road-15","gate")]
        return .init(points:points,edges:edges)
    }
    public static func projection(_ world:WorldState,cityID:String)->TownProjection? {
        guard let s=world.appearance(cityID:cityID), let plan=world.growth?.cities[cityID] else { return nil }
        var result=TownProjection(cityID:cityID,title:s.name,actors:[],hasWorkshop:plan.level(.workshop)>0,
                                  hasField:plan.level(.farm)>0,isDemo:false)
        result.appearance=s
        let hall=plan.buildings.first{$0.kind == .hall}!
        let home="plot-\(hall.plot)"
        let travelling = Set(world.realm?.journeys.map(\.personID) ?? [])
        result.actors=world.people.values.filter{$0.cityID==cityID && !travelling.contains($0.id)}.sorted{$0.id<$1.id}.prefix(6).map { person in
            ActorSpec(id:"person:"+person.id,name:person.name,costume:person.office != nil ? .official : .warrior,
                      home:home,destination:"gate",work:.idle,handItem:CivicTownArt.equippedHandItem(personID:person.id,world:world))
        }
        let roles:[(String,BuildingKind,Motion)]=[("grain",.farm,.cultivate),("wine",.tavern,.carry),("tools",.workshop,.hammer)]
        for (key,kind,motion) in roles where plan.lastWorkKinds.contains(key) {
            if let b=plan.buildings.first(where:{$0.kind==kind && $0.isOperating}) {
                result.actors.append(.init(id:"job-\(cityID)-\(key)",name:kind.title+"岗位代表",costume:.artisan,
                    home:"gate",destination:"plot-\(b.plot)",work:motion,representative:true))
            }
        }
        for p in plan.projects where p.status == .working && p.builders>0 {
            if let b=plan.buildings.first(where:{$0.id==p.buildingID}) {
                result.actors.append(.init(id:p.id,name:"施工代表",costume:.artisan,home:"gate",destination:"plot-\(b.plot)",work:.hammer,representative:true))
            }
        }
        // Real population drives how many decorative residents are represented, not vice versa.
        for b in plan.buildings.filter({$0.kind == .house && $0.isOperating}).prefix(max(0,(s.population-8)/8)) {
            result.actors.append(.init(id:"resident-\(b.id)",name:"居民代表",costume:.artisan,home:"plot-\(b.plot)",destination:"gate",work:.idle,representative:true))
        }
        if let p=s.civic?.project, !p.paused, p.workers>0 {
            let plot = CivicTownArt.workPlot(p.track, buildings:s.buildings)
            result.actors.append(.init(id:"civic-"+cityID,name:p.track.title+"施工代表",costume:.artisan,
                home:"gate",destination:"plot-\(plot)",work:.hammer,representative:true))
        }
        if s.legionActive>0, s.legionAway != true,let camp=plan.buildings.first(where:{$0.kind == .barracks && $0.isOperating}) {
            result.actors.append(.init(id:"legion-representative",name:"在营\(s.legionActive)人·队列代表",costume:.warrior,
                home:"plot-\(camp.plot)",destination:"gate",work:.strike,representative:true))
        }
        return result
    }
    public static func background(_ s:CityAppearanceSnapshot)->VNode {
        var a:[VNode] = [
            .rect("sky",0,0,960,300,"#EBEDE1"),
            .polygon("hills",[(0,268),(100,297),(180,260),(290,289),(420,255),(550,284),(690,264),(800,298),(960,272),(960,0),(0,0)],"#AABCAF",stroke:"none"),
            .rect("town-soil",12,20,936,248,"#BECAA3",radius:12),
            .rect("upper-road",20,152,928,16,"#D5C5A6",radius:3),
            .rect("lower-road",20,32,928,16,"#D5C5A6",radius:3),
            .rect("right-road",941,35,16,130,"#D5C5A6"),
            .rect("wall-back",10,261,940,10,"#8E9D91",stroke:"#677E77"),
            .rect("wall-left",6,25,10,240,"#8E9D91"),
            .rect("wall-right",944,105,10,160,"#8E9D91")]
        for i in 0..<38 { a.append(.rect("battlement-\(i)",Double(i)*25+10,270,13,5,"#8E9D91")) }
        for plot in 0..<16 {
            let p=position(plot)
            a.append(.rect("alley-\(plot)",p.x-5,plot<8 ? 160 : 40,10,plot<8 ? 30 : 25,"#D5C5A6"))
            if !s.buildings.contains(where:{$0.plot==plot}) {
                a.append(.ellipse("empty-plot-\(plot)",p.x-36,p.y+5,72,22,"#ADB995"))
                a.append(.line("grass-\(plot)",[(p.x-12,p.y+10),(p.x-10,p.y+18),(p.x-7,p.y+12)],"#7C9576",width:2))
            }
        }
        a += CivicTownArt.nodes(s)
        return .init("growth-landscape",children:a)
    }
    public static func building(_ b:BuildingInstance, snapshot:CityAppearanceSnapshot)->VNode {
        let p=position(b.plot),prefix=b.id
        let project=snapshot.projects.first{$0.buildingID==b.id && $0.live}
        let effective=b.level>0 ? b.level : 1
        let roof=["#7B6F56","#667D73","#4B6B69"][min(2,max(0,effective-1))]
        let wall=b.kind == .workshop ? "#BEAB88" : "#E4D3AC"
        var children:[VNode] = [.ellipse(prefix+"-shadow",-49,-4,98,18,"#9EAD8F")]
        func buildingBody() -> [VNode] {
            var c:[VNode]=[
                .rect(prefix+"-plinth",-42,0,84,8,"#889888",radius:2),
                .rect(prefix+"-wall",-38,7,76,33,wall,stroke:"#786F58"),
                .rect(prefix+"-door",-8,7,16,24,"#536557"),
                .rect(prefix+"-window",-29,20,13,12,"#A2B3A0",stroke:"#736D59"),
                .polygon(prefix+"-roof",[(-49,37),(-35,53),(33,53),(49,37)],roof,stroke:"#52665D")]
            for i in 0..<7 { let x = -32.0+Double(i)*10;c.append(.line(prefix+"-tile-\(i)",[(x,50),(x+6,39)],"#879484")) }
            if effective>=2 {
                c += [.rect(prefix+"-yard",-47,-4,5,23,"#BAB594"),.rect(prefix+"-yard2",43,-4,5,23,"#BAB594"),
                      .rect(prefix+"-lantern",24,25,7,10,"#C59155",radius:2)]
            }
            if effective>=3 {
                c += [.polygon(prefix+"-upper-roof",[(-33,53),(-22,64),(22,64),(33,53)],"#426667"),
                      .rect(prefix+"-upper-window",-10,51,20,7,"#CCBB8E")]
            }
            if b.kind == .hall && !b.restored { c.append(.line(prefix+"-old-roof",[(-30,46),(-16,39),(-5,47)],"#C3B693",width:4)) }
            return c
        }
        if b.isOperating || (project?.phase ?? 0)>=2 {
            if b.kind == .farm {
                children.append(.polygon(prefix+"-field",[(-46,1),(44,1),(40,48),(-40,48)],"#99895D",stroke:"#6A7759"))
                for row in 0..<4 { for col in 0..<9 {
                    let x = -36.0+Double(col)*9, y = 7.0+Double(row)*10
                    children.append(.line(prefix+"-crop-\(row)-\(col)",[(x-2,y+4),(x,y),(x+3,y+7)],effective>=2 ? "#D4C97B" : "#B7C275",width:2))
                } }
                if effective>=2 { children.append(.rect(prefix+"-irrigation",-47,-1,94,4,"#7AA5A2")) }
            } else { children += buildingBody() }
            if b.isOperating {
                switch b.kind {
                case .house:
                    if snapshot.population>8 { children += [.line(prefix+"-clothes-line",[(-32,18),(29,18)],"#766C51"),.rect(prefix+"-cloth",18,9,9,9,"#9EA9BB")] }
                case .granary:
                    for i in 0..<(snapshot.grainBand*3) { children.append(.ellipse(prefix+"-sack-\(i)",18+Double(i%3)*10,2+Double(i/3)*10,12,12,"#C2AB74",stroke:"#8B805C")) }
                case .market:
                    for i in 0..<effective+1 {
                        let x = -44.0+Double(i)*27
                        children += [.rect(prefix+"-stall-\(i)",x,-3,23,14,"#B99367"),.polygon(prefix+"-awning-\(i)",[(x-2,11),(x+5,23),(x+19,23),(x+25,11)],i%2==0 ? "#A67362" : "#748F88")]
                    }
                case .workshop:
                    children += [.rect(prefix+"-chimney",22,46,10,20,"#849185"),.polygon(prefix+"-anvil",[(25,0),(43,0),(38,11),(45,15),(20,15),(30,10)],"#536967")]
                    if snapshot.workingResources.contains("tools") { children.append(.ellipse(prefix+"-fire",-25,4,9,11,"#D39859")) }
                case .tavern:
                    children += [.rect(prefix+"-flagpole",42,8,2,35,"#6F6F52"),.rect(prefix+"-flag",44,27,15,16,"#A47350"),.ellipse(prefix+"-jar",25,2,14,17,"#967D57")]
                case .barracks:
                    // Empty authorized ranks are not rendered as actual people.
                    for i in 0..<max(1,(snapshot.legionActive+29)/30) {
                        let x = -35.0+Double(i)*28
                        children.append(.polygon(prefix+"-tent-\(i)",[(x,0),(x+12,20),(x+24,0)],"#A99F7C"))
                    }
                    children += [.line(prefix+"-banner-pole",[(46,0),(46,56)],"#5A6D5A",width:2),.rect(prefix+"-banner",47,39,17,15,"#8A6658")]
                case .stable:
                    children += [.rect(prefix+"-fence",-42,-1,84,4,"#9C8A65"),.rect(prefix+"-trough",17,1,20,8,"#8C927A")]
                case .station:
                    children.append(.rect(prefix+"-route-sign",40,13,17,8,"#AF9D6B"))
                default:break
                }
            }
        }
        if let project {
            let phase=project.phase
            if phase<=1 {
                children += [.rect(prefix+"-foundation",-44,0,88,8,"#AFA482"),.rect(prefix+"-materials",26,7,18,9,"#A47A51")]
            }
            if phase>=1 {
                for x in [-42.0,0,42] { children.append(.line(prefix+"-scaffold-\(x)",[(x,0),(x,59)],"#B18D59",width:2)) }
                children.append(.line(prefix+"-crossbeam",[(-46,34),(46,34)],"#A88452",width:2))
            }
            children.append(.rect(prefix+"-progress-bg",-39,-9,78,4,"#7F8F7B",radius:1))
            children.append(.rect(prefix+"-progress",-39,-9,78*project.fraction,4,project.status == .paused ? "#A37362" : "#D5B773",radius:1))
            if project.status == .paused || project.status == .waiting {
                children += [.rect(prefix+"-paused-a",-4,12,3,12,"#A76C57"),.rect(prefix+"-paused-b",2,12,3,12,"#A76C57")]
            }
        }
        return .init(prefix+"-art",transform:.init(x:p.x,y:p.y),children:children)
    }
    public static func svg(_ snapshot:CityAppearanceSnapshot)->String {
        var body=SVG.node(background(snapshot))
        for b in snapshot.buildings.sorted(by:{position($0.plot).y>position($1.plot).y}) { body += SVG.node(building(b,snapshot:snapshot)) }
        var labels=""
        for b in snapshot.buildings {
            let p=position(b.plot)
            let project=snapshot.projects.first{$0.buildingID==b.id}
            let text=project.map { "\(b.kind.title)·\($0.phaseTitle)" } ?? "\(b.kind.title) \(b.level)级"
            labels += "<text x=\"\(p.x)\" y=\"\(300-p.y+18)\" text-anchor=\"middle\" font-family=\"Noto Sans CJK SC, PingFang SC, sans-serif\" font-size=\"9\" fill=\"#40594d\">\(SVG.escape(text))</text>"
        }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 960 300\" width=\"960\" height=\"300\" role=\"img\" aria-label=\"游戏内城市状态，不是Mac截图\"><g transform=\"translate(0 300) scale(1 -1)\">\(body)</g>\(labels)</svg>"
    }
}

public enum TownProjectionSnapshotAdapter {
    public static func make(_ s:CityAppearanceSnapshot)->TownProjection {
        var p=TownProjection(cityID:s.cityID,title:s.name,actors:[],hasWorkshop:s.buildings.contains{$0.kind == .workshop && $0.isOperating},
                             hasField:s.buildings.contains{$0.kind == .farm && $0.isOperating},isDemo:false)
        p.appearance=s;return p
    }
}
