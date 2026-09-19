import Foundation

enum Economy {
    /// G1 slice: atomic 10-minute production batches; no project queue or trade contracts yet.
    static func tick(world: inout WorldState) {
        var activeCities = Set<String>()
        for id in world.cities.keys.sorted() {
            var city = world.cities[id]!
            func workers(_ r: Resource) -> Int64 { Int64(city.jobs[r.rawValue, default: 0]) }
            city.inventory.add(.grain, workers(.grain) * 5_000 * city.grainRatePercent / 100)
            city.inventory.add(.wood, workers(.wood) * 6_000)
            city.inventory.add(.iron, workers(.iron) * 2_000 * city.ironRatePercent / 100)
            let numerator = Int64(city.population) * 500 + city.grainRemainder
            let need = numerator / 6
            city.grainRemainder = numerator % 6
            let paid = min(need, city.inventory.free(.grain))
            city.inventory[.grain] -= paid
            if paid == need { activeCities.insert(id) }
            // Process only whole supported batches and protect all reservations + food floor.
            let wineWorkers = workers(.wine)
            let batches = min(wineWorkers, max(0, (city.inventory.free(.grain) - city.grainFloor) / 5_000),
                              (city.inventory.capacity - city.inventory[.wine]) / 1_000)
            city.inventory[.grain] -= batches * 5_000
            city.inventory[.wine] += batches * 1_000
            let tools = min(workers(.tools), city.inventory.free(.wood) / 2_000,
                            city.inventory.free(.iron) / 1_000,
                            (city.inventory.capacity - city.inventory[.tools]) / 500)
            city.inventory[.wood] -= tools * 2_000; city.inventory[.iron] -= tools * 1_000
            city.inventory[.tools] += tools * 500
            world.cities[id] = city
            if paid == need {
                let since = world.people[city.prefectID]?.office?.since ?? world.simulationTime
                world.people[city.prefectID]?.credit(.governance, seconds: Int(min(600, world.simulationTime - since)))
            }
        }
        for district in world.districts.values.sorted(by: { $0.id < $1.id }) {
            if district.cityIDs.allSatisfy({ activeCities.contains($0) }) {
                // One governor credit per tick, not one credit per city.
                let since = world.people[district.governorID]?.office?.since ?? world.simulationTime
                world.people[district.governorID]?.credit(.coordination, seconds: Int(min(600, world.simulationTime - since)))
            }
        }
        if world.simulationTime % 3600 == 0 {
            world.record("hour", "第\(world.simulationTime / 3600)模拟小时：\(activeCities.count)/\(world.cities.count)城按时供粮，已结算在岗经历。")
        }
    }
}
