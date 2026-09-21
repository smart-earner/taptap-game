import AppKit
import SwiftUI
import SanguoLife
import SanguoLifeVisual

@MainActor
final class LifeModel:ObservableObject {
    static let shared=LifeModel()
    @Published private(set) var world:LifeWorld? {didSet{LifeDesktop.shared.sync(world)}}
    @Published private(set) var catalog:LifeCatalog?
    @Published private(set) var busy=false
    @Published var error:String?
    private var session:LifeSession?
    private var heartbeat:Task<Void,Never>?
    private var attemptedRestore=false
    private init(){}
    func restore() async {guard !attemptedRestore else{return};attemptedRestore=true;await open(create:false)}
    func open(create:Bool) async {
        guard session==nil,!busy else{return}
        busy=true;defer{busy=false}
        do {
            let root=try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true).appendingPathComponent("SanguoTown-Life072",isDirectory:true)
            let store=LifeSaveStore(url:root.appendingPathComponent("world.json")), c=try LifeCatalog.bundled()
            let loaded=try await Task.detached{try store.load()}.value
            catalog=c
            guard loaded != nil || create else{return}
            let engine:LifeRuntime
            if let loaded {engine=try LifeRuntime(catalog:c,world:loaded)} else{engine=try LifeRuntime(catalog:c,wallUTC:AppModel.now())}
            let session=LifeSession(engine:engine,store:store);try await session.save()
            try await session.advance(wallUTC:AppModel.now())
            self.session=session;world=await session.snapshot();error=nil
            heartbeat=Task{[weak self] in
                while !Task.isCancelled {
                    do {try await Task.sleep(for:.seconds(5))}catch{break}
                    await self?.refresh()
                }
            }
        }catch{self.error="生活版读取或保存失败，旧城与原文件未清空：\(error.localizedDescription)"}
    }
    func refresh() async {
        guard let session,!busy else{return};busy=true;defer{busy=false}
        do{try await session.advance(wallUTC:AppModel.now());world=await session.snapshot();error=nil}catch{self.error=error.localizedDescription}
    }
    func send(_ command:LifeCommand) async {
        guard let session,!busy else{return};busy=true;defer{busy=false}
        do{try await session.advance(wallUTC:AppModel.now());try await session.send(command);world=await session.snapshot();error=nil}catch{self.error=error.localizedDescription}
    }
    func saveForExit() async -> Bool {
        guard let session else{return true}
        do{try await session.save();return true}catch{self.error=error.localizedDescription;return false}
    }
}

