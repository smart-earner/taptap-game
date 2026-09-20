import Foundation
import SanguoCore

/// Presentation preferences only. Never stored in WorldState or used by the economy.
public struct DesktopPreferences: Codable, Equatable, Sendable {
    public var enabled = false
    public var screenID: UInt32? = nil
    public var cityID = ""
    public var width: Double = 780
    public var horizontal: Double = 0.5
    public var vertical: Double = 0.03
    public var animate = true
    public init() {}
    public mutating func sanitize() {
        width = width.isFinite ? min(1440, max(360, width)) : 780
        horizontal = horizontal.isFinite ? min(1, max(0, horizontal)) : 0.5
        vertical = vertical.isFinite ? min(1, max(0, vertical)) : 0.03
        cityID = String(cityID.prefix(100))
    }
    public static func load(_ data: Data?) -> Self {
        guard let data, data.count < 16_384,
              var value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        value.sanitize(); return value
    }
}

public struct DesktopRect: Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}
public struct DesktopScreen: Equatable, Sendable {
    public var id: UInt32
    public var visible: DesktopRect
    public init(id: UInt32, visible: DesktopRect) { self.id = id; self.visible = visible }
}
public enum DesktopPlacement {
    /// Input is in points and can have negative origins (external displays). No pixel scaling.
    public static func screen(preferred: UInt32?, in screens: [DesktopScreen]) -> DesktopScreen? {
        screens.first(where: { $0.id == preferred }) ?? screens.first
    }
    public static func frame(in area: DesktopRect, preferences: DesktopPreferences) -> DesktopRect? {
        guard [area.x, area.y, area.width, area.height].allSatisfy(\.isFinite),
              area.width > 24, area.height > 24 else { return nil }
        var p = preferences; p.sanitize()
        let width = min(p.width, area.width - 24, (area.height - 24) * 3.2)
        let height = width / 3.2
        return .init(x: area.x + 12 + (area.width - 24 - width) * p.horizontal,
                     y: area.y + 12 + (area.height - 24 - height) * p.vertical,
                     width: width, height: height)
    }
    /// Finder's transparent icon canvas can make occlusionState conservative on the desktop.
    /// Do not read other apps' windows to work around it. Limit FPS instead, and expose Pause.
    public static func fps(desktop: Bool, lowPower: Bool) -> Int {
        desktop ? (lowPower ? 6 : 12) : (lowPower ? 15 : 30)
    }
    public static func paused(desktop: Bool, visible: Bool, onSpace: Bool, occluded: Bool,
                              hidden: Bool, sleeping: Bool, manual: Bool, reduceMotion: Bool) -> Bool {
        !visible || !onSpace || (!desktop && occluded) || hidden || sleeping || manual || reduceMotion
    }
}

/// Remove only the presentation's opaque canvas. Buildings and routes retain identical positions.
/// No wall-paper access, screenshots, added buildings, awards, or changes to simulation state.
public enum DesktopTownArt {
    public static func background(_ snapshot: CityAppearanceSnapshot) -> VNode {
        let source = GrowthTownArt.background(snapshot)
        let removed: Set<String> = ["identity-sky", "identity-ridges", "sky", "hills", "town-soil"]
        var layers = source.children.filter { !removed.contains($0.id) }
        let terrain = VNode.polygon("desktop-terrain", [
            (9,45),(30,17),(132,12),(208,19),(285,8),(405,14),(510,7),
            (622,15),(739,9),(868,17),(941,34),(951,93),(944,171),
            (953,228),(927,275),(813,283),(730,276),(641,286),(523,277),
            (416,285),(311,277),(219,285),(184,277),(98,285),(24,269),(8,207),(15,127)
        ], "#BCC5A2", stroke: "#A1AE8D", width: 1)
        // Keep alpha at the edges so the user's own wallpaper is visible outside the city.
        var shadow = VNode.ellipse("desktop-ground-shadow", 14, 4, 932, 48, "#172825")
        shadow.opacity = 0.18
        layers.insert(terrain, at: 0); layers.insert(shadow, at: 0)
        return .init("desktop-landscape", children: layers)
    }
    public static func svg(_ snapshot: CityAppearanceSnapshot) -> String {
        var content = SVG.node(background(snapshot))
        for building in snapshot.buildings.sorted(by: {
            GrowthTownArt.position($0.plot, snapshot: snapshot).y > GrowthTownArt.position($1.plot, snapshot: snapshot).y
        }) { content += SVG.node(GrowthTownArt.building(building, snapshot: snapshot)) }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 960 300\"><g transform=\"translate(0 300) scale(1 -1)\">\(content)</g></svg>"
    }
}
