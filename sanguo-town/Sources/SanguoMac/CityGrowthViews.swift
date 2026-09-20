import SwiftUI
import SanguoCore
import SanguoPresentation

@MainActor
struct DevelopmentControls: View {
    @ObservedObject var model: AppModel
    let world:WorldState
    @State private var choice:Policy = .balanced
    @State private var style:InvestmentStyle = .balanced
    @State private var legionCapacity=30
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            if world.growth?.enabled != true {
                Text(world.growth == nil ? "旧开发存档：确认后迁移到真实建筑与30日离线规则。原人物与资源保留，岗位示意不当作已付费建筑。" : "先定一个方向，太守持续建设。无每日任务；30日正常离线补算。暂停治理只暂停新增项目。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if world.realm?.identity == nil {
                        Picker("城市方向",selection:$choice) { ForEach(Policy.allCases,id:\.self) { Text($0.title).tag($0) } }
                    } else {
                        Text("按原有方针继续，不刷新预算或重开工程").font(.caption)
                    }
                    Button(world.realm?.identity == nil ? "接受长期治理" : "恢复原有治理") { Task { await model.command(.realm(.adoptIdentity(policy:choice,investment:style))) } }
                }.disabled(model.busy)
            } else {
                HStack {
                    Text("持续养城中 · 第\((world.growth!.normalGrowthSeconds / 86_400)+1)成长日").font(.headline)
                    Spacer()
                    Button("暂停新增建设") { Task { await model.command(.pauseDevelopment(true)) } }
                }
                Picker("再投资风格",selection:Binding(get:{world.growth!.investment},set:{value in Task { await model.command(.setInvestment(value)) }})) {
                    ForEach(InvestmentStyle.allCases,id:\.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).disabled(model.busy)
                Text("调整风格在下一财政周期生效；不是增加金币。城务与施工明细可不操作。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let growth=world.growth {
                if let legion=growth.legion {
                    Text("军团现役 \(legion.active) / 批准\(legion.authorizedCapacity) · 训练\(legion.trainingLevel)级 · \(legion.pausedReason)").font(.caption)
                } else if let proposal=growth.proposals.first {
                    Text(proposal.title).font(.headline)
                    Text(proposal.detail).font(.caption)
                }
                if growth.enabled, let city=world.cities.keys.sorted().first {
                    DisclosureGroup("可选：批准或提高军团目标（不是战争授权）") {
                        HStack {
                            Picker("目标",selection:$legionCapacity) { ForEach([30,60,90],id:\.self) { Text("\($0)人").tag($0) } }.frame(maxWidth:160)
                            Button("批准目标，总预算\(legionCapacity*12)铜") {
                                Task { await model.command(.authorizeLegion(cityID:city,capacity:legionCapacity,budget:Int64(legionCapacity*12))) }
                            }.disabled(model.busy || (growth.legion?.authorizedCapacity ?? 0)>legionCapacity)
                        }
                        Text("营地由太守建设；每批培养后才增加现役，军需不足自动等待，不抽空民生。到上限不自动再扩军。").font(.caption)
                    }
                }
            }
        }.padding(10)
    }
}

