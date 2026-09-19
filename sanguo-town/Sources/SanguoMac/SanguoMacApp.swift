import SwiftUI
import AppKit
import SanguoCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published private(set) var world: WorldState?
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
            let created = try GameSession(world: loaded ?? Seed.oneCity(wallUTC: Self.now()), persistence: store)
            try await created.save()
            session = created
            await refresh()
            heartbeat = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { break }
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
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }
    @objc private func didWake(_ notification: Notification) {
        Task { await AppModel.shared.refresh() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !waitingForExit else { return .terminateLater }
        waitingForExit = true
        Task {
            let saved = await AppModel.shared.flushForExit()
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
    var body: some Scene {
        Window("小城志 · 主公府", id: "main") {
            Dashboard(model: model).task { await model.start() }
        }.defaultSize(width: 1000, height: 680)
        Window("小城志 · 城市概览", id: "town") {
            TownStrip(model: model).task { await model.start() }
        }.defaultSize(width: 640, height: 240)
        MenuBarExtra("小城志", systemImage: "building.2") { TownMenu(model: model) }
    }
}

@MainActor
struct TownMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("小城志 · 开发版")
        Button("打开主公府") { openWindow(id: "main") }
        Button("显示城市概览") { openWindow(id: "town") }
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
                Text("core-0.1 开发切片：生产、分工与存档已接通；不是完整游戏。").foregroundStyle(.secondary)
                if let error = model.errorMessage { Text(error).textSelection(.enabled) }
                if let world = model.world {
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
                    Text("后续开发：建造与培养项目、跨城物流、军团战斗、收藏路径。三城测试场景请使用命令行演示，不会覆盖本窗口存档。")
                        .font(.caption).foregroundStyle(.secondary)
                } else if model.errorMessage == nil { ProgressView("读取小城…") }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: 680, minHeight: 420)
            .onChange(of: phase) { _, value in if value == .active { Task { await model.refresh() } } }
    }
}

@MainActor
struct TownStrip: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("桌面三国 · 小城志").font(.title2.bold())
            if let world = model.world, let city = world.cities.values.sorted(by: { $0.id < $1.id }).first {
                Text("\(city.name) · \(world.people[city.prefectID]?.name ?? "代理太守")正在处理城务")
                Text("\(world.policy(for: city).title)方针 · 粮食\(city.inventory[.grain] / 1000) · 人口\(city.population)")
                Text(world.events.last?.message ?? "部属将在经营批次到期时处理生产。")
                    .font(.caption).lineLimit(3)
            }
            Text("当前为数据窗口；像素街景尚未制作。").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(minWidth: 440, minHeight: 160, alignment: .leading)
    }
}
