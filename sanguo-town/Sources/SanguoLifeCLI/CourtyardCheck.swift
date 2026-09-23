import Foundation
import SanguoLife

enum CourtyardCheck {
    static func run() throws {
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw LifeError.invalid("共享院落验收：\(message)") }
        }
        let catalog = try LifeCatalog.bundled()
        let old = try LifeRuntime(catalog: catalog, wallUTC: 0, formalHeroTown: true, rngSeed: 7)
        let oldBytes = try LifeSaveStore.encode(old.world)
        var town = try LifeRuntime(catalog: catalog, world: LifeSaveStore.decode(oldBytes))
        try town.enableSharedCourtyards()
        let migrated = town.world
        let housing = migrated.heroTown!.courtyard!
        try check(migrated.heroTown!.city.layoutVersion == 7 && migrated.heroTown!.city.plots.count == 29,
                  "旧城升级到29个功能地块")
        try check(LifeLayout7.categoryRows.count == 7 && LifeLayout7.categoryRows.allSatisfy { $0.count == 12 } &&
                  LifeLayout7.residentialParcels.count == 15, "84格及15座院落规划")
        try check(housing.units.count == 2 && housing.legacyOccupiedLeases.count == 3 && migrated.housing == 5,
                  "开局五名真实武将保留住处，新增户位不凭空增加")
        try check(Set(housing.households.keys) == Set(migrated.agents.keys) &&
                  Set(housing.households.values.compactMap(\.unitID)).count == 5, "一人一户，不重复占位")
        try town.enableSharedCourtyards()
        try check(town.world == migrated, "重复迁移幂等")
        let roundTrip = try LifeSaveStore.decode(LifeSaveStore.encode(town.world))
        try check(roundTrip == migrated, "新住房数据可保存与恢复")
        try town.advance(to: 86_400)
        try check(town.world.heroTown!.city.plot("house-2")!.level > 0 &&
                  town.world.heroTown!.courtyard!.units.count >= 4,
                  "太守真实施工后开放第二院落户位")
        try check(town.world.heroTown!.courtyard!.legacyOccupiedLeases.count < 3,
                  "新户位建成后旧居武将自动迁居并释放过渡租约")
        let request = LifeGachaRequest.player(id: "courtyard-check-draw", revision: town.world.sequence,
                                              action: .draw(count: 1, pool: town.definition!.gacha.pool_version))
        _ = try town.performGacha(request)
        try town.advance(to: town.world.time + 60)
        try check(Set(town.world.heroTown!.courtyard!.households.keys) == Set(town.world.agents.keys),
                  "新人到达后有唯一家庭归属")
        try town.world.validate()
        print("COURTYARD_PASS migration, 84 parcels, 15 permits, households, construction, draw/arrival, save round-trip")
    }
}
