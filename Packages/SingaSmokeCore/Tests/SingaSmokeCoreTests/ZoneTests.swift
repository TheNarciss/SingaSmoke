import XCTest
@testable import SingaSmokeCore

final class ZoneTests: XCTestCase {
    func testBusStopRadius() {
        let stop = Fixtures.pointZone(id: "bus", kind: .busStop, at: Fixtures.at(0, 0), radius: 11)
        XCTAssertEqual(stop.signedDistance(to: Fixtures.at(5, 0)), -6, accuracy: 0.1)
        XCTAssertEqual(stop.signedDistance(to: Fixtures.at(0, 20)), 9, accuracy: 0.1)
        XCTAssertTrue(stop.contains(Fixtures.at(0, 10.9)))
        XCTAssertFalse(stop.contains(Fixtures.at(0, 11.2)))
    }

    func testPolygonWithBuffer() {
        // A school compound, prohibited up to 5 m outside its fence.
        let school = Fixtures.polygonZone(id: "school", kind: .school, buffer: 5,
                                          rings: [Fixtures.rect(x0: 0, y0: 0, x1: 100, y1: 100)])
        XCTAssertEqual(school.signedDistance(to: Fixtures.at(103, 50)), -2, accuracy: 0.1)
        XCTAssertEqual(school.signedDistance(to: Fixtures.at(110, 50)), 5, accuracy: 0.1)
        XCTAssertEqual(school.signedDistance(to: Fixtures.at(50, 50)), -55, accuracy: 0.1)
        XCTAssertTrue(school.contains(Fixtures.at(104, 50)))
        XCTAssertFalse(school.contains(Fixtures.at(106, 50)))
    }

    func testMultiPolygon() {
        let parks = NoSmokingZone(id: "two", kind: .park, name: nil, source: .nparks, buffer: 0, geometry: .polygons([
            Polygon(rings: [Fixtures.rect(x0: 0, y0: 0, x1: 50, y1: 50)])!,
            Polygon(rings: [Fixtures.rect(x0: 200, y0: 0, x1: 250, y1: 50)])!,
        ]))
        XCTAssertTrue(parks.contains(Fixtures.at(25, 25)))
        XCTAssertTrue(parks.contains(Fixtures.at(225, 25)))
        XCTAssertFalse(parks.contains(Fixtures.at(125, 25)))
        XCTAssertEqual(parks.signedDistance(to: Fixtures.at(125, 25)), 75, accuracy: 0.1)
        XCTAssertTrue(parks.bbox.contains(Fixtures.at(125, 25)), "the box spans both parts")
    }

    func testExitFromInsideAPolygonLandsOutside() {
        let park = Fixtures.polygonZone(id: "park", kind: .park, rings: [Fixtures.rect(x0: 0, y0: 0, x1: 400, y1: 200)])
        let inside = Fixtures.at(380, 100)   // 20 m from the east edge
        let exit = park.exitPoint(from: inside)
        XCTAssertGreaterThan(park.signedDistance(to: exit), 0)
        XCTAssertEqual(Geo.distance(inside, exit), 25, accuracy: 0.5, "20 m to the edge + 5 m margin")
        XCTAssertEqual(CompassDirection(bearing: Geo.bearing(from: inside, to: exit)), .east)
    }

    func testExitFromInsideTheBuffer() {
        let school = Fixtures.polygonZone(id: "school", kind: .school, buffer: 5,
                                          rings: [Fixtures.rect(x0: 0, y0: 0, x1: 100, y1: 100)])
        let nearFence = Fixtures.at(50, 102)   // 2 m north of the fence
        let exit = school.exitPoint(from: nearFence)
        XCTAssertGreaterThan(school.signedDistance(to: exit), 0)
        XCTAssertEqual(CompassDirection(bearing: Geo.bearing(from: nearFence, to: exit)), .north)
    }

    func testExitFromAPointZone() {
        let stop = Fixtures.pointZone(id: "bus", kind: .busStop, at: Fixtures.at(0, 0), radius: 11)
        let exit = stop.exitPoint(from: Fixtures.at(-4, 0))
        XCTAssertEqual(stop.signedDistance(to: exit), 5, accuracy: 0.2)
        XCTAssertEqual(CompassDirection(bearing: Geo.bearing(from: Fixtures.at(-4, 0), to: exit)), .west)
        // Standing right on the pole still gives a way out.
        XCTAssertGreaterThan(stop.signedDistance(to: stop.exitPoint(from: Fixtures.at(0, 0))), 0)
    }

