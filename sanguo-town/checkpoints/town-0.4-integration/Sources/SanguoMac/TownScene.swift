import AppKit
import SwiftUI
@preconcurrency import SpriteKit
import SanguoPresentation
import SanguoCore

/// Persistent SpriteKit nodes: pose updates change joints, not textures or art allocation.
@MainActor
final class VectorSprite: SKNode {
    private var parts: [String: SKNode] = [:]
    private var defaults: [String: VTransform] = [:]
    init(_ art: VNode) {
        super.init(); addChild(make(art))
    }
    required init?(coder: NSCoder) { fatalError("Programmatic vector scene only") }
    private func color(_ hex: String) -> NSColor {
        guard hex != "none", let value = UInt32(hex.dropFirst(),radix:16) else { return .clear }
        return NSColor(srgbRed:CGFloat((value >> 16) & 255)/255,
                       green:CGFloat((value >> 8) & 255)/255,blue:CGFloat(value & 255)/255,alpha:1)
    }
    private func make(_ art: VNode) -> SKNode {
        let node: SKNode
        if let shape = art.shape {
            let path: CGPath
            switch shape {
            case .polygon(let points), .line(let points):
                let p = CGMutablePath()
                if let first = points.first {
                    p.move(to:CGPoint(x:first.x,y:first.y))
                    for pt in points.dropFirst() { p.addLine(to:CGPoint(x:pt.x,y:pt.y)) }
                    if case .polygon = shape { p.closeSubpath() }
                }
                path = p
            case .ellipse(let x,let y,let w,let h):
                path = CGPath(ellipseIn:CGRect(x:x,y:y,width:w,height:h),transform:nil)
            case .rect(let x,let y,let w,let h,let r):
                path = CGPath(roundedRect:CGRect(x:x,y:y,width:w,height:h),cornerWidth:r,cornerHeight:r,transform:nil)
            }
            let drawable = SKShapeNode(path:path)
            drawable.fillColor = color(art.fill); drawable.strokeColor = color(art.stroke)
            drawable.lineWidth = art.stroke == "none" ? 0 : CGFloat(art.strokeWidth)
            drawable.lineJoin = .round; drawable.lineCap = .round
            node = drawable
        } else { node = SKNode() }
        node.name = art.id; node.alpha = CGFloat(art.opacity)
        parts[art.id] = node; defaults[art.id] = art.transform
        transform(node,art.transform)
        for (index,child) in art.children.enumerated() {
            let built = make(child); built.zPosition = CGFloat(index)*0.0001; node.addChild(built)
        }
        return node
    }
    private func transform(_ node:SKNode,_ t:VTransform) {
        node.position = CGPoint(x:t.x,y:t.y); node.zRotation = CGFloat(t.angle)
        node.xScale = CGFloat(t.sx); node.yScale = CGFloat(t.sy)
    }
    func pose(_ pose:RigPose) {
        for (id,t) in defaults {
            guard let node = parts[id] else { continue }
            transform(node,pose.transforms[id] ?? t); node.isHidden = pose.hidden.contains(id)
        }
    }
}

