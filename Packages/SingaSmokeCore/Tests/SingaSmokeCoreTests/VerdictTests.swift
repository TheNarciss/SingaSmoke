import XCTest
@testable import SingaSmokeCore

/// A miniature Orchard: an NSZ with one yellow box, a park, a bus stop, a community spot.
final class VerdictTests: XCTestCase {
    private let nsz = Fixtures.polygonZone(id: "nsz", kind: .nsz, source: .nea,
                                           rings: [Fixtures.rect(x0: 0, y0: 0, x1: 1000, y1: 400)])
    private let park = Fixtures.polygonZone(id: "park", kind: .park, source: .nparks,
                                            rings: [Fixtures.rect(x0: 2000, y0: 0, x1: 2400, y1: 400)])
    private let busStop = Fixtures.pointZone(id: "bus", kind: .busStop, at: Fixtures.at(2405, 200), radius: 11)
    private let yellowBox = Fixtures.spot("dsa", .nea, at: Fixtures.at(500, 200))
    private let communityInPark = Fixtures.spot("osm-park", .osmArea, at: Fixtures.at(2200, 200))
    private let communityInTheOpen = Fixtures.spot("osm-open", .osmVenue, at: Fixtures.at(3000, 1000))

    private var spots: [SmokingSpot] { [yellowBox, communityInPark, communityInTheOpen] }
    private var index: ZoneIndex { ZoneIndex(zones: [nsz, park, busStop]) }

    private func verdict(_ x: Double, _ y: Double, accuracy: Double = 5) -> Verdict {
        VerdictEngine.evaluate(fix: Fixtures.fix(Fixtures.at(x, y), accuracy: accuracy), spots: spots, index: index)
    }

    func testNoFix() {
        guard case .noLocation = VerdictEngine.evaluate(fix: nil, spots: spots, index: index) else {
            return XCTFail("expected noLocation")
        }
    }

    func testOutsideSingapore() {
        let paris = GPSFix(coordinate: Coordinate(latitude: 48.8566, longitude: 2.3522), horizontalAccuracy: 5)
        guard case .outsideSingapore = VerdictEngine.evaluate(fix: paris, spots: spots, index: index) else {
            return XCTFail("expected outsideSingapore")
        }
    }

    func testYellowBoxWinsOverTheZoneAroundIt() {
        guard case .atSpot(let spot, let distance, let caution) = verdict(510, 205) else {
            return XCTFail("expected atSpot")
        }
        XCTAssertEqual(spot.id, "dsa")
        XCTAssertLessThan(distance, 20)
        XCTAssertNil(caution)
    }

    func testInsideTheZoneAwayFromTheBox() {
        guard case .prohibited(let hit, let others, let spotHere) = verdict(100, 200) else {
            return XCTFail("expected prohibited")
        }
        XCTAssertEqual(hit.zone.kind, .nsz)
        XCTAssertTrue(others.isEmpty)
        XCTAssertNil(spotHere)
        XCTAssertTrue(hit.isCertain)
        XCTAssertEqual(hit.exitDirection, .west)
        XCTAssertEqual(hit.exitDistance, 105, accuracy: 1, "100 m to the west edge + 5 m margin")
    }

    func testInsideButWithinGPSErrorOfTheEdgeIsNotCertain() {
        guard case .prohibited(let hit, _, _) = verdict(990, 200, accuracy: 30) else {
            return XCTFail("expected prohibited")
        }
        XCTAssertFalse(hit.isCertain)
    }

    func testCommunitySpotInsideAParkDoesNotOverrideTheBan() {
        guard case .prohibited(let hit, _, let spotHere) = verdict(2200, 205) else {
            return XCTFail("expected prohibited")
        }
        XCTAssertEqual(hit.zone.id, "park")
        XCTAssertEqual(spotHere?.id, "osm-park")
    }

    func testOfficialZoneIsReportedFirst() {
        // At the park's east edge, inside both the park and the bus stop's 11 m radius.
        guard case .prohibited(let hit, let others, _) = verdict(2398, 200) else {
            return XCTFail("expected prohibited")
        }
        XCTAssertEqual(hit.zone.id, "park")
        XCTAssertEqual(others.map(\.zone.id), ["bus"])
    }

    func testNearTheEdgeWithinGPSError() {
        guard case .nearZone(let hit) = verdict(1015, 200, accuracy: 25) else {
            return XCTFail("expected nearZone")
        }
        XCTAssertEqual(hit.zone.id, "nsz")
        XCTAssertEqual(hit.signedDistance, 15, accuracy: 0.5)
    }

    func testSameSpotWithAPreciseFixIsClear() {
        guard case .clear(let nearby) = verdict(1015, 200, accuracy: 5) else {
            return XCTFail("expected clear")
        }
        XCTAssertEqual(nearby?.zone.id, "nsz", "the zone 15 m away is mentioned")
    }

