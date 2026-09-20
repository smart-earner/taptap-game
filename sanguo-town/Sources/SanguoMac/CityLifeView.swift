import SwiftUI
import AppKit
import SanguoLifeCore
import SanguoDesktopHost
import SanguoPresentation

@MainActor
final class LifeModel: ObservableObject {
    static let shared=LifeModel()
    @Published private(set) var state:LifeState?
    @Published private(set) var rules:LifeRules?
    @Published var error:String?
    @Published var busy=false
    @Published var animationPaused=false
    @Published var publishedAt=Date()
    private var session:LifeSession?
    private var heartbeat:Task<Void,Never>?
    private var loaded=false
    private func store() throws -> LifeSaveStore {
        let directory=try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("SanguoTown-Development")
        return LifeSaveStore(url:directory.appendingPathComponent("city-life-0.6.json"))
    }
    func load() async {
        guard !loaded else {return};loaded=true
        do {
            let r=try LifeRules.loadForApplication();rules=r
            let persistence=try store()
            if let s=try await Task.detached(operation:{try persistence.load(rules:r)}).value {
                session=try LifeSession(state:s,rules:r,persistence:persistence)
                await refresh();beginHeartbeat()
            }
        } catch {self.error="生活档读取失败，未创建新城覆盖：\(error.localizedDescription)"}
    }
    func start() async {
        guard session==nil,error==nil,let rules else{return}
        busy=true;defer{busy=false}
        do {
            let s=try LifeEngine.newGame(wallUTC:Int64(Date().timeIntervalSince1970),rules:rules)
            let created=try LifeSession(state:s,rules:rules,persistence:store())
            try await created.save();session=created;state=await created.snapshot();publishedAt=Date();beginHeartbeat()
        } catch {self.error=error.localizedDescription}
    }
    private func beginHeartbeat() {
        guard heartbeat==nil else{return}
        heartbeat=Task { [weak self] in
            while !Task.isCancelled {
                do {try await Task.sleep(for:.seconds(15))} catch {return}
                await self?.refresh()
            }
        }
    }
    func refresh() async {
        guard !busy,let session else{return};busy=true;defer{busy=false}
        do {try await session.advance(to:Int64(Date().timeIntervalSince1970));state=await session.snapshot();publishedAt=Date();error=nil}
        catch {self.error=error.localizedDescription}
    }
    func chooseCrop(_ id:String) async {
        guard !busy,let session else{return};busy=true;defer{busy=false}
        do {try await session.chooseCrop(site:"field",crop:id);state=await session.snapshot();publishedAt=Date();error=nil}
        catch {self.error=error.localizedDescription}
    }
    func flush() async -> Bool {
        guard let session else{return true}
        do {try await session.save();return true} catch {self.error=error.localizedDescription;return false}
    }
}

@MainActor
final class LifeDesktopPresenter: NSObject,ObservableObject {
    static let shared=LifeDesktopPresenter()
    @Published private(set) var visible=false
    private let host=DesktopWindowHost()
    private var view:NSHostingView<LifeMap>?
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self,selector:#selector(screensChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
    }
    func show() {
        guard LifeModel.shared.state != nil else{return}
        // Only one desktop city renderer at a time; no duplicated simulation is created.
        DesktopPresenter.shared.update{$0.enabled=false}
        visible=true;place()
    }
    func hide() {visible=false;host.hide();view=nil;host.dispose()}
    @objc private func screensChanged(_ note:Notification) {if visible {place()}}
    private func place() {
        guard let screen=NSScreen.main ?? NSScreen.screens.first else{host.hide();return}
        if view==nil {view=NSHostingView(rootView:LifeMap(model:.shared,labels:false))}
        guard let view else{return}
        let f=screen.frame
        host.show(view:view,frame:.init(x:f.minX,y:f.minY,width:f.width,height:f.height))
    }
}

