import Foundation
import Testing
@testable import SanguoCore

@Suite("Sanguo core runtime")
struct CoreTests {
    private func demo() throws -> WorldState {
        var world = Seed.threeCityDemo(wallUTC: 1_000)
        try GameEngine.apply(.init(id: "district", expectedRevision: 0,
            action: .establishDistrict(id: "east", cityIDs: ["plain", "stone", "river"], governorID: "xunyu")), to: &world)
        return world
    }
    @Test func oneCityIsNotThreeCityGift() throws {
        let world = Seed.oneCity(wallUTC: 1_000)
        try world.validate()
        #expect(world.cities.count == 1 && world.districts.isEmpty && world.people.count == 1)
    }
    @Test func fiveAttributesWithinBounds() throws {
        var world = try demo(); world.people["liang"]!.attributes.administration = 101
        #expect(throws: GameError.self) { try world.validate() }
    }
    @Test func unknownRulesRejected() {
        var world = Seed.oneCity(wallUTC: 0); world.rulesVersion = "future"
        #expect(throws: GameError.self) { try world.validate() }
    }
    @Test func negativeStockRejected() {
        var world = Seed.oneCity(wallUTC: 0); world.cities["plain"]!.inventory[.grain] = -1
        #expect(throws: GameError.self) { try world.validate() }
    }
    @Test func overReservationRejected() {
        var world = Seed.oneCity(wallUTC: 0); world.cities["plain"]!.inventory.reserved["grain"] = 900_000
        #expect(throws: GameError.self) { try world.validate() }
    }
    @Test func overLaborRejected() {
        var world = Seed.oneCity(wallUTC: 0); world.cities["plain"]!.jobs = ["grain": 100]
        #expect(throws: GameError.self) { try world.validate() }
    }
    @Test func staleCommandRollsBack() {
        var world = Seed.oneCity(wallUTC: 0)
        let before = world
        #expect(throws: GameError.stale) { try GameEngine.apply(.init(id: "bad", expectedRevision: 9, action: .setPolicy(scope: .realm, policy: .trade)), to: &world) }
        #expect(world == before)
    }
    @Test func duplicateCommandReturnsOriginalReceipt() throws {
        var world = Seed.oneCity(wallUTC: 0)
        let command = GameCommand(id: "policy", expectedRevision: 0, action: .setPolicy(scope: .realm, policy: .trade))
        let receipt = try GameEngine.apply(command, to: &world), before = world
        #expect(try GameEngine.apply(command, to: &world) == receipt)
        #expect(world == before)
    }
    @Test func reusedIDWithDifferentActionRejected() throws {
        var world = Seed.oneCity(wallUTC: 0)
        try GameEngine.apply(.init(id: "policy", expectedRevision: 0, action: .setPolicy(scope: .realm, policy: .trade)), to: &world)
        #expect(throws: GameError.duplicateID) {
            try GameEngine.apply(.init(id: "policy", expectedRevision: world.revision, action: .setPolicy(scope: .realm, policy: .industry)), to: &world)
        }
    }
    @Test func prefectCannotSetRealmPolicy() {
        var world = Seed.oneCity(wallUTC: 0)
        #expect(throws: GameError.self) {
            try GameEngine.apply(.init(id: "escape", expectedRevision: 0, principal: .person("npc-plain"), action: .setPolicy(scope: .realm, policy: .military)), to: &world)
        }
    }
    @Test func governorAppointsLocalPrefects() throws {
        var world = try demo()
        try GameEngine.advance(to: 4_600, world: &world)
        #expect(world.cities["stone"]!.prefectID == "liang")
        #expect(world.cities["river"]!.prefectID == "lusu")
        #expect(world.people["xunyu"]!.office?.kind == .governor)
        try world.validate()
    }
    @Test func lockedPrefectIsNotReplaced() throws {
        var world = try demo(); world.people["npc-stone"]!.locked = true
        try GameEngine.advance(to: 4_600, world: &world)
        #expect(world.cities["stone"]!.prefectID == "npc-stone")
    }
    @Test func governorCannotUseTalentOutsidePool() throws {
        var world = try demo(); world.districts["east"]!.talentIDs.removeAll { $0 == "liang" }
        #expect(throws: GameError.self) {
            try GameEngine.apply(.init(id: "outside", expectedRevision: world.revision, principal: .person("xunyu"), action: .appointPrefect(cityID: "stone", personID: "liang")), to: &world)
        }
    }
    @Test func prefectCannotAppointAnotherPrefect() throws {
        var world = try demo()
        #expect(throws: GameError.self) {
            try GameEngine.apply(.init(id: "outside", expectedRevision: world.revision, principal: .person("npc-plain"), action: .appointPrefect(cityID: "stone", personID: "liang")), to: &world)
        }
    }
    @Test func cannotTeleportPerson() throws {
        var world = try demo(); let before = world
        #expect(throws: GameError.self) {
            try GameEngine.apply(.init(id: "teleport", expectedRevision: world.revision, action: .appointPrefect(cityID: "plain", personID: "liang")), to: &world)
        }
        #expect(world == before)
    }
    @Test func onePersonCannotBeGovernorAndPrefect() throws {
        var world = try demo()
        #expect(throws: GameError.self) {
            try GameEngine.apply(.init(id: "double", expectedRevision: world.revision, action: .appointPrefect(cityID: "plain", personID: "xunyu")), to: &world)
        }
    }
    @Test func oneCityCannotFormMultiCityDistrict() {
        var world = Seed.oneCity(wallUTC: 0)
        #expect(throws: GameError.self) {
            try GameEngine.apply(.init(id: "district", expectedRevision: 0, action: .establishDistrict(id: "east", cityIDs: ["plain"], governorID: "npc-plain")), to: &world)
        }
    }
    @Test func policyChangesActualOutput() throws {
        var trade = try demo(), industry = trade
        try GameEngine.apply(.init(id: "policy", expectedRevision: trade.revision, action: .setPolicy(scope: .realm, policy: .trade)), to: &trade)
        try GameEngine.apply(.init(id: "policy", expectedRevision: industry.revision, action: .setPolicy(scope: .realm, policy: .industry)), to: &industry)
        try GameEngine.advance(to: 22_600, world: &trade)
        try GameEngine.advance(to: 22_600, world: &industry)
        #expect(trade.cities["plain"]!.inventory[.wine] > industry.cities["plain"]!.inventory[.wine])
        #expect(industry.cities["plain"]!.inventory[.tools] > trade.cities["plain"]!.inventory[.tools])
    }
    @Test func supplyFloorBeatsTradePolicy() throws {
        var world = try demo(); world.policy = .trade
        world.cities["plain"]!.inventory[.grain] = 0
        try GameEngine.advance(to: 1_600, world: &world)
        #expect(world.cities["plain"]!.jobs["grain"] == 4)
    }
    @Test func productionDoesNotConsumeReservedGrain() throws {
        var world = try demo(); world.policy = .trade
        world.cities["plain"]!.inventory.reserved["grain"] = 200_000
        try GameEngine.advance(to: 4_600, world: &world)
        #expect(world.cities["plain"]!.inventory[.grain] >= 200_000)
    }
    @Test func splitAndWholeAdvanceMatchExactly() throws {
        var whole = try demo(), split = whole
        try GameEngine.advance(to: 87_400, world: &whole)
        for target in stride(from: Int64(1_001), through: 87_399, by: 137) { try GameEngine.advance(to: target, world: &split) }
        try GameEngine.advance(to: 87_400, world: &split)
        #expect(whole == split)
    }
    @Test func subBatchTimeDoesNotGenerateResources() throws {
        var world = Seed.oneCity(wallUTC: 1000); let inventory = world.cities["plain"]!.inventory
        try GameEngine.advance(to: 1599, world: &world)
        #expect(world.cities["plain"]!.inventory == inventory)
        #expect(world.simulationTime == 599)
    }
    @Test func repeatedWallTimeIsNoOp() throws {
        var world = try demo(); try GameEngine.advance(to: 5000, world: &world)
        let before = world
        let result = try GameEngine.advance(to: 5000, world: &world)
        #expect(result.tickCount == 0 && world == before)
    }
    @Test func backwardsClockDoesNotMoveWatermark() throws {
        var world = Seed.oneCity(wallUTC: 1000)
        try GameEngine.advance(to: 900, world: &world)
        #expect(world.lastWallUTC == 1000 && world.simulationTime == 0)
    }
    @Test func sevenDayRestCannotBeClaimedTwice() throws {
        var world = Seed.oneCity(wallUTC: 1000)
        let target: Int64 = 1000 + 10 * 86400
        let result = try GameEngine.advance(to: target, world: &world), before = world
        #expect(result.simulatedSeconds == 7 * 86400 && result.restedSeconds == 3 * 86400)
        try GameEngine.advance(to: target, world: &world)
        #expect(world == before)
        try GameEngine.advance(to: target + 600, world: &world)
        #expect(world.simulationTime == 7 * 86400 + 600)
    }
    @Test func ongoingOfficeDoesNotExpire() throws {
        var world = try demo(); try GameEngine.advance(to: 1000 + 3 * 86400, world: &world)
        #expect(world.people["xunyu"]!.office?.kind == .governor)
        #expect(world.policy == .supply)
    }
    @Test func experienceRequiresActualWorkNotAppointments() throws {
        var world = try demo()
        try GameEngine.apply(.init(id: "appoint", expectedRevision: world.revision, action: .appointPrefect(cityID: "stone", personID: "liang")), to: &world)
        #expect(world.people["liang"]!.experience.isEmpty)
        try GameEngine.advance(to: 4600, world: &world)
        #expect(world.people["liang"]!.experience["governance"] == 10)
    }
    @Test func governorExperienceNotMultipliedByCities() throws {
        var world = try demo(); try GameEngine.advance(to: 8200, world: &world)
        #expect(world.people["xunyu"]!.experience["coordination"] == 20)
    }
    @Test func idlePeopleDoNotGainWorkExperience() throws {
        var world = try demo(); try GameEngine.advance(to: 8200, world: &world)
        #expect(world.people["zhangfei"]!.experience.isEmpty)
    }
    @Test func budgetReservationAndConsumptionConserveAllowance() throws {
        var budget = try BudgetLedger(grant: 100)
        try budget.reserve(id: "a", amount: 60); try budget.reserve(id: "a", amount: 60)
        #expect(budget.reserved == 60 && budget.available == 40)
        try budget.consume(id: "a")
        #expect(budget.spent == 60 && budget.reserved == 0 && budget.available == 40)
        #expect(throws: GameError.self) { try budget.consume(id: "a") }
    }
    @Test func budgetRejectsOverdrawAndNegative() throws {
        var budget = try BudgetLedger(grant: 100)
        #expect(throws: GameError.self) { try budget.reserve(id: "a", amount: 101) }
        #expect(throws: GameError.self) { try budget.reserve(id: "a", amount: -1) }
        #expect(budget.available == 100)
    }
    @Test func releaseDoesNotRefundSpentMoney() throws {
        var budget = try BudgetLedger(grant: 100)
        try budget.reserve(id: "a", amount: 70); try budget.consume(id: "a")
        try budget.reserve(id: "b", amount: 20); try budget.release(id: "b")
        #expect(budget.available == 30 && budget.spent == 70)
    }
    @Test func saveRoundTripIncludesReceipts() throws {
        var world = try demo(); try GameEngine.advance(to: 8200, world: &world)
        let decoded = try SaveStore.decode(SaveStore.encode(world))
        #expect(world == decoded)
    }
    @Test func corruptedSaveIsRejected() throws {
        let data = try SaveStore.encode(Seed.oneCity(wallUTC: 1000))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["checksum"] = "wrong"
        let corrupted = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: GameError.self) { try SaveStore.decode(corrupted) }
    }
    @Test func oversizedSaveIsRejectedBeforeDecode() {
        let data = Data(repeating: 0, count: SaveStore.maximumBytes + 1)
        #expect(throws: GameError.self) { try SaveStore.decode(data) }
    }
    @Test func backupsAndCorruptionNeverSilentlyResetWorld() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SaveStore(fileURL: dir.appendingPathComponent("world.json"))
        var world = Seed.oneCity(wallUTC: 1000)
        try store.save(world)
        for hour in 1...4 { try GameEngine.advance(to: 1000 + Int64(hour) * 3600, world: &world); try store.save(world) }
        #expect(try store.load() == world)
        #expect(store.backupURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        try Data("corrupt".utf8).write(to: store.fileURL)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(throws: (any Error).self) { try store.save(world) }
        #expect(try Data(contentsOf: store.fileURL) == Data("corrupt".utf8))
    }
    @Test func persistenceFailureDoesNotCommitMemory() async throws {
        struct FailingStore: WorldPersistence {
            func save(_ world: WorldState) throws { throw GameError.invalid("injected disk failure") }
        }
        let world = Seed.oneCity(wallUTC: 1000)
        let session = try GameSession(world: world, persistence: FailingStore())
        await #expect(throws: GameError.self) {
            try await session.send(.init(id: "policy", expectedRevision: 0, action: .setPolicy(scope: .realm, policy: .trade)))
        }
        #expect(await session.snapshot() == world)
    }
    @Test func concurrentSameCommandOnlyCommitsOnce() async throws {
        let session = try GameSession(world: Seed.oneCity(wallUTC: 1000))
        let command = GameCommand(id: "one", expectedRevision: 0, action: .setPolicy(scope: .realm, policy: .trade))
        try await withThrowingTaskGroup(of: Receipt.self) { group in
            for _ in 0..<20 { group.addTask { try await session.send(command) } }
            for try await receipt in group { #expect(receipt.revision == 1) }
        }
        #expect(await session.snapshot().receipts.count == 1)
    }
    @Test func appointmentAtTickCannotEarnPreviousHour() throws {
        var world = try demo()
        try GameEngine.advance(to: 4600, world: &world)
        #expect(world.people["liang"]!.experience.isEmpty)
        #expect(world.people["npc-stone"]!.experience["governance"] == 10)
    }
    @Test func policyOverrideDoesNotLeakIntoOtherCities() throws {
        var world = try demo()
        try GameEngine.apply(.init(id: "city-policy", expectedRevision: world.revision,
            principal: .person("npc-stone"), action: .setPolicy(scope: .city("stone"), policy: .industry)), to: &world)
        #expect(world.policy(for: world.cities["stone"]!) == .industry)
        #expect(world.policy(for: world.cities["plain"]!) == .supply)
    }

}