    func testTitleUsesTheName() {
        let named = NoSmokingZone(id: "p", kind: .park, name: "Bishan-Ang Mo Kio Park", source: .osm, buffer: 0,
                                  geometry: .point(Fixtures.origin))
        XCTAssertEqual(named.title, "Parc ou jardin · Bishan-Ang Mo Kio Park")
        let anonymous = Fixtures.pointZone(id: "b", kind: .busStop, at: Fixtures.origin, radius: 11)
        XCTAssertEqual(anonymous.title, "Arrêt de bus")
    }

    func testReliabilityFollowsTheSource() {
        XCTAssertEqual(ZoneSource.nea.reliability, .official)
        XCTAssertEqual(ZoneSource.nparks.reliability, .official)
        XCTAssertEqual(ZoneSource.osm.reliability, .indicative)
        XCTAssertEqual(SpotSource.nea.reliability, .official)
        XCTAssertEqual(SpotSource.changi.reliability, .official)
        XCTAssertEqual(SpotSource.osmArea.reliability, .indicative)
        XCTAssertEqual(SpotSource.osmVenue.reliability, .indicative)
    }
}

final class ZoneIndexTests: XCTestCase {
    func testIndexAgreesWithBruteForce() {
        var generator = SeededGenerator(seed: 42)
        var zones: [NoSmokingZone] = []
        for i in 0..<300 {
            let x = Double.random(in: -3000...3000, using: &generator)
            let y = Double.random(in: -3000...3000, using: &generator)
            if i.isMultiple(of: 3) {
                zones.append(Fixtures.pointZone(id: "p\(i)", kind: .busStop, at: Fixtures.at(x, y), radius: 11))
            } else {
                let w = Double.random(in: 20...600, using: &generator), h = Double.random(in: 20...600, using: &generator)
                zones.append(Fixtures.polygonZone(id: "z\(i)", kind: .park, buffer: i.isMultiple(of: 5) ? 5 : 0,
                                                  rings: [Fixtures.rect(x0: x, y0: y, x1: x + w, y1: y + h)]))
            }
        }
        let index = ZoneIndex(zones: zones)
        for _ in 0..<2000 {
            let p = Fixtures.at(Double.random(in: -3200...3700, using: &generator), Double.random(in: -3200...3700, using: &generator))
            let fromIndex = Set(index.zones(containing: p).map(\.id))
            let bruteForce = Set(zones.filter { $0.contains(p) }.map(\.id))
            XCTAssertEqual(fromIndex, bruteForce)
        }
    }

    func testNearIsSortedAndBounded() {
        let zones = [
            Fixtures.pointZone(id: "near", kind: .busStop, at: Fixtures.at(30, 0), radius: 11),
            Fixtures.pointZone(id: "nearer", kind: .busStop, at: Fixtures.at(15, 0), radius: 11),
            Fixtures.pointZone(id: "far", kind: .busStop, at: Fixtures.at(900, 0), radius: 11),
        ]
        let found = ZoneIndex(zones: zones).zones(near: Fixtures.origin, radius: 50)
        XCTAssertEqual(found.map(\.zone.id), ["nearer", "near"])
        XCTAssertEqual(found[0].signedDistance, 4, accuracy: 0.1)
    }

    func testZonesInABox() {
        let zones = [
            Fixtures.polygonZone(id: "in", kind: .park, rings: [Fixtures.rect(x0: 0, y0: 0, x1: 50, y1: 50)]),
            Fixtures.polygonZone(id: "out", kind: .park, rings: [Fixtures.rect(x0: 5000, y0: 5000, x1: 5050, y1: 5050)]),
        ]
        let box = BoundingBox([Fixtures.at(-100, -100), Fixtures.at(100, 100)])!
        XCTAssertEqual(ZoneIndex(zones: zones).zones(in: box).map(\.id), ["in"])
    }
}

/// Deterministic randomness, so a failure can be replayed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