@MainActor
final class TownScene: SKScene {
    private var director = TownDirector()
    private var backgroundArt: VectorSprite?
    private var tree: VectorSprite?
    private var characters: [String: VectorSprite] = [:]
    private var costumes: [String: Costume] = [:]
    private var labels: [String: SKLabelNode] = [:]
    private var facilityLabels: [SKLabelNode] = []
    private var lastFrame: TimeInterval?
    private var growthNodes: [VectorSprite] = []
    private var previousAppearance: CityAppearanceSnapshot?
    var previewItem: HandItem = .spear
    var reducedMotion = false
    override init() {
        super.init(size:CGSize(width:TownArt.width,height:TownArt.height))
        scaleMode = .aspectFit; backgroundColor = NSColor(srgbRed:0.65,green:0.71,blue:0.57,alpha:1)
    }
    required init?(coder:NSCoder) { fatalError("Programmatic scene only") }
    func sync(_ projection:TownProjection) {
        if let appearance=projection.appearance {
            if previousAppearance != appearance {
                backgroundArt?.removeFromParent(); tree?.removeFromParent(); tree=nil
                for n in growthNodes { n.removeFromParent() }; growthNodes=[]
                for label in facilityLabels { label.removeFromParent() };facilityLabels=[]
                let landscape=VectorSprite(GrowthTownArt.background(appearance));landscape.zPosition = -100
                addChild(landscape);backgroundArt=landscape
                for building in appearance.buildings {
                    let p=GrowthTownArt.position(building.plot)
                    let node=VectorSprite(GrowthTownArt.building(building,snapshot:appearance));node.zPosition=CGFloat(500-p.y)
                    addChild(node);growthNodes.append(node)
                    let label=SKLabelNode(fontNamed:"PingFangSC-Regular")
                    let project=appearance.projects.first { $0.buildingID==building.id }
                    label.text=project.map { "\(building.kind.title)·\($0.phaseTitle)" } ?? "\(building.kind.title) \(building.level)级"
                    label.fontSize=9;label.fontColor=NSColor(srgbRed:0.24,green:0.34,blue:0.28,alpha:1)
                    label.position=CGPoint(x:p.x,y:p.y-18);label.zPosition=1000;addChild(label);facilityLabels.append(label)
                }
                previousAppearance=appearance
            }
        } else if previousAppearance != nil || director.projection?.cityID != projection.cityID || director.projection?.hasWorkshop != projection.hasWorkshop ||
            director.projection?.hasField != projection.hasField || director.projection?.isDemo != projection.isDemo {
            previousAppearance=nil
            for n in growthNodes { n.removeFromParent() };growthNodes=[]
            backgroundArt?.removeFromParent(); tree?.removeFromParent()
            for label in facilityLabels { label.removeFromParent() }; facilityLabels = []
            let bg = VectorSprite(TownArt.background(projection)); bg.zPosition = -100; addChild(bg); backgroundArt = bg
            let foreground = VectorSprite(TownArt.foreground()); foreground.zPosition = 438; addChild(foreground); tree = foreground
            for (text,x,y) in [("府署",225.0,189.0),("粮仓",75.0,166.0),
                (projection.hasWorkshop ? "工坊" : "工坊预留地",455.0,projection.hasWorkshop ? 178.0 : 141.0),("农桑",704.0,174.0)] {
                let label = SKLabelNode(fontNamed:"PingFangSC-Medium")
                label.text = text; label.fontSize = 11; label.fontColor = .init(srgbRed:0.22,green:0.27,blue:0.24,alpha:1)
                label.position = CGPoint(x:x,y:y); label.zPosition = 1; addChild(label); facilityLabels.append(label)
            }
        }
        director.sync(projection)
        for id in Array(characters.keys) where director.actors[id] == nil {
            characters.removeValue(forKey:id)?.removeFromParent(); labels.removeValue(forKey:id)?.removeFromParent(); costumes[id] = nil
        }
        for (id,actor) in director.actors {
            if characters[id] == nil || costumes[id] != actor.spec.costume {
                characters.removeValue(forKey:id)?.removeFromParent(); labels.removeValue(forKey:id)?.removeFromParent()
                let character = VectorSprite(CharacterRig.artwork(actor.spec.costume)); addChild(character)
                characters[id] = character; costumes[id] = actor.spec.costume
                let label = SKLabelNode(fontNamed:"PingFangSC-Regular"); label.fontSize = 9
                label.fontColor = .init(srgbRed:0.16,green:0.23,blue:0.21,alpha:1)
                label.text = String(actor.spec.name.prefix(12)); label.zPosition = 1000
                labels[id] = label; addChild(label)
            }
        }
        displayActors()
    }
    func resetFrameClock() { lastFrame = nil }
    override func update(_ currentTime:TimeInterval) {
        defer { lastFrame = currentTime }
        guard let old = lastFrame else { return }
        director.paused = reducedMotion
        director.tick(currentTime-old)
        displayActors()
    }
    private func displayActors() {
        for (id,actor) in director.actors {
            guard let node = characters[id] else { continue }
            node.position = CGPoint(x:actor.position.x,y:actor.position.y); node.zPosition = CGFloat(actor.depth)
            node.setScale(director.projection?.appearance == nil ? 1 : 0.55)
            let item: HandItem = director.projection?.isDemo == true && actor.spec.costume == .warrior ? previewItem : .none
            node.pose(CharacterRig.pose(motion:actor.motion,time:actor.phaseTime,distance:actor.distance,
                                        facing:actor.facing,item:item,reducedMotion:reducedMotion))
            labels[id]?.position = CGPoint(x:actor.position.x,y:actor.position.y+(director.projection?.appearance == nil ? 80 : 47))
        }
    }
}

