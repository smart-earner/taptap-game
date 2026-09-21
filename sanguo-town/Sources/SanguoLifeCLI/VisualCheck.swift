import Foundation
import SanguoLife
import SanguoLifeVisual
import SanguoPresentation

enum VisualCheck {
    static func run(output:String?)throws {
        var checks=0
        func check(_ condition:Bool,_ message:String)throws {
            guard condition else{throw LifeError.invalid("Visual check: \(message)")}
            checks+=1;print("PASS \(message)")
        }
        let runtime=try LifeRuntime(catalog:.bundled(),wallUTC:0,gachaMode:true,rngSeed:42)
        let world=runtime.world,before=try LifeSaveStore.encode(world)
        let definition=runtime.definition!
        try check(Set(LifeHeroArt.appearances.keys)==Set(definition.heroes.map(\.id)),"all 30 owned identities have appearance definitions")
        var rendered=Set<String>()
        for hero in definition.heroes {
            let art=LifeHeroArt.artwork(hero.id,fallback:.warrior),ids=art.allIDs
            try check(ids.count==Set(ids).count,"unique animation node IDs: \(hero.id)")
            try check(Set(["body","head","nearArm","farArm","nearLeg","farLeg","grip","facing"]).isSubset(of:Set(ids)),"animation sockets preserved: \(hero.id)")
            rendered.insert(SVG.node(art))
        }
        try check(rendered.count==30,"30 visually distinct vector definitions")
        let houses=(1...3).map{LifeTownArt.building("house",at:.init(0,0),night:false,level:$0)}
        try check(Set(houses.map{SVG.node($0)}).count==3,"three housing levels have distinct facades")
        try check(houses[1].allIDs.contains("veranda") && houses[2].allIDs.contains("upper-floor"),"real level gates veranda and upper floor")
        let phases=(0...3).map{LifeTownArt.building("house",at:.init(0,0),night:false,phase:$0)}
        try check(Set(phases.map{SVG.node($0)}).count==4,"four construction phases are distinct")
        try check(!phases[0].allIDs.contains("roof") && !phases[1].allIDs.contains("roof") && !phases[2].allIDs.contains("roof") && phases[3].allIDs.contains("roof"),"unfinished construction does not show finished roof")
        let scene=LifeVisual.scene(world)
        try check(scene.count==Set(scene.map(\.id)).count,"scene cache keys are unique")
        try check(!scene.contains{$0.id=="market" || $0.id=="workshop"},"unbuilt facilities are not invented for scenery")
        var housing=world;housing.gacha!.houseLevels=[1,2,3];housing.buildings["house"]=3
        housing.projects=housing.projects.filter{!$0.value.kind.hasPrefix("house")}
        let grown=LifeVisual.scene(housing)
        try check(grown.filter{$0.id.hasPrefix("home-")}.count==3,"only saved houses are rendered")
        try check(grown.first{$0.id=="home-2"}?.art.allIDs.contains("upper-floor")==true,"saved house level is used by map")
        let terrain=LifeTownArt.terrain(night:false)
        for (_,p) in LifeMap.places {
            let y=[220.0,660.0,1010.0].min{abs($0-p.y)<abs($1-p.y)}!
            let exists=terrain.children.contains{node in
                guard node.id.hasPrefix("road-"),case .line(let points)=node.shape else{return false}
                return points==[.init(p.x,p.y),.init(p.x,y)]
            }
            try check(exists,"economic route endpoint shown: \(p.x),\(p.y)")
        }
        var night=world;night.time=2400
        try check(LifeVisual.scene(night).first?.art != scene.first?.art,"night palette differs without wallpaper overlay")
        try check(try LifeSaveStore.encode(world)==before,"rendering leaves world, wallet and save untouched")
        if let output {
            let directory=URL(fileURLWithPath:output,isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            func svg(_ art:VNode)->String {"<svg viewBox=\"-100 -160 200 190\"><g transform=\"scale(1 -1)\">\(SVG.node(art))</g></svg>"}
            let portraits=definition.heroes.map{h in
                let body=SVG.node(LifeHeroArt.artwork(h.id,fallback:.warrior),hidden:["sword","spear","hammer","book","basket","hoe","axe"])
                return "<figure><svg viewBox=\"-45 -105 90 110\"><g transform=\"scale(1 -1)\">\(body)</g></svg><figcaption>\(h.name)</figcaption></figure>"
            }.joined()
            let html="""
            <!doctype html><html lang="zh"><meta charset="utf-8"><title>小城志 · 视觉验收夹具</title>
            <style>body{background:#f4f0e4;color:#293f39;font:16px system-ui;margin:36px}h1,h2{font-family:serif}section{display:grid;grid-template-columns:repeat(6,1fr);gap:16px}figure{background:#fffcf2;border:1px solid #ded9c8;border-radius:16px;margin:0;padding:16px;text-align:center}svg{width:100%;max-height:210px}.map svg{max-height:none}.houses{grid-template-columns:repeat(3,1fr)}</style>
            <h1>小城志 · 原生矢量视觉验收</h1><p>隔离夹具，不读取或修改玩家存档；非新玩法或完整PRD验收。</p>
            <h2>30位人物 · 共用真实动画骨架</h2><section>\(portraits)</section>
            <h2>住宅一至三阶</h2><section class="houses">\(houses.enumerated().map{"<figure>\(svg($0.element))<figcaption>\($0.offset+1)阶</figcaption></figure>"}.joined())</section>
            <h2>四阶段施工</h2><section>\(phases.enumerated().map{"<figure>\(svg($0.element))<figcaption>阶段\($0.offset)</figcaption></figure>"}.joined())</section>
            <h2>日景</h2><div class="map">\(LifeVisual.svg(world))</div><h2>夜景</h2><div class="map">\(LifeVisual.svg(night))</div>
            </html>
            """
            try Data(html.utf8).write(to:directory.appendingPathComponent("visual-review.html"),options:.atomic)
        }
        print("Visual layer: \(checks) checks passed; human visual review and full engine acceptance are separate.")
    }
}
