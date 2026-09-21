import SwiftUI
import SanguoLife

@MainActor
struct LifeFoodPanel: View {
    @ObservedObject var model: LifeModel
    let world: LifeWorld
    @State private var target = 2
    @State private var budget: Int64 = 40
    @State private var confirmation = false
    @State private var rules: LifeHusbandryRules?
    @State private var rulesError: String?
    private var status: LifeFoodStatus { .init(world: world) }

    var body: some View {
        GroupBox("让居民吃得更好") {
            VStack(alignment: .leading, spacing: 9) {
                Text("农田供粮 → 牧工照料 → 肉食台 → 厨房 → 居民实际用餐")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("普通饭 \(Double(status.basicMealsAvailable)/1000, specifier: "%.1f")")
                    Spacer()
                    Text("肉食饭 \(Double(status.heartyMealsAvailable)/1000, specifier: "%.1f")")
                }.font(.caption).monospacedDigit()
                Text("累计实际吃到肉食饭：\(status.heartyMealsConsumed)份").font(.callout.bold())
                if let h = world.husbandry {
                    Text(status.reason).font(.caption)
                    Text("在途\(status.pigsInTransit) · 城门待接\(status.pigsAtGate) · 城内\(status.pigsInCity) · 已出栏\(status.pigsProcessed)").font(.caption)
                    Text("本6小时采购：\(status.purchaseSpent)/\(status.purchaseLimit)铜；已喂食粮\(Double(status.feedConsumed)/1000, specifier: "%.2f")份。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(status.heartyTargetBP == 0 ? "当前方针以家常饭为主，不新增肉料生产；已有动物照料继续。" : "当前方向的肉食饭目标\(status.heartyTargetBP/100)%；缺肉自动做家常饭，不强迫凑比例。")
                        .font(.caption)
                    Button(h.enabled ? "暂停新增养殖和出栏" : "恢复原有养殖计划") {
                        Task { await model.send(.pauseHusbandry(h.enabled)) }
                    }
                    DisclosureGroup("调整授权上限") {
                        Stepper("最多养\(target)头", value: $target, in: 1...8)
                        Picker("每6小时采购上限", selection: $budget) {
                            ForEach([20,40,80,160], id: \.self) { amount in Text("\(amount)铜").tag(Int64(amount)) }
                        }
                        Button("按此上限调整") { confirmation = true }
                    }.font(.caption)
                    DisclosureGroup("看看每头猪") {
                        ForEach(h.animals.values.sorted { $0.id < $1.id }) { pig in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(pig.id) · \(pig.stage.title)")
                                ProgressView(value: Double(pig.completedSegments), total: Double(h.rules.growthSegments))
                                Text("已完成\(pig.completedSegments)/\(h.rules.growthSegments)段；成长等待不包含缺料和排班。").foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }.font(.caption)
                } else {
                    Text("先保供、再改善。接受一次授权，太守自行建牧栏、购买幼猪并安排照料。")
                        .font(.caption)
                    Button("授权改善饭食 · 先养2头") { confirmation = true }
                        .disabled(rules == nil)
                }
                if let rulesError { Text(rulesError).font(.caption).foregroundStyle(.red) }
                Text("暂停不退回已花的钱、不重置采购额度；已有动物、在途交付和已开工工程继续安全收尾。")
                    .font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(model.busy)
        .onAppear {
            if let h = world.husbandry { target = h.herdTarget; budget = h.purchaseLimit; rules = h.rules }
            else {
                do { rules = try LifeHusbandryRules.bundled() }
                catch { rulesError = "养殖配置无法读取：\(error.localizedDescription)" }
            }
        }
        .confirmationDialog("确认长期饭食改善授权？", isPresented: $confirmation) {
            Button("保留民食底线并执行") {
                Task { await model.send(.husbandry(herdTarget: target, purchaseLimit: budget)) }
            }
            Button("继续当前发展", role: .cancel) {}
        } message: {
            if let r = rules {
                Text("最多\(target)头；幼猪每头\(r.purchasePrice)铜，每6小时采购不超过\(budget)铜。缺少设施时，另按实际需要建设牧栏\(r.pastureCash)铜、肉食台\(r.butcherCash)铜，并消耗木材\(Double(r.pastureMaterials["wood",default:0]+r.butcherMaterials["wood",default:0])/1000,specifier:"%.1f")、石材\(Double(r.pastureMaterials["stone",default:0]+r.butcherMaterials["stone",default:0])/1000,specifier:"%.1f")。一头猪完整成长需食粮\(Double(Int64(r.growthSegments)*r.feedPerSegment)/1000,specifier:"%.2f")份及实际劳动。保护居民口粮和100铜底线，不会立即扣全额或立刻生成动物。")
            } else { Text("配置尚未就绪，不能开始新授权。") }
        }
    }
}
