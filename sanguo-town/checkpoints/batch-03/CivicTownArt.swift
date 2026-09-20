import Foundation
import SanguoCore

/// Decorative detail is derived exclusively from completed civic levels in the supplied snapshot.
/// Historical views never query the live world. Numbers of props are deliberately representative.
public enum CivicTownArt {
    public static func equippedHandItem(personID:String,world:WorldState) -> HandItem {
        guard let id=world.realm?.equipment.keys.sorted().first(where:{
            world.realm?.equipment[$0] == personID && CollectionCatalog.item($0)?.kind == .weapon
        }) else { return .none }
        return id.contains("spear") ? .spear : .sword
    }
    public static func workPlot(_ track:CivicTrack,buildings:[BuildingInstance]) -> Int {
        let kind:BuildingKind
        switch track {
        case .water: kind = .farm
        case .homes,.gardens: kind = .house
        case .commerce,.streets: kind = .market
        case .industry: kind = .workshop
        case .ramparts: kind = .barracks
        case .academy: kind = .hall
        }
        return buildings.first{$0.kind == kind && $0.isOperating}?.plot ?? buildings.first{$0.kind == .hall}?.plot ?? 0
    }
    public static func nodes(_ snapshot:CityAppearanceSnapshot) -> [VNode] {
        guard let civic=snapshot.civic else { return [] }
        var a:[VNode]=[]
        let roads=civic.level(.streets), water=civic.level(.water), homes=civic.level(.homes)
        if roads>0 {
            for row in 0..<2 {
                let y=Double(row)*120+32
                a.append(.rect("civic-paving-\(row)",20,y,916,16,"#B5B5A0",radius:2))
                for i in 0..<30 { let x=25+Double(i)*30
                    a.append(.line("civic-paving-joint-\(row)-\(i)",[(x,y+1),(x+6,y+15)],"#979F8E"))
                }
            }
            if roads>=2 { for i in 0..<6 { let x=90+Double(i)*154
                a += [.rect("civic-lamp-post-\(i)",x,137,2,23,"#6E745A"),.rect("civic-lamp-\(i)",x-3,154,8,10,"#D6B36C",radius:2)]
            } }
            if roads>=3 { a.append(pavilion("civic-road-pavilion",x:910,y:124,roof:"#647F7E")) }
        }
        if water>0 {
            a.append(.rect("civic-canal",20,105,912,5+Double(water),"#769C9B",radius:2))
            for i in 0..<water { let x=305+Double(i)*235
                a += [.ellipse("civic-well-\(i)",x,110,19,9,"#AAB2A4",stroke:"#677F77"),.ellipse("civic-well-water-\(i)",x+4,113,11,4,"#5D7F80")]
            }
            if water>=2 { a.append(.rect("civic-canal-bridge",463,102,36,12,"#BBA77D")) }
            if water>=3 { a += [.ellipse("civic-waterwheel",714,112,25,25,"none",stroke:"#867555"),.line("civic-waterwheel-spoke",[(717,115),(736,135),(717,135),(736,115)],"#867555",width:2)] }
        }
        if homes>0 { for b in snapshot.buildings where b.kind == .house && b.isOperating {
            let p=GrowthTownArt.position(b.plot),id="civic-yard-"+b.id
            a += [.rect(id,p.x-48,p.y-5,96,4,"#C4BA99"),.rect(id+"-gate",p.x-5,p.y-5,10,13,"#A79773")]
            if homes>=2 { a += [.ellipse(id+"-plant",p.x-49,p.y+10,11,17,"#65856E"),.ellipse(id+"-plant2",p.x+41,p.y+10,11,17,"#79966C")] }
            if homes>=3 { a.append(.rect(id+"-paved",p.x-47,p.y-11,94,5,"#A8B09A")) }
        } }
        for track in [CivicTrack.commerce,.industry,.academy] {
            let n=civic.level(track)
            guard n>0 else {continue}
            let origin=track == .commerce ? 350.0 : track == .industry ? 590.0 : 45.0
            for i in 0..<n {
                let x=origin+Double(i)*43,id="civic-\(track.rawValue)-\(i)"
                if track == .industry {
                    a += [.rect(id+"-pile",x,113,29,12,"#A68D66"),.line(id+"-hoist",[(x,113),(x,142),(x+27,142),(x+27,127)],"#827051",width:2)]
                } else { a.append(pavilion(id,x:x,y:113,roof:track == .academy ? "#63877D" : "#A47D61")) }
            }
        }
        let gardens=civic.level(.gardens)
        if gardens>0 { for i in 0..<(gardens*3) { let x=150+Double(i)*80,id="civic-tree-\(i)"
            a += [.rect(id+"-trunk",x,273,3,10,"#827759"),.ellipse(id+"-leaves",x-10,279,24,17,"#6E9273")]
        } }
        if gardens>=2 { a.append(.ellipse("civic-pond",775,112,42,18,"#87A9A0")) }
        let wall=civic.level(.ramparts)
        if wall>0 { for i in 0..<(wall*2) { let x=30+Double(i)*175
            a += [.rect("civic-tower-\(i)",x,259,24,23,"#82978E"),.polygon("civic-tower-roof-\(i)",[(x-4,280),(x+12,291),(x+28,280)],"#546F69")]
        } }
        if let p=civic.project {
            let point=GrowthTownArt.position(workPlot(p.track,buildings:snapshot.buildings))
            a += [.rect("civic-work-materials",point.x+38,point.y-5,14,8,"#AB885D"),
                  .rect("civic-work-progress-bg",point.x-31,point.y-16,62,4,"#748673"),
                  .rect("civic-work-progress",point.x-31,point.y-16,62*max(0,min(1,p.progress)),4,p.paused ? "#AE8167" : "#D3B369")]
        }
        return [.init("civic-districts",children:a)]
    }
    private static func pavilion(_ id:String,x:Double,y:Double,roof:String)->VNode {
        .init(id,transform:.init(x:x,y:y),children:[
            .rect(id+"-floor",-3,0,33,4,"#B0AD8D"),.rect(id+"-pillar-a",0,0,3,18,"#8E7755"),
            .rect(id+"-pillar-b",25,0,3,18,"#8E7755"),.polygon(id+"-roof",[(-7,17),(7,28),(22,28),(36,17)],roof)])
    }
}
