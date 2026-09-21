import AppKit
import SpriteKit
import SwiftUI
import SanguoLife
import SanguoLifeVisual
import SanguoPresentation
import SanguoDesktopHost

@MainActor
final class LifeScene: SKScene {
    private let city = SKNode()
    private let scenery = SKNode()
    private var animals:[String:VectorSprite]=[:]
    private var costumes:[String:Costume]=[:]
    private var characters:[String:VectorSprite]=[:]
    private var cargo:[String:VectorSprite]=[:]
    private var labels:[String:SKLabelNode]=[:]
    private var current:LifeWorld?
    private var lastSync = Date()
    var limit=96
    var desktop=false
    var reducedMotion=false
    var onSelect:((String)->Void)?
    override init() {
        super.init(size:CGSize(width:1920,height:1080))
        scaleMode = .resizeFill; backgroundColor = .clear
        addChild(city); city.addChild(scenery)
    }
    required init?(coder:NSCoder){fatalError("Programmatic scene")}
    override func didChangeSize(_ oldSize:CGSize){layoutCity()}
    private func layoutCity(){
        let scale=min(size.width/1920,size.height/1080)
        city.setScale(scale);city.position = .init(x:(size.width-1920*scale)/2,y:(size.height-1080*scale)/2)
    }
    func sync(_ world:LifeWorld) {
        current=world;lastSync=Date();layoutCity()
        scenery.removeAllChildren()
        for item in LifeVisual.scene(world) {
            let node=VectorSprite(item.art);node.zPosition=CGFloat(item.depth);scenery.addChild(node)
            if !item.title.isEmpty && !desktop {
                let label=SKLabelNode(fontNamed:"PingFangSC-Regular")
                label.text=item.title;label.fontSize=13;label.fontColor=world.isNight ? .init(white:0.92,alpha:1):.init(white:0.2,alpha:1)
                label.position = .init(x:item.point.x,y:item.point.y-22);label.zPosition=3000;scenery.addChild(label)
            }
        }
        let frames=LifePigArt.frames(world,at:Double(world.time))
        for node in animals.values { node.removeFromParent() }; animals=[:]
        for f in frames { let node=VectorSprite(LifePigArt.body());animals[f.id]=node;city.addChild(node) }
        let visibleAgents=LifeVisual.visibleAgents(world,limit:limit)
        let ids=Set(visibleAgents.map(\.id))
        for id in Array(characters.keys) where !ids.contains(id) {characters.removeValue(forKey:id)?.removeFromParent();cargo.removeValue(forKey:id)?.removeFromParent();labels.removeValue(forKey:id)?.removeFromParent()}
        for a in visibleAgents {
            let frame=LifeVisual.actor(a,world:world,at:Double(world.time))
            if characters[a.id]==nil || costumes[a.id] != frame.costume {
                characters[a.id]?.removeFromParent();labels[a.id]?.removeFromParent()
                costumes[a.id]=frame.costume
                let sprite=VectorSprite(CharacterRig.artwork(frame.costume));characters[a.id]=sprite;city.addChild(sprite)
                let label=SKLabelNode(fontNamed:"PingFangSC-Regular");label.fontSize=12;label.zPosition=4000;labels[a.id]=label;city.addChild(label)
            }
            cargo.removeValue(forKey:a.id)?.removeFromParent()
            if let resource=frame.cargo {
                let item=VectorSprite(LifeVisual.cargo(resource,quality:frame.quality));item.setScale(0.8);cargo[a.id]=item;city.addChild(item)
            }
        }
        display()
    }
    override func update(_ currentTime:TimeInterval){display()}
    private func display(){
        guard let w=current else{return}
        let visible=Set(LifeVisual.visibleAgents(w,limit:limit).map(\.id))
        let animalTime=Double(w.time)+(reducedMotion ? 0:max(0,Date().timeIntervalSince(lastSync)))
        for f in LifePigArt.frames(w,at:animalTime) {
            animals[f.id]?.position = .init(x:f.point.x,y:f.point.y)
            animals[f.id]?.zPosition = CGFloat(1100-f.point.y)
            animals[f.id]?.setScale(f.scale)
        }
        for (id,node) in characters {
            guard let a=w.agents[id] else{continue}
            let t=a.taskID.flatMap{w.tasks[$0]}
            let now=reducedMotion ? Double(w.time):min(Double(t?.due ?? w.time),Double(w.time)+max(0,Date().timeIntervalSince(lastSync)))
            let f=LifeVisual.actor(a,world:w,at:now),hide=f.sleeping || !visible.contains(id)
            node.isHidden=hide;cargo[id]?.isHidden=hide;labels[id]?.isHidden=hide || desktop
            node.position = .init(x:f.position.x,y:f.position.y);node.zPosition=CGFloat(1100-f.position.y);node.setScale(0.62)
            node.pose(CharacterRig.pose(motion:f.motion,time:f.phase,distance:f.distance,facing:f.facing,item:.none,reducedMotion:reducedMotion))
            cargo[id]?.position = .init(x:f.position.x,y:f.position.y+19);cargo[id]?.zPosition=node.zPosition+0.3
            labels[id]?.text="\(f.name) · \(f.action)";labels[id]?.position = .init(x:f.position.x,y:f.position.y+53)
            labels[id]?.fontColor=w.isNight ? .white:.init(white:0.15,alpha:1)
        }
    }
    override func mouseDown(with event:NSEvent){
        guard !desktop,let w=current else{return}
        let point=city.convert(event.location(in:self),from:self)
        let found=w.agents.values.compactMap {a -> (String,Double)? in
            let f=LifeVisual.actor(a,world:w,at:Double(w.time));guard !f.sleeping else{return nil}
            return (a.id,hypot(f.position.x-point.x,f.position.y+20-point.y))
        }.min{$0.1<$1.1}
        if let found,found.1<50 {onSelect?(found.0)}
    }
}

