import Foundation
import SanguoLife
import SanguoPresentation

/// State-driven 2.5D artwork. Does not create buildings, workers or economic routes.
public enum LifeTownArt {
    public static func scene(_ w:LifeWorld)->[LifeArtElement] {
        let night=w.isNight
        var result:[LifeArtElement]=[]
        func put(_ id:String,_ art:VNode,_ p:LifePoint,_ title:String="",depth:Double?=nil) {
            result.append(.init(id:id,art:art,depth:depth ?? (1100-p.y),title:title,point:p))
        }
        put("landscape",terrain(night:night),.init(0,0),depth:-10000)
        for i in 0..<24 {
            let p=LifePoint(115+Double(i%6)*34,825+Double(i/6)*48)
            let ready=w.treeReady.indices.contains(i) && w.treeReady[i]>=0 && w.treeReady[i]<=w.time
            put("tree-\(i)",tree(id:"tree-\(i)",at:p,ready:ready,night:night,variant:i),p)
        }
        for f in w.fields.values.sorted(by:{$0.id<$1.id}) {
            let p=LifeMap.point(f.id)
            var a:[VNode]=[
                .rect("earth-edge",p.x-64,p.y+4,124,80,night ? "#394841":"#AD9E73",radius:9),
                .rect("earth",p.x-59,p.y+10,114,69,night ? "#3C3934":"#795E43",radius:6)]
            for row in 0..<5 {
                let y=p.y+17+Double(row)*12
                a.append(.line("furrow-\(row)",[(p.x-52,y),(p.x+49,y)],night ? "#585545":"#AF885B",width:3))
            }
            let grown=["growing1","water2","watering2","growing2","ripe","harvesting"].contains(f.state)
            if grown {
                let ripe=f.state=="ripe" || f.state=="harvesting"
                for i in 0..<30 {
                    let x=p.x-48+Double(i%6)*18,y=p.y+14+Double(i/6)*12
                    a += [.line("stem-\(i)",[(x,y),(x+1,y+13)],ripe ? "#D3B35B":"#678349",width:2),
                          .line("leaf-\(i)",[(x-5,y+10),(x,y+4),(x+6,y+12)],ripe ? "#EDD190":"#99B65C",width:2.5)]
                }
            }
            for x in [p.x-65,p.x+60] {a.append(.rect("post-\(x)",x,p.y+3,4,17,"#92774E",radius:1))}
            put(f.id,.init(f.id,children:a),p,"田畴")
        }
        let entries=[("hall","hall","府署"),("farm","farm","农庄"),("granary","warehouse","粮仓"),("market","market","集市"),("workshop","workshop","工造院"),("tavern","tavern","酒馆"),("stable","stable","马厩"),("station","station","驿站"),("barracks","barracks","营地")]
        for (kind,node,title) in entries {
            let project=w.projects.values.sorted{$0.id<$1.id}.first{!$0.completed && ($0.kind==kind || (kind=="hall" && $0.kind=="repair"))}
            let count=w.buildings[kind,default:0]
            guard count>0 || project != nil else{continue}
            let p=LifeMap.point(node)
            put(node,building(kind,at:p,night:night,level:1,phase:count>0 ? nil:project?.phase),p,title+(project == nil ? "":" · 营造"))
            if let project,count>0 {put(node+"-works",scaffold(at:p,phase:project.phase),p,depth:1102-p.y)}
        }
        let levels=w.gacha?.houseLevels ?? [1]
        for (i,level) in levels.enumerated() {
            let p=homePoint(i)
            put("home-\(i)",building("house",at:p,night:night,level:level,phase:nil),p,"民居 · \(["","一","二","三"][min(3,level)])阶")
        }
        for project in w.projects.values.filter({!$0.completed && $0.kind.hasPrefix("house")}).sorted(by:{$0.id<$1.id}) {
            let index=project.kind=="house" ? levels.count : (Int(project.id.split(separator:"-").dropFirst(2).first ?? "0") ?? 0)
            let p=homePoint(min(3,index))
            if project.kind=="house" {put("new-home",building("house",at:p,night:night,level:1,phase:project.phase),p,"新居 · 营造")}
            else {put("upgrade-home",scaffold(at:p,phase:project.phase),p,depth:1102-p.y)}
        }
        let well=LifeMap.point("well")
        put("well",.init("well",children:[
            .ellipse("shadow",well.x-29,well.y-8,65,23,"#819174"),
            .rect("stone",well.x-22,well.y,44,19,"#A4ABA0",radius:6),
            .ellipse("rim",well.x-23,well.y+10,46,22,"#CCD0B9"),
            .ellipse("water",well.x-16,well.y+15,32,12,"#497B78"),
            .line("frame",[(well.x-29,well.y),(well.x-29,well.y+64),(well.x+29,well.y+64),(well.x+29,well.y)],"#745C42",width:5),
            roof(id:"well-roof",x:well.x,y:well.y+56,half:41,color:"#526C68"),
            .line("rope",[(well.x,well.y+53),(well.x,well.y+24)],"#BDAC7D",width:2)]),well,"古井")
        let kitchen=LifeMap.point("kitchen"),cooking=["prepare","passive","finish"].contains(w.stations["kitchen"]?.phase ?? "")
        put("kitchen",workplace("kitchen",at:kitchen,night:night,active:cooking),kitchen,"炊烟处")
        for id in ["mine","quarry","goldmine"] {
            let p=LifeMap.point(id)
            put(id,mine(at:p,gold:id=="goldmine",night:night),p,id=="goldmine" ? "金矿":(id=="mine" ? "铁矿":"石场"))
        }
        let smelter=LifeMap.point("smelter"),lit=w.stations["smelter"]?.phase=="passive"
        put("smelter",workplace("smelter",at:smelter,night:night,active:lit),smelter,"冶金坊")
        for (id,s) in w.storages.sorted(by:{$0.key<$1.key}) {
            let lots=w.lots.values.filter{$0.location==id && $0.amount>0}.sorted{$0.id<$1.id}
            guard let lot=lots.first else{continue}
            let p=LifeMap.point(s.node),amount=lots.reduce(Int64(0)){$0+$1.amount}
            for i in 0..<min(3,max(1,Int(amount/4000))) {
                var art=LifeVisual.cargo(lot.resource,quality:lot.quality)
                art.id="stock-\(id)-\(i)";art.transform = .init(x:p.x+48+Double(i)*16,y:p.y-10,sx:0.75,sy:0.75)
                put(art.id,art,p,depth:1103-p.y)
            }
        }
        return result.sorted{$0.depth == $1.depth ? $0.id<$1.id:$0.depth<$1.depth}
    }
    public static func homePoint(_ index:Int)->LifePoint {
        let p=LifeMap.point("home")
        // Existing save uses one shared residential entrance; facades are in the same courtyard.
        return [.init(p.x,p.y),.init(p.x+185,p.y),.init(p.x+370,p.y),.init(p.x+555,p.y)][min(3,max(0,index))]
    }
    public static func terrain(night:Bool)->VNode {
        let green=night ? "#263E3E":"#B9C6A0",road=night ? "#66716A":"#DED4B6"
        var a:[VNode]=[.rect("meadow",0,0,1920,1080,green),
            .polygon("distant-bank",[(0,970),(240,1045),(640,1000),(920,1080),(0,1080)],night ? "#294343":"#A6BB91",stroke:"none"),
            .polygon("south-meadow",[(0,0),(1720,0),(1670,145),(1100,100),(800,180),(340,80),(0,190)],night ? "#2C4844":"#9FB68A",stroke:"none"),
            .rect("courtyard",785,700,850,272,night ? "#44534B":"#C8CBA9",radius:55),
            .polygon("river-bank",[(1765,0),(1738,265),(1790,535),(1805,840),(1755,1080),(1920,1080),(1920,0)],night ? "#496660":"#D8D7AD",stroke:"none"),
            .polygon("river",[(1791,0),(1767,265),(1820,535),(1834,840),(1784,1080),(1920,1080),(1920,0)],night ? "#315A65":"#6DA8A6",stroke:"none")]
        for i in 0..<130 {
            let x=Double((i*137+31)%1730),y=Double((i*233+71)%1080)
            a.append(.ellipse("grass-wash-\(i)",x,y,20+Double(i%4)*11,7+Double(i%3)*5,night ? "#314B44":"#AFBF98"))
            if i%3==0 {a.append(.line("grass-\(i)",[(x,y),(x-3,y+5),(x,y),(x+4,y+6)],night ? "#456052":"#8BA477",width:1.5))}
        }
        for i in 0..<20 {
            let y=Double(i)*53+14,x=1850+Double(i%3)*15
            a.append(.line("ripple-\(i)",[(x,y),(x+28,y+2),(x+48,y)],night ? "#487680":"#A4CCBB",width:2))
        }
        var roads:[[(Double,Double)]]=[]
        for y in [220.0,660.0,1010.0] {roads.append([(85,y),(1740,y)])}
        roads.append([(700,115),(700,1040)])
        // Exact route centerlines used by LifeMap.path; appearance does not shorten travel.
        for (_,p) in LifeMap.places.sorted(by:{$0.key<$1.key}) {
            let y=[220.0,660.0,1010.0].min{abs($0-p.y)<abs($1-p.y)}!
            roads.append([(p.x,p.y),(p.x,y)])
        }
        for (i,points) in roads.enumerated() {
            let width=i<4 ? 25.0:13.0
            a += [.line("road-edge-\(i)",points,night ? "#43554F":"#AAA886",width:width+6),
                  .line("road-\(i)",points,road,width:width),
                  .line("road-light-\(i)",points,night ? "#758078":"#ECE2C7",width:1)]
        }
        for row in [220.0,660.0,1010.0] {
            for i in 0..<55 {let x=100+Double(i)*30
                a.append(.line("paver-\(row)-\(i)",[(x,row-9),(x-3,row+9)],night ? "#59675F":"#C9BE9F",width:1))}
        }
        // Residential garden walk is decorative: all residents still use the saved shared entrance.
        a.append(.line("garden-walk",[(920,885),(1500,885)],road,width:10))
        for y in [330.0,410.0,490.0,570.0,750.0,830.0,910.0] {
            a += [.rect("wall-side-\(y)",1700,y,14,65,night ? "#4A5C57":"#8E9C88",radius:3),
                  .rect("wall-cap-\(y)",1697,y+4,20,61,night ? "#637169":"#C6CAB0",radius:2)]
        }
        for x in stride(from:800.0,through:1600.0,by:160) {
            a.append(.ellipse("hedge-\(x)",x,956,66,23,night ? "#344D42":"#809A6B"))
        }
        for (i,p) in [LifePoint(655,650),.init(745,650),.init(1525,220),.init(1615,220)].enumerated() {
            a += [.rect("lantern-post-\(i)",p.x,p.y,4,43,"#776449"),
                  .rect("lantern-top-\(i)",p.x-5,p.y+43,14,4,"#4C6259",radius:2),
                  .rect("lantern-\(i)",p.x-3,p.y+29,10,14,night ? "#F2CD82":"#B66E46",radius:3)]
        }
        return .init("terrain",children:a)
    }
    public static func tree(id:String,at p:LifePoint,ready:Bool,night:Bool,variant:Int)->VNode {
        var a:[VNode]=[.ellipse("shade",p.x-22,p.y-6,51,16,night ? "#243B37":"#8FA37D"),
            .rect("trunk",p.x-4,p.y,9,38,"#806849",radius:2),
            .line("branch",[(p.x,p.y+17),(p.x-10,p.y+32)],"#806849",width:4)]
        if ready {
            let shades=night ? ["#36564A","#416555","#56735C"]:["#668958","#80A16A","#9EB77A"]
            a += [.ellipse("back",p.x-29,p.y+24,56,47,shades[0]),
                  .ellipse("left",p.x-37,p.y+29,36,32,shades[1]),
                  .ellipse("top",p.x-21,p.y+47,43,32,shades[1]),
                  .ellipse("light",p.x-18,p.y+57,28,16,shades[2]),
                  .ellipse("right",p.x+8,p.y+30,25,27,shades[0])]
        } else {a.append(.ellipse("cut",p.x-5,p.y+7,12,5,"#C5AA7B"))}
        return .init(id,children:a)
    }
    static func roof(id:String,x:Double,y:Double,half:Double,color:String)->VNode {
        var a:[VNode]=[
            .polygon(id+"-under",[(x-half-5,y-5),(x+half+7,y-5),(x+half+10,y+2),(x-half-8,y+2)],"#304C4B",stroke:"none"),
            .polygon(id+"-tiles",[(x-half-8,y+3),(x-half+12,y+14),(x-half+26,y+40),(x+half-23,y+40),(x+half-9,y+14),(x+half+10,y+3)],color,stroke:"#385553",width:1),
            .line(id+"-ridge",[(x-half+23,y+41),(x+half-21,y+41)],"#ABC0AC",width:4)]
        for i in 0..<7 {let t=Double(i)/6,x0=x-half+24+t*(2*half-47),x1=x-half+6+t*(2*half-12)
            a.append(.line(id+"-seam-\(i)",[(x0,y+37),(x1,y+4)],"#80998B",width:1.5))}
        for row in 0..<3 {let yy=y+9+Double(row)*9
            a.append(.line(id+"-row-\(row)",[(x-half+14+Double(row)*5,yy),(x+half-13-Double(row)*5,yy)],"#405F5B",width:1))}
        return .init(id,children:a)
    }
    public static func building(_ kind:String,at p:LifePoint,night:Bool,level:Int=1,phase:Int?=nil)->VNode {
        let half=kind=="hall" ? 83.0:(kind=="granary" ? 76:67)
        let wall=night ? "#8B8970":"#E9D9B4",timber=night ? "#655849":"#886C4C",tile=night ? "#385450":"#557C73"
        let top=level>=3 ? 105.0:72.0
        var a:[VNode]=[.ellipse("shadow",-half-12,-15,half*2+46,38,night ? "#283C36":"#8C9C7B"),
            .polygon("foundation",[(-half-7,0),(half+16,0),(half+26,13),(-half+3,13)],night ? "#59675D":"#AFB79B",stroke:"none"),
            .rect("step",-28,-9,58,12,night ? "#6D796C":"#D0CEAD",radius:3)]
        if phase==0 {
            a += [.rect("timber-stack",-44,12,75,9,"#BA9360",radius:3),.rect("timber-stack2",-34,24,55,8,"#A48253",radius:3),.rect("stones",33,12,23,16,"#A5AC98",radius:3)]
        } else if phase==1 {
            a += [.line("frame",[(-half+10,6),(-half+10,top),(half-10,top),(half-10,6)],timber,width:7),
                  .line("roof-frame",[(-half-8,top),(-20,top+40),(20,top+40),(half+8,top)],timber,width:5)]
        } else {
            a += [.rect("front-wall",-half+8,9,half*2-16,top-4,wall,radius:2),
                  .polygon("side-wall",[(half-8,9),(half+14,23),(half+14,top+8),(half-8,top)],night ? "#6C7463":"#BEBD97",stroke:"none"),
                  .rect("sill",-half+8,9,half*2-16,8,timber),
                  .rect("door",-17,10,34,45,night ? "#D7B071":"#4E6255",radius:3),
                  .line("door-split",[(0,12),(0,52)],timber,width:2)]
            for x in [-half+9,half-12] {a.append(.rect("column-\(x)",x,10,5,top-5,timber))}
            for x in [-half+25,half-41] {
                a += [.rect("window-\(x)",x,34,20,24,night ? "#EDC984":"#93A38A",radius:2,stroke:timber),
                      .line("lattice-v-\(x)",[(x+10,34),(x+10,58)],timber,width:2),
                      .line("lattice-h-\(x)",[(x,46),(x+20,46)],timber,width:2)]
            }
            if level>=2 {
                a += [.line("veranda",[(-half-6,0),(-half-6,55),(half+8,55),(half+8,0)],timber,width:4),
                      .rect("balustrade",-half-9,0,27,5,timber),.rect("balustrade2",half-17,0,27,5,timber)]
            }
            if level>=3 {
                a.append(.line("upper-floor",[(-half+8,70),(half-8,70)],timber,width:5))
                for x in [-34.0,15.0] {a.append(.rect("upper-window-\(x)",x,80,21,16,night ? "#EAC57D":"#81977C",radius:2,stroke:timber))}
            }
            if phase != 2 {a.append(roof(id:"roof",x:0,y:top,half:half,color:tile))}
            if kind=="hall" {a.append(roof(id:"hall-upper",x:0,y:top+37,half:42,color:tile));a.append(.rect("plaque",-20,top-13,40,12,"#39564F",radius:2))}
            if kind=="tavern" || kind=="market" {
                a += [.polygon("awning",[(-half-8,24),(-half-2,49),(half-5,49),(half+3,24)],"#B76F49",stroke:"none"),
                      .line("awning-trim",[(-half-8,24),(half+3,24)],"#E3C58D",width:4),
                      .rect("table",-half-16,-5,30,8,"#92724B",radius:2),
                      .ellipse("jar",half-7,0,23,32,"#876A4E"),.ellipse("jar-rim",half-2,28,13,5,"#D4BB87")]
            }
            if kind=="granary" {
                for i in 0..<3 {a.append(.ellipse("grain-sack-\(i)",-half+Double(i)*21,-3,20,26,"#CEB67C"))}
            }
            if kind=="farm" {a += [.line("tool",[(half+12,4),(half+19,54)],timber,width:3),.rect("rack",-half-10,1,24,22,"#B59965",radius:3)]}
            if kind=="workshop" {a += [.rect("chimney",half-29,top+19,19,44,"#7F7B69"),.rect("bench",half-10,-5,40,15,"#997851",radius:2)]}
            if kind=="house" {a += [.rect("planter",-half+8,-4,18,13,"#AD7652",radius:3),.ellipse("plant",-half+4,7,25,16,"#638554")]}
            for x in [-half+9,half-13] {a.append(.rect("lantern-\(x)",x,top-23,8,14,night ? "#F8CD7D":"#B36B47",radius:3))}
        }
        return .init("building-\(kind)-\(p.x)-\(p.y)",transform:.init(x:p.x,y:p.y),children:a)
    }
    static func scaffold(at p:LifePoint,phase:Int)->VNode {
        var a:[VNode]=[.line("poles",[(-80,0),(-80,125),(83,125),(83,0)],"#B39462",width:4),
            .line("cross",[(-80,5),(83,110),(-80,110),(83,5)],"#9D8057",width:2),
            .line("platform",[(-88,64),(89,64)],"#CCB381",width:7)]
        for i in 0..<4 {a.append(.line("ladder-\(i)",[(70,Double(i)*15),(82,Double(i)*15)],"#755E43",width:2))}
        return .init("scaffold-\(phase)",transform:.init(x:p.x,y:p.y),children:a)
    }
    static func mine(at p:LifePoint,gold:Bool,night:Bool)->VNode {
        var a:[VNode]=[.ellipse("shadow",-68,-9,150,31,night ? "#2B3B36":"#8D9B7C"),
            .polygon("rock",[(-66,0),(-57,44),(-32,73),(5,86),(47,49),(65,0)],night ? "#616C64":"#999D8B",stroke:"none"),
            .polygon("light-face",[(-57,44),(-32,73),(5,86),(-12,40),(-22,0),(-66,0)],night ? "#778073":"#BABC9F",stroke:"none"),
            .polygon("dark-face",[(5,86),(47,49),(65,0),(20,6),(-12,40)],night ? "#4F605C":"#7F8D7B",stroke:"none"),
            .rect("opening",-23,0,47,42,"#334744",radius:16),
            .line("beams",[(-28,0),(-28,46),(29,46),(29,0)],"#99774A",width:7),
            .line("track-a",[(-15,13),(-27,-16)],"#6B6F5C",width:3),
            .line("track-b",[(14,13),(24,-16)],"#6B6F5C",width:3)]
        if gold {a.append(.line("gold-vein",[(-46,35),(-31,48),(-37,61),(-21,68)],"#E0BA64",width:5))}
        return .init("mine",transform:.init(x:p.x,y:p.y),children:a)
    }
    static func workplace(_ kind:String,at p:LifePoint,night:Bool,active:Bool)->VNode {
        let furnace=kind=="smelter"
        var a:[VNode]=[.ellipse("shadow",-69,-12,148,32,night ? "#2F413B":"#90A17D"),
            .rect("platform",-60,0,125,10,"#A6AB90",radius:4),
            .rect("oven",-29,8,64,furnace ? 75:38,"#977B60",radius:9),
            .rect("door",-17,11,35,27,active ? "#C86B38":"#3C4C44",radius:9),
            .line("bands",[(-29,48),(34,48)],"#655D4E",width:5),
            .rect("table",39,3,34,25,"#9D7B4C",radius:3)]
        if furnace {a += [.rect("chimney",10,68,22,65,"#7A7966"),.rect("chimney-lip",6,130,30,7,"#A4A58D",radius:2)]}
        else {a += [.ellipse("pot",-24,37,54,17,"#334C47"),.line("shelter",[(-55,5),(-55,94),(64,94),(64,5)],"#8D744F",width:4),roof(id:"canopy",x:4,y:87,half:72,color:"#6B8266")]}
        if active {
            a += [.polygon("flame",[(-11,12),(-9,30),(-3,21),(3,37),(13,12)],"#F2BC65",stroke:"none"),
                  .ellipse("smoke-a",16,furnace ? 140:132,20,13,night ? "#80938A":"#D4D5BB"),
                  .ellipse("smoke-b",25,furnace ? 158:146,28,17,night ? "#657D75":"#E2E1CB")]
        }
        return .init(kind,transform:.init(x:p.x,y:p.y),children:a)
    }
}
