import Foundation

/// Housing slice of layout 7.  The existing economic coordinates and v0.9
/// content remain authoritative while the larger parcel map is introduced.
public enum LifeLayout7 {
    public static let categoryRows = [
        "PSPLIIIIPSPL", "PHHSHHIPHHLP", "SHHPHHILPSHP",
        "IIIIIIIIIIII", "LPSPLPISPLPS", "PHLPHSIHPLPH", "SPLPSPILPSPL"
    ]
    public static let columns = 12
    public static let rows = 7
    public static let residentialParcels: [Int] = categoryRows.enumerated().flatMap { row, text in
        text.enumerated().compactMap { column, category in category == "H" ? row * columns + column : nil }
    }.sorted { a, b in
        func phase(_ id: Int) -> Int {
            let column = id % columns, row = id / columns
            if column < 8 && row < 5 { return 0 }
            if column < 10 && row < 5 { return 1 }
            if column < 10 && row < 6 { return 2 }
            return 3
        }
        return phase(a) == phase(b) ? a < b : phase(a) < phase(b)
    }
    public static func point(_ parcelID: Int) -> LifePoint {
        .init(125 + Double(parcelID % columns) * 220, 125 + Double((rows - 1) - parcelID / columns) * 205)
    }
    public static func units(for level: Int) -> Int { [0, 2, 3, 4][max(0, min(3, level))] }
    public static func people(for level: Int) -> Int { [0, 4, 6, 8][max(0, min(3, level))] }

    public static func category(for kind: String) -> Character {
        switch kind {
        case "house": return "H"
        case "farm", "workshop", "goldmine", "smelter", "station", "barracks": return "P"
        case "hall", "granary", "tavern", "clinic": return "S"
        default: return "L"
        }
    }
}

public struct LifeHousehold: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var memberPersonIDs: [String]
    public var residencePlotID: String
    public var unitID: String?
    public var createdAt: Int64
    public init(id:String,memberPersonIDs:[String],residencePlotID:String,unitID:String?,createdAt:Int64) {
        self.id=id;self.memberPersonIDs=memberPersonIDs;self.residencePlotID=residencePlotID
        self.unitID=unitID;self.createdAt=createdAt
    }
}

public struct LifeResidentialUnit: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var parcelID: Int
    public var plotID: String
    public var occupantHouseholdID: String?
    public init(id:String,parcelID:Int,plotID:String,occupantHouseholdID:String?) {
        self.id=id;self.parcelID=parcelID;self.plotID=plotID;self.occupantHouseholdID=occupantHouseholdID
    }
}

public struct LifeCourtyardState: Codable, Equatable, Sendable {
    public var unlockedColumns: Int = 8
    public var unlockedRows: Int = 5
    public var parcelByPlotID: [String: Int] = [:]
    public var households: [String: LifeHousehold] = [:] // keyed by heroID in this slice
    public var units: [String: LifeResidentialUnit] = [:]
    public var legacyOccupiedLeases: [String: String] = [:] // heroID -> old plotID
    public static func initial() -> Self { .init() }

    public var formalCapacity: Int { units.count + legacyOccupiedLeases.count }
    public var freeUnits: Int { units.values.filter { $0.occupantHouseholdID == nil }.count }
    public func unitID(plotID: String) -> String? {
        units.values.filter { $0.plotID == plotID && $0.occupantHouseholdID == nil }.map(\.id).sorted().first
    }
}

extension LifeRuntime {
    /// Idempotent, in-memory migration. The caller persists its candidate only
    /// after ordinary world validation; an old save remains recoverable on error.
    public mutating func enableSharedCourtyards() throws {
        guard world.isFormalHeroTown, var formal = world.heroTown else { return }
        guard formal.courtyard == nil else { return }
        var courtyard = LifeCourtyardState.initial()
        var available: [Character: [Int]] = [:]
        for row in 0..<5 {
            for column in 0..<8 {
                let category = Array(LifeLayout7.categoryRows[row])[column]
                available[category, default: []].append(row * 12 + column)
            }
        }
        let existing = formal.city.plots.sorted { $0.id < $1.id }
        for plot in existing {
            let category = LifeLayout7.category(for: plot.kind)
            guard let parcel = available[category]?.first else {
                throw LifeError.invalid("共享院落迁移地块不足：\(plot.kind)")
            }
            available[category]!.removeFirst()
            courtyard.parcelByPlotID[plot.id] = parcel
        }
        // The clinic is a persisted facility outside the old 18 plot array.
        guard let clinicParcel = available["S"]?.first else { throw LifeError.invalid("共享院落缺少医舍地块") }
        available["S"]!.removeFirst()
        courtyard.parcelByPlotID["clinic-1"] = clinicParcel

        let usedHouseParcels = Set(courtyard.parcelByPlotID.filter { $0.key.hasPrefix("house-") }.map(\.value))
        let openHouses = LifeLayout7.residentialParcels.filter { !usedHouseParcels.contains($0) }
        for (offset, parcel) in openHouses.enumerated() {
            let number = offset + 5
            let id = "house-\(number)"
            courtyard.parcelByPlotID[id] = parcel
            formal.city.plots.append(.init(id: id, index: formal.city.plots.count, kind: "house", node: "home-\(number)",
                                           point: LifeLayout7.point(parcel), level: 0, capacity: 0, occupancy: 0,
                                           service: 0, developmentPermit: number <= 8, identity: id))
        }
        for plot in formal.city.plots where plot.kind == "house" && plot.level > 0 {
            guard let parcel = courtyard.parcelByPlotID[plot.id] else { continue }
            for slot in 1...LifeLayout7.units(for: plot.level) {
                let id = "house:\(parcel):\(slot)"
                courtyard.units[id] = .init(id: id, parcelID: parcel, plotID: plot.id, occupantHouseholdID: nil)
            }
        }
        // Old reserved beds for travellers are released. On actual arrival they
        // will obtain a free unit, or use a real tavern guest bed.
        for heroID in (world.gacha?.arrivals.keys ?? [:].keys).sorted() {
            guard var owned = formal.ownedHeroes[heroID] else { continue }
            if let index = formal.city.plots.firstIndex(where: { $0.id == owned.bedReservation }) {
                formal.city.plots[index].occupancy = max(0, formal.city.plots[index].occupancy - 1)
            }
            owned.bedReservation = "tavern-1.guest"
            formal.ownedHeroes[heroID] = owned
        }
        for heroID in world.agents.keys.sorted() {
            guard let agent = world.agents[heroID] else { continue }
            let owned = formal.ownedHeroes[heroID]
            let plotID = agent.home == "tavern" ? "tavern-1" : (owned?.bedReservation ?? "house-1")
            let householdID = "household:\(heroID)"
            var unitID: String?
            if plotID != "tavern-1" {
                if let availableID = courtyard.unitID(plotID: plotID) {
                    courtyard.units[availableID]!.occupantHouseholdID = householdID
                    unitID = availableID
                } else {
                    unitID = "legacy:\(heroID)"
                    courtyard.legacyOccupiedLeases[heroID] = plotID
                }
            }
            courtyard.households[heroID] = .init(id: householdID, memberPersonIDs: ["hero:\(heroID)"],
                                                 residencePlotID: plotID, unitID: unitID, createdAt: world.time)
        }
        formal.city.layoutVersion = 7
        formal.courtyard = courtyard
        world.heroTown = formal
        syncFormalCapacities()
        try world.validate()
    }
}
