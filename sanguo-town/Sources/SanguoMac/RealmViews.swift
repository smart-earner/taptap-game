import SwiftUI
import SanguoCore

/// Optional management sheets. The default city window stays free of daily tasks and approval queues.
@MainActor
struct RealmPanel: View {
    @ObservedObject var model: AppModel
    let world: WorldState
    @State private var wish = ""
    @State private var operation: RegionalGoal = .riverTrade
    @State private var confirmOperation = false
    @State private var confirmWish = false
    @State private var selectedPerson = ""
    @State private var destination = ""
    @State private var selectedItem = ""
    private var cities:[City] { world.cities.values.sorted{$0.id<$1.id} }
    private var people:[Person] { world.people.values.sorted{$0.id<$1.id} }
    var body: some View {
        if let realm=world.realm {
            CityIdentityView(model:model,world:world)
            VStack(alignment:.leading,spacing:12) {
                Text("街区改善 \(realm.civicCount)项 · 已入藏 \(realm.collections.values.filter{$0.completedAt != nil}.count)/16 · 城池 \(world.cities.count)").font(.headline)
                Text("日常街区由太守推进；以下是可选方向，不是待办清单。不操作也继续原有建设。").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("街区进展与临时暂停") {
                    ForEach(cities) { city in
                        if let civic=realm.civic[city.id] {
                            VStack(alignment:.leading,spacing:5) {
                                Text(city.name).font(.headline)
                                Text(CivicTrack.allCases.map{ "\($0.title) \(civic.level($0))/3" }.joined(separator:" · ")).font(.caption)
                                if let p=civic.project {
                                    Text("\(p.track.title) 第\(p.level)阶段 · \(p.workers)人施工 · 已投入\(p.spent)/\(p.cash)铜")
                                    ProgressView(value:p.progress)
                                    Button(p.paused ? "继续此工程" : "暂停此工程") { Task { await model.command(.realm(.pauseCivic(city:city.id,paused:!p.paused))) } }
                                } else { Text("等待合理的下一项工程；没有每日维护要求。").font(.caption) }
                            }.padding(.vertical,6)
                        }
                    }
                }
                DisclosureGroup("选择一个收藏心愿") {
                    if let id=realm.collectionGoal,let item=CollectionCatalog.item(id) {
                        let progress=realm.collections[id]
                        Text("当前：\(item.name) · 已完成\(progress?.stage ?? 0)/\(item.stages.count)步")
                        if let due=progress?.dueAt { Text("已付费步骤剩余约\(max(0,(due-world.simulationTime+3599)/3600))模拟小时").font(.caption) }
                    }
                    Picker("心愿",selection:$wish) {
                        Text("选择目标").tag("")
                        ForEach(CollectionCatalog.all.filter{realm.collections[$0.id]?.completedAt == nil},id:\.id) { item in Text(item.name).tag(item.id) }
                    }
                    if let item=CollectionCatalog.item(wish) {
                        Text("全路径合计\(item.totalCash)铜、至少\(item.totalHours)小时；材料："+materials(item.totalMaterials)).font(.caption)
                        Text("需要\(item.building.title)。选定后允许自动执行列明的步骤；缺少资源时等待，已开工步骤不退款，换心愿保留进度。无需战斗或联网。").font(.caption)
                        Button("确认路径预算并追求此目标") { confirmWish=true }
                    }
                    Button("暂停新收藏步骤") { Task { await model.command(.realm(.collection(nil))) } }
                }
                DisclosureGroup("藏品与人物配备") {
                    Picker("藏品",selection:$selectedItem) {
                        Text("选择已拥有物品").tag("")
                        ForEach(CollectionCatalog.all.filter{$0.kind != .person && realm.collections[$0.id]?.completedAt != nil},id:\.id) { Text($0.name).tag($0.id) }
                    }
                    personPicker
                    if !selectedItem.isEmpty {
                        Text("当前使用者：\(realm.equipment[selectedItem].flatMap{world.people[$0]?.name} ?? "收藏中")").font(.caption)
                        HStack {
                            Button("交给此人") { Task { await model.command(.realm(.equip(item:selectedItem,person:selectedPerson))) } }.disabled(selectedPerson.isEmpty)
                            Button("收回内库") { Task { await model.command(.realm(.equip(item:selectedItem,person:nil))) } }
                        }
                        Text("长兵器／佩剑共用基础外观；坐骑已可收藏与配备，骑乘动画尚未制作。没有同一物品的分身。").font(.caption)
                    }
                }
                DisclosureGroup("地区合作与新城市（可不扩张）") {
                    if let op=realm.operation { Text("执行中：\(op.goal.title)；约\(max(0,(op.dueAt-world.simulationTime+3599)/3600))小时后结算") }
                    Picker("地区目标",selection:$operation) { ForEach(RegionalGoal.allCases,id:\.self) { Text($0.title).tag($0) } }
                    Text("费用\(operation.cash)铜；材料：\(materials(operation.materials))；工期\(operation.hours)模拟小时。").font(.caption)
                    Text("本批采用预付合作合同，新城到期接管；尚未实现逐车建城。护送开路采用有限军力检验，不是完整战术战斗。未满足资源或军团条件会明确拒绝，不扣款。").font(.caption)
                    Button("查看并授权此目标") { confirmOperation=true }.disabled(realm.operation != nil || realm.completedGoals.contains(operation.rawValue))
                }
                DisclosureGroup("重要人事与在途交接") {
                    personPicker
                    Picker("目标城市",selection:$destination) {
                        Text("选择城市").tag("")
                        ForEach(cities) { Text($0.name).tag($0.id) }
                    }
                    HStack {
                        Button("到任本城太守") { Task { await model.command(.appointPrefect(cityID:destination,personID:selectedPerson)) } }
                        Button("调往此城（先交接再旅行）") { Task { await model.command(.realm(.movePerson(person:selectedPerson,destination:destination))) } }
                    }.disabled(selectedPerson.isEmpty || destination.isEmpty)
                    if world.cities.count>=2 && world.districts.isEmpty {
                        Button("任此人为都督，统辖现有城市") {
                            Task { await model.command(.establishDistrict(id:"district-1",cityIDs:cities.map(\.id),governorID:selectedPerson)) }
                        }.disabled(selectedPerson.isEmpty)
                        Text("都督必须已空闲、未锁定且不在途；人才池为当前人物，自动太守任用仍限已在当地的候选。跨城调任可在上方明确安排。").font(.caption)
                    }
                    ForEach(realm.journeys,id:\.personID) { trip in
                        Text("\(world.people[trip.personID]?.name ?? trip.personID) → \(world.cities[trip.destination]?.name ?? trip.destination)").font(.caption)
                    }
                }
            }.disabled(model.busy)
            .confirmationDialog("授权完整收藏路径？",isPresented:$confirmWish) {
                Button("按已展示总成本执行") { Task { await model.command(.realm(.collection(wish))) } }
                Button("暂不决定",role:.cancel) {}
            } message: { Text("普通步骤自动推进，已付费步骤保留并继续；不会在缺资源时透支，也不自动改成下一个心愿。") }
            .confirmationDialog("批准地区目标？",isPresented:$confirmOperation) {
                Button("支付列明费用并开始") { Task { await model.command(.realm(.regional(operation))) } }
                Button("保留当前发展",role:.cancel) {}
            } message: { Text("费用和材料在开始时支付；本开发版本尚无中途撤回。军务可能出现伤兵与无成果，不会自动升级战争范围。") }
        } else if world.growth?.enabled == true {
            GroupBox("继续养好这座城") {
                Text("启用八类长期街区、收藏与地区合作规则。既有城池、人物和资源保留；不会自动开战或建新城。").font(.caption)
                Button("启用长期街区发展") { Task { await model.command(.realm(.adoptIdentity(policy:world.policy,investment:world.growth?.investment ?? .balanced))) } }
            }
        }
    }
    private var personPicker:some View {
        Picker("人物",selection:$selectedPerson) {
            Text("选择人物").tag("")
            ForEach(people) { Text($0.name).tag($0.id) }
        }
    }
    private func materials(_ stock:[String:Int64])->String {
        let text=stock.keys.sorted().map{ "\(Resource(rawValue:$0)?.title ?? $0) \(stock[$0,default:0]/1000)" }.joined(separator:"、")
        return text.isEmpty ? "无" : text
    }
}
