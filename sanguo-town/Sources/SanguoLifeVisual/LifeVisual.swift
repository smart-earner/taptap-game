import Foundation
import SanguoLife
import SanguoPresentation

public struct LifeArtElement: Sendable {
    public var id:String, art:VNode
    public var depth:Double
    public var title:String
    public var point:LifePoint
}
public struct LifeActorFrame: Sendable {
    public var id:String, name:String, action:String
    public var position:LifePoint, facing:Double, phase:Double, distance:Double
    public var costume:Costume, motion:Motion
    public var cargo:LifeResource?, quantity:Int64
    public var sleeping:Bool
}
/// Read-only, shared between SpriteKit and recorded HTML. Never mutates the simulation.
public enum LifeVisual {
    public static let width=1920.0, height=1080.0
    public static let jobNames=["prefect":"太守","farmer":"农夫","logger":"伐木工","miner":"矿工","cook":"厨师","porter":"挑夫","builder":"营造工","carpenter":"木匠","clerk":"仓吏","handyman":"杂役","guard_day":"日巡","guard_night":"夜巡","guard":"巡兵","flex":"机动居民","courier":"驿卒","smith":"铁匠","rationer":"制粮工","merchant":"商贩","server":"堂役"]
    public static func scene(_ w:LifeWorld) -> [LifeArtElement] {
        let night=w.isNight, earth=night ? "#455956":"#B1BC82",road=night ? "#647370":"#DCCBA3"
        var elements:[LifeArtElement]=[]
        func put(_ id:String,_ art:VNode,_ depth:Double=0,_ title:String="",_ point:LifePoint = .init(0,0)) {
            elements.append(.init(id:id,art:art,depth:depth,title:title,point:point))
        }
        var ground:[VNode]=[
            .rect("meadow",0,0,width,height,earth,radius:30),
            .polygon("river",[(1790,0),(1870,0),(1810,350),(1900,660),(1880,1080),(1815,1080),(1815,680),(1730,355)],night ? "#38596A":"#83B9B6",stroke:"none"),
            .rect("city-earth",735,330,980,640,night ? "#57675F":"#C9C99D",radius:45),
            .rect("fields-soil",165,305,335,290,night ? "#5B6250":"#938D59",radius:12)]
        for y in [220.0,660.0,1010.0] {ground.append(.line("road-\(y)",[(100,y),(1740,y)],road,width:20))}
        ground.append(.line("road-spine",[(700,120),(700,1040)],road,width:24))
        for (id,p) in LifeMap.places.sorted(by:{$0.key<$1.key}) {
            let y=[220.0,660.0,1010.0].min{abs($0-p.y)<abs($1-p.y)}!
            ground.append(.line("lane-"+id,[(p.x,p.y),(p.x,y)],road,width:10))
        }
        ground += [.line("wall-back",[(740,974),(1715,974),(1715,285)],night ? "#667575":"#9EA591",width:15),
                   .line("wall-front",[(735,285),(1450,285)],night ? "#667575":"#9EA591",width:15)]
        for i in 0..<30 {ground.append(.rect("wall-tooth\(i)",750+Double(i)*31,976,15,9,night ? "#728483":"#ACB09B"))}
        put("ground",.init("ground",children:ground),-10000)
        for i in 0..<24 {
            let x=115+Double(i%6)*34,y=825+Double(i/6)*48
            let ready=w.treeReady.indices.contains(i) && w.treeReady[i]>=0 && w.treeReady[i]<=w.time
            var a:[VNode]=[.rect("trunk\(i)",x-4,y,8,16,"#746147")]
            if ready {a += [.ellipse("leaves\(i)",x-18,y+12,36,30,night ? "#37534D":"#718C55"),.ellipse("leavesb\(i)",x-15,y+29,28,24,night ? "#42635B":"#86A167")]}
            put("tree\(i)",.init("tree\(i)",children:a),1100-y)
        }
        for f in w.fields.values.sorted(by:{$0.id<$1.id}) {
            let p=LifeMap.point(f.id)
            var a:[VNode]=[.rect(f.id+"bed",p.x-60,p.y+8,116,72,night ? "#5A5647":"#88774F",radius:4)]
            for row in 0..<4 {a.append(.line(f.id+"furrow\(row)",[(p.x-55,p.y+19+Double(row)*16),(p.x+50,p.y+19+Double(row)*16)],"#A99A64",width:3))}
            let grown=["growing1","water2","watering2","growing2","ripe","harvesting"].contains(f.state)
            if grown {
                let ripe=f.state=="ripe" || f.state=="harvesting"
                let mature=["growing2","ripe","harvesting"].contains(f.state)
                for i in 0..<24 {
                    let x=p.x-48+Double(i%6)*18,y=p.y+14+Double(i/6)*17
                    a.append(.line(f.id+"crop\(i)",[(x-4,y+5),(x,y+11),(x+4,y+5),(x,y),(x,y+(mature ? 16:9))],ripe ? "#E4C36A":(night ? "#91A36E":"#74A35A"),width:3))
                }
            }
            put(f.id,.init(f.id,children:a),1100-p.y,"\(f.crop=="rice" ? "水稻":"粟") · \(cropState(f.state))",p)
        }
        let buildings:[(String,String,String)]=[("hall","hall","府署"),("house","home","民居"),("farm","farm","农庄"),("granary","warehouse","粮仓"),("market","market","集市"),("workshop","workshop","工造院"),("tavern","tavern","饭馆"),("stable","stable","马厩"),("station","station","驿站"),("barracks","barracks","营地")]
        for (kind,node,title) in buildings {
            let p=LifeMap.point(node),count=w.buildings[kind,default:0]
            let live=w.projects.values.first{!$0.completed && $0.kind==kind}
            guard count>0 || live != nil else{continue}
            let stage=live?.phase
            var a=building(kind,at:p,night:night,phase:count>0 ? nil:stage)
            if kind=="house",count>1 {for i in 1..<min(count,4){a.children.append(building("house",at:.init(p.x+Double(i%2)*130-90,p.y-Double((i+1)/2)*110),night:night,phase:nil))}}
            if stage != nil {a.children += [.line(node+"scaffold",[(p.x-65,p.y),(p.x-65,p.y+85),(p.x+65,p.y+85),(p.x+65,p.y)],"#A48658",width:5)]}
            if night {a.children.append(.ellipse(node+"lantern",p.x+53,p.y+24,9,16,"#F3C976"))}
            put(node,a,1100-p.y,title+(live == nil ? "":" · 施工中"),p)
        }
        let kp=LifeMap.point("kitchen"),busy=w.stations["kitchen"]?.phase != "idle"
        var cook:[VNode]=[.rect("stove",kp.x-35,kp.y+4,70,38,night ? "#70736B":"#AF9B7A",radius:4),.ellipse("pot",kp.x-25,kp.y+28,48,14,"#3D4A44"),.rect("shelf",kp.x+36,kp.y+3,36,25,"#9B805D")]
        if busy {cook.append(.polygon("fire",[(kp.x-13,kp.y+10),(kp.x-5,kp.y+26),(kp.x,kp.y+19),(kp.x+8,kp.y+28),(kp.x+15,kp.y+10)],"#E6A251",stroke:"none"))}
        put("kitchen",.init("kitchen",children:cook),1100-kp.y,"公共灶 · "+(busy ? "备餐中":"按需开灶"),kp)
        let wp=LifeMap.point("well")
        put("well",.init("well",children:[.ellipse("well-base",wp.x-20,wp.y,40,22,"#7C8C86"),.ellipse("well-water",wp.x-12,wp.y+7,24,12,"#4A777D"),.line("well-frame",[(wp.x-24,wp.y),(wp.x-24,wp.y+50),(wp.x+24,wp.y+50),(wp.x+24,wp.y)],"#826B4F",width:5)]),1100-wp.y,"水井",wp)
        for id in ["mine","quarry"] {
            let p=LifeMap.point(id)
            put(id,.init(id,children:[.polygon(id+"rock",[(p.x-62,p.y),(p.x-40,p.y+45),(p.x-5,p.y+75),(p.x+25,p.y+35),(p.x+53,p.y)],night ? "#667475":"#9CA39A"),.polygon(id+"entrance",[(p.x-17,p.y),(p.x-10,p.y+30),(p.x+13,p.y+30),(p.x+23,p.y)],"#405354")]),1100-p.y,id=="mine" ? "矿区":"采石点",p)
        }
        for (id,s) in w.storages.sorted(by:{$0.key<$1.key}) {
            let lots=w.lots.values.filter{$0.location==id && $0.amount>0}.sorted{$0.id<$1.id}
            guard let lot=lots.first else{continue}
            let p=LifeMap.point(s.node),q=lots.reduce(Int64(0)){$0+$1.amount}
            for i in 0..<min(4,max(1,Int(q/4000))) {
                var art=cargo(lot.resource);art.id="stock-\(id)-\(i)";art.transform = .init(x:p.x+40+Double(i)*14,y:p.y-7,sx:0.75,sy:0.75)
                put(art.id,art,1101-p.y)
            }
        }
        if w.owned.contains("founders_seal") {
            let p=LifeMap.point("seal")
            put("seal",.init("display-seal",children:[.rect("display-table",p.x-16,p.y,32,19,"#75593E"),.rect("wooden-seal",p.x-7,p.y+19,14,17,"#C79B56"),.line("seal-mark",[(p.x-4,p.y+25),(p.x+4,p.y+25)],"#EBDCAB",width:3)]),1100-p.y,"开城木印 · 已入藏",p)
        }
        return elements.sorted{$0.depth == $1.depth ? $0.id<$1.id:$0.depth<$1.depth}
    }
    public static func building(_ kind:String,at p:LifePoint,night:Bool,phase:Int?) -> VNode {
        let id=kind+"-\(p.x)-\(p.y)",wall=night ? "#7F8173":"#E7D3AA",roof=night ? "#425C5A":"#6E8578"
        var a:[VNode]=[.ellipse(id+"shadow",p.x-70,p.y-10,148,33,night ? "#3C4E4B":"#899B75"),.rect(id+"base",p.x-63,p.y,126,9,"#8C9B87",radius:3)]
        if phase==0 {a.append(.rect(id+"materials",p.x-45,p.y+12,43,16,"#AF8D5C"));return .init(id,children:a)}
        if phase==1 {a.append(.line(id+"posts",[(p.x-54,p.y+6),(p.x-54,p.y+64),(p.x+54,p.y+64),(p.x+54,p.y+6)],"#9D825B",width:7));return .init(id,children:a)}
        a += [.rect(id+"wall",p.x-55,p.y+8,110,58,wall,stroke:"#7C7E67"),.rect(id+"door",p.x-13,p.y+8,26,36,"#5A6050"),.rect(id+"win",p.x+27,p.y+29,19,20,night ? "#DAB575":"#ABBA9C",stroke:"#6F7965"),.polygon(id+"roof",[(p.x-72,p.y+62),(p.x-48,p.y+89),(p.x+43,p.y+89),(p.x+72,p.y+62)],roof,stroke:"#4F6961")]
        if kind=="hall" {a.append(.polygon(id+"upper",[(p.x-38,p.y+86),(p.x-23,p.y+105),(p.x+20,p.y+105),(p.x+38,p.y+86)],roof))}
        if kind=="market" || kind=="tavern" {a += [.rect(id+"awning",p.x-65,p.y+16,30,26,"#B77352"),.rect(id+"table",p.x-75,p.y,48,12,"#AD8D57")]}
        if kind=="workshop" {a.append(.rect(id+"chimney",p.x+35,p.y+67,18,42,"#8B8270"))}
        return .init(id,children:a)
    }
    public static func cargo(_ r:LifeResource) -> VNode {
        switch r {
        case .wood:return .init("logs",children:[.rect("log-a",-20,5,40,8,"#AC8654",radius:4),.rect("log-b",-19,12,37,8,"#BE9B66",radius:4),.line("tie",[(0,4),(0,21)],"#675E40",width:3)])
        case .meal:return .init("tray",children:[.rect("tray-bottom",-17,1,34,4,"#956B46"),.ellipse("bowl",-12,5,24,10,"#E8D5AD"),.ellipse("rice",-10,9,20,6,"#F7ECCD")])
        case .iron,.stone:return .init("basket",children:[.rect("basket-body",-13,1,26,15,"#AA9168",radius:2),.polygon("ore",[(-9,16),(-4,24),(2,19),(8,25),(13,14)],r == .iron ? "#7D8890":"#A0A69A")])
        case .rations,.tools:return .init("box",children:[.rect("box-body",-14,1,28,22,r == .tools ? "#77958C":"#AA8B5A",stroke:"#5D6854"),.line("box-cross",[(-13,3),(13,22)],"#E2C98D",width:2)])
        case .grain,.meat:return .init("bag",children:[.ellipse("bag-body",-13,1,26,23,r == .grain ? "#D9BC77":"#B88B72"),.line("bag-tie",[(-7,22),(7,22)],"#776342",width:2)])
        }
    }
    public static func actor(_ a:LifeAgent,world w:LifeWorld,at time:Double) -> LifeActorFrame {
        let t=a.taskID.flatMap{w.tasks[$0]},p=t.flatMap{LifeMap.position($0,at:time)} ?? LifeMap.point(a.node)
        let cargoLots=t.map{task in w.lots.values.filter{$0.location==task.id}} ?? []
        let costume:Costume=a.job=="prefect" ? .official:((a.job.hasPrefix("guard") || a.heroID != nil) ? .warrior:.artisan)
        var action=a.job=="prefect" ? "处理城务":"等待调度",motion:Motion = a.job=="prefect" ? .read:.idle
        let sleeping=t==nil && a.node==a.home && a.restStart != nil
        if sleeping {action="在家休息"}
        if let t {
            if !t.current.route.isEmpty {motion = .walk;action=t.current.kind=="carry" ? "负重送货":"前往工作点"}
            else {
                switch t.kind {
                case "sow","water","harvest":motion = .cultivate;action=["sow":"播种","water":"浇灌","harvest":"收割"][t.kind]!
                case "gather","replant":motion=t.resource == .wood ? .chop:.hammer;action=t.kind=="replant" ? "补植林木":"采集整理"
                case "prepare","finish":motion = .hammer;action=t.job=="cook" ? "做饭出餐":"加工制作"
                case "build":motion = .hammer;action=t.job=="carpenter" ? "雕制木印":"营造施工"
                case "eat":motion = .read;action="用餐"
                case "patrol":motion = .idle;action="巡更值守"
                case "haul":motion = .carry;action=t.current.kind=="load" ? "装货":"卸货"
                case "recruit_prepare","recruit_finish":motion = .read;action="接待访贤"
                case "export":motion = .carry;action="对外交货"
                default:break
                }
            }
        }
        let elapsed=max(0,time-Double(t?.started ?? w.time)),before=t.flatMap{LifeMap.position($0,at:max(Double($0.started),time-0.05))}
        return .init(id:a.id,name:a.name,action:action,position:p,facing:before.map{p.x<$0.x ? -1:1} ?? 1,phase:elapsed,distance:elapsed*32,costume:costume,motion:motion,cargo:cargoLots.first?.resource,quantity:cargoLots.reduce(0){$0+$1.amount},sleeping:sleeping)
    }
    public static func cropState(_ s:String)->String { ["empty":"待播","sowing":"播种","water1":"等灌溉","watering1":"浇灌","growing1":"幼苗","water2":"待二灌","watering2":"二次浇灌","growing2":"抽穗","ripe":"已成熟","harvesting":"收割"][s] ?? s }
    public static func svg(_ w:LifeWorld,at time:Double?=nil) -> String {
        let clock=time ?? Double(w.time)
        var ordered:[(Double,String)]=scene(w).map{($0.depth,SVG.node($0.art))}
        for a in w.agents.values.sorted(by:{$0.id<$1.id}).prefix(96) {
            let f=actor(a,world:w,at:clock);if f.sleeping{continue}
            let pose=CharacterRig.pose(motion:f.motion,time:f.phase,distance:f.distance,facing:f.facing,item:.none,reducedMotion:false)
            var body=SVG.node(CharacterRig.artwork(f.costume),overrides:pose.transforms,hidden:pose.hidden)
            if let r=f.cargo {var c=cargo(r);c.transform = .init(x:0,y:25);body+=SVG.node(c)}
            ordered.append((1100-f.position.y,"<g transform=\"translate(\(f.position.x) \(f.position.y)) scale(.62)\">\(body)</g>"))
        }
        let shapes=ordered.sorted{$0.0<$1.0}.map(\.1).joined()
        let labels=scene(w).filter{!$0.title.isEmpty}.map{"<text x=\"\($0.point.x)\" y=\"\(height-$0.point.y+22)\" text-anchor=\"middle\" font-size=\"13\" fill=\"\(w.isNight ? "#EEE2BF":"#40584E")\">\(SVG.escape($0.title))</text>"}.joined()
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1920 1080\"><g transform=\"translate(0 1080) scale(1 -1)\">\(shapes)</g>\(labels)</svg>"
    }
}