@MainActor
struct CityLifeView:View {
    @ObservedObject private var model=LifeModel.shared
    @ObservedObject private var desktop=LifeDesktopPresenter.shared
    var body:some View {
        VStack(spacing:0) {
            HStack {
                Text("小城志 · 城市生活").font(.title2.bold())
                Text("L1 独立试验城，不覆盖旧存档").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.state != nil {
                    Button(desktop.visible ? "收起桌面城":"铺满桌面") {desktop.visible ? desktop.hide():desktop.show()}
                    Button(model.animationPaused ? "继续动画":"暂停动画") {model.animationPaused.toggle()}
                }
            }.padding()
            if let error=model.error {Text(error).foregroundStyle(.red).textSelection(.enabled).padding()}
            if let s=model.state {
                HStack(spacing:18) {
                    Text("\(s.clockName) · 第\(s.time/2880+1)个生活昼夜")
                    Text("居民\(s.population) / 住房\(s.housing)")
                    Text("满意度\(s.satisfaction)")
                    Text("真实供餐\(s.totalServed)份")
                    Text("铜钱\(s.treasury)")
                    Spacer()
                    Button("保存并刷新") {Task{await model.refresh()}}.disabled(model.busy)
                }.font(.callout).padding(.horizontal)
                LifeMap(model:model,labels:true).aspectRatio(16/9,contentMode:.fit)
                HStack(alignment:.top) {
                    GroupBox("现在谁在做什么") {
                        VStack(alignment:.leading) {
                            ForEach(Array(s.agents.filter{$0.task != nil}.prefix(5))) {a in
                                Text("\(a.name)：\(model.rules.map{LifeProjection.title(a,state:s,rules:$0)} ?? a.activity)").font(.caption)
                            }
                            if s.tasks.isEmpty {Text(s.isNight ? "居民已经归家休息。":"等待下一轮原料与任务。")}
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    GroupBox("食物确实去了哪里") {
                        VStack(alignment:.leading) {
                            Text("田边稻谷 \(s.stock("field","paddy")) · 碾坊成粮 \(s.stock("mill","grain"))")
                            Text("厨房饭 \(s.stock("kitchen","meal")) · 里坊餐箱 \(s.stock("home","meal"))")
                            Text("在途货物 \(s.tasks.reduce(0){$0+$1.cargo})份；未到货不能开饭。")
                        }.font(.caption).frame(maxWidth:.infinity,alignment:.leading)
                    }
                    GroupBox("我的第一份收藏") {
                        VStack(alignment:.leading) {
                            Text(s.achievements.contains("first-meal") ? "已入藏：乡里第一餐图录":"目标：让全体居民吃到第一餐")
                            Text("纪念自动入账，不领取、不发钱。六将招募与名器实物尚未接入生活档。")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                }.padding(.horizontal)
                DisclosureGroup("一次决策：下一茬作物／首批名将规格") {
                    HStack {
                        Button("下一茬水稻") {Task{await model.chooseCrop("rice")}}
                        Button("下一茬粟米") {Task{await model.chooseCrop("millet")}}
                        Text("不清除正在生长的作物。名将仅参数图鉴，尚未拥有。").font(.caption)
                    }
                    if let r=model.rules {
                        ForEach(r.heroes,id:\.id) {h in Text("\(h.name)：\(h.effect)").font(.caption).frame(maxWidth:.infinity,alignment:.leading)}
                    }
                }.padding()
            } else {
                VStack(spacing:16) {
                    Text("让一袋稻谷，变成居民的一餐饭。").font(.title)
                    Text("16位真实居民，自己种植、搬运、做饭、吃饭和回家。\n这是新规则的独立试验档；你的原有城池、人物和收藏保持不变。")
                    Button("开始城市生活") {Task{await model.start()}}.disabled(model.rules==nil || model.busy || model.error != nil)
                    Text("无快捷加速，无额外登录奖励。暂含基础食物链、首座新居和夜巡；牧业、军粮和六将实际招募尚未接入。").font(.caption).foregroundStyle(.secondary)
                }.padding(40).frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }.frame(minWidth:1000,minHeight:650).task{await model.load()}
    }
}

@MainActor
struct LifeMap:View {
    @ObservedObject var model:LifeModel
    let labels:Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/15,paused:model.animationPaused || reduceMotion || phase == .background)) { timeline in
            Canvas { context,size in
                guard let s=model.state,let r=model.rules else{return}
                let scale=min(size.width/1920,size.height/1080)
                context.translateBy(x:(size.width-1920*scale)/2,y:(size.height-1080*scale)/2)
                context.scaleBy(x:scale,y:scale)
                let renderTime=Double(s.time)+(model.animationPaused || reduceMotion ? 0:min(15,max(0,timeline.date.timeIntervalSince(model.publishedAt))))
                draw(&context,state:s,rules:r,at:renderTime)
            }
        }.accessibilityLabel("真实城市生活地图，资源任务与昼夜来自独立存档")
    }
    private func draw(_ c:inout GraphicsContext,state s:LifeState,rules r:LifeRules,at time:Double) {
        let light=LifeProjection.light(at:s.time,rules:r)
        func fill(_ rect:CGRect,_ color:Color,round:CGFloat=0) {c.fill(Path(roundedRect:rect,cornerRadius:round),with:.color(color))}
        func line(_ points:[CGPoint],_ color:Color,_ width:CGFloat=3) {var p=Path();if let first=points.first{p.move(to:first);for point in points.dropFirst(){p.addLine(to:point)}};c.stroke(p,with:.color(color),lineWidth:width)}
        func text(_ value:String,_ x:Double,_ y:Double,_ font:Double=18) {c.draw(Text(value).font(.system(size:font,weight:.medium)).foregroundColor(.white),at:.init(x:x,y:y))}
        let soil=Color(red:0.24*light,green:0.40*light,blue:0.29*light)
        fill(.init(x:10,y:38,width:1900,height:1014),soil,round:50)
        fill(.init(x:630,y:130,width:1170,height:800),Color(red:0.62*light,green:0.62*light,blue:0.43*light),round:30)
        line([.init(x:70,y:550),.init(x:1850,y:550)],Color(red:0.72*light,green:0.66*light,blue:0.47*light),24)
        for f in r.facilities {line([.init(x:f.x,y:f.y),.init(x:f.x,y:540)],Color(red:0.66*light,green:0.61*light,blue:0.44*light),12)}
        line([.init(x:435,y:65),.init(x:450,y:350),.init(x:475,y:710),.init(x:490,y:1000)],Color(red:0.22*light,green:0.48*light,blue:0.60*light),28)
        for f in r.facilities {
            let x=f.x,y=f.y
            if ["field","garden"].contains(f.id) {
                fill(.init(x:x-108,y:y-65,width:216,height:105),Color(red:0.42*light,green:0.31*light,blue:0.18*light),round:10)
                let field=s.fields[f.id]
                let grown=field?.plantedAt.flatMap { start in field?.maturesAt.map{Double(max(0,s.time-start))/Double(max(1,$0-start))} } ?? 0
                if field?.phase=="growing" {
                    for row in 0..<4 {for col in 0..<10 {
                        let h=10+min(1,grown)*25
                        line([.init(x:x-90+Double(col)*20,y:y-40+Double(row)*25),.init(x:x-90+Double(col)*20,y:y-40+Double(row)*25-h)],grown>=1 ? .yellow:.green,4)
                    }}
                }
                if labels {text(f.name,x,y+65);text(field?.phase=="empty" ? "等待播种":grown>=1 ? "成熟，等收割":"生长 \(Int(min(1,grown)*100))%",x,y+88,15)}
                continue
            }
            if f.id=="forest" {
                for n in 0..<10 {let xx=x-90+Double(n%5)*46,yy=y-60+Double(n/5)*70;fill(.init(x:xx-5,y:yy,width:10,height:48),.brown);c.fill(Path(ellipseIn:.init(x:xx-25,y:yy-28,width:52,height:60)),with:.color(Color(red:0.1*light,green:0.36*light,blue:0.2*light)))}
                if labels{text("林地·可采\(s.forestRemaining)",x,y+100)};continue
            }
            if ["quarry","mine","ranch","forge","tavern","market"].contains(f.id) {
                fill(.init(x:x-68,y:y-25,width:136,height:50),Color.black.opacity(0.18),round:12)
                if labels {text(f.name+"·待扩展",x,y+45,15)}
                continue
            }
            if f.id=="well" {c.fill(Path(ellipseIn:.init(x:x-30,y:y-25,width:60,height:50)),with:.color(.gray));c.fill(Path(ellipseIn:.init(x:x-22,y:y-20,width:44,height:32)),with:.color(.blue));if labels{text("井水·已提\(s.stock("well","water"))桶",x,y+55)};continue}
            if f.id=="construction" && s.constructionCount==0 {
                fill(.init(x:x-80,y:y-36,width:160,height:70),.brown.opacity(0.6),round:8)
                let task=s.tasks.first{$0.kind=="build"}
                if task?.phase=="work" {for i in 0..<5 {line([.init(x:x-70+Double(i)*35,y:y+20),.init(x:x-70+Double(i)*35,y:y-70)],.orange,6)}}
                if labels {text(task==nil ? "新居·等材料到场":"新居·正在施工",x,y+62)};continue
            }
            fill(.init(x:x-77,y:y-15,width:154,height:53),Color(red:0.84*light,green:0.72*light,blue:0.50*light),round:3)
            var roof=Path();roof.move(to:.init(x:x-92,y:y-18));roof.addLine(to:.init(x:x,y:y-77));roof.addLine(to:.init(x:x+92,y:y-18));roof.closeSubpath()
            c.fill(roof,with:.color(Color(red:0.32*light,green:0.31*light,blue:0.23*light)))
            fill(.init(x:x-14,y:y,width:28,height:38),.black.opacity(0.65))
            for dx in [-53.0,36.0] {fill(.init(x:x+dx,y:y,width:19,height:23),s.isNight ? .yellow:Color(red:0.36,green:0.45,blue:0.40))}
            if labels {text(f.id=="construction" ? "里坊新居·已建成":f.name,x,y+65)}
            let count=f.id=="kitchen" || f.id=="home" ? s.stock(f.id,"meal"):f.id=="warehouse" ? s.stock(f.id,"grain"):0
            for i in 0..<min(6,count/8) {fill(.init(x:x-70+Double(i)*19,y:y+36,width:15,height:17),.orange,round:4)}
        }
        let cap=96
        for a in s.agents.prefix(cap) {
            if a.site=="home" && a.task==nil && (s.isNight || a.role=="patrol-night") {continue}
            let p=LifeProjection.position(a,state:s,rules:r,at:time),task=s.tasks.first{$0.id==a.task}
            // Tiny deterministic offsets separate simultaneous workers without changing simulation routes.
            let index=Int(a.id.suffix(3)) ?? 0,offset=Double(index%4)*8-12
            let x=p.x+offset,y=p.y+Double(index%3)*5
            let moving=task?.phase=="approach" || task?.phase=="loaded"
            let stride=moving ? sin(time*5+Double(index))*7:0
            let color:Color=a.role.contains("patrol") ? .red:a.role=="farmer" ? .green:a.role=="cook" ? .white:a.role=="forester" ? .brown:.cyan
            c.fill(Path(ellipseIn:.init(x:x-13,y:y+17,width:26,height:8)),with:.color(.black.opacity(0.2)))
            line([.init(x:x-4,y:y+6),.init(x:x-7+stride,y:y+21)],.black,5)
            line([.init(x:x+4,y:y+6),.init(x:x+7-stride,y:y+21)],.black,5)
            fill(.init(x:x-8,y:y-13,width:16,height:23),color,round:4)
            c.fill(Path(ellipseIn:.init(x:x-7,y:y-26,width:14,height:14)),with:.color(Color(red:0.9,green:0.73,blue:0.53)))
            let arm=(task?.phase=="work" ? sin(time*5)*7:stride)
            line([.init(x:x-6,y:y-6),.init(x:x-15,y:y+arm)],color,4)
            line([.init(x:x+6,y:y-6),.init(x:x+15,y:y-arm)],color,4)
            if let task,task.cargo>0 {
                if task.key=="wood" {for n in 0..<3 {line([.init(x:x+8,y:y-8+Double(n)*5),.init(x:x+33,y:y-8+Double(n)*5)],.brown,4)}}
                else {fill(.init(x:x+10,y:y-7,width:20,height:17),task.key=="water" ? .blue:task.key=="meal" ? .orange:.yellow,round:5)}
            }
            if a.role=="patrol-night" && s.isNight {c.fill(Path(ellipseIn:.init(x:x+9,y:y-12,width:23,height:23)),with:.color(.yellow.opacity(0.35)));fill(.init(x:x+17,y:y-5,width:6,height:9),.yellow)}
        }
        if s.achievements.contains("first-meal") {fill(.init(x:1070,y:125,width:200,height:55),.brown,round:8);text("乡里第一餐 · 已入藏",1170,151,16)}
        text("\(s.clockName) · 真实任务\(s.tasks.count) · 里坊现有\(s.stock("home","meal"))份饭",960,65,24)
    }
}
