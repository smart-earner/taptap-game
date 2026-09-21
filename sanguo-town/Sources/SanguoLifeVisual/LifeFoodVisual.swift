import Foundation
import SanguoLife
import SanguoPresentation

public struct LifeAnimalFrame: Equatable, Sendable {
    public let id: String
    public let position: LifePoint
    public let scale: Double
    public let walking: Bool
    public let facing: Double
    public let action: String
    public let completedSegments: Int
}

/// Projections never create livestock or settle a task. The native scene and
/// recorded SVG use the same identities, positions, cargo quality and priorities.
public enum LifeFoodVisual {
    public static func visibleAgents(_ w: LifeWorld, limit: Int) -> [LifeAgent] {
        let carriers = Set(w.lots.values.filter { $0.amount > 0 }.map(\.location))
        func rank(_ a: LifeAgent) -> Int {
            if a.heroID != nil { return 0 }
            if let id = a.taskID, carriers.contains(id) { return 1 }
            if let id = a.taskID, w.tasks[id]?.kind == "patrol" { return 2 }
            return a.taskID != nil ? 3 : 4
        }
        return Array(w.agents.values.filter {
            !($0.taskID == nil && $0.node == $0.home && $0.restStart != nil)
        }.sorted { a, b in
            rank(a) == rank(b) ? a.id < b.id : rank(a) < rank(b)
        }.prefix(max(0, min(160, limit))))
    }

    public static func animals(_ w: LifeWorld, at time: Double) -> [LifeAnimalFrame] {
        guard let h = w.husbandry else { return [] }
        return h.animals.values.sorted { $0.id < $1.id }.enumerated().compactMap { index, pig in
            // Outside the city or behind the processing-room door: no visible pig.
            guard pig.stage != .inTransit && pig.stage != .processing else { return nil }
            let task = pig.taskID.flatMap { w.tasks[$0] }
            let following = task?.current.kind == "lead"
            let pasture = LifeMap.point("pasture")
            var p = pig.node == "gate" ? LifeMap.point("gate") : LifePoint(
                pasture.x - 46 + Double(index % 4) * 30,
                pasture.y + 18 + Double(index / 4) * 30)
            var facing = 1.0
            if following, let task {
                let t = min(max(Double(task.started), time), Double(task.due))
                // Follow the same committed route, slightly behind the handler.
                p = LifeMap.position(task, at: max(Double(task.started), t - 0.5)) ?? p
                let before = LifeMap.position(task, at: max(Double(task.started), t - 0.7)) ?? p
                facing = p.x < before.x ? -1 : 1
            }
            return .init(id: pig.id, position: p,
                scale: 0.55 + 0.45 * Double(pig.completedSegments) / Double(h.rules.growthSegments),
                walking: following, facing: facing, action: pig.stage.title,
                completedSegments: pig.completedSegments)
        }
    }

    public static func pigArtwork() -> VNode {
        .init("pig", children: [
            .ellipse("shadow", -28, -3, 61, 12, "#6C7860"),
            .rect("back-leg", -17, 0, 8, 20, "#AD7F72", radius: 3),
            .rect("front-leg", 13, 0, 8, 20, "#B78B7B", radius: 3),
            .ellipse("body", -30, 10, 65, 36, "#DAAF98", stroke: "#967365"),
            .line("tail", [(-29,29),(-38,34),(-40,28),(-34,27)], "#B78979", width: 3),
            .init("head", children: [
                .ellipse("face", 18, 21, 32, 26, "#E4B8A1"),
                .polygon("ear", [(23,43),(21,58),(36,46)], "#BE8B81", stroke: "none"),
                .ellipse("nose", 41, 24, 16, 13, "#BF8C7D"),
                .ellipse("eye", 37, 37, 3.5, 4, "#4D4940"),
                .ellipse("nostril", 51, 28, 2.4, 3.5, "#805A53")
            ])
        ])
    }