/// Visibility != key-window status. The town continues moving while the user types in another app.
@MainActor
final class TownSKView: SKView {
    let townScene = TownScene()
    private var sleeping = false
    private var closing = false
    var manuallyPaused = false
    override init(frame:CGRect) {
        super.init(frame:frame)
        preferredFramesPerSecond = 30; ignoresSiblingOrder = false
        presentScene(townScene); isPaused = true
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self,selector:#selector(suspendScene),name:NSWorkspace.willSleepNotification,object:nil)
        workspace.addObserver(self,selector:#selector(suspendScene),name:NSWorkspace.sessionDidResignActiveNotification,object:nil)
        workspace.addObserver(self,selector:#selector(resumeScene),name:NSWorkspace.didWakeNotification,object:nil)
        workspace.addObserver(self,selector:#selector(resumeScene),name:NSWorkspace.sessionDidBecomeActiveNotification,object:nil)
    }
    required init?(coder:NSCoder) { fatalError("Programmatic view only") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); closing = false
        NotificationCenter.default.removeObserver(self)
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification,NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification] {
                NotificationCenter.default.addObserver(self,selector:#selector(visibilityChanged),name:name,object:window)
            }
            NotificationCenter.default.addObserver(self,selector:#selector(willClose),name:NSWindow.willCloseNotification,object:window)
        }
        for name in [NSApplication.didHideNotification,NSApplication.didUnhideNotification] {
            NotificationCenter.default.addObserver(self,selector:#selector(visibilityChanged),name:name,object:nil)
        }
        refreshRendering()
    }
    @objc private func visibilityChanged(_ note:Notification) { refreshRendering() }
    @objc private func suspendScene(_ note:Notification) { sleeping = true; refreshRendering() }
    @objc private func resumeScene(_ note:Notification) { sleeping = false; townScene.resetFrameClock(); refreshRendering() }
    @objc private func willClose(_ note:Notification) { closing = true; refreshRendering() }
    func refreshRendering() {
        preferredFramesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 15 : 30
        let visible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
        let pause = manuallyPaused || townScene.reducedMotion || sleeping || closing || !visible || isHiddenOrHasHiddenAncestor || NSApp.isHidden
        if isPaused != pause { townScene.resetFrameClock(); isPaused = pause }
    }
    func tearDown() {
        isPaused = true; presentScene(nil)
        NotificationCenter.default.removeObserver(self); NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

@MainActor
struct TownCanvas: NSViewRepresentable {
    let projection: TownProjection
    var paused: Bool
    var reducedMotion: Bool
    var item: HandItem
    func makeNSView(context:Context) -> TownSKView { TownSKView(frame:.zero) }
    func updateNSView(_ view:TownSKView,context:Context) {
        view.townScene.reducedMotion = reducedMotion; view.townScene.previewItem = item
        view.townScene.sync(projection); view.manuallyPaused = paused; view.refreshRendering(); view.needsDisplay = true
    }
    static func dismantleNSView(_ view:TownSKView,coordinator:()) { view.tearDown() }
}
