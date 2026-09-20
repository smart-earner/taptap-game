import Foundation

public enum Seed {
    public static func oneCity(wallUTC: Int64) -> WorldState {
        var world = WorldState(wallUTC: wallUTC)
        addCity(id: "plain", name: "平川", world: &world)
        return world
    }
    /// Explicit test/demo fixture. Never grants three cities in the normal new-game flow.
    public static func threeCityDemo(wallUTC: Int64) -> WorldState {
        var world = oneCity(wallUTC: wallUTC)
        addCity(id: "stone", name: "白石", world: &world)
        addCity(id: "river", name: "南渡", world: &world)
        for id in world.cities.keys.sorted() {
            world.cities[id]?.population = 16
            world.cities[id]?.jobCapacity = ["grain": 4, "wood": 2, "iron": 2, "wine": 4, "tools": 4]
        }
        world.cities["plain"]?.grainRatePercent = 125
        world.cities["stone"]?.grainRatePercent = 80
        world.cities["stone"]?.ironRatePercent = 125
        let templates: [(String, String, String, Attributes)] = [
            ("xunyu", "荀彧", "plain", .init(command: 55, valor: 35, strategy: 88, administration: 94, charisma: 85)),
            ("liang", "诸葛亮", "stone", .init(command: 85, valor: 35, strategy: 96, administration: 92, charisma: 84)),
            ("lusu", "鲁肃", "river", .init(command: 70, valor: 40, strategy: 84, administration: 86, charisma: 94)),
            ("zhaoyun", "赵云", "plain", .init(command: 92, valor: 94, strategy: 74, administration: 62, charisma: 82)),
            ("guanyu", "关羽", "stone", .init(command: 90, valor: 96, strategy: 72, administration: 60, charisma: 80)),
            ("zhangfei", "张飞", "river", .init(command: 88, valor: 97, strategy: 55, administration: 42, charisma: 60))
        ]
        for (id, name, city, attributes) in templates {
            world.people[id] = .init(id: id, name: name, cityID: city, attributes: attributes)
        }
        return world
    }
    private static func addCity(id: String, name: String, world: inout WorldState) {
        let npcID = "npc-\(id)"
        world.people[npcID] = .init(id: npcID, name: "\(name)代理太守", cityID: id,
            office: .init(kind: .prefect, scope: id, since: 0), isProxy: true)
        world.cities[id] = .init(id: id, name: name, prefectID: npcID)
        Governance.plan(cityID: id, world: &world)
    }
}