@MainActor
struct LifeView:View {
    @ObservedObject private var model=LifeModel.shared
    @ObservedObject private var desktop=LifeDesktop.shared
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var page=0
    @State private var selected:String?
    @State private var confirmHero:String?
    @State private var showConfirmation=false
    var body:some View {
        VStack(spacing:0){
            HStack{
                VStack(alignment:.leading,spacing:3){Text("小城志 · 城市生活").font(.title2.bold());Text("life-0.7.2-v2 · 饭食改善试玩，旧城不迁移").font(.caption).foregroundStyle(.secondary)}
                Spacer()
                Picker("查看",selection:$page){Text("我的城").tag(0);Text("武将宝鉴 · 30").tag(1);Text("城务记录").tag(2)}.pickerStyle(.segmented).frame(width:310)
                Button(desktop.enabled ? "隐藏桌面城景":"铺满桌面"){desktop.setEnabled(!desktop.enabled)}.disabled(model.world==nil)
                if desktop.enabled {Button(desktop.paused ? "继续动画":"暂停动画"){desktop.paused.toggle()}}
            }.padding(16)
            if let error=model.error {Text(error).foregroundStyle(.red).textSelection(.enabled).padding(8)}
            if let w=model.world,let c=model.catalog {
                HStack(spacing:18){Text("人口 \(w.agents.count)/\(w.housing)");Text("国库 \(w.treasury) 铜");Text("\(w.coverageText()) · \(w.foodCoverage/100)%");Text("满意 \(w.happiness)");Spacer();Text(w.isNight ? "夜间 · 归家与巡更":"白昼 · 生产与建设");Text("第 \(w.cycle+1) 个昼夜")}.font(.callout).padding(.horizontal,18).padding(.vertical,10).background(.quaternary.opacity(0.35))
                if page==0 {
                    HStack(spacing:0){
                        LifeCanvas(world:w,reducedMotion:reducedMotion,onSelect:{selected=$0}).accessibilityLabel("真实城市生活。可点击人物查看当前任务；桌面模式鼠标穿透。")
                        ScrollView{VStack(alignment:.leading,spacing:16){
                            GroupBox("主公定方向"){
                                Picker("城市方向",selection:Binding(get:{w.policy},set:{p in Task{await model.send(.policy(p))}})){
                                    Text("安民").tag("supply");Text("兴商").tag("trade");Text("兴业").tag("industry");Text("备战").tag("military");Text("均衡").tag("balanced")
                                }.disabled(model.busy)
                                Text("本批各方针仍共用开局工程链；不是五条完整特色城市。无自动宣战。").font(.caption).foregroundStyle(.secondary)
                            }
                            LifeFoodPanel(model:model,world:w)
                            GroupBox("正在做什么"){
                                VStack(alignment:.leading,spacing:6){
                                    ForEach(w.projects.values.filter{!$0.completed}.sorted{$0.id<$1.id}){p in
                                        Text(p.kind=="seal" ? "雕制开城木印":"\(["house":"民居","repair":"府署修缮","market":"集市","workshop":"工造院","tavern":"饭馆","pasture":"牧栏","butcher":"肉食台"][p.kind] ?? p.kind)")
                                        ProgressView(value:Double(p.completedWork)/Double(max(1,p.totalWork)))
                                        Text("\(p.completedWork)/\(p.totalWork) 人工秒 · 第\(p.phase+1)段").font(.caption)
                                    }
                                    Text(w.tasks.isEmpty ? "居民正在休息或等待合法需求":"\(w.tasks.count)名居民有实际任务").font(.caption)
                                }.frame(maxWidth:.infinity,alignment:.leading)
                            }
                            GroupBox("下一份期待"){
                                VStack(alignment:.leading,spacing:8){
                                    if w.owned.contains("founders_seal"){Text("开城木印已在府署藏架展示。")}else{Button("制作开城木印 · 10铜/木2"){Task{await model.send(.seal)}}.disabled(model.busy || w.projects["founders_seal"] != nil)}
                                    if let wish=w.wish {Text("正在结识：\(c.hero(wish)?.name ?? wish)")}
                                    Button("打开宝鉴，选择一位想招募的人"){page=1}
                                }.font(.callout)
                            }
                            GroupBox("实际物资"){
                                VStack(spacing:5){ForEach(LifeResource.allCases,id:\.self){r in HStack{Text(r.title);Spacer();Text(String(format:"%.1f",Double(w.amount(r))/1000)).monospacedDigit()}}}
                                Text("合计包括在途；只有送达工作点才可使用。").font(.caption).foregroundStyle(.secondary)
                            }
                            if let id=selected,let a=w.agents[id] {
                                let frame=LifeLiveVisual.actor(a,world:w,at:Double(w.time))
                                GroupBox("\(a.name) · \(LifeLiveVisual.jobName(a.job))"){
                                    VStack(alignment:.leading){Text(frame.action);if let r=frame.cargo {Text("携带 \(r.title) \(Double(frame.quantity)/1000,specifier:"%.1f")份")};if let tid=a.taskID,let t=w.tasks[tid]{Text("任务：\(t.kind) → \(t.subject)").font(.caption)}}.frame(maxWidth:.infinity,alignment:.leading)
                                }
                            }
                            if desktop.enabled {Picker("显示器",selection:$desktop.screenID){Text("主屏幕").tag(0);ForEach(Array(NSScreen.screens.enumerated()),id:\.offset){_,s in Text(s.localizedName).tag((s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0)}}}
                            Text("本版已接真实供餐、种植、搬运、基础城建、招募与昼夜。养殖需明确授权；军团作战、多城和完整收藏装备仍未接入。").font(.caption).foregroundStyle(.secondary)
                        }.padding(14)}.frame(width:300)
                    }
                } else if page==1 {codex(w,c)}
                else {ScrollView{LazyVStack(alignment:.leading,spacing:10){ForEach(w.records.reversed()){r in HStack(alignment:.top){Text("\(r.time/60)分").monospacedDigit().frame(width:65,alignment:.trailing);Text(r.text).frame(maxWidth:.infinity,alignment:.leading)}.padding(8)}}.padding(18)}}
                HStack{Text(w.records.last?.text ?? "日常事务由太守安排。").lineLimit(1);Spacer();Button("保存"){Task{await model.refresh()}}}.font(.caption).padding(10)
            }else{
                Spacer()
                Text("让城市真正过起日子").font(.largeTitle.bold())
                Text("16名居民种粮、搬运、做饭、建设；夜间回家，巡兵守夜。\n采用独立生活版存档，不会覆盖你原来的小城。").multilineTextAlignment(.center).padding()
                Button("接受默认保供 · 开始生活版小城"){Task{await model.open(create:true)}}.buttonStyle(.borderedProminent).disabled(model.busy)
                Text("这是首个可玩切片，不是全部PRD完成版。原型新存档格式暂不承诺后续自动迁移。").font(.caption).foregroundStyle(.secondary).padding()
                Spacer()
            }
        }.frame(minWidth:980,minHeight:650).task{await model.restore()}
        .confirmationDialog("授权完整招募路径？",isPresented:$showConfirmation){
            Button("按已显示成本追求此人"){if let h=confirmHero {Task{await model.send(.recruit(h))}}}
            Button("暂不决定",role:.cancel){}
        }message:{Text("每段按实际资源和保供条件启动，已完成进度保留；同一时间一个主动心愿。没有限时领取。")}
    }
    @ViewBuilder private func codex(_ w:LifeWorld,_ c:LifeCatalog)->some View {
        ScrollView{
            VStack(alignment:.leading){
                HStack{Text("已加入 \(c.heroes.filter{w.owned.contains($0.id)}.count)/30 · 已发现 \(w.discovered.count)/30").font(.title3.bold());Spacer();if w.wish != nil {Button("暂停下一招募阶段"){Task{await model.send(.recruit(nil))}}}}
                Text("四维和技能来自同一配置库。卡片是数据与招募入口；30名人物的独立精修美术尚未完成。").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns:[GridItem(.adaptive(minimum:290),spacing:12)],spacing:12){
                    ForEach(c.heroes){h in
                        let owned=w.owned.contains(h.id),known=w.discovered.contains(h.id),route=c.recruitment.first{$0.hero==h.id}
                        GroupBox{
                            VStack(alignment:.leading,spacing:8){
                                HStack{Text(h.name).font(.title2.bold());Spacer();Text(owned ? "已加入":(w.wish==h.id ? "正在结识":(known ? "已发现":"待发现"))).font(.caption).foregroundStyle(owned ? .green:.secondary)}
                                HStack{ForEach([("administration","政"),("strategy","智"),("valor","武"),("command","统")],id:\.0){k,n in Text("\(n) \(h.attributes[k,default:0])").monospacedDigit()}}
                                Text(h.skill_ids.map{id in c.skills.first{$0.id==id}?.name ?? id}.joined(separator:" · ")).font(.caption)
                                if let r=route {
                                    Text("全程\(r.stages.reduce(0){$0+$1.cash})铜 · 最少\(r.stages.reduce(Int64(0)){$0+$1.passive_s}/60)分钟等待，另计实际工作与缺料").font(.caption).foregroundStyle(.secondary)
                                    if !known {Text("条件："+r.unlock.map{condition in metricName(condition.metric)+" ≥ \(condition.amount)"}.joined(separator:"；")).font(.caption)}
                                    if let p=w.recruits[h.id] {Text("已完成\(p.stage)/3段 · 实付\(p.spent)铜 · \(p.state)").font(.caption)}
                                }
                                if !owned {Button(w.wish==h.id ? "当前心愿":"关注并招募"){confirmHero=h.id;showConfirmation=true}.disabled(!known || model.busy || w.wish==h.id)}
                                else {
                                    Text("已在城中，占用真实床位和饭食；无每日训练领奖。").font(.caption).foregroundStyle(.secondary)
                                    Button(w.prefect==h.id ? "现任太守":"任为太守（空闲时）"){Task{await model.send(.prefect(h.id))}}.disabled(w.prefect==h.id || w.agents[h.id]?.taskID != nil || model.busy)
                                }
                            }.frame(maxWidth:.infinity,alignment:.leading).padding(5)
                        }
                    }
                }
            }.padding(20)
        }
    }
    private func metricName(_ metric:String)->String{
        ["population":"人口","counter.harvests":"实际收割","counter.external_transactions":"外部交易","counter.consecutive_full_meals":"连续足餐","counter.resident_meals_consumed":"累计供餐","counter.forge_completed":"完成器材加工","building.workshop":"工造院","building.station":"驿站","building.tavern":"饭馆"][metric] ?? metric
    }
}
