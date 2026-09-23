import Foundation

/// Optional economy delta for the formal desktop town. Older preview worlds keep
/// the v0.9 recipe and mint ledger; a formal save records its mint transition.
public struct LifeEconomyPacing: Decodable, Sendable {
    public let spec_version: String
    public let coin_per_ingot: Int64
    public let recipe_wood_mU: [String:Int64]
    public let first_post_seed_draw_target_real_seconds: Int64
    public let default_speed: Int64
    public let simulated_day_seconds: Int64
    public let meals_per_hero_per_cycle: Int64
    public let soldier_rations_per_real_day_numerator: Int64
    public let soldier_rations_per_real_day_denominator: Int64

    public static func bundled() throws -> Self {
        let url=Bundle.main.url(forResource:"hero-town-v0.12-economy-delta",withExtension:"json",subdirectory:"HeroTown12")
            ?? Bundle.module.url(forResource:"hero-town-v0.12-economy-delta",withExtension:"json")
        guard let url else {throw LifeError.invalid("缺少v0.12经济节奏参数包")}
        let value=try JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
        guard value.spec_version=="0.12.0-economy-preview1",
              (10...1000).contains(value.coin_per_ingot),
              value.recipe_wood_mU.keys.sorted()==["cook_basic","cook_meat","ration_plain"],
              value.recipe_wood_mU.values.allSatisfy({(1...250).contains($0)}),
              value.default_speed==2,value.simulated_day_seconds==2880,
              value.meals_per_hero_per_cycle==2,
              value.soldier_rations_per_real_day_numerator==1,
              value.soldier_rations_per_real_day_denominator==2,
              value.first_post_seed_draw_target_real_seconds>0
        else {throw LifeError.invalid("v0.12经济参数不合法")}
        return value
    }

    public func apply(to catalog:inout LifeCatalog) {
        for index in catalog.recipes.indices {
            let id=catalog.recipes[index].id
            if let wood=recipe_wood_mU[id] {catalog.recipes[index].input_mU["wood"]=wood}
        }
    }

    /// Demand budget, not a claim that existing buildings can produce this much.
    public func dailyDemand(heroCount:Int,soldierCount:Int) -> (grain:Int64,wood:Int64,mealBatches:Int64,rationBatches:Int64) {
        let cycles=86_400*default_speed/simulated_day_seconds
        let meals=Int64(heroCount)*meals_per_hero_per_cycle*cycles
        let mealBatches=(meals+3)/4
        let rations=(Int64(soldierCount)*soldier_rations_per_real_day_numerator+soldier_rations_per_real_day_denominator-1)/soldier_rations_per_real_day_denominator
        let rationBatches=(rations+3)/4
        return (mealBatches+rationBatches,
                (mealBatches*recipe_wood_mU["cook_basic"]!+rationBatches*recipe_wood_mU["ration_plain"]!),
                mealBatches,rationBatches)
    }
}