@MainActor
final class LifeSKView: SKView {
    let lifeScene=LifeScene()
    private var sleeping=false
    var manuallyPaused=false
    var desktop=false {didSet{lifeScene.desktop=desktop;refresh()}}
    override init(frame:CGRect){
        super.init(frame:frame);allowsTransparency=true;presentScene(lifeScene)
        let workspace=NSWorkspace.shared.notificationCenter
        workspace.addObserver(self,selector:#selector(sleep),name:NSWorkspace.willSleepNotification,object:nil)
        workspace.addObserver(self,selector:#selector(wake),name:NSWorkspace.didWakeNotification,object:nil)
        workspace.addObserver(self,selector:#selector(sleep),name:NSWorkspace.sessionDidResignActiveNotification,object:nil)
        workspace.addObserver(self,selector:#selector(wake),name:NSWorkspace.sessionDidBecomeActiveNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(changed),name:NSApplication.didHideNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(changed),name:NSApplication.didUnhideNotification,object:nil)
        refresh()
    }
    required init?(coder:NSCoder){fatalError("Programmatic view")}
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();refresh()}
    @objc private func changed(){refresh()}
    @objc private func sleep(){sleeping=true;refresh()}
    @objc private func wake(){sleeping=false;refresh()}
    func refresh(){
        preferredFramesPerSecond=ProcessInfo.processInfo.isLowPowerModeEnabled ? 8:(desktop ? 15:30)
        isPaused=sleeping || manuallyPaused || lifeScene.reducedMotion || NSApp.isHidden || window?.isVisible != true
    }
    func stop(){isPaused=true;presentScene(nil);NotificationCenter.default.removeObserver(self);NSWorkspace.shared.notificationCenter.removeObserver(self)}
}
@MainActor
struct LifeCanvas:NSViewRepresentable {
    let world:LifeWorld
    var reducedMotion:Bool
    var onSelect:(String)->Void
    func makeNSView(context:Context)->LifeSKView {LifeSKView(frame:.zero)}
    func updateNSView(_ view:LifeSKView,context:Context){view.lifeScene.reducedMotion=reducedMotion;view.lifeScene.onSelect=onSelect;view.lifeScene.sync(world);view.refresh()}
    static func dismantleNSView(_ view:LifeSKView,coordinator:()){view.stop()}
}

@MainActor
final class LifeDesktop:ObservableObject {
    static let shared=LifeDesktop()
    @Published private(set) var enabled=false
    @Published var paused=false {didSet{view?.manuallyPaused=paused;view?.refresh()}}
    @Published var screenID:Int=0 {didSet{render()}}
    private let host=DesktopWindowHost()
    private var view:LifeSKView?
    private var world:LifeWorld?
    private init(){NotificationCenter.default.addObserver(self,selector:#selector(screensChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)}
    @objc private func screensChanged(){render()}
    func sync(_ world:LifeWorld?){self.world=world;render()}
    func setEnabled(_ value:Bool){
        enabled=value
        if value {DesktopPresenter.shared.update{$0.enabled=false}}
        render()
    }
    private func render(){
        guard enabled,let world else{host.hide();view?.manuallyPaused=true;view?.refresh();return}
        guard let screen=NSScreen.screens.first(where:{($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue==screenID}) ?? NSScreen.main ?? NSScreen.screens.first else{host.hide();return}
        if view==nil {view=LifeSKView(frame:.zero);view!.desktop=true}
        guard let view else{return}
        let frame=screen.frame
        host.show(view:view,frame:.init(x:frame.minX,y:frame.minY,width:frame.width,height:frame.height))
        view.lifeScene.reducedMotion=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        view.lifeScene.sync(world);view.manuallyPaused=paused;view.refresh()
    }
    func shutdown(){host.dispose();view?.stop();view=nil}
}
