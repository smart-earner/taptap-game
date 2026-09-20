import Foundation

public enum TownArt {
    public static let width = 960.0, height = 300.0
    public static func background(_ projection: TownProjection) -> VNode {
        var a: [VNode] = [
            .rect("sky",0,0,960,300,"#E7EDDD"),
            .ellipse("sun",775,225,45,45,"#F4D6A1"),
            .polygon("far-mountains",[(0,198),(85,266),(148,222),(250,277),(340,207),(423,251),(525,208),(616,264),(750,214),(866,268),(960,231),(960,0),(0,0)],"#B8CABB",stroke:"none"),
            .polygon("near-mountains",[(0,176),(105,224),(194,190),(320,236),(452,186),(575,223),(700,184),(818,234),(960,187),(960,0),(0,0)],"#94B1A1",stroke:"none"),
            .rect("ground",0,0,960,166,"#A9B692"),
            .rect("street",0,54,960,45,"#D5C6A7"),
            .line("street-edge",[(0,54),(960,54)],"#B0AA8A",width:2)]
        for (i,x) in [75.0,225,455,700].enumerated() {
            a.append(.rect("alley-\(i)",x-13,85,26,55,"#D5C6A7"))
        }
        for i in 0..<26 {
            let x = Double(i)*39 + 9, y = 60 + Double((i*7)%25)
            a.append(.line("paving-\(i)",[(x,y),(x+13,y)],"#C0B498",width:1))
        }
        a.append(building("hall",x:225,base:140,w:132,h:65,roof:"#3C6062"))
        a.append(building("store",x:75,base:134,w:98,h:48,roof:"#80724B"))
        if projection.hasWorkshop {
            a.append(building("forge",x:455,base:140,w:142,h:49,roof:"#73594C"))
            a.append(.rect("chimney",485,193,15,28,"#8D8E7D",stroke:"#55676A"))
            a.append(.rect("forge-fire",411,142,20,20,"#C27943",radius:3))
            a.append(.ellipse("forge-glow",415,144,12,12,"#E5B466"))
            a.append(.polygon("anvil",[(472,128),(492,128),(488,134),(487,142),(503,145),(503,150),(477,149),(468,145),(479,140),(479,134)],"#506369"))
        } else {
            a.append(.rect("empty-workshop",390,132,134,15,"#929F85"));
            a.append(.line("planned-workshop",[(390,136),(523,136)],"#D8CFAD",width:2))
        }
        if projection.hasField {
            a.append(.polygon("field-soil",[(643,116),(786,116),(751,165),(655,165)],"#857C50",stroke:"#8C9666"))
            for row in 0..<3 { for col in 0..<9 {
                let x = 653 + Double(col)*13 + Double(row)*4, y = 120 + Double(row)*13
                a.append(.line("crop-\(row)-\(col)",[(x-3,y+4),(x,y),(x+4,y+9)],"#CBCB74",width:2))
            } }
        }
        a.append(.rect("gate-left",862,105,16,75,"#887D68",stroke:"#5A695F"))
        a.append(.rect("gate-right",937,105,16,75,"#887D68",stroke:"#5A695F"))
        a.append(.polygon("gate-roof",[(851,178),(875,193),(945,193),(960,178)],"#52716B"))
        a.append(.rect("wood-stack",782,102,33,20,"#8C6449",radius:3,stroke:"#5C5341"))
        for i in 0..<3 { a.append(.ellipse("log-\(i)",784+Double(i)*10,103,9,9,"#C49C6C",stroke:"#7E6549")) }
        a.append(.polygon("ore",[(540,103),(535,116),(548,127),(561,121),(570,103)],"#86948A"))
        return .init("town-background", children:a)
    }
    public static func foreground() -> VNode {
        .init("tree",transform:.init(x:594,y:62),children:[
            .ellipse("tree-shadow",-38,-6,76,13,"#8A9F81"),
            .polygon("tree-trunk",[(-5,0),(5,0),(5,49),(13,66),(7,65),(-1,48),(-9,62),(-11,57),(-5,43)],"#756443"),
            .ellipse("leaves-left",-38,48,60,44,"#5E8163"),
            .ellipse("leaves-right",-6,54,49,38,"#668C64"),
            .ellipse("leaves-top",-24,69,55,36,"#789A6A"),
            .line("leaf-light",[(-19,89),(-7,96),(7,94)],"#A2B67A",width:3)])
    }
    private static func building(_ id:String,x:Double,base:Double,w:Double,h:Double,roof:String) -> VNode {
        var pieces: [VNode] = [
            .rect(id+"-shadow",-w/2-5,-4,w+10,9,"#87997F",radius:3),
            .rect(id+"-wall",-w/2,0,w,h,"#D9CCAA",stroke:"#786F57"),
            .rect(id+"-beam",-w/2,h-6,w,7,"#826044"),
            .rect(id+"-pillar1",-w/2+5,0,5,h,"#866449"),
            .rect(id+"-pillar2",w/2-10,0,5,h,"#866449"),
            .rect(id+"-door",-13,0,26,h*0.66,"#655A42",radius:2),
            .line(id+"-door-mid",[(0,1),(0,h*0.64)],"#A68B60"),
            .rect(id+"-window",w/2-34,17,19,22,"#9CA68A",stroke:"#806F4F"),
            .line(id+"-lattice",[(w/2-25,17),(w/2-25,39)],"#806F4F"),
            .polygon(id+"-roof",[(-w/2-15,h-2),(-w/2+4,h+7),(-w/2+17,h+26),(w/2-17,h+26),(w/2-4,h+7),(w/2+15,h-2)],roof),
            .line(id+"-ridge",[(-w/2+16,h+27),(w/2-16,h+27)],"#ADC0A8",width:2),
            .line(id+"-eave",[(-w/2-11,h),(w/2+11,h)],"#9AA992",width:2)]
        for i in 1..<7 {
            let px = -w/2 + Double(i)*w/8
            pieces.append(.line(id+"-tile-\(i)",[(px,h+4),(px*0.75,h+23)],"#A0AE97",width:0.65))
        }
        return .init(id,transform:.init(x:x,y:base),children:pieces)
    }
    /// Uses exactly the same rig, pose, paths and depth order as the SpriteKit adapter, not a screenshot.
    public static func svg(director: TownDirector, item: HandItem = .spear, reducedMotion: Bool = false, includeHiddenParts: Bool = false) -> String {
        guard let projection = director.projection else { return "" }
        var s = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"960\" height=\"300\" viewBox=\"0 0 960 300\" role=\"img\" aria-label=\"Sanguo original vector animation preview\"><g transform=\"translate(0 300) scale(1 -1)\">"
        s += SVG.node(background(projection))
        var entities: [(Double,String,String)] = [(500-62,"tree",SVG.node(foreground()))]
        for (id,actor) in director.actors {
            let pose = CharacterRig.pose(motion:actor.motion,time:actor.phaseTime,distance:actor.distance,
                facing:actor.facing,item:projection.isDemo && actor.spec.costume == .warrior ? item : .none,reducedMotion:reducedMotion)
            let art = SVG.node(CharacterRig.artwork(actor.spec.costume),overrides:pose.transforms,hidden:includeHiddenParts ? [] : pose.hidden)
            entities.append((actor.depth,id,"<g data-actor=\"\(SVG.escape(id))\" transform=\"translate(\(SVG.number(actor.position.x)) \(SVG.number(actor.position.y)))\">\(art)</g>"))
        }
        s += entities.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }.map(\.2).joined()
        s += "</g><text x=\"24\" y=\"28\" font-family=\"sans-serif\" font-size=\"16\" fill=\"#304B48\">SANGUO TOWN / ORIGINAL 2D RIG</text>"
        s += "<text x=\"24\" y=\"287\" font-family=\"sans-serif\" font-size=\"12\" fill=\"#52674E\">\(projection.isDemo ? "ANIMATION SAMPLE - NO SAVE CHANGES" : "READ-ONLY CITY PRESENTATION") / t=\(SVG.number(director.visibleTime))s</text></svg>"
        return s
    }
}
