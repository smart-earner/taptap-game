import Foundation

public enum Costume: String, CaseIterable, Sendable { case official, warrior, artisan }
public enum HandItem: String, CaseIterable, Sendable { case none, sword, spear }
public enum Motion: String, CaseIterable, Sendable { case idle, walk, read, hammer, carry, cultivate, chop, strike }
public struct RigPose: Equatable, Sendable {
    public var transforms: [String: VTransform]
    public var hidden: Set<String>
}
public enum CharacterRig {
    public static func artwork(_ costume: Costume) -> VNode {
        let coat = costume == .official ? "#37666B" : costume == .warrior ? "#587A86" : "#B88851"
        let edge = costume == .official ? "#A8C3B0" : costume == .warrior ? "#C4CDD0" : "#E0BD82"
        let skin = "#EDBF8E", ink = "#26373B", dark = "#304749"
        func leg(_ id: String, x: Double, fill: String) -> VNode {
            .init(id, transform: .init(x: x, y: 21), children: [
                .rect(id+"-cloth", -3.3, -11, 6.6, 12, fill, radius: 2),
                .init(id+"-shin", transform: .init(y: -10), children: [
                    .rect(id+"-boot", -3.5, -9, 7, 11, ink, radius: 2),
                    .ellipse(id+"-toe", -3, -10, 11, 5, ink),
                    .line(id+"-trim", [(-2,-5),(3,-5)], "#B5AB8C", width: 1)
                ])])
        }
        func prop(_ id: String, _ children: [VNode]) -> VNode { .init(id, children: children) }
        let props: [VNode] = [
            prop("sword", [.rect("sword-grip", -1.5, -7, 3, 11, "#50362C", radius: 1),
                .polygon("sword-blade", [(-2,3),(-2,25),(0,31),(2,25),(2,3)], "#DCE5DF"),
                .line("sword-edge", [(0,5),(0,25)], "#91A5A6"),
                .rect("sword-guard", -6, 2, 12, 3, "#C3A050", radius: 1)]),
            prop("spear", [.rect("spear-shaft", -1.1, -24, 2.2, 66, "#80583F", radius: 1),
                .polygon("spear-point", [(-4,41),(0,56),(4,41),(0,36)], "#D6E0DD"),
                .polygon("spear-tassel", [(0,38),(-8,29),(-4,41)], "#B95445")]),
            prop("hammer", [.rect("hammer-grip", -1.5, -5, 3, 21, "#785A3D", radius: 1),
                .rect("hammer-head", -7, 11, 15, 8, "#53666A", radius: 1.5, stroke: ink),
                .line("hammer-highlight", [(-5,17),(5,17)], "#B5C5BD")]),
            prop("book", [.polygon("book-pages", [(-10,-2),(-9,13),(9,14),(11,0)], "#DFCC95"),
                .line("book-spine", [(0,0),(0,13)], "#927951"),
                .line("book-writing", [(-7,9),(-2,10)], "#927951"),
                .line("book-writing2", [(3,9),(7,10)], "#927951")]),
            prop("basket", [.polygon("basket-body", [(-13,-8),(-16,10),(15,10),(12,-8)], "#B68851"),
                .rect("basket-band", -16, 6, 31, 4, "#DEC492", radius: 1),
                .line("basket-weave1", [(-10,-5),(-10,6)], "#745634"),
                .line("basket-weave2", [(-3,-5),(-3,6)], "#745634"),
                .line("basket-weave3", [(5,-5),(5,6)], "#745634")]),
            prop("hoe", [.rect("hoe-handle", -1, -20, 2.5, 42, "#875D3C"),
                .polygon("hoe-blade", [(-1,21),(12,20),(12,15),(0,17)], "#718080")]),
            prop("axe", [.rect("axe-handle", -1.5, -7, 3, 27, "#875D3C"),
                .polygon("axe-blade", [(-1,18),(9,24),(12,14),(-1,13)], "#9CB3AC")])
        ]
        let farArm = VNode("farArm", transform: .init(x: -10, y: 33), children: [
            .rect("far-sleeve", -4, -13, 8, 15, dark, radius: 3),
            .ellipse("far-hand", -3, -17, 6, 6, skin)])
        let nearArm = VNode("nearArm", transform: .init(x: 11, y: 33), children: [
            .rect("near-sleeve", -4.5, -11, 9, 13, coat, radius: 3, stroke: ink),
            .init("forearm", transform: .init(y: -9), children: [
                .rect("cuff", -4, -7, 8, 9, edge, radius: 1),
                .ellipse("hand", -3, -11, 6.5, 7, skin),
                .init("grip", transform: .init(x: 1, y: -8, angle: -0.12), children: props)])])
        var head: [VNode] = [
            .ellipse("hair-back", -13, -10, 25, 27, ink),
            .ellipse("ear", -11, -3, 7, 9, skin),
            .ellipse("face", -8, -8, 21, 22, skin, stroke: "#A57859"),
            .polygon("hair-fringe", [(-12,6),(-11,16),(0,18),(11,13),(12,7),(5,9),(0,6),(-2,12),(-7,7)], ink),
            .line("brow-near", [(3,5),(8,5)], ink, width: 1.4),
            .ellipse("eye-near", 4, 0.8, 2.4, 3.2, ink),
            .ellipse("eye-far", -4, 1, 2.0, 2.8, ink),
            .ellipse("cheek", 6, -3, 5, 2.5, "#DCA075"),
            .line("mouth", [(4,-5),(7,-4)], "#9A6751")]
        if costume == .official {
            head += [.rect("hat", -12, 11, 22, 8, ink, radius: 2),
                .rect("hat-crown", -7, 18, 12, 8, ink, radius: 2),
                .line("hat-band", [(-10,14),(8,14)], "#C4A65E", width: 2),
                .rect("hat-jade", -2, 13, 4, 4, "#ADC9B5", radius: 1)]
        } else {
            head += [.ellipse("topknot", -5, 15, 10, 10, ink),
                .rect("headband", -12, 9, 24, 3.5, costume == .warrior ? "#B64D41" : "#E0C17D"),
                .polygon("ribbon", [(-11,10),(-19,8),(-17,1),(-14,5)], costume == .warrior ? "#B64D41" : "#CFAD6B")]
        }
        var torso: [VNode] = [
            .polygon("robe", [(-11,34),(10,34),(13,26),(10,18),(15,8),(1,6),(-15,9),(-10,22)], coat),
            .polygon("lapel", [(-8,33),(0,26),(9,34),(6,27),(0,23),(-10,30)], "#E4D6B4", stroke: "none"),
            .line("robe-fold", [(0,23),(-2,9)], edge),
            .rect("belt", -11, 18, 23, 4.5, "#624639", radius: 1),
            .rect("buckle", 0, 18, 5, 5, "#CCAC62", radius: 1)]
        if costume == .warrior {
            torso += [.rect("armor-chest", -8, 23, 17, 7, "#9CAFB0", radius: 2),
                .line("armor-row1", [(-8,25),(9,25)], "#617C81"),
                .line("armor-row2", [(-8,27.5),(9,27.5)], "#617C81"),
                .polygon("tasset", [(-9,17),(9,17),(12,9),(-12,9)], "#6E858B")]
        }
        let body = VNode("body", children: [
            .init("cape", transform: .init(y: 31), children: [
                .polygon("cape-cloth", [(-9,1),(-18,-5),(-23,-26),(-7,-24),(4,-11)], costume == .warrior ? "#A1473C" : dark),
                .line("cape-fold", [(-11,-3),(-17,-21)], costume == .warrior ? "#D07654" : coat)]),
            leg("farLeg", x: -4, fill: dark), farArm,
            leg("nearLeg", x: 5, fill: coat),
            .init("torso", children: torso),
            .init("head", transform: .init(y: 46), children: head), nearArm])
        return .init("actor", children: [.ellipse("shadow", -15, -2, 30, 5, "#758477"),
            .init("facing", children: [body])])
    }

