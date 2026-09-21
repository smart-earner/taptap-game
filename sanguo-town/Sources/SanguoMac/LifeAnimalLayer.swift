import AppKit
import SpriteKit
import SanguoLife
import SanguoLifeVisual

/// Persistent nodes for real livestock. No timer here can grant meat or grow pigs.
@MainActor
final class LifeAnimalLayer: SKNode {
    private var animals: [String: VectorSprite] = [:]
    private var labels: [String: SKLabelNode] = [:]

    func sync(_ world: LifeWorld) {
        let ids = Set(world.husbandry?.animals.keys ?? [:].keys)
        for id in Array(animals.keys) where !ids.contains(id) {
            animals.removeValue(forKey: id)?.removeFromParent()
            labels.removeValue(forKey: id)?.removeFromParent()
        }
        for id in ids.sorted() where animals[id] == nil {
            let node = VectorSprite(LifeFoodVisual.pigArtwork())
            animals[id] = node; addChild(node)
            let label = SKLabelNode(fontNamed: "PingFangSC-Regular")
            label.fontSize = 12; label.zPosition = 4000
            labels[id] = label; addChild(label)
        }
    }

    func display(_ world: LifeWorld, at time: Double, desktop: Bool, reducedMotion: Bool) {
        for node in animals.values { node.isHidden = true }
        for node in labels.values { node.isHidden = true }
        for frame in LifeFoodVisual.animals(world, at: time) {
            guard let node = animals[frame.id] else { continue }
            node.isHidden = false
            node.position = .init(x: frame.position.x, y: frame.position.y)
            node.zPosition = CGFloat(1100-frame.position.y)
            node.setScale(CGFloat(frame.scale))
            node.pose(LifeFoodVisual.pigPose(frame, time: time, reducedMotion: reducedMotion))
            let label = labels[frame.id]
            label?.isHidden = desktop
            label?.text = "猪\(frame.id.split(separator: "-").last ?? "") · \(frame.action)"
            label?.fontColor = world.isNight ? .white : .darkGray
            label?.position = .init(x: frame.position.x, y: frame.position.y + 65*frame.scale)
        }
    }
}
