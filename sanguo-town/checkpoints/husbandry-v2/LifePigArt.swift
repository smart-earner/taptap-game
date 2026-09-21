import Foundation
import SanguoLife
import SanguoPresentation

public struct LifeAnimalFrame: Sendable {
    public let id: String
    public let point: LifePoint
    public let title: String
    public let scale: Double
    public let walking: Bool
}

/// Animal bodies follow the same paid, single-identity tasks as the simulation.
/// Processing is indoors; there is no duplicate pig in the pen while meat is produced.
public enum LifePigArt {
    public static func frames(_ world: LifeWorld, at time: Double) -> [LifeAnimalFrame] {
        guard let herd = world.husbandry else { return [] }
        return herd.pigs.values.sorted { $0.id < $1.id }.compactMap { pig in
            guard pig.phase != .inTransit, pig.phase != .processing else { return nil }
            let index = Int(pig.id.split(separator: "-").last ?? "0") ?? 0
            let home = LifeMap.point("pasture")
            var point = LifePoint(home.x - 50 + Double(index % 4) * 28,
                                  home.y + 15 + Double(index % 2) * 20)
            var walking = false
            if pig.phase == .awaitingEscort { point = LifeMap.point("gate") }
            if let tid = pig.taskID, let t = world.tasks[tid] {
                if t.current.kind == "lead", let location = LifeMap.position(t, at: min(time, Double(t.due))) {
                    point = LifePoint(location.x - 18, location.y - 7)
                    walking = true
                } else if pig.phase == .arriving {
                    point = t.current.kind == "arrive" ? home : LifeMap.point("gate")
                }
            }
            let title: String
            switch pig.phase {
            case .inTransit: title = "商旅送达途中"
            case .awaitingEscort: title = "待牵入牧栏"
            case .arriving: title = "牧工牵入"
            case .needsCare: title = "等待照料"
            case .caring: title = "喂养与照料"
            case .growing: title = "成长第\(pig.segmentsFed)/6段"
            case .ready: title = "已成熟·等待饭馆需求"
            case .leading: title = "出栏交接"
            case .processing: title = "院内加工"
            }
            return .init(id: pig.id, point: point, title: title,
                         scale: 0.65 + 0.35 * pig.growthProgress(at: world.time), walking: walking)
        }
    }

    public static func body() -> VNode {
        .init("pig", children: [
            .ellipse("shadow", -26, -3, 53, 10, "#68765D"),
            .rect("leg-back", -16, 0, 7, 13, "#B87972", radius: 2),
            .rect("leg-front", 11, 0, 7, 13, "#B87972", radius: 2),
            .ellipse("body", -26, 7, 48, 27, "#DBA698"),
            .ellipse("head", 12, 12, 25, 24, "#E7B5A4"),
            .polygon("ear", [(17,31),(15,43),(26,34)], "#C4867F", stroke: "none"),
            .ellipse("snout", 28, 16, 14, 12, "#D4938B"),
            .ellipse("eye", 26, 28, 3, 3, "#37443D"),
            .ellipse("nose", 36, 20, 2, 2, "#865D59"),
            .line("tail", [(-24,22),(-32,25),(-33,32),(-28,31)], "#C89085", width: 3)
        ])
    }

    public static func structures(_ world: LifeWorld) -> [LifeArtElement] {
        guard world.husbandry != nil else { return [] }
        var result: [LifeArtElement] = []
        for (id, title) in [("pasture", "牧栏"), ("butcher", "肉食台")] {
            let built = world.buildings[id, default: 0] > 0
            let project = world.projects[id]
            guard built || project != nil else { continue }
            let p = LifeMap.point(id), phase = built ? 4 : (project?.phase ?? 0)
            let timber = world.isNight ? "#786C56" : "#B19868"
            let floor = VNode.rect(id + "floor", p.x - 85, p.y - 8, 170, 85,
                                   world.isNight ? "#526052" : "#B4B886", radius: 6)
            result.append(.init(id:id+"floor",art:floor,depth:-9999,title:"",point:p))
            var parts: [VNode] = []
            if id == "pasture" {
                for i in 0..<6 {
                    let x = p.x - 80 + Double(i) * 32
                    parts.append(.rect(id + "post-\(i)", x, p.y - 4, 6, phase > 0 ? 31 : 9, timber))
                }
                if phase >= 2 {
                    parts.append(.line(id + "fence", [(p.x-80,p.y+8),(p.x+80,p.y+8)], timber, width: 5))
                    parts.append(.line(id + "back", [(p.x-80,p.y+66),(p.x+80,p.y+66)], timber, width: 6))
                }
                if phase >= 3 {
                    parts.append(.polygon(id + "shade", [(p.x-75,p.y+69),(p.x-48,p.y+97),(p.x+8,p.y+97),(p.x+32,p.y+69)], "#8C7855"))
                }
                if built { parts.append(.rect(id + "trough", p.x+45, p.y+26, 29, 12, "#81795D", radius: 3)) }
            } else {
                if phase >= 1 { parts.append(.rect(id + "wall", p.x-48, p.y+5, 96, 40, "#CCB995")) }
                if phase >= 2 { parts.append(.polygon(id + "roof", [(p.x-60,p.y+43),(p.x-38,p.y+74),(p.x+39,p.y+74),(p.x+60,p.y+43)], "#786F60")) }
                if phase >= 3 { parts.append(.rect(id + "door", p.x-15, p.y+5, 30, 31, "#58665A")) }
                if built { parts.append(.rect(id + "table", p.x+52, p.y+3, 31, 18, timber)) }
            }
            result.append(.init(id: id, art: .init(id, children: parts), depth: 1100-p.y,
                                title: title + (built ? "" : "·第\(phase+1)段施工"), point: p))
        }
        return result
    }
}
