import AppKit
import SwiftUI
import SanguoCore
import SanguoPresentation
import SanguoDesktopHost

struct DesktopDisplayOption: Identifiable {
    let id: UInt32
    let name: String
    let screen: DesktopScreen
}

/// MainActor bridge consumes AppModel snapshots; it never opens another GameSession or timer.
@MainActor
final class DesktopPresenter: NSObject, ObservableObject {
    static let shared = DesktopPresenter()
    private static let key = "sanguo.desktop.preferences.v1"
    @Published private(set) var preferences: DesktopPreferences
    @Published private(set) var displays: [DesktopDisplayOption] = []
    @Published private(set) var status = "桌面模式未开启"
    private let host = DesktopWindowHost()
    private var canvas: TownSKView?
    private var lastWorld: WorldState?
    private override init() {
        preferences = .load(UserDefaults.standard.data(forKey:Self.key))
        super.init()
        NotificationCenter.default.addObserver(self,selector:#selector(screenChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(screenChanged),name:NSWorkspace.activeSpaceDidChangeNotification,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(screenChanged),name:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil)
        reloadDisplays()
    }
    func update(_ change: (inout DesktopPreferences) -> Void) {
        var p=preferences;change(&p);p.sanitize();preferences=p
        if let data=try? JSONEncoder().encode(p) { UserDefaults.standard.set(data,forKey:Self.key) }
        render()
    }
    func sync(_ world: WorldState?) { lastWorld=world;render() }
    func shutdown() { canvas?.tearDown();canvas=nil;host.dispose() }
    @objc private func screenChanged(_ note: Notification) { reloadDisplays();render() }
    private func reloadDisplays() {
        displays=NSScreen.screens.compactMap { screen in
            guard let number=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {return nil}
            let f=screen.visibleFrame
            return .init(id:number.uint32Value,name:screen.localizedName,
                         screen:.init(id:number.uint32Value,visible:.init(x:f.minX,y:f.minY,width:f.width,height:f.height)))
        }
    }
    private func render() {
        guard preferences.enabled else {host.hide();canvas?.refreshRendering();status="桌面模式未开启";return}
        guard let world=lastWorld else {host.hide();status="等待存档载入；不会生成展示用城市";return}
        let id=world.cities[preferences.cityID] != nil ? preferences.cityID : world.cities.keys.sorted().first ?? ""
        guard let projection=TownProjection.live(world,cityID:id),projection.appearance != nil else {
            host.hide();status="请先从普通窗口确认城建规则；桌面模式不会自动迁移旧存档";return
        }
        guard let display=DesktopPlacement.screen(preferred:preferences.screenID,in:displays.map(\.screen)),
              let frame=DesktopPlacement.frame(in:display.visible,preferences:preferences) else {
            host.hide();canvas?.refreshRendering();status="暂无可用显示器，已收起城景";return
        }
        if canvas == nil {let view=TownSKView(frame:.zero);view.desktopMode=true;canvas=view}
        guard let canvas else {return}
        canvas.townScene.reducedMotion=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        canvas.manuallyPaused = !preferences.animate
        canvas.townScene.sync(projection)
        host.show(view:canvas,frame:frame);canvas.refreshRendering()
        let name=displays.first(where:{$0.id==display.id})?.name ?? "当前屏幕"
        let fallback=preferences.screenID != nil && preferences.screenID != display.id
        status="\(projection.title) · \(name) · 鼠标穿透\(fallback ? "（原屏幕断开，暂用此屏）" : "")"
    }
}

@MainActor
struct DesktopSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var desktop = DesktopPresenter.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    private func bind<T>(_ path: WritableKeyPath<DesktopPreferences,T>) -> Binding<T> {
        Binding(get:{desktop.preferences[keyPath:path]},set:{value in desktop.update{$0[keyPath:path]=value}})
    }
    var body: some View {
        Form {
            Section {
                Text("把小城放进桌面").font(.title2.bold())
                Text("透明城景位于壁纸上方、普通窗口后方。不会更换壁纸；桌面文件仍可点击。它不是始终置顶的浮窗。").font(.callout)
                Toggle("启用桌面融入模式",isOn:bind(\.enabled))
                Text(desktop.status).font(.caption).foregroundStyle(.secondary)
            }
            Section("位置与大小（只调整显示，不修改城市）") {
                Picker("显示器",selection:Binding(get:{desktop.preferences.screenID ?? 0},set:{id in desktop.update{$0.screenID=id == 0 ? nil:id}})) {
                    Text("自动／主显示器").tag(UInt32(0))
                    ForEach(desktop.displays) { Text($0.name).tag($0.id) }
                    if let id=desktop.preferences.screenID,!desktop.displays.contains(where:{$0.id==id}) {
                        Text("原显示器已断开").tag(id)
                    }
                }
                Picker("关注城市",selection:bind(\.cityID)) {
                    Text("首城").tag("")
                    if let world=model.world {ForEach(world.cities.values.sorted{$0.id<$1.id}) {Text($0.name).tag($0.id)}}
                }
                Slider(value:bind(\.width),in:360...1440,step:20) {Text("宽度 \(Int(desktop.preferences.width))点")}
                Slider(value:bind(\.horizontal),in:0...1) {Text("水平位置")}
                Slider(value:bind(\.vertical),in:0...1) {Text("垂直位置")}
                HStack {
                    Button("左下") {desktop.update{$0.horizontal=0;$0.vertical=0}}
                    Button("下方居中") {desktop.update{$0.horizontal=0.5;$0.vertical=0.03}}
                    Button("右下") {desktop.update{$0.horizontal=1;$0.vertical=0}}
                }
            }
            Section("安静陪伴") {
                Toggle("播放城内动画",isOn:bind(\.animate))
                Text("桌面模式最多12帧／秒，低电量模式6帧／秒；遵循系统减少动态效果。合盖、锁屏和收起时暂停画面。暂停动画不暂停城市经营。").font(.caption)
                Text("不读取桌面图片、文件内容或其他应用窗口。Finder图标层会影响遮挡判断，暂不能保证被工作窗口完全覆盖时停止渲染；可手动暂停。Spaces、台前调度与能耗仍需你的M4实测。").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("打开主公府") {openWindow(id:"main")}
                Button("返回普通窗口") {desktop.update{$0.enabled=false};openWindow(id:"town");dismissWindow(id:"desktop-settings")}
                Spacer()
                Button("设置完成") {dismissWindow(id:"desktop-settings")}.keyboardShortcut(.defaultAction)
            }
        }.formStyle(.grouped).padding(12).frame(minWidth:580,minHeight:570)
            .task {await model.start();desktop.sync(model.world)}
    }
}
