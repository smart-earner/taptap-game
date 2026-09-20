import Foundation
import SanguoCore

/// Stable plot IDs retain ownership; a versioned presentation plan groups them into courtyards.
/// All road segments run in front of entrances and around footprints. No policy-driven reshuffle.
public enum TownLayout {
    public static let positions: [VPoint] = [
        .init(307,202), .init(267,78), .init(377,58), .init(432,201),
        .init(55,210), .init(157,182), .init(55,94), .init(157,53),
        .init(547,211), .init(665,218), .init(550,56), .init(665,126),
        .init(801,200), .init(785,73), .init(899,196), .init(893,56)
    ]
    public static func position(_ plot: Int) -> VPoint {
        positions.indices.contains(plot) ? positions[plot] : .init(480,150)
    }
    public static var roads: RoadGraph {
        var points: [String: VPoint] = [:], edges: [(String,String)] = []
        func chain(_ prefix: String, _ coords: [VPoint]) {
            for (i,p) in coords.enumerated() {
                points["\(prefix)\(i)"] = p
                if i>0 { edges.append(("\(prefix)\(i-1)", "\(prefix)\(i)")) }
            }
        }
        chain("main", [20,55,157,210,307,432,480,547,606].map { .init(Double($0),158) })
        chain("east", [.init(606,158),.init(606,100),.init(665,100),.init(725,100),
                        .init(725,158),.init(801,158),.init(899,158),.init(945,158)])
        edges.append(("main8","east0"))
        chain("south", [20,55,157,267,377,480,550,725,785,893,945].map { .init(Double($0),26) })
        edges += [("main6","south5"),("east3","south7")]
        chain("court", [.init(725,158),.init(725,202),.init(665,202)])
        edges.append(("court0","east4"))
        let anchors = ["main4","south3","south4","main5","main1","main2","south1","south2",
                       "main7","court2","south6","east2","east5","south8","east6","south9"]
        for plot in positions.indices {
            points["plot-\(plot)"] = positions[plot]
            edges.append((anchors[plot],"plot-\(plot)"))
        }
        points["gate"] = .init(945,158); edges.append(("gate","east7"))
        return .init(points:points,edges:edges)
    }
    public static func background(_ s: CityAppearanceSnapshot) -> VNode {
        var nodes: [VNode] = [
            .rect("identity-sky",0,0,960,300,"#EEF0E6"),
            .polygon("identity-ridges",[(0,273),(100,296),(165,276),(250,300),(395,277),(530,297),(670,273),(830,295),(960,278),(960,0),(0,0)],"#AFBFB0",stroke:"none"),
            .rect("identity-fields",7,23,194,249,"#B7C9A0",radius:18),
            .polygon("identity-town-ground",[(215,17),(927,17),(943,41),(943,256),(923,279),(233,279),(211,257)],"#D9D8BC",stroke:"#A3AF92",width:2),
            .rect("identity-residential-yard",222,35,247,234,"#D0D2AC",radius:18),
            .rect("identity-market-yard",510,30,209,240,"#DBCCA9",radius:18),
            .rect("identity-camp-yard",746,30,187,234,"#C7C7A6",radius:14),
            .line("identity-wall-north",[(215,274),(936,274),(946,258)],"#859A8D",width:7),
            .line("identity-wall-west",[(210,274),(210,179)],"#859A8D",width:7),
            .line("identity-wall-west-south",[(210,139),(210,16),(938,16)],"#859A8D",width:6),
            .line("identity-wall-east",[(946,25),(946,142)],"#859A8D",width:6),
            .line("identity-wall-east-north",[(946,175),(946,257)],"#859A8D",width:6)
        ]
        let level = s.civic?.level(.streets) ?? 0
        let graph = roads
        for (i, edge) in graph.edges.enumerated() {
            guard let a=graph.points[edge.0],let b=graph.points[edge.1],a != b else {continue}
            nodes.append(.line("identity-road-\(i)",[(a.x,a.y),(b.x,b.y)],level>0 ? "#ADAFA0":"#CABD9E",width:level>0 ? 12:9))
        }
        for plot in positions.indices where !s.buildings.contains(where:{$0.plot==plot}) {
            let p=positions[plot]
            nodes.append(.line("identity-empty-\(plot)",[(p.x-16,p.y+8),(p.x-12,p.y+17),(p.x-7,p.y+9),(p.x+4,p.y+14)],"#95A07D",width:2))
        }
        nodes += civicDetails(s)
        return .init("identity-landscape",children:nodes)
    }
    public static func civicDetails(_ s: CityAppearanceSnapshot) -> [VNode] {
        guard let civic=s.civic else {return []}
        var nodes:[VNode]=[]
        let streets=civic.level(.streets),water=civic.level(.water),homes=civic.level(.homes)
        if streets>=2 {
            for (i,p) in [VPoint(224,159),.init(464,159),.init(727,105),.init(927,159)].enumerated() {
                nodes += [.rect("identity-lamp-pole-\(i)",p.x,p.y,2,20,"#766C54"),
                          .rect("identity-lamp-\(i)",p.x-3,p.y+15,8,9,"#D2A562",radius:2)]
            }
        }
        if streets>=3 { nodes += pavilion("identity-road-pavilion",.init(477,191),"#637E73") }
        if water>0 {
            nodes += [.line("identity-channel",[(12,168),(187,168),(187,39)],"#739D9A",width:Double(3+water)),
                      .ellipse("identity-well",180,227,19,10,"#A5B1A0",stroke:"#627F78")]
        }
        if water>=2 {nodes.append(.rect("identity-channel-bridge",183,148,12,20,"#BCA982"))}
        if water>=3 {
            nodes += [.ellipse("identity-water-wheel",167,87,21,21,"none",stroke:"#897453"),
                      .line("identity-water-spokes",[(169,90),(186,104),(169,104),(186,90)],"#897453",width:2)]
        }
        for b in s.buildings where b.kind == .house && b.isOperating && homes>0 {
            let p=position(b.plot),id="identity-yard-"+b.id
            nodes += [.line(id,[(p.x-49,p.y+10),(p.x-49,p.y-6),(p.x-9,p.y-6)],"#ACA081",width:3),
                      .line(id+"-right",[(p.x+10,p.y-6),(p.x+48,p.y-6),(p.x+48,p.y+10)],"#ACA081",width:3)]
            if homes>=2 {nodes.append(.ellipse(id+"-tree",p.x+38,p.y+9,13,20,"#769368"))}
            if homes>=3 {nodes.append(.rect(id+"-porch",p.x-31,p.y-3,20,9,"#B9AA7B",radius:2))}
        }
        for (track,kind) in [(CivicTrack.commerce,BuildingKind.market),(.industry,.workshop),(.academy,.hall)] {
            let n=civic.level(track)
            guard n>0, let b=s.buildings.first(where:{$0.kind==kind && $0.isOperating}) else {continue}
            let p=position(b.plot)
            for i in 0..<n {
                let x=p.x-37+Double(i)*25,y=p.y-9,id="identity-\(track.rawValue)-\(i)"
                nodes.append(.rect(id+"-goods",x,y,19,9,track == .industry ? "#A08664":"#BBAB7E",radius:2))
                if track == .commerce {
                    nodes.append(.polygon(id+"-awning",[(x-2,y+8),(x+4,y+18),(x+17,y+18),(x+22,y+8)],"#B58465"))
                } else if track == .industry {
                    nodes.append(.line(id+"-hoist",[(x-2,y),(x-2,y+26),(x+18,y+26),(x+18,y+11)],"#7D735C",width:2))
                } else { nodes.append(.line(id+"-books",[(x+3,y+1),(x+3,y+8),(x+7,y+8),(x+7,y+1)],"#6D826F",width:2)) }
            }
        }
        let gardens=civic.level(.gardens)
        if gardens>0 {
            for i in 0..<(gardens*2) {
                let x=235+Double(i)*111,id="identity-garden-\(i)"
                nodes += [.rect(id+"-trunk",x,275,2,10,"#8A795D"),.ellipse(id+"-leaves",x-9,281,22,15,"#6F9473")]
            }
        }
        if gardens>=2 {nodes.append(.ellipse("identity-garden-pool",473,65,44,22,"#8BA79B"))}
        if gardens>=3 {nodes += pavilion("identity-garden-pavilion",.init(477,101),"#6A8373")}
        let wall=civic.level(.ramparts)
        if wall>0 {
            for i in 0..<(wall*2) {
                let x=230+Double(i)*135,id="identity-tower-\(i)"
                nodes += [.rect(id,x,266,22,18,"#82988A"),.polygon(id+"-roof",[(x-3,281),(x+11,291),(x+25,281)],"#5D7A70")]
            }
        }
        if let p=civic.project {
            let point=position(CivicTownArt.workPlot(p.track,buildings:s.buildings))
            nodes += [.rect("identity-work-supplies",point.x+36,point.y-4,13,7,"#AC8B61"),
                      .rect("identity-work-progress-base",point.x-32,point.y-18,64,3,"#8A977D"),
                      .rect("identity-work-progress",point.x-32,point.y-18,64*max(0,min(1,p.progress)),3,p.paused ? "#A27B61":"#C0A769")]
        }
        return nodes
    }
    private static func pavilion(_ id:String,_ p:VPoint,_ roof:String) -> [VNode] {
        [.rect(id+"-floor",p.x,p.y,28,3,"#B1AA8F"),
         .line(id+"-pillars",[(p.x+2,p.y),(p.x+2,p.y+17),(p.x+25,p.y+17),(p.x+25,p.y)],"#8A765A",width:2),
         .polygon(id+"-roof",[(p.x-4,p.y+17),(p.x+9,p.y+27),(p.x+19,p.y+27),(p.x+32,p.y+17)],roof)]
    }
}
