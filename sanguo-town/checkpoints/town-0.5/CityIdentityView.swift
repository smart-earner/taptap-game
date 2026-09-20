import SwiftUI
import SanguoCore

/// One optional planning panel, not a new queue of daily approval cards.
@MainActor
struct CityIdentityView: View {
    @ObservedObject var model: AppModel
    let world: WorldState
    @State private var confirmUpgrade = false
    var body: some View {
        if let realm=world.realm {
            if let identity=realm.identity {
                DisclosureGroup("城市方向与太守安排（无需逐项批准）") {
                    ForEach(world.cities.values.sorted{$0.id<$1.id}) { city in
                        VStack(alignment:.leading,spacing:8) {
                            Text(city.name).font(.headline)
                            Picker("持续发展方向",selection:Binding(
                                get:{world.policy(for:city)},
                                set:{policy in Task { await model.command(.setPolicy(scope:.city(city.id),policy:policy)) }})) {
                                ForEach(Policy.allCases,id:\.self) { Text($0.title).tag($0) }
                            }.pickerStyle(.segmented)
                            Text(CityIdentityPlanner.summary(city:city.id,world:world)).font(.callout)
                            Text("已有街区不降级、在建项目按原约定完成；新方向只改变后续投入。没有每周必答任务。")
                                .font(.caption).foregroundStyle(.secondary)
                            let targets=CityIdentityRules.goals(for:world.policy(for:city))
                            Text(CivicTrack.allCases.map { track in
                                "\(track.title) \(realm.civic[city.id]?.level(track) ?? 0)／目标\(targets[track,default:1])"
                            }.joined(separator:" · ")).font(.caption)
                            if let trace=identity.traces[city.id]?.last {
                                GroupBox("最近一次实际安排") {
                                    VStack(alignment:.leading,spacing:5) {
                                        Text("主公方向：\(trace.policy.title) · 当时负责人：\(world.people[trace.officialID]?.name ?? "原太守")")
                                        Text("执行：\(trace.track.title)第\(trace.level)阶段；\(trace.reason)")
                                        Text(trace.completedAt == nil ? "状态：已开工，预留\(trace.committedCash)铜，尚未记作完工" : "结果：第\(trace.completedAt!/86_400)模拟日实际完成")
                                        Text("其他方案：\(trace.alternative)").foregroundStyle(.secondary)
                                    }.font(.caption).frame(maxWidth:.infinity,alignment:.leading)
                                }
                            }
                        }.padding(.vertical,8)
                    }
                }.disabled(model.busy)
            } else {
                GroupBox("可选升级：城池有自己的发展特色") {
                    VStack(alignment:.leading,spacing:8) {
                        Text("各类工程采用相关前置条件，特色方向不再自动全升满；新增分区城景和太守规划记录。旧资产、进行中的工程与旧留影保留。")
                            .font(.caption)
                        Button("查看并采用城市特色规则") { confirmUpgrade=true }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
                .confirmationDialog("启用town-0.5规则和新城景布局？",isPresented:$confirmUpgrade) {
                    Button("保留城池，采用新规则") {
                        Task { await model.command(.realm(.adoptIdentity(policy:world.policy,investment:world.growth?.investment ?? .balanced))) }
                    }
                    Button("继续旧规则",role:.cancel) {}
                } message: {
                    Text("不会删除房屋、人物或收藏，不重算历史收益。在建项目遵守原合同，之后按新的街区目标发展。旧历史画面保留当时布局。")
                }
            }
        }
    }
}
