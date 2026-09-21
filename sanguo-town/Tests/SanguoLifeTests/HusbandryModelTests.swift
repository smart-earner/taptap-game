import XCTest
@testable import SanguoLife

final class HusbandryModelTests: XCTestCase {
    func testPaidDeliveryIsNotImmediatelyAvailable() throws {
        var pig = LifePig(id: "pig-1", orderedAt: 0)
        pig.advancePassive(to: 299)
        XCTAssertEqual(pig.phase, .inTransit)
        pig.advancePassive(to: 300)
        XCTAssertEqual(pig.phase, .awaitingEscort)
        XCTAssertNil(pig.due)
        try pig.validate(at: 300)
    }
    func testNeedsSixFundedCareSegments() throws {
        var pig = LifePig(id: "pig-1", orderedAt: 0)
        pig.advancePassive(to: 300)
        pig.phase = .needsCare // Fixture: escorted to the completed pen.
        var clock: Int64 = 300
        for i in 0..<6 {
            try pig.beginCare(task: "care-\(i)")
            XCTAssertThrowsError(try pig.finishCare(task: "care-\(i)", at: clock))
            pig.feedConsumed = true
            clock += 30
            try pig.finishCare(task: "care-\(i)", at: clock)
            try pig.validate(at: clock)
            pig.advancePassive(to: clock + 2879)
            XCTAssertEqual(pig.phase, .growing)
            clock += 2880
            pig.advancePassive(to: clock)
            XCTAssertEqual(pig.phase, i == 5 ? .ready : .needsCare)
        }
        XCTAssertEqual(clock, 17760)
        XCTAssertEqual(pig.segmentsFed, 6)
        XCTAssertThrowsError(try pig.beginCare(task: "seventh-fee"))
        try pig.validate(at: clock)
    }
    func testDuplicateCareCannotChargeTwice() throws {
        var pig = LifePig(id: "pig-1", orderedAt: 0)
        pig.advancePassive(to: 300)
        pig.phase = .needsCare
        try pig.beginCare(task: "care")
        XCTAssertThrowsError(try pig.beginCare(task: "other"))
        pig.feedConsumed = true
        try pig.finishCare(task: "care", at: 330)
        XCTAssertThrowsError(try pig.finishCare(task: "care", at: 330))
        XCTAssertEqual(pig.segmentsFed, 1)
    }
    func testNoFeedMeansNoGrowthOrDeathEvenAfterDays() throws {
        var pig = LifePig(id: "pig-1", orderedAt: 0)
        pig.advancePassive(to: 300)
        let before = pig
        pig.advancePassive(to: 604800)
        XCTAssertEqual(pig, before)
        try pig.validate(at: 604800)
    }
    func testModelRejectsImpossibleState() throws {
        var pig = LifePig(id: "pig-1", orderedAt: 0)
        pig.phase = .ready
        pig.due = nil
        XCTAssertThrowsError(try pig.validate(at: 300))
        pig.segmentsFed = 6
        try pig.validate(at: 300)
        pig.due = 301
        XCTAssertThrowsError(try pig.validate(at: 300))
    }
    func testInTransitReservesAnimalCapacityAndRoundTrips() throws {
        var h = LifeHusbandry()
        h.pigs["pig-1"] = LifePig(id: "pig-1", orderedAt: 0)
        XCTAssertEqual(h.occupiedPlaces, 1)
        XCTAssertEqual(h.purchaseLimit, 40)
        XCTAssertEqual(try JSONDecoder().decode(LifeHusbandry.self, from: JSONEncoder().encode(h)), h)
    }
}