    /// Walk phase derives from distance, not frame count. All props remain children of the hand socket.
    public static func pose(motion: Motion, time: Double, distance: Double = 0,
                            facing: Double = 1, item: HandItem = .none, reducedMotion: Bool = false) -> RigPose {
        let safeTime = time.isFinite ? max(0, time) : 0
        let phase = motion == .walk ? (distance.isFinite ? distance : 0) / 32 * 2 * Double.pi : safeTime * 3.8
        let wave = reducedMotion ? 0 : sin(phase)
        var t: [String: VTransform] = ["facing": .init(sx: facing < 0 ? -1 : 1)]
        t["body"] = .init(y: reducedMotion ? 0 : (motion == .walk ? abs(wave) * 1.4 : sin(safeTime*2)*0.45))
        t["farLeg"] = .init(x: -4, y: 21, angle: motion == .walk ? -wave * 0.40 : 0)
        t["nearLeg"] = .init(x: 5, y: 21, angle: motion == .walk ? wave * 0.40 : 0)
        t["farLeg-shin"] = .init(y: -10, angle: motion == .walk ? max(0, wave)*0.35 : 0)
        t["nearLeg-shin"] = .init(y: -10, angle: motion == .walk ? max(0, -wave)*0.35 : 0)
        var arm = motion == .walk ? -wave*0.30 : -0.15
        var elbow = 0.12
        var grip = VTransform(x: 1, y: -8, angle: -0.12)
        let all: Set<String> = ["sword","spear","hammer","book","basket","hoe","axe"]
        var shown: String? = item == .none ? nil : item.rawValue
        switch motion {
        case .hammer: arm = 0.65 + wave*0.60; elbow = 0.3; shown = "hammer"; grip.angle = -1.8
        case .read: arm = 0.7; elbow = 0.5 + wave*0.035; shown = "book"; grip.angle = -1.2
        case .carry: arm = 0.85; elbow = 0.55; shown = "basket"; grip.angle = -1.4
        case .cultivate: arm = 0.5 + wave*0.32; elbow = 0.4; shown = "hoe"; grip.angle = 2.2
        case .chop: arm = 0.9 + wave*0.65; elbow = 0.4; shown = "axe"; grip.angle = -1.8
        case .strike: arm = 0.65 + wave*0.95; elbow = 0.15; grip.angle = -2.3
        case .idle, .walk: break
        }
        t["nearArm"] = .init(x: 11, y: 33, angle: arm)
        t["forearm"] = .init(y: -9, angle: elbow)
        t["grip"] = grip
        t["farArm"] = .init(x: -10, y: 33, angle: motion == .walk ? wave*0.30 : -0.2)
        t["cape"] = .init(y: 31, angle: reducedMotion ? 0 : sin(phase - 0.6)*0.04)
        t["head"] = .init(y: 46, angle: motion == .read ? -0.08 : 0)
        let blink = !reducedMotion && safeTime.truncatingRemainder(dividingBy: 4.7) > 4.55
        t["eye-near"] = .init(sy: blink ? 0.2 : 1)
        t["eye-far"] = .init(sy: blink ? 0.2 : 1)
        return .init(transforms: t, hidden: shown.map { all.subtracting([$0]) } ?? all)
    }
}
