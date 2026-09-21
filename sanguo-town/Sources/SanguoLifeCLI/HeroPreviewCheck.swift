import Foundation
import SanguoLife
import SanguoLifeVisual

enum HeroPreviewCheck {
    static func run() throws {
        var checks=0
        func check(_ value:Bool,_ message:String) throws {
            guard value else {throw LifeError.invalid("CHECK FAILED: \(message)")}
            checks+=1;print("PASS \(message)")
        }
        let c=try LifeCatalog.bundled()
        var a=try LifeRuntime(catalog:c,wallUTC:0,heroPreview:true)
        try check(a.world.agents.count==5 && a.world.housing==5,"five unique heroes and beds")
        try check(a.world.amount(.grain)==24000 && a.world.amount(.meal)==10000 && a.world.treasury==400,"PRD bootstrap assets")
        try check(a.catalog.recipe("cook_basic")?.input_mU==["grain":1000,"wood":250],"PRD basic recipe")
        try a.advance(to:333)
        var b=try LifeRuntime(catalog:c,world:LifeSaveStore.decode(LifeSaveStore.encode(a.world)))
        try a.advance(to:7200)
        for t in stride(from:Int64(350),to:7200,by:17){try b.advance(to:t)}
        try b.advance(to:7200)
        try check(a.world==b.world,"save reload and frame-cadence determinism")
        try check(a.world.produced["grain",default:0]>0 && a.world.produced["meal",default:0]>0,"real harvest and cooking")
        try check(a.world.counters["deliveries",default:0]>0 && a.world.counters["resident_meals_consumed",default:0]>0,"real delivery and eating")
        try check(a.world.foodCoverage==10000,"full food coverage after two cycles")
        try check(a.world.projects["repair"]?.completed==true,"hall repair completed through work")
        try a.advance(to:86400)
        try check(a.world.agents.count==5,"no ordinary immigration after one day")
        let before=a.world
        do {try a.setHusbandry(enabled:true);throw LifeError.invalid("unexpected husbandry success")} catch let e as LifeError {try check(e.localizedDescription.contains("暂未开放"),"unsupported feature rejected")}
        try check(a.world==before,"rejected command preserves world")
        var old=try LifeRuntime(catalog:c,wallUTC:0);try old.advance(to:7200)
        try check(old.world.agents.count==16 && old.world.foodCoverage==10000,"legacy 16-resident food chain preserved")
        print("Hero preview: \(checks) integration checks passed. XCTest suite not covered by this command.")
    }
}