    public static func pigPose(_ frame: LifeAnimalFrame, time: Double, reducedMotion: Bool = false) -> RigPose {
        let beat = reducedMotion ? 0 : sin(time * (frame.walking ? 7 : 1.5))
        var transforms: [String: VTransform] = [:]
        transforms["pig"] = .init(sx: frame.facing)
        transforms["back-leg"] = .init(x: frame.walking ? beat * 4 : 0)
        transforms["front-leg"] = .init(x: frame.walking ? -beat * 4 : 0)
        transforms["head"] = .init(y: frame.walking ? 0 : beat * 0.8)
        var pose = CharacterRig.pose(motion: .idle, time: 0)
        pose.transforms = transforms
        pose.hidden = []
        return pose
    }

    public static func cargo(_ resource: LifeResource, hearty: Bool) -> VNode {
        if resource == .meat {
            return .init("meat-basket", children: [
                .rect("basket", -15, 0, 30, 13, "#AC8965", radius: 3),
                .ellipse("piece-a", -11, 10, 13, 10, "#C29483"),
                .ellipse("piece-b", 1, 10, 12, 11, "#BC8674")])
        }
        var art = LifeVisual.cargo(resource)
        if resource == .meal && hearty {
            art.children.append(.ellipse("meat-topping", -5, 11, 11, 6, "#B97C60"))
        }
        return art
    }

    public static func heartyCargo(_ agent: LifeAgent, world: LifeWorld) -> Bool {
        guard let id = agent.taskID else { return false }
        return world.lots.values.contains { $0.location == id && $0.resource == .meal && $0.quality == "hearty" }
    }

    public static func scene(_ w: LifeWorld) -> [LifeArtElement] {
        guard w.husbandry != nil else { return [] }
        var result: [LifeArtElement] = []
        let night = w.isNight
        for (kind, title) in [("pasture", "牧栏"), ("butcher", "肉食台")] {
            let exists = w.buildings[kind, default: 0] > 0
            let project = w.projects.values.first { $0.kind == kind && !$0.completed }
            guard exists || project != nil else { continue }
            let p = LifeMap.point(kind)
            if !exists {
                result.append(.init(id: "life-" + kind, art: LifeVisual.building(kind, at: p, night: night, phase: project?.phase), depth: 1100-p.y, title: title + " · 施工中", point: p))
                continue
            }
            if kind == "butcher" {
                let busy = w.husbandry?.animals.values.contains { $0.stage == .processing } == true
                result.append(.init(id: "life-butcher", art: LifeVisual.building(kind, at: p, night: night, phase: nil), depth: 1100-p.y, title: "肉食台 · " + (busy ? "院内加工" : "按需出栏"), point: p))
            } else {
                // Ground behind livestock, front rail in front: preserve depth order.
                let timber = night ? "#706959" : "#A28759"
                let base: [VNode] = [
                    .rect("pen-ground", p.x-82, p.y+4, 164, 87, night ? "#515B4B" : "#BDB483", radius: 8),
                    .line("pen-back", [(p.x-80,p.y+78),(p.x+80,p.y+78)], timber, width: 6),
                    .line("pen-left", [(p.x-80,p.y+8),(p.x-80,p.y+87)], timber, width: 6),
                    .line("pen-right", [(p.x+80,p.y+8),(p.x+80,p.y+87)], timber, width: 6),
                    .rect("feeding-trough", p.x+50, p.y+48, 22, 13, "#837158", radius: 3)]
                result.append(.init(id: "life-pasture-back", art: .init("pasture-back", children: base), depth: 1000-p.y, title: "牧栏 · 真实动物与饲喂", point: p))
                result.append(.init(id: "life-pasture-front", art: .line("pen-front", [(p.x-80,p.y+6),(p.x-25,p.y+6),(p.x-25,p.y+20)], timber, width: 6), depth: 1101-p.y, title: "", point: p))
            }
        }
        return result
    }
}
