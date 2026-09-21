import Foundation
import SanguoLife
import SanguoPresentation

/// Current live projection. Keeps the legacy scene reusable and adds food-chain
/// evidence without changing simulation state or maintaining an alternate clock.
public enum LifeLiveVisual {
    public static func scene(_ w: LifeWorld) -> [LifeArtElement] {
        (LifeVisual.scene(w) + LifeFoodVisual.scene(w)).sorted {
            $0.depth == $1.depth ? $0.id < $1.id : $0.depth < $1.depth
        }
    }
    public static func actor(_ a: LifeAgent, world w: LifeWorld, at time: Double) -> LifeActorFrame {
        var f = LifeVisual.actor(a, world: w, at: time)
        guard let id = a.taskID, let t = w.tasks[id] else { return f }
        if !t.current.route.isEmpty {
            if t.current.kind == "lead" { f.action = t.kind == "pig_receive" ? "牵幼猪回牧栏" : "牵往肉食台" }
            else if t.kind == "home" { f.action = "收工回家" }
            else if t.kind == "meal_trip" { f.action = "前往用餐" }
            else if t.kind == "patrol" { f.action = "沿街巡更" }
            else if t.kind == "pig_receive" { f.action = "去城门接幼猪" }
        } else {
            switch t.kind {
            case "pig_care": f.motion = .carry; f.action = "添料照料（已扣饲料）"
            case "pig_receive": f.motion = .idle; f.action = "交接幼猪"
            case "pig_process": f.motion = .hammer; f.action = "院内肉食加工"
            default: break
            }
        }
        return f
    }
    public static func jobName(_ job: String) -> String {
        ["herder":"牧工", "butcher":"肉食工", "groom":"马夫"][job] ?? LifeVisual.jobNames[job] ?? job
    }
    public static func svg(_ w: LifeWorld, at time: Double? = nil, limit: Int = 96) -> String {
        let clock = time ?? Double(w.time)
        var ordered: [(Double, String, String)] = scene(w).map { ($0.depth, $0.id, SVG.node($0.art)) }
        for a in LifeFoodVisual.visibleAgents(w, limit: limit) {
            let f = actor(a, world: w, at: clock)
            let pose = CharacterRig.pose(motion:f.motion,time:f.phase,distance:f.distance,facing:f.facing,item:.none,reducedMotion:false)
            var body = SVG.node(CharacterRig.artwork(f.costume),overrides:pose.transforms,hidden:pose.hidden)
            if let r = f.cargo {
                var item = LifeFoodVisual.cargo(r,hearty:LifeFoodVisual.heartyCargo(a,world:w))
                item.transform = .init(x:0,y:25)
                body += SVG.node(item)
            }
            ordered.append((1100-f.position.y,f.id,"<g data-agent=\"\(SVG.escape(f.id))\" transform=\"translate(\(f.position.x) \(f.position.y)) scale(.62)\"><title>\(SVG.escape(f.name + " · " + f.action))</title>\(body)</g>"))
        }
        for f in LifeFoodVisual.animals(w,at:clock) {
            let pose = LifeFoodVisual.pigPose(f,time:clock)
            let body = SVG.node(LifeFoodVisual.pigArtwork(),overrides:pose.transforms,hidden:pose.hidden)
            ordered.append((1100-f.position.y,f.id,"<g data-animal=\"\(SVG.escape(f.id))\" transform=\"translate(\(f.position.x) \(f.position.y)) scale(\(f.scale))\"><title>\(SVG.escape(f.id + " · " + f.action))</title>\(body)</g>"))
        }
        let shapes = ordered.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }.map(\.2).joined()
        let labels = scene(w).filter{!$0.title.isEmpty}.map {
            "<text x=\"\($0.point.x)\" y=\"\(1080-$0.point.y+22)\" text-anchor=\"middle\" font-size=\"13\" fill=\"\(w.isNight ? "#EEE2BF":"#40584E")\">\(SVG.escape($0.title))</text>"
        }.joined()
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1920 1080\"><g transform=\"translate(0 1080) scale(1 -1)\">\(shapes)</g>\(labels)</svg>"
    }
}