@MainActor
struct ConstructionDetails:View {
    @ObservedObject var model:AppModel
    let world:WorldState
    @State private var cancelling:String?
    @State private var cancellingCity:String?
    var body:some View {
        VStack(alignment:.leading) {
            ForEach(world.cities.values.sorted{$0.id<$1.id}) { city in
                if let plan=world.growth?.cities[city.id] {
                    GroupBox("\(city.name) · \(city.population)/\(plan.housing)居民 · \(plan.completedCount)项改善") {
                        VStack(alignment:.leading,spacing:8) {
                            Text(plan.blockedReason).font(.caption)
                            ForEach(plan.projects.filter(\.live)) { p in
                                VStack(alignment:.leading) {
                                    let name=plan.buildings.first{$0.id==p.buildingID}?.kind.title ?? "工程"
                                    Text("\(name) · \(p.phaseTitle) · \(p.builders)名实际工匠 · \(p.reason)")
                                    ProgressView(value:p.fraction)
                                    HStack {
                                        Text("已投入\(p.cashSpent)/\(p.cashCost)铜；未消费材料仍预留").font(.caption)
                                        Spacer()
                                        Button(p.status == .paused ? "继续" : "暂停") { Task { await model.command(.pauseBuilding(cityID:city.id,projectID:p.id,paused:p.status != .paused)) } }
                                        Button("取消") { cancelling=p.id;cancellingCity=city.id }
                                    }
                                }.padding(.vertical,4)
                            }
                            DisclosureGroup("可选地块锁定：只阻止新工程，不撤销在建项目") {
                                LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:8)) {
                                    ForEach(0..<16,id:\.self) { plot in
                                        Button("\(plan.lockedPlots.contains(plot) ? "锁" : "地")\(plot+1)") {
                                            Task { await model.command(.lockPlot(cityID:city.id,plot:plot,locked:!plan.lockedPlots.contains(plot))) }
                                        }
                                    }
                                }
                            }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                }
            }
        }.disabled(model.busy)
        .confirmationDialog("取消工程？已消耗资源不会返还，未消耗预留会释放。太守可能重新规划；需要长期保留空地可锁定地块。",isPresented:Binding(get:{cancelling != nil},set:{if !$0 {cancelling=nil}})) {
            Button("确认取消",role:.destructive) {
                if let id=cancelling,let city=cancellingCity { Task { await model.command(.cancelBuilding(cityID:city,projectID:id)) } }
                cancelling=nil
            }
            Button("保留工程",role:.cancel) { cancelling=nil }
        }
    }
}

@MainActor
struct CityMemoryView:View {
    @ObservedObject var model:AppModel
    @State private var selected=""
    @State private var selectedCity=""
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                Text("我的城，一点点变好").font(.largeTitle.bold())
                if let world=model.world,let growth=world.growth,let firstCity=world.cities.keys.sorted().first {
                    let city = world.cities[selectedCity] == nil ? firstCity : selectedCity
                    Picker("城市",selection:$selectedCity) {
                        Text("首城").tag("")
                        ForEach(world.cities.values.sorted{$0.id<$1.id}) { Text($0.name).tag($0.id) }
                    }.onChange(of:selectedCity) { _,_ in selected="" }
                    Picker("回看时点",selection:$selected) {
                        Text("建城起点").tag("")
                        ForEach(growth.memories.filter{$0.snapshot.cityID==city}) { m in Text("\(m.title) · 第\(m.snapshot.growthAgeSeconds/86_400)日").tag(m.id) }
                    }
                    let memory=growth.memories.first{$0.id==selected && $0.snapshot.cityID==city} ?? growth.memories.first{$0.snapshot.cityID==city}
                    if let memory {
                        Text("过去：\(memory.title)").font(.headline)
                        SnapshotCanvas(snapshot:memory.snapshot).aspectRatio(3.2,contentMode:.fit)
                        if memory.pinned && world.realm != nil {
                            Button("移除此固定快照（不影响城市）") { Task { await model.command(.realm(.removeMemory(memory.id)));selected="" } }
                        }
                        Text("此刻").font(.headline)
                        if let current=world.appearance(cityID:city) { SnapshotCanvas(snapshot:current).aspectRatio(3.2,contentMode:.fit) }
                    }
                    Button("固定当前城景（不奖励资源）") { Task { await model.command(.rememberCity(cityID:city)) } }.disabled(model.busy)
                    Text("只保存游戏内历史状态，不截取桌面。固定快照最多20张；自动纪念最多60张。可移除自己固定的快照；自动里程碑不会被此操作删除。").font(.caption).foregroundStyle(.secondary)
                } else { Text("先开启长期养城，成长册会记录实际建设成果。") }
            }.padding(20)
        }.frame(minWidth:700,minHeight:450)
    }
}

@MainActor
struct SnapshotCanvas:NSViewRepresentable {
    let snapshot:CityAppearanceSnapshot
    func makeNSView(context:Context)->TownSKView { TownSKView(frame:.zero) }
    func updateNSView(_ view:TownSKView,context:Context) {
        var projection=TownProjectionSnapshotAdapter.make(snapshot)
        projection.actors=[]
        view.townScene.sync(projection);view.manuallyPaused=true;view.refreshRendering()
    }
    static func dismantleNSView(_ view:TownSKView,coordinator:()) { view.tearDown() }
}
