import AppKit
import CoreGraphics
import SanguoPresentation

/// Deliberately non-activating: management stays in a separate ordinary window.
@MainActor
public final class DesktopCityPanel: NSPanel {
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
    public init() {
        super.init(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        title = "小城志 · 桌面城景"
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        ignoresMouseEvents = true; acceptsMouseMovedEvents = false
        isFloatingPanel = false; hidesOnDeactivate = false
        isReleasedWhenClosed = false; isRestorable = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces,.stationary,.ignoresCycle]
        // Above wallpaper, below desktop icons and every normal application window.
        let desktop = CGWindowLevelForKey(.desktopWindow)
        let icons = CGWindowLevelForKey(.desktopIconWindow)
        level = .init(rawValue:Int(min(desktop + 1, icons - 1)))
    }
}

/// A host owns exactly one display surface, not a second game/session/heartbeat.
@MainActor
public final class DesktopWindowHost {
    public private(set) var panel: DesktopCityPanel?
    public init() {}
    public func show(view: NSView, frame: DesktopRect) {
        guard [frame.x,frame.y,frame.width,frame.height].allSatisfy(\.isFinite),
              frame.width > 0,frame.height > 0 else { return }
        if panel == nil { panel = DesktopCityPanel() }
        guard let panel else { return }
        if panel.contentView !== view { panel.contentView = view }
        panel.setFrame(.init(x:frame.x,y:frame.y,width:frame.width,height:frame.height),display:true)
        view.frame = .init(origin:.zero,size:panel.contentLayoutRect.size)
        view.autoresizingMask = [.width,.height]
        if !panel.isVisible { panel.orderFront(nil) } // Never activate, makeKey, or raise level.
    }
    public func hide() { panel?.orderOut(nil) }
    public func dispose() {
        panel?.orderOut(nil); panel?.contentView = nil; panel?.close(); panel = nil
    }
}
