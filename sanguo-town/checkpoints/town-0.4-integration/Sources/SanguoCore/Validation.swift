import Foundation

extension WorldState {
    public func validate() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw GameError.invalid(message) }
        }
        try require((schemaVersion == 1 && rulesVersion == Self.currentRules && growth == nil) || (schemaVersion == 2 && rulesVersion == GrowthRules.version && growth != nil && realm == nil) || (schemaVersion == 3 && rulesVersion == RealmRules.version && growth != nil && realm != nil), "未知存档／规则版本")
        try require((0...31_536_000_000).contains(simulationTime) && (0...4_000_000_000_000).contains(lastWallUTC), "时钟范围")
        try require((0...1_000_000_000).contains(treasury) && (0...1_000_000_000).contains(revision), "国库／版本范围")
        try require((1...3).contains(cities.count) && districts.count <= 1 && people.count <= 64, "场景容量")
        try require(receipts.count <= 10_000 && events.count <= 100, "记录容量")
        let resources = Set(Resource.allCases.map(\.rawValue))
        var officeHolders = Set<String>()
        for key in cities.keys.sorted() {
            let city = cities[key]!
            try require(city.id == key && !key.isEmpty && city.name.count <= 80, "城市标识")
            try require((1...200).contains(city.population), "人口")
            try require((1...1_000_000_000).contains(city.inventory.capacity), "仓库容量")
            try require(Set(city.inventory.amounts.keys).isSubset(of: resources) && Set(city.inventory.reserved.keys).isSubset(of: resources), "未知物资")
            for resource in Resource.allCases {
                try require(city.inventory[resource] >= 0 && city.inventory[resource] <= city.inventory.capacity && city.inventory.free(resource) >= 0 && city.inventory.reserved[resource.rawValue, default: 0] >= 0, "库存／预留")
            }
            try require(Set(city.jobs.keys).isSubset(of: resources) && Set(city.jobCapacity.keys).isSubset(of: resources), "未知岗位")
            try require(city.jobCapacity.values.allSatisfy { (0...200).contains($0) }, "岗位容量")
            try require(city.jobs.values.allSatisfy { (0...200).contains($0) }, "岗位人数")
            try require(city.jobs.values.reduce(0, +) + (growth?.cities[key]?.builders ?? 0) + (realm?.civic[key]?.workers ?? 0) <= city.labor, "超额分配劳力")
            try require(city.jobs.allSatisfy { $0.value <= city.jobCapacity[$0.key, default: 0] }, "设施岗位不足")
            try require((0..<6).contains(city.grainRemainder), "口粮余数")
            try require((50...150).contains(city.grainRatePercent) && (50...150).contains(city.ironRatePercent), "城市禀赋")
            try require(city.lastAppointment >= 0 && city.lastAppointment <= simulationTime, "任职时间")
            guard let prefect = people[city.prefectID] else { throw GameError.invalid("太守不存在") }
            try require(prefect.cityID == key && prefect.office?.kind == .prefect && prefect.office?.scope == key, "太守必须真实到岗")
            try require(officeHolders.insert(prefect.id).inserted, "人物重复任职")
            if let districtID = city.districtID {
                try require(districts[districtID]?.cityIDs.contains(key) == true, "辖区双向关系")
            }
        }
        for (id, district) in districts {
            try require(id == district.id && !id.isEmpty && district.cityIDs.count >= 2 && district.cityIDs.count <= 3, "辖区容量")
            try require(Set(district.cityIDs).count == district.cityIDs.count, "重复辖区城市")
            try require(district.cityIDs.allSatisfy { cities[$0]?.districtID == id }, "辖区城市归属")
            try require(Set(district.talentIDs).count == district.talentIDs.count && district.talentIDs.allSatisfy { people[$0] != nil }, "人才池")
            guard let governor = people[district.governorID] else { throw GameError.invalid("都督不存在") }
            try require(governor.office?.kind == .governor && governor.office?.scope == id && district.cityIDs.contains(governor.cityID), "都督任职")
            try require(officeHolders.insert(governor.id).inserted, "都督重复任职")
        }
        for (id, person) in people {
            try require(id == person.id && !id.isEmpty && id.count <= 80 && person.name.count <= 80 && cities[person.cityID] != nil, "人物标识／地点")
            try require(person.attributes.all.allSatisfy { (1...100).contains($0) }, "五维范围")
            let domains = Set(Profession.allCases.map(\.rawValue))
            try require(Set(person.experience.keys).isSubset(of: domains) && Set(person.workSeconds.keys).isSubset(of: domains), "职业类别")
            try require(person.experience.values.allSatisfy { (0...1_000_000).contains($0) } && person.workSeconds.values.allSatisfy { (0..<3600).contains($0) }, "经验范围")
            if let office = person.office {
                try require(officeHolders.contains(id) && office.since >= 0 && office.since <= simulationTime, "游离职位")
            }
        }
        if growth != nil { try validateGrowth() }
        if realm != nil { try validateRealm() }
        for (id, receipt) in receipts {
            try require(!id.isEmpty && id.count <= 80 && receipt.fingerprint.utf8.count <= 4096 && receipt.revision > 0 && receipt.revision <= revision, "命令回执")
        }
        for event in events {
            try require(event.time >= 0 && event.time <= simulationTime && event.message.count <= 1000 && event.kind.count <= 80, "事件范围")
        }
    }
}
