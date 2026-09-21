import SwiftUI
import AppKit
import SanguoCore
import SanguoPresentation
import SanguoLife
import Darwin

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published private(set) var world: WorldState? { didSet { DesktopPresenter.shared.sync(world) } }
    @Published private(set) var busy = false
    @Published var errorMessage: String?
    private var session: GameSession?
    private var started = false
    private var heartbeat: Task<Void, Never>?
    private init() {}

    func start() async {
        guard !started else { return }; started = true
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("SanguoTown-Development", isDirectory: true)
            let store = SaveStore(fileURL: directory.appendingPathComponent("world.json"))
            let loaded = try await Task.detached { try store.load() }.value
            let created = try GameSession(world: loaded ?? GrowthRuntime.newGame(wallUTC: Self.now()), persistence: store)
            try await created.save()
            session = created
            await refresh()
            heartbeat = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { break }
                    await self?.refresh()
                }
            }
        } catch { errorMessage = "读取／保存失败，未重建存档。\(error.localizedDescription) 请按开发说明检查备份。" }
    }
    static func now() -> Int64 { Int64(Date().timeIntervalSince1970) }
    func refresh() async {
        guard let session, !busy else { return }
        busy = true; defer { busy = false }
        do {
            try await session.advance(to: Self.now())
            world = await session.snapshot(); errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func choose(_ policy: Policy) async {
        guard let session, !busy else { return }
        busy = true; defer { busy = false }
        do {
            try await session.advance(to: Self.now())
            let current = await session.snapshot()
            try await session.send(.init(id: UUID().uuidString, expectedRevision: current.revision,
                                         action: .setPolicy(scope: .realm, policy: policy)))
            world = await session.snapshot(); errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func command(_ action:GameAction) async {
        guard let session,!busy else { return }
        busy=true;defer { busy=false }
        do {
            try await session.advance(to:Self.now())
            let current=await session.snapshot()
            try await session.send(.init(id:UUID().uuidString,expectedRevision:current.revision,action:action))
            world=await session.snapshot();errorMessage=nil
        } catch { errorMessage=error.localizedDescription }
    }
    func flushForExit() async -> Bool {
        guard let session else { return true }
        do { try await session.save(); return true }
        catch { errorMessage = "退出前保存失败：\(error.localizedDescription)"; return false }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var waitingForExit = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await LifeModel.shared.restore() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }
    func applicationWillTerminate(_ notification: Notification) { DesktopPresenter.shared.shutdown(); LifeDesktop.shared.shutdown() }
    @objc private func didWake(_ notification: Notification) {
        Task { await AppModel.shared.refresh(); await LifeModel.shared.refresh() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !waitingForExit else { return .terminateLater }
        waitingForExit = true
        Task {
            let oldSaved = await AppModel.shared.flushForExit()
            let lifeSaved = await LifeModel.shared.saveForExit()
            let saved = oldSaved && lifeSaved
            waitingForExit = false
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
}

@main
@MainActor
struct SanguoMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    init() {
        if CommandLine.arguments.contains("--life-catalog-check") {
            do { let c=try LifeCatalog.bundled(); print("Bundled life catalog: \(c.heroes.count) heroes, \(c.recipes.count) recipes"); exit(0) }
            catch { FileHandle.standardError.write(Data("Life catalog failed: \(error.localizedDescription)\n".utf8)); exit(1) }
        }
    }
    var body: some Scene {
        Window("小城志 · 城市生活", id: "life") {
            LifeView()
        }.defaultSize(width:1360,height:850)
        Window("小城志 · 旧版城景", id: "town") {
            TownStrip(model: model).task { await model.start() }
        }.defaultSize(width: 960, height: 450)
        Window("小城志 · 主公府", id: "main") {
            Dashboard(model: model).task { await model.start() }
        }.defaultSize(width: 1000, height: 680)
        Window("小城志 · 城市成长册", id: "memories") {
            CityMemoryView(model:model).task { await model.start() }
        }.defaultSize(width:1000,height:700)
        Window("小城志 · 桌面城景设置", id:"desktop-settings") {
            DesktopSettingsView(model:model)
        }.defaultSize(width:640,height:640)
        MenuBarExtra("小城志", systemImage: "building.2") { TownMenu(model: model) }
    }
}

@MainActor
struct TownMenu: View {
    @ObservedObject private var desktop = DesktopPresenter.shared
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("小城志 · 生活版开发中")
        Button("城市生活 · 新版试玩") { openWindow(id: "life") }
        Divider()
        Button("打开主公府") { openWindow(id: "main") }
        Button("显示城市概览") { openWindow(id: "town") }
        Button("城市成长册") { openWindow(id:"memories") }
        Divider()
        Button(desktop.preferences.enabled ? "隐藏桌面城景" : "开启桌面融入模式") {
            desktop.update { $0.enabled.toggle() }
        }
        Button("桌面城景设置…") { openWindow(id:"desktop-settings") }
        if desktop.preferences.enabled {
            Button(desktop.preferences.animate ? "暂停桌面动画" : "继续桌面动画") {
                desktop.update { $0.animate.toggle() }
            }
        }
        Button("刷新并保存") { Task { await model.refresh() } }
        Divider()
        Text("无键盘采集 · 无网络联动")
        Button("退出小城") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}

@MainActor
struct Dashboard: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("一城任太守，多城托都督").font(.largeTitle.bold())
                Text("town-0.5：城池分区成长，方向影响街区特色；你定方向，普通事务交给太守。").foregroundStyle(.secondary)
                if let error = model.errorMessage { Text(error).textSelection(.enabled) }
                if let world = model.world {
                    DevelopmentControls(model:model,world:world)
                    RealmPanel(model:model,world:world)
                    if world.growth != nil { DisclosureGroup("可选：查看施工与地块明细") { ConstructionDetails(model:model,world:world) } }
                    GroupBox("主公定策") {
                        Picker("施政方针", selection: Binding(get: { world.policy }, set: { value in Task { await model.choose(value) } })) {
                            ForEach(Policy.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).disabled(model.busy)
                        Text("官职和方针不会到期。新城尚无加工设施时，方针能改变的分工有限。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("城市 \(world.cities.count)")
                        Text("国库 \(world.treasury)铜")
                        Text("因果时间 \(world.simulationTime / 3600)小时")
                    }.font(.headline)
                    ForEach(world.cities.values.sorted { $0.id < $1.id }) { city in
                        GroupBox(city.name) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("太守：\(world.people[city.prefectID]?.name ?? "未知") · 人口\(city.population)")
                                HStack {
                                    ForEach(Resource.allCases, id: \.self) { resource in
                                        Text("\(resource.title) \(String(format: "%.1f", Double(city.inventory[resource]) / 1000))")
                                    }
                                }
                                Text("实际分工：" + city.jobs.keys.sorted().map { "\(Resource(rawValue: $0)?.title ?? $0) \(city.jobs[$0]!)人" }.joined(separator: " / "))
                                    .font(.caption)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    GroupBox("人才与经历") {
                        ForEach(world.people.values.sorted { $0.id < $1.id }) { person in
                            HStack {
                                Text(person.name)
                                Spacer()
                                Text("内政\(person.attributes.administration) · 智谋\(person.attributes.strategy) · 治理XP \(person.experience["governance", default: 0])")
                            }
                        }
                    }
                    GroupBox("最新奏报 · 来自已发生事件") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(world.events.suffix(3).enumerated()), id: \.offset) { _, event in Text(event.message) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("本版为长期养城开发版：地区合作与军务使用简化结算；完整战术战斗、骑乘动画、完整培养分支与现实联动仍未实现。")
                        .font(.caption).foregroundStyle(.secondary)
                } else if model.errorMessage == nil { ProgressView("读取小城…") }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: 680, minHeight: 420)
            .onChange(of: phase) { _, value in if value == .active { Task { await model.refresh() } } }
    }
}

@MainActor
struct TownStrip: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var demo = false
    @State private var paused = false
    @State private var selectedCity = ""
    @State private var item: HandItem = .spear
    @Environment(\.openWindow) private var openWindow
    private var projection: TownProjection? {
        if demo { return .demo }
        guard let world = model.world else { return nil }
        let cityID = world.cities[selectedCity] != nil ? selectedCity : world.cities.keys.sorted().first ?? ""
        return TownProjection.live(world, cityID: cityID)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("小城志").font(.headline)
                Button("融入桌面") {
                    DesktopPresenter.shared.update { $0.enabled = true }
                    dismissWindow(id:"town")
                }.disabled(demo || projection?.appearance == nil)
                Button("发展方向") { openWindow(id:"main") }
                Button("成长册") { openWindow(id:"memories") }
                if let world = model.world {
                    Picker("城市", selection: $selectedCity) {
                        Text("首城").tag("")
                        ForEach(world.cities.values.sorted { $0.id < $1.id }) { Text($0.name).tag($0.id) }
                    }.frame(maxWidth: 180).disabled(demo)
                }
                Spacer()
                Toggle("动作样板", isOn: $demo).toggleStyle(.switch)
                Button(paused ? "继续动画" : "暂停动画") { paused.toggle() }
            }.padding(.horizontal, 14).padding(.vertical, 8)
            if let world=model.world, world.growth?.enabled != true {
                DevelopmentControls(model:model,world:world).padding(.horizontal,14)
            }
            if let projection {
                TownCanvas(projection: projection, paused: paused, reducedMotion: reducedMotion, item: item)
                    .aspectRatio(960.0/300, contentMode: .fit)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(projection.title)，\(projection.actors.count)个可见角色。动画只作展示，不改变产出。")
                HStack {
                    if demo {
                        Text("演示角色／工坊，不读取或写入存档").font(.caption)
                        Picker("武将试装", selection: $item) {
                            Text("无兵器").tag(HandItem.none)
                            Text("长枪").tag(HandItem.spear)
                            Text("佩剑").tag(HandItem.sword)
                        }.frame(maxWidth: 220)
                    } else {
                        Text(projection.appearance == nil ? "旧版岗位示意；可在发展方向中确认迁移" : "\(projection.title) · 建筑和施工来自实际存档，居民为活动代表").font(.caption)
                    }
                    Spacer()
                    if reducedMotion { Text("系统减少动态效果：静态展示").font(.caption) }
                }.padding(.horizontal, 14).padding(.vertical, 8)
            } else if let error = model.errorMessage {
                Text(error).padding().textSelection(.enabled)
            } else { ProgressView("读取小城…").padding(40) }
            if let world=model.world,world.growth != nil {
                ForEach(Array(world.events.filter { ["construction_complete","population","legion_recruit","civic_complete","collection_acquired","city_joined"].contains($0.kind) }.suffix(3).enumerated()),id:\.offset) { _,e in
                    Text(e.message).font(.caption).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,14)
                }
            }
        }.padding(.bottom,8).frame(minWidth: 700, minHeight: 310)
    }
}
