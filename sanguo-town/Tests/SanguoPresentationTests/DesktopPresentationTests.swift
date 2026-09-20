import Foundation
import Testing
import SanguoCore
@testable import SanguoPresentation

@Suite("Desktop presentation without changing gameplay")
struct DesktopPresentationTests {
    @Test func defaultIsOptIn() { #expect(!DesktopPreferences().enabled) }
    @Test func corruptPreferencesDoNotEnableOverlay() { #expect(!DesktopPreferences.load(Data("bad".utf8)).enabled) }
    @Test func preferencesRoundTrip() throws {
        var p = DesktopPreferences(); p.enabled = true; p.screenID = 42; p.cityID = "river"
        #expect(DesktopPreferences.load(try JSONEncoder().encode(p)) == p)
    }
    @Test func invalidPlacementIsClamped() {
        var p = DesktopPreferences(); p.width = .infinity; p.horizontal = -1; p.vertical = 5
        p.sanitize(); #expect(p.width == 780); #expect(p.horizontal == 0); #expect(p.vertical == 1)
    }
    @Test func externalNegativeOriginIsPreserved() {
        let a = DesktopRect(x:-1920,y:-400,width:1920,height:1080)
        let f = DesktopPlacement.frame(in:a,preferences:.init())!
        #expect(f.x >= -1908 && f.x + f.width <= -12)
        #expect(f.y >= -388 && f.y + f.height <= 668)
    }
    @Test func smallScreenStillFits() {
        let a = DesktopRect(x:0,y:0,width:400,height:150)
        let f = DesktopPlacement.frame(in:a,preferences:.init())!
        #expect(f.width <= 376); #expect(f.height <= 126)
    }
    @Test func placementRejectsInvalidScreen() {
        #expect(DesktopPlacement.frame(in:.init(x:0,y:0,width:0,height:20),preferences:.init()) == nil)
    }
    @Test func unplugFallbackKeepsPreference() {
        var p=DesktopPreferences();p.screenID=42
        let screen=DesktopScreen(id:7,visible:.init(x:0,y:0,width:1440,height:900))
        #expect(DesktopPlacement.screen(preferred:p.screenID,in:[screen])?.id == 7)
        #expect(p.screenID == 42)
    }
    @Test func reconnectReselectsPreferredScreen() {
        let a=DesktopRect(x:0,y:0,width:1440,height:900)
        #expect(DesktopPlacement.screen(preferred:42,in:[.init(id:7,visible:a),.init(id:42,visible:a)])?.id == 42)
    }
    @Test func noScreensIsSafe() { #expect(DesktopPlacement.screen(preferred:42,in:[]) == nil) }
    @Test func desktopFPSIsBounded() {
        #expect(DesktopPlacement.fps(desktop:true,lowPower:false) == 12)
        #expect(DesktopPlacement.fps(desktop:true,lowPower:true) == 6)
    }
    @Test func finderOcclusionDoesNotPermanentlyFreezeDesktop() {
        #expect(!DesktopPlacement.paused(desktop:true,visible:true,onSpace:true,occluded:true,hidden:false,sleeping:false,manual:false,reduceMotion:false))
        #expect(DesktopPlacement.paused(desktop:false,visible:true,onSpace:true,occluded:true,hidden:false,sleeping:false,manual:false,reduceMotion:false))
    }
    @Test func lockedOrHiddenSessionPausesDesktop() {
        #expect(DesktopPlacement.paused(desktop:true,visible:true,onSpace:true,occluded:false,hidden:false,sleeping:true,manual:false,reduceMotion:false))
        #expect(DesktopPlacement.paused(desktop:true,visible:false,onSpace:true,occluded:false,hidden:false,sleeping:false,manual:false,reduceMotion:false))
        #expect(DesktopPlacement.paused(desktop:true,visible:true,onSpace:true,occluded:false,hidden:false,sleeping:false,manual:false,reduceMotion:true))
    }
    @Test func desktopHasNoFullOpaqueCanvas() throws {
        let w=GrowthRuntime.newGame(wallUTC:0),s=try #require(w.appearance(cityID:"plain"))
        let ids=DesktopTownArt.background(s).allIDs
        #expect(!ids.contains("sky"));#expect(!ids.contains("hills"));#expect(!ids.contains("identity-sky"))
        #expect(ids.contains("desktop-terrain"))
    }
    @Test func rendererDoesNotChangeGameOrAddBuildings() throws {
        let w=GrowthRuntime.newGame(wallUTC:0),before=w,s=try #require(w.appearance(cityID:"plain"))
        let text=DesktopTownArt.svg(s)
        #expect(w == before);#expect(text.contains("viewBox"));#expect(!text.contains("<image"))
        #expect(DesktopTownArt.background(s).allIDs.count == Set(DesktopTownArt.background(s).allIDs).count)
    }
    @Test func allPositionExtremesFit() {
        let area=DesktopRect(x:123,y:-321,width:1512,height:887)
        for x in [0.0,0.5,1] { for y in [0.0,0.5,1] {
            var p=DesktopPreferences();p.horizontal=x;p.vertical=y;p.width=1440
            let f=DesktopPlacement.frame(in:area,preferences:p)!
            #expect(f.x >= area.x && f.y >= area.y)
            #expect(f.x+f.width <= area.x+area.width+0.001 && f.y+f.height <= area.y+area.height+0.001)
        }}
    }
}
