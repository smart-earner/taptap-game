import SwiftUI
import SanguoLife

@MainActor
struct HusbandryPanel: View {
    @ObservedObject var model: LifeModel
    let world: LifeWorld
    @State private var confirm = false

    var body: some View {
        GroupBox("让饭馆有肉菜") {
            VStack(alignment: .leading, spacing: 9) {
                if let herd = world.husbandry {
                    Text(herd.status).font(.callout)
                    Text("累计出栏 \(herd.processedTotal)头 · 居民实际吃到肉食饭 \(world.counters["hearty_meals_consumed", default: 0])份")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(herd.pigs.values.sorted { $0.id < $1.id }) { pig in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pig.id + " · " + stateName(pig.phase)).font(.caption)
                            ProgressView(value: pig.growthProgress(at: world.time), total: 1)
                            if let due = pig.due {
                                Text("本阶段还需约 \(max(0, (due-world.time+59)/60))模拟分钟；后续照料另计")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button(herd.enabled ? "暂停新购幼猪" : "恢复新购幼猪") {
                        Task { await model.send(.husbandry(!herd.enabled)) }
                    }.disabled(model.busy)
                    Text("已有牲畜仍按需照料；不需要点击喂养。缺肉时居民吃家常饭，缺粮时先保民食。")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("完成饭馆后，太守安排牧栏、养殖、出栏和送肉。你只批准这个方向。")
                    Text("两项设施共100铜、木11、石6；实际分段施工。常备2头，幼猪20铜/头，固定每6小时补购上限40铜。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("批准肉食供应…") { confirm = true }.disabled(model.busy)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("启用养殖与肉食供应？", isPresented: $confirm) {
            Button("批准，由太守持续安排") { Task { await model.send(.husbandry(true)) } }
            Button("先保持现在的生活", role: .cancel) {}
        } message: {
            Text("保留现有人物、物资和工程；生活试玩存档升至格式2并留备份，旧开发包将拒绝打开新格式。已有经典版城池不动。只有实际建设、购猪和照料才花费，不凭空送肉。")
        }
    }
    private func stateName(_ phase: LifePigPhase) -> String {
        switch phase {
        case .inTransit: "已购·商旅在途"
        case .awaitingEscort: "城门等待牧工"
        case .arriving: "牵入牧栏"
        case .needsCare: "等饲料和照料"
        case .caring: "正在照料"
        case .growing: "自然成长中"
        case .ready: "成熟·等饭馆需求"
        case .leading: "牵往肉食台"
        case .processing: "院内加工中"
        }
    }
}