    func testAtACommunitySpotInTheOpen() {
        guard case .atSpot(let spot, _, let caution) = verdict(3005, 1000) else {
            return XCTFail("expected atSpot")
        }
        XCTAssertEqual(spot.id, "osm-open")
        XCTAssertNil(caution)
    }

    func testFarFromEverything() {
        guard case .clear(let nearby) = verdict(5000, 5000) else {
            return XCTFail("expected clear")
        }
        XCTAssertNil(nearby)
    }

    func testEffectiveAccuracyIsClamped() {
        XCTAssertEqual(GPSFix(coordinate: Fixtures.origin, horizontalAccuracy: -1).effectiveAccuracy, 50)
        XCTAssertEqual(GPSFix(coordinate: Fixtures.origin, horizontalAccuracy: 2).effectiveAccuracy, 5)
        XCTAssertEqual(GPSFix(coordinate: Fixtures.origin, horizontalAccuracy: 500).effectiveAccuracy, 100)
        XCTAssertEqual(GPSFix(coordinate: Fixtures.origin, horizontalAccuracy: 12).effectiveAccuracy, 12)
    }
}

final class RankingTests: XCTestCase {
    func testNearestIsSortedAndLimited() {
        let spots = [
            Fixtures.spot("c", .nea, at: Fixtures.at(300, 0)),
            Fixtures.spot("a", .nea, at: Fixtures.at(100, 0)),
            Fixtures.spot("b", .nea, at: Fixtures.at(0, 200)),
            Fixtures.spot("d", .nea, at: Fixtures.at(0, -900)),
        ]
        let ranked = Ranking.nearest(spots, to: Fixtures.origin, limit: 3)
        XCTAssertEqual(ranked.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(ranked[0].straightLine, 100, accuracy: 0.2)
        XCTAssertTrue(ranked[0].walking.isEstimate)
        XCTAssertEqual(ranked[0].walking.meters, 130, accuracy: 0.3)
        XCTAssertTrue(Ranking.nearest(spots, to: Fixtures.origin, limit: 0).isEmpty)
    }

    func testReorderByWalkingDistance() {
        var ranked = Ranking.nearest([
            Fixtures.spot("across-the-canal", .nea, at: Fixtures.at(100, 0)),
            Fixtures.spot("straight-ahead", .nea, at: Fixtures.at(0, 150)),
        ], to: Fixtures.origin, limit: 2)
        ranked[0].walking = WalkingDistance(meters: 900, seconds: 700, isEstimate: false)
        ranked[1].walking = WalkingDistance(meters: 170, seconds: 130, isEstimate: false)
        XCTAssertEqual(Ranking.byWalking(ranked).map(\.id), ["straight-ahead", "across-the-canal"])
    }

    func testWalkingEstimate() {
        let w = WalkingDistance.estimate(straightLine: 800)
        XCTAssertEqual(w.meters, 1040, accuracy: 0.01)
        XCTAssertEqual(w.seconds, 1040 / (4.8 / 3.6), accuracy: 0.01)
        XCTAssertTrue(w.isEstimate)
    }
}

final class FormatTests: XCTestCase {
    func testDistance() {
        XCTAssertEqual(Format.distance(0.3), "1 m")
        XCTAssertEqual(Format.distance(8), "8 m")
        XCTAssertEqual(Format.distance(43), "45 m")
        XCTAssertEqual(Format.distance(349), "350 m")
        XCTAssertEqual(Format.distance(944), "940 m")
        XCTAssertEqual(Format.distance(960), "1,0 km")
        XCTAssertEqual(Format.distance(1234), "1,2 km")
        XCTAssertEqual(Format.distance(9_960), "10 km")
        XCTAssertEqual(Format.distance(12_345), "12 km")
        XCTAssertEqual(Format.distance(.infinity), "—")
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(20), "< 1 min")
        XCTAssertEqual(Format.duration(300), "5 min")
        XCTAssertEqual(Format.duration(3_900), "1 h 05")
        XCTAssertEqual(Format.duration(4_500), "1 h 15")
    }

    func testWalking() {
        XCTAssertEqual(Format.walking(WalkingDistance(meters: 350, seconds: 300, isEstimate: false)), "350 m · 5 min à pied")
        XCTAssertEqual(Format.walking(WalkingDistance(meters: 350, seconds: 300, isEstimate: true)), "≈ 350 m · 5 min à pied")
        XCTAssertEqual(Format.spokenWalking(WalkingDistance(meters: 1_234, seconds: 900, isEstimate: true)),
                       "1 virgule 2 kilomètres, 15 minutes à pied, estimation")
    }

    func testDate() {
        XCTAssertEqual(Format.date("2026-09-19"), "19/09/2026")
        XCTAssertNil(Format.date(nil))
        XCTAssertNil(Format.date("2026"))
    }
}
