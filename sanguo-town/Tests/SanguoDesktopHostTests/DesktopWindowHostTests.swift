import AppKit
import CoreGraphics
import Testing
import SanguoPresentation
@testable import SanguoDesktopHost

@MainActor @Suite(.serialized)
struct DesktopWindowHostTests {
    @Test func panelRejectsKeyboardAndMouseFocus() {
        _ = NSApplication.shared
        let p=DesktopCityPanel();defer {p.close()}
        #expect(!p.canBecomeKey && !p.canBecomeMain)
        #expect(p.ignoresMouseEvents && !p.acceptsMouseMovedEvents)
    }
    @Test func panelIsClearAndBorderless() {
        let p=DesktopCityPanel();defer {p.close()}
        #expect(!p.isOpaque && !p.hasShadow)
        #expect(p.backgroundColor.alphaComponent == 0)
        #expect(!p.styleMask.contains(.titled))
    }
    @Test func levelIsBetweenWallpaperAndIcons() {
        let p=DesktopCityPanel();defer {p.close()}
        #expect(p.level.rawValue > Int(CGWindowLevelForKey(.desktopWindow)))
        #expect(p.level.rawValue < Int(CGWindowLevelForKey(.desktopIconWindow)))
        #expect(p.level.rawValue < NSWindow.Level.normal.rawValue)
    }
    @Test func desktopBehaviorsNeverRequestFullScreenOverlay() {
        let p=DesktopCityPanel();defer {p.close()}
        #expect(p.collectionBehavior.contains(.stationary))
        #expect(p.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(p.collectionBehavior.contains(.ignoresCycle))
        #expect(!p.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!p.collectionBehavior.contains(.canJoinAllApplications))
        #expect(!p.hidesOnDeactivate)
    }
    @Test func hideAndDisposeAreIdempotent() {
        let host=DesktopWindowHost()
        host.hide();host.dispose();host.dispose()
        #expect(host.panel == nil)
    }
    @Test func repeatedShowReusesOnePanelWithoutKeyWindow() {
        let host=DesktopWindowHost();defer {host.dispose()}
        let key=NSApp.keyWindow
        let view=NSView(frame:.zero), rect=DesktopRect(x:20,y:20,width:640,height:200)
        host.show(view:view,frame:rect)
        let first=host.panel
        host.show(view:view,frame:rect)
        #expect(host.panel === first)
        #expect(host.panel?.contentView === view)
        #expect(NSApp.keyWindow === key)
        host.hide();#expect(host.panel?.isVisible == false)
        host.dispose();#expect(host.panel == nil)
    }
    @Test func invalidFrameDoesNotCreatePanel() {
        let host=DesktopWindowHost()
        host.show(view:NSView(frame:.zero),frame:.init(x:0,y:0,width:.nan,height:100))
        #expect(host.panel == nil)
    }
}
