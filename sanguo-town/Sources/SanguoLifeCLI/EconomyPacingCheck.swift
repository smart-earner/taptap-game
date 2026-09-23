import Foundation
import SanguoLife

enum EconomyPacingCheck {
    static func run() throws {
        let parameters=try LifeEconomyPacing.bundled()
        func check(_ ok:Bool,_ message:String) throws {
            guard ok else {throw LifeError.invalid("ECONOMY FAILED: \(message)")}
            print("PASS \(message)")
        }
        let early=parameters.dailyDemand(heroCount:30,soldierCount:0)
        let late=parameters.dailyDemand(heroCount:60,soldierCount:200)
        try check(early.grain==900 && early.wood==90_000 && early.mealBatches==900,
                  "30 heroes at 2x require 900 grain and 90 wood per real day before war")
        try check(late.grain==1_825 && late.wood==182_500 && late.rationBatches==25,
                  "60 heroes and 200 soldiers require 1825 grain and 182.5 wood per real day")

        var runtime=try LifeRuntime(catalog:.bundled(),wallUTC:0,formalHeroTown:true,rngSeed:92)
        try check(runtime.catalog.recipe("cook_basic")?.input_mU["wood"]==100 &&
                  runtime.catalog.recipe("ration_plain")?.input_mU["wood"]==100,
                  "formal meals and rations use the versioned wood-cost delta")
        let legacyPreview=try LifeRuntime(catalog:.bundled(),wallUTC:0,gachaMode:true,rngSeed:92)
        try check(legacyPreview.catalog.recipe("cook_basic")?.input_mU["wood"]==250 &&
                  legacyPreview.world.gacha?.goldRebalance == nil,
                  "the older preview keeps its original recipe and ten-coin ledger")
        try runtime.advance(to:300)
        for _ in 0..<2 {
            let action=LifeGachaAction.draw(count:1,pool:runtime.definition!.gacha.pool_version)
            _=try runtime.performGacha(.player(revision:runtime.world.sequence,action:action))
        }
        try check(runtime.world.treasury==0,"the player alone spends both opening draws")
        try runtime.advance(to:300+parameters.first_post_seed_draw_target_real_seconds*parameters.default_speed)
        try check(runtime.world.treasury>=100 && runtime.world.gacha!.minted>=100 &&
                  runtime.world.gacha!.minted==runtime.world.consumed["gold_ingot",default:0]/1000*parameters.coin_per_ingot,
                  "the first earned draw is backed by delivered ingots within the target")

        var oreBuffer=runtime.world
        oreBuffer.lots["fixture-mine-buffer"] = .init(id:"fixture-mine-buffer",origin:"fixture",location:"smelter-in",resource:.gold_ore,amount:40_000)
        oreBuffer.initial["gold_ore",default:0]+=40_000
        var smelting=try LifeRuntime(catalog:.bundled(),world:oreBuffer)
        while smelting.world.treasury>=100 {
            let draw=LifeGachaAction.draw(count:1,pool:smelting.world.gacha!.poolVersion(formal:true))
            _=try smelting.performGacha(.player(revision:smelting.world.sequence,action:draw))
        }
        let mintedBefore=smelting.world.gacha!.minted
        try smelting.advance(to:smelting.world.time+2_880)
        try check(smelting.world.gacha!.minted>mintedBefore &&
                  smelting.world.amount(.gold_ore)<oreBuffer.amount(.gold_ore),
                  "a full ore buffer cannot disable smelting while the player has no coins")

        var old=try LifeRuntime(catalog:.bundled(),wallUTC:0,formalHeroTown:true,rngSeed:92)
        try old.advance(to:7_200)
        var oldWorld=old.world
        let oldIngots=oldWorld.consumed["gold_ingot",default:0]/1000
        try check(oldIngots>0,"legacy fixture has a real smelting history")
        oldWorld.gacha!.goldRebalance=nil
        oldWorld.gacha!.minted=oldIngots*10
        oldWorld.treasury=200+oldWorld.gacha!.minted
        let decoded=try LifeSaveStore.decode(LifeSaveStore.encode(oldWorld))
        var migrated=try LifeRuntime(catalog:.bundled(),world:decoded)
        try check(migrated.world.treasury==oldWorld.treasury && migrated.world.gacha!.minted==oldWorld.gacha!.minted &&
                  migrated.world.gacha!.goldRebalance?.historicalIngots==oldIngots,
                  "old saves anchor historical ingots without changing their wallet")
        try migrated.advance(to:12_000)
        let newIngots=migrated.world.consumed["gold_ingot",default:0]/1000-oldIngots
        try check(newIngots>0 && migrated.world.gacha!.minted==oldIngots*10+newIngots*parameters.coin_per_ingot,
                  "newly delivered ingots use the new rate without repricing old production")
        _=try LifeSaveStore.decode(LifeSaveStore.encode(migrated.world))
        print("Economy pacing: 10/10 checks passed.")
    }
}
